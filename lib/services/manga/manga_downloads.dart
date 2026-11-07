import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:path_provider/path_provider.dart';

/// One downloaded chapter, stored as page image files under the
/// app documents directory (batch 15, M1). The index is a JSON
/// file next to the page folders, so wiping the folder wipes
/// everything consistently.
class MangaDownloadEntry {
  const MangaDownloadEntry({
    required this.source,
    required this.mangaId,
    required this.mangaTitle,
    required this.coverUrl,
    required this.chapterId,
    required this.chapterLabel,
    required this.pageCount,
    required this.downloadedAtMs,
  });

  final String source;
  final String mangaId;
  final String mangaTitle;
  final String coverUrl;
  final String chapterId;
  final String chapterLabel;
  final int pageCount;
  final int downloadedAtMs;

  String get key => '$source:$mangaId:$chapterId';

  Map<String, dynamic> toJson() => {
        'source': source,
        'mangaId': mangaId,
        'mangaTitle': mangaTitle,
        'coverUrl': coverUrl,
        'chapterId': chapterId,
        'chapterLabel': chapterLabel,
        'pageCount': pageCount,
        'downloadedAtMs': downloadedAtMs,
      };

  static MangaDownloadEntry? fromJson(Map<dynamic, dynamic> json) {
    final chapterId = json['chapterId']?.toString() ?? '';
    final mangaId = json['mangaId']?.toString() ?? '';
    if (chapterId.isEmpty || mangaId.isEmpty) return null;
    return MangaDownloadEntry(
      source: json['source']?.toString() ?? 'mangadex',
      mangaId: mangaId,
      mangaTitle: json['mangaTitle']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      chapterId: chapterId,
      chapterLabel: json['chapterLabel']?.toString() ?? '',
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      downloadedAtMs: (json['downloadedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class MangaDownloadStore {
  MangaDownloadStore._();

  static Directory? _rootCache;

  static Future<Directory> root() async {
    if (_rootCache != null) return _rootCache!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/manga_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _rootCache = dir;
  }

  static String _safe(String segment) =>
      segment.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  static Future<Directory> chapterDir(MangaDownloadEntry entry) async {
    final base = await root();
    return Directory(
      '${base.path}/${_safe(entry.source)}/${_safe(entry.mangaId)}/${_safe(entry.chapterId)}',
    );
  }

  static Future<File> _indexFile() async {
    final base = await root();
    return File('${base.path}/index.json');
  }

  static Future<List<MangaDownloadEntry>> loadIndex() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map) ?MangaDownloadEntry.fromJson(entry),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Batch 83: backup restore — merges records whose
  /// chapter files still exist on this device. The chapter
  /// images themselves never travel inside a JSON backup,
  /// so records pointing at missing files are skipped
  /// instead of becoming zombie entries. Returns
  /// (restored, skipped).
  static Future<(int, int)> mergeIndexEntries(
    List<MangaDownloadEntry> incoming,
  ) async {
    if (incoming.isEmpty) return (0, 0);
    final existing = await loadIndex();
    final byKey = {for (final e in existing) e.key: e};
    var restored = 0;
    var skipped = 0;
    for (final entry in incoming) {
      final dir = await chapterDir(entry);
      if (await dir.exists()) {
        byKey[entry.key] = entry;
        restored++;
      } else {
        skipped++;
      }
    }
    if (restored > 0) {
      await _saveIndex(byKey.values.toList());
    }
    return (restored, skipped);
  }

  static Future<void> _saveIndex(List<MangaDownloadEntry> entries) async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  static Future<bool> isDownloaded(
    String source,
    String mangaId,
    String chapterId,
  ) async {
    final entries = await loadIndex();
    return entries.any(
      (e) => e.key == '$source:$mangaId:$chapterId',
    );
  }

  /// Local page list for a downloaded chapter, in order, as
  /// 'file://' URLs the reader renders from disk.
  static Future<List<MangaPage>?> localPages(
    String source,
    String mangaId,
    String chapterId,
  ) async {
    final entries = await loadIndex();
    final entry = entries
        .where((e) => e.key == '$source:$mangaId:$chapterId')
        .firstOrNull;
    if (entry == null) return null;
    final dir = await chapterDir(entry);
    if (!await dir.exists()) return null;
    final files = await dir
        .list()
        .where((f) => f is File && f.path.endsWith('.img'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) return null;
    return [for (final f in files) MangaPage('file://${f.path}')];
  }

  /// Downloads every page of [chapter]; [onProgress] receives
  /// (done, total). Returns the stored entry, or null on failure
  /// (partial files are cleaned up).
  static Future<MangaDownloadEntry?> downloadChapter({
    required MangaItem manga,
    required MangaChapter chapter,
    void Function(int done, int total)? onProgress,
  }) async {
    final pages = await MangaApi.fetchChapterPages(manga, chapter);
    if (pages.isEmpty) return null;
    final entry = MangaDownloadEntry(
      source: manga.source,
      mangaId: manga.id,
      mangaTitle: manga.title,
      coverUrl: manga.coverUrl,
      chapterId: chapter.id,
      chapterLabel: chapter.displayLabel,
      pageCount: pages.length,
      downloadedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final dir = await chapterDir(entry);
    await dir.create(recursive: true);
    final dio = Dio();
    try {
      // Batch 16: three pages in parallel (was strictly
      // sequential), each via a .part file renamed on success,
      // and pages already on disk are skipped — an interrupted
      // download now resumes instead of starting over, and a
      // failed run keeps its partial pages for next time (the
      // index entry is only written on full success, so partial
      // chapters never surface as downloaded).
      var done = 0;
      Future<void> fetchPage(int i) async {
        final name = i.toString().padLeft(4, '0');
        final target = File('${dir.path}/$name.img');
        if (await target.exists() && await target.length() > 0) {
          done++;
          onProgress?.call(done, pages.length);
          return;
        }
        final part = File('${dir.path}/$name.img.part');
        await dio.download(
          pages[i].url,
          part.path,
          options: Options(headers: pages[i].headers),
        );
        await part.rename(target.path);
        done++;
        onProgress?.call(done, pages.length);
      }

      for (var i = 0; i < pages.length; i += 3) {
        await Future.wait([
          for (var j = i; j < i + 3 && j < pages.length; j++) fetchPage(j),
        ]);
      }
    } catch (_) {
      return null;
    }
    final entries = [
      ...await loadIndex()
        ..removeWhere((e) => e.key == entry.key),
      entry,
    ];
    await _saveIndex(entries);
    return entry;
  }

  static Future<void> deleteEntry(MangaDownloadEntry entry) async {
    final dir = await chapterDir(entry);
    if (await dir.exists()) await dir.delete(recursive: true);
    final entries = await loadIndex()
      ..removeWhere((e) => e.key == entry.key);
    await _saveIndex(entries);
  }

  /// Total size of the downloads folder in bytes.
  static Future<int> totalSizeBytes() async {
    final base = await root();
    var total = 0;
    await for (final entity in base.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  static Future<void> clearAll() async {
    final base = await root();
    await base.delete(recursive: true);
    _rootCache = null;
    await root();
  }
}
