import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_source.dart';

/// Batch 102: local manga — books imported from CBZ / ZIP
/// files. An import extracts the archive's image pages into
/// app storage once; from then on the book is an ordinary
/// manga served by [LocalMangaSource]: its pages are local
/// files, so the reader, favorites and progress all work
/// offline through the existing flows.

const _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'avif',
  'bmp',
};

bool isLocalMangaImageName(String name) {
  if (name.endsWith('/')) return false;
  if (name.startsWith('__MACOSX/')) return false;
  final base = name.split('/').last;
  if (base.startsWith('.') || base.isEmpty) return false;
  final dot = base.lastIndexOf('.');
  if (dot < 0) return false;
  return _imageExtensions.contains(base.substring(dot + 1).toLowerCase());
}

/// Natural (human) ordering for page file names: digit runs
/// compare by value, so `page_2` sorts before `page_10`.
int naturalCompare(String a, String b) {
  final x = a.toLowerCase();
  final y = b.toLowerCase();
  var i = 0;
  var j = 0;
  bool digit(int c) => c >= 0x30 && c <= 0x39;
  while (i < x.length && j < y.length) {
    final ca = x.codeUnitAt(i);
    final cb = y.codeUnitAt(j);
    if (digit(ca) && digit(cb)) {
      var i2 = i;
      var j2 = j;
      while (i2 < x.length && digit(x.codeUnitAt(i2))) {
        i2++;
      }
      while (j2 < y.length && digit(y.codeUnitAt(j2))) {
        j2++;
      }
      final na = int.parse(x.substring(i, i2));
      final nb = int.parse(y.substring(j, j2));
      if (na != nb) return na.compareTo(nb);
      final la = i2 - i;
      final lb = j2 - j;
      if (la != lb) return la.compareTo(lb);
      i = i2;
      j = j2;
    } else {
      if (ca != cb) return ca.compareTo(cb);
      i++;
      j++;
    }
  }
  return (x.length - i).compareTo(y.length - j);
}

/// Extraction runs in a worker isolate (compute): ZIP
/// inflate of a few hundred pages is real CPU work and must
/// not stall the UI. Returns the number of pages written, 0
/// when the archive holds no images.
int _extractArchiveToDir(List<String> args) {
  final sourcePath = args[0];
  final destDir = args[1];
  final archive = ZipDecoder().decodeBytes(File(sourcePath).readAsBytesSync());
  final images = [
    for (final file in archive.files)
      if (file.isFile && isLocalMangaImageName(file.name)) file,
  ]..sort((a, b) => naturalCompare(a.name, b.name));
  var n = 0;
  for (final file in images) {
    n++;
    final ext = file.name.split('.').last.toLowerCase();
    final out = File(
      '$destDir/${n.toString().padLeft(4, '0')}.$ext',
    );
    out.writeAsBytesSync(file.content);
  }
  return n;
}

/// One imported book's stored metadata (book.json in its
/// directory under the local library root).
class LocalBook {
  const LocalBook({
    required this.id,
    required this.title,
    required this.dirPath,
    required this.pages,
    required this.coverFile,
    required this.importedAt,
  });

  final String id;
  final String title;
  final String dirPath;
  final int pages;

  /// File name of the first page inside [dirPath] (the cover).
  final String coverFile;
  final DateTime importedAt;

