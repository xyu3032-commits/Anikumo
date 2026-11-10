import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';

import '../../models/novel_item.dart';
import '../storage/storage.dart';
import 'legado_gbk.dart';
import 'novel_source.dart';

/// Batch 158: one imported local book (feature repository's
/// 本地书籍）. The original file and its parsed chapters
/// live under the app's documents directory; this registry
/// entry is what the shelf and the local source read.
class LocalBook {
  const LocalBook({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.chapterCount,
    required this.addedAt,
  });

  final String id;
  final String title;
  final String author;

  /// 'epub' or 'txt'.
  final String format;
  final int chapterCount;
  final int addedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'format': format,
        'chapters': chapterCount,
        'addedAt': addedAt,
      };

  static LocalBook? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return LocalBook(
      id: id,
      title: json['title']?.toString() ?? id,
      author: json['author']?.toString() ?? '',
      format: json['format']?.toString() ?? 'txt',
      chapterCount: (json['chapters'] as num?)?.toInt() ?? 0,
      addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One parsed chapter of a local book.
typedef LocalChapter = ({String title, String text});

/// Split plain text into chapters by heading lines
/// (第X章/回/节/卷… or Chapter N). Text before the first
/// heading becomes a leading chapter only when it is
/// substantial; a book with no headings is one chapter.
List<LocalChapter> splitTxtChapters(String text, {String fallbackTitle = '正文'}) {
  final headingPattern = RegExp(
    r'^\s*(第\s*[0-9零一二三四五六七八九十百千万两]+\s*[章回节卷部篇][^\n]{0,40}|Chapter\s+\d+[^\n]{0,40})\s*$',
  );
  // A body line can also start with 第X章 ("第二章的战斗持续
  // 了一整夜。") — headings are short and never end with
  // sentence punctuation, body lines usually fail one of
  // the two checks.
  bool isHeading(String line) {
    final t = line.trim();
    if (t.length > 40) return false;
    if (t.endsWith('。') ||
        t.endsWith('！') ||
        t.endsWith('？') ||
        t.endsWith('；')) {
      return false;
    }
    return headingPattern.hasMatch(line);
  }

  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final chapters = <LocalChapter>[];
  var title = '';
  final buf = StringBuffer();
  void flush() {
    final body = buf.toString().trim();
    if (body.isEmpty) {
      buf.clear();
      return;
    }
    if (chapters.isEmpty && title.isEmpty && body.length < 100) {
      // A short preamble (title page blurbs etc.) joins
      // the first real chapter instead of standing alone.
      return;
    }
    chapters.add((
      title: title.isEmpty ? fallbackTitle : title,
      text: body,
    ));
    buf.clear();
  }

  for (final line in lines) {
    if (isHeading(line)) {
      flush();
      title = line.trim();
    } else {
      buf.writeln(line);
    }
  }
  flush();
  if (chapters.isEmpty) {
    final body = text.trim();
    if (body.isNotEmpty) {
      chapters.add((title: fallbackTitle, text: body));
    }
  }
  return chapters;
}

/// Parse an EPUB file's chapters in spine order: title
/// from the first heading (or the document title), text
/// from block-level elements, one chapter per spine item.
List<LocalChapter> parseEpubChapters(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String? readText(String name) {
    final f = archive.findFile(name);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final container = readText('META-INF/container.xml');
  if (container == null) return const [];
  final rootfile = RegExp(r'full-path="([^"]+)"').firstMatch(container);
  if (rootfile == null) return const [];
  final opfPath = rootfile.group(1)!;
  final opf = readText(opfPath);
  if (opf == null) return const [];
  final opfDir = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';

  final manifest = <String, ({String href, String type})>{};
  for (final m in RegExp(r'<item\s+[^>]*>').allMatches(opf)) {
    final tag = m.group(0)!;
    String attr(String name) =>
        RegExp('$name="([^"]*)"').firstMatch(tag)?.group(1) ?? '';
    final id = attr('id');
    if (id.isNotEmpty) {
      manifest[id] = (href: attr('href'), type: attr('media-type'));
    }
  }
  final spine = <String>[
    for (final m in RegExp(r'<itemref\s+[^>]*idref="([^"]+)"').allMatches(opf))
      m.group(1)!,
  ];

  final chapters = <LocalChapter>[];
  for (final idref in spine) {
    final item = manifest[idref];
    if (item == null) continue;
    if (!item.type.contains('xhtml') && !item.type.contains('html')) {
      continue;
    }
    final path = Uri.decodeComponent('$opfDir${item.href}');
    final xhtml = readText(path);
    if (xhtml == null) continue;
    final doc = html_parser.parse(xhtml);
    final body = doc.body;
    if (body == null) continue;
    var title = doc.querySelector('h1')?.text.trim() ??
        doc.querySelector('h2')?.text.trim() ??
        '';
    final lines = <String>[];
    void walk(dom.Node node) {
      if (node is! dom.Element) return;
      const leafTags = {
        'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote',
      };
      final tag = node.localName ?? '';
      if (leafTags.contains(tag)) {
        final t = node.text.trim();
        if (t.isNotEmpty) lines.add(t);
        return;
      }
      for (final child in node.nodes) {
        walk(child);
      }
    }

    for (final child in body.nodes) {
      walk(child);
    }
    final text = lines.join('\n');
    if (text.trim().isEmpty) continue;
    if (title.isEmpty) title = '第 ${chapters.length + 1} 章';
    chapters.add((title: title, text: text));
  }
  return chapters;
}

/// EPUB package metadata (dc:title / dc:creator).
({String title, String author}) epubMetadata(List<int> bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) return (title: '', author: '');
    final container =
        utf8.decode(containerFile.content as List<int>, allowMalformed: true);
    final opfPath =
        RegExp(r'full-path="([^"]+)"').firstMatch(container)?.group(1);
    if (opfPath == null) return (title: '', author: '');
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) return (title: '', author: '');
    final opf = utf8.decode(opfFile.content as List<int>, allowMalformed: true);
    String tag(String name) =>
        RegExp('<dc:$name[^>]*>([^<]*)</dc:$name>').firstMatch(opf)?.group(1)?.trim() ?? '';
    return (title: tag('title'), author: tag('creator'));
  } catch (_) {
    return (title: '', author: '');
  }
}