  String get coverPath => '$dirPath/$coverFile';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'pages': pages,
        'coverFile': coverFile,
        'importedAt': importedAt.toIso8601String(),
      };

  factory LocalBook.fromJson(Map<String, dynamic> json, String dirPath) {
    return LocalBook(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      dirPath: dirPath,
      pages: (json['pages'] as num?)?.toInt() ?? 0,
      coverFile: json['coverFile'] as String? ?? '',
      importedAt:
          DateTime.tryParse(json['importedAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  MangaItem toItem() {
    return MangaItem(
      id: id,
      title: title,
      description: '本地导入 · $pages 页',
      coverUrl: Uri.file(coverPath).toString(),
      author: '',
      status: '',
      year: null,
      tags: const ['本地'],
      source: LocalMangaSource.sourceId,
    );
  }
}

/// The on-disk library of imported books: one directory per
/// book under `<documents>/manga_local/`, each holding the
/// extracted pages and a book.json. The book list is cached
/// in memory; [ensureLoaded] fills it once per process.
class LocalMangaLibrary {
  LocalMangaLibrary._();

  static List<LocalBook> _cache = const [];
  static bool _loaded = false;
  static Future<bool>? _loading;

  /// The last loaded book list (empty until [ensureLoaded]
  /// has run). The source registry reads this synchronously.
  static List<LocalBook> get cachedBooks => _cache;

  static Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/manga_local');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Loads the book list from disk once. Returns true when
  /// the visible set changed (first load that found books,
  /// or a reload after import/delete) so callers can bump
  /// the registry revision.
  static Future<bool> ensureLoaded() {
    if (_loaded) return Future.value(false);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<bool> reload() async {
    _loaded = false;
    return _load();
  }

  static Future<bool> _load() async {
    final before = _cache.length;
    try {
      final root = await _root();
      final books = <LocalBook>[];
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        final meta = File('${entity.path}/book.json');
        if (!await meta.exists()) continue;
        try {
          final decoded = jsonDecode(await meta.readAsString());
          if (decoded is Map) {
            final book = LocalBook.fromJson(
              decoded.cast<String, dynamic>(),
              entity.path,
            );
            if (book.id.isNotEmpty && book.pages > 0) books.add(book);
          }
        } catch (_) {
          // A corrupt book.json drops that one book from the
          // shelf, never the whole library.
        }
      }
      books.sort((a, b) => b.importedAt.compareTo(a.importedAt));
      _cache = books;
    } catch (_) {
      _cache = const [];
    }
    _loaded = true;
    return _cache.length != before;
  }

  static LocalBook? byId(String id) {
    for (final book in _cache) {
      if (book.id == id) return book;
    }
    return null;
  }

  static String _bookId(String title, String fileName) {
    var slug = title
        .replaceAll(RegExp(r'[^\w一-龥-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (slug.isEmpty) slug = 'book';
    if (slug.length > 32) slug = slug.substring(0, 32);
    var hash = 0x811c9dc5;
    for (final c in '$title|$fileName'.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return '${slug}_${hash.toRadixString(16).padLeft(8, '0')}';
  }

  /// Imports one CBZ / ZIP file: extracts its image pages
  /// into a new book directory and registers the book.
  /// Throws a [FormatException] when the archive holds no
  /// image pages.
  static Future<LocalBook> importArchive(String sourcePath) async {
    final root = await _root();
    final fileName = sourcePath.split(Platform.pathSeparator).last;
    var title = fileName
        .replaceAll(RegExp(r'\.(cbz|zip)$', caseSensitive: false), '')
        .trim();
    if (title.isEmpty) title = '未命名漫画';
    var id = _bookId(title, fileName);
    var dir = Directory('${root.path}/$id');
    if (await dir.exists()) {
      id = '${id}_2';
      dir = Directory('${root.path}/$id');
    }
    await dir.create(recursive: true);
    try {
      final count = await compute(
        _extractArchiveToDir,
        [sourcePath, dir.path],
      );
      if (count == 0) {
        throw const FormatException('压缩包里没有图片页');
      }
      final entries = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      entries.sort((a, b) => naturalCompare(a.path, b.path));
      final book = LocalBook(
        id: id,
        title: title,
        dirPath: dir.path,
        pages: count,
        coverFile: entries.isEmpty
            ? ''
            : entries.first.path.split(Platform.pathSeparator).last,
        importedAt: DateTime.now(),
      );
      await File('${dir.path}/book.json')
          .writeAsString(jsonEncode(book.toJson()));
      await reload();
      return book;
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  /// Deletes one book's files. Favorites and progress that
  /// reference it stay stored (the same contract as removing
  /// an online source) but can no longer open it.
  static Future<void> deleteBook(String id) async {
    final book = byId(id);
    if (book == null) return;
    final dir = Directory(book.dirPath);
    if (await dir.exists()) await dir.delete(recursive: true);
    await reload();
  }

  /// The book's page files in reading order.
  static Future<List<File>> pageFiles(LocalBook book) async {
    final dir = Directory(book.dirPath);
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File &&
          isLocalMangaImageName(
            entity.path.split(Platform.pathSeparator).last,
          )) {
        files.add(entity);
      }
    }
    files.sort((a, b) => naturalCompare(a.path, b.path));
    return files;
  }
}

/// The built-in source serving imported local books. It
/// joins the registry only while at least one book exists.
class LocalMangaSource extends MangaSource {
  LocalMangaSource._();

  static final LocalMangaSource instance = LocalMangaSource._();
  static const String sourceId = 'local';

  @override
  String get id => sourceId;

  @override
  String get name => '本地导入';

  @override
  String get description => 'CBZ / ZIP 导入的本地漫画';

  List<MangaItem> _slice(List<LocalBook> books, int page, int limit) {
    final start = (page - 1) * limit;
    if (start >= books.length) return const [];
    final end = start + limit > books.length ? books.length : start + limit;
    return [for (final book in books.sublist(start, end)) book.toItem()];
  }

  @override
  Future<List<MangaItem>> search(
    String keyword, {
    int limit = 30,
    int page = 1,
  }) async {
    await LocalMangaLibrary.ensureLoaded();
    final needle = keyword.trim().toLowerCase();
    final hits = [
      for (final book in LocalMangaLibrary.cachedBooks)
        if (needle.isEmpty || book.title.toLowerCase().contains(needle))
          book,
    ];
    return _slice(hits, page, limit);
  }

  @override
  Future<List<MangaItem>> popular({int limit = 20, int page = 1}) async {
    await LocalMangaLibrary.ensureLoaded();
    return _slice(LocalMangaLibrary.cachedBooks, page, limit);
  }

  @override
  Future<List<MangaItem>> updated({int limit = 20, int page = 1}) =>
      popular(limit: limit, page: page);

  @override
  Future<List<MangaChapter>> chapters(MangaItem manga) async {
    await LocalMangaLibrary.ensureLoaded();
    final book = LocalMangaLibrary.byId(manga.id);
    if (book == null) return const [];
    return [
      MangaChapter(
        id: 'all',
        volume: null,
        chapter: null,
        title: '',
        language: '',
        pages: book.pages,
        publishedAt: null,
      ),
    ];
  }

  @override
  Future<List<MangaPage>> pages(
    MangaItem manga,
    MangaChapter chapter,
  ) async {
    await LocalMangaLibrary.ensureLoaded();
    final book = LocalMangaLibrary.byId(manga.id);
    if (book == null) return const [];
    final files = await LocalMangaLibrary.pageFiles(book);
    return [
      for (final file in files) MangaPage(Uri.file(file.path).toString()),
    ];
  }
}