/// The local-books store: registry + on-disk files.
class LocalBookStore {
  LocalBookStore._();

  static List<LocalBook> books() {
    final raw = GStorage.getSetting(SettingsKeys.novelLocalBooksJson);
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final out = <LocalBook>[];
        for (final e in decoded) {
          if (e is Map) {
            final book = LocalBook.fromJson(e.cast<String, dynamic>());
            if (book != null) out.add(book);
          }
        }
        return out;
      }
    } catch (_) {}
    return const [];
  }

  static Future<void> _save(List<LocalBook> books) => GStorage.putSetting(
        SettingsKeys.novelLocalBooksJson,
        jsonEncode([for (final b in books) b.toJson()]),
      );

  static Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/novel_local_books');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _contentId(List<int> bytes) {
    // FNV-1a over the bytes: re-importing the same file is
    // recognised instead of duplicating the book.
    var hash = 0x811c9dc5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'b${hash.toRadixString(16).padLeft(8, '0')}';
  }

  /// Import one file's bytes. Returns the book, or null
  /// when the same content is already on the shelf.
  static Future<LocalBook?> importBytes(
    String fileName,
    List<int> bytes,
  ) async {
    final lower = fileName.toLowerCase();
    final isEpub = lower.endsWith('.epub');
    if (!isEpub && !lower.endsWith('.txt')) {
      throw const FormatException('只支持 EPUB / TXT 文件');
    }
    final id = _contentId(bytes);
    final existing = books();
    if (existing.any((b) => b.id == id)) return null;

    final List<LocalChapter> chapters;
    var title = fileName.replaceAll(RegExp(r'\.(epub|txt)$', caseSensitive: false), '');
    var author = '';
    if (isEpub) {
      chapters = parseEpubChapters(bytes);
      final meta = epubMetadata(bytes);
      if (meta.title.isNotEmpty) title = meta.title;
      author = meta.author;
    } else {
      var text = '';
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        await Gb2312.ensureLoaded();
        text = Gb2312.decode(bytes);
      }
      chapters = splitTxtChapters(text, fallbackTitle: title);
    }
    if (chapters.isEmpty) {
      throw const FormatException('文件里没有解析到正文');
    }
    final root = await _root();
    final dir = Directory('${root.path}/$id');
    await dir.create(recursive: true);
    await File('${dir.path}/book.${isEpub ? 'epub' : 'txt'}').writeAsBytes(bytes);
    await File('${dir.path}/chapters.json').writeAsString(
      jsonEncode([
        for (final c in chapters) {'t': c.title, 'x': c.text},
      ]),
    );
    final book = LocalBook(
      id: id,
      title: title,
      author: author,
      format: isEpub ? 'epub' : 'txt',
      chapterCount: chapters.length,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _save([...existing, book]);
    return book;
  }

  static Future<List<LocalChapter>> chaptersOf(LocalBook book) async {
    final root = await _root();
    final file = File('${root.path}/${book.id}/chapters.json');
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        return [
          for (final e in decoded)
            if (e is Map)
              (
                title: e['t']?.toString() ?? '',
                text: e['x']?.toString() ?? '',
              ),
        ];
      }
    } catch (_) {}
    return const [];
  }

  static Future<void> remove(String id) async {
    await _save(books().where((b) => b.id != id).toList());
    final root = await _root();
    final dir = Directory('${root.path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// The local books as a novel source: searching and the
/// explore shelf see them alongside network sources, and
/// the detail/reader flow works unchanged. Registered in
/// the source list only while the feature is installed.
class LocalNovelSource implements NovelSource {
  const LocalNovelSource();

  static const sourceId = 'local_books';
  static const shelfUrl = 'local://shelf';

  @override
  String get id => sourceId;

  @override
  String get name => '本地书籍';

  @override
  bool get builtin => false;

  @override
  int get type => 0;

  @override
  Map<String, String> get headers => const {};

  @override
  String get loginUrl => '';

  NovelItem _itemFor(LocalBook book) => NovelItem(
        bookUrl: 'local://book/${book.id}',
        title: book.title,
        author: book.author,
        coverUrl: '',
        intro: '',
        kind: book.format.toUpperCase(),
        lastChapter: '',
        source: sourceId,
        sourceName: name,
      );

  LocalBook? _bookOf(NovelItem item) {
    final prefix = 'local://book/';
    if (!item.bookUrl.startsWith(prefix)) return null;
    final id = item.bookUrl.substring(prefix.length);
    for (final b in LocalBookStore.books()) {
      if (b.id == id) return b;
    }
    return null;
  }

  @override
  Future<List<NovelItem>> search(String key, {int page = 1}) async {
    final needle = key.trim().toLowerCase();
    return [
      for (final b in LocalBookStore.books())
        if (needle.isEmpty ||
            b.title.toLowerCase().contains(needle) ||
            b.author.toLowerCase().contains(needle))
          _itemFor(b),
    ];
  }

  @override
  @override
  bool get hasDynamicExplore => false;

  @override
  bool get exploreKindsResolved => true;

  @override
  Future<void> ensureExploreKinds() async {}

  @override
  List<NovelExploreCategory> get exploreCategories => const [
        NovelExploreCategory(title: '本地书架', url: shelfUrl),
      ];

  @override
  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  }) async =>
      [for (final b in LocalBookStore.books()) _itemFor(b)];

  @override
  Future<NovelItem> bookInfo(NovelItem item) async {
    final book = _bookOf(item);
    if (book == null) return item;
    final chapters = await LocalBookStore.chaptersOf(book);
    return item.copyWith(
      lastChapter: chapters.isEmpty ? '' : chapters.last.title,
    );
  }

  @override
  Future<List<NovelChapter>> chapters(NovelItem item) async {
    final book = _bookOf(item);
    if (book == null) return const [];
    final chapters = await LocalBookStore.chaptersOf(book);
    return [
      for (var i = 0; i < chapters.length; i++)
        NovelChapter(
          title: chapters[i].title,
          url: 'local://book/${book.id}/$i',
        ),
    ];
  }

  @override
  Future<List<NovelBlock>> content(
    NovelItem item,
    NovelChapter chapter,
  ) async {
    final book = _bookOf(item);
    if (book == null) return const [];
    final index = int.tryParse(chapter.url.split('/').last) ?? -1;
    final chapters = await LocalBookStore.chaptersOf(book);
    if (index < 0 || index >= chapters.length) return const [];
    return [
      for (final line in chapters[index].text.split(RegExp(r'\n+')))
        if (line.trim().isNotEmpty) NovelTextBlock(line.trim()),
    ];
  }
}
