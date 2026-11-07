import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/novel/novel_source.dart';

/// Batch 67: a Legado 图片型 (type 2) book source, adapted
/// into the manga zone's [MangaSource] interface. The
/// source itself lives in the novel registry (the single
/// store for every Legado-format source, whatever its
/// type); this adapter only translates models and calls
/// through the novel layer's public [NovelSource] API —
/// search / explore / bookInfo / chapters / content map
/// one-to-one onto the manga operations, with chapter
/// content expected as image blocks.
class LegadoMangaSource extends MangaSource {
  LegadoMangaSource(this.novel);

  final NovelSource novel;

  static const String idPrefix = 'legado:';

  static String adapterId(String novelSourceId) =>
      '$idPrefix$novelSourceId';

  static String? novelIdOf(String adapterId) =>
      adapterId.startsWith(idPrefix)
          ? adapterId.substring(idPrefix.length)
          : null;

  @override
  String get id => adapterId(novel.id);

  @override
  String get name => novel.name;

  @override
  String get description => '漫画书源';

  MangaItem _toManga(NovelItem item) {
    final tags = <String>[
      for (final part in item.kind.split(RegExp(r'[/·、\s]+')))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    return MangaItem(
      id: item.bookUrl,
      title: item.title,
      description: item.intro,
      coverUrl: item.coverUrl,
      author: item.author,
      status: normalizeMangaStatus(item.kind),
      year: null,
      tags: tags,
      source: id,
      headers: novel.headers,
    );
  }

  NovelItem _toNovel(MangaItem manga) => NovelItem(
        bookUrl: manga.id,
        title: manga.title,
        author: manga.author,
        coverUrl: manga.coverUrl,
        intro: manga.description,
        source: novel.id,
        sourceName: novel.name,
      );

  @override
  Future<List<MangaItem>> search(
    String keyword, {
    int limit = 30,
    int page = 1,
  }) async {
    final items = await novel.search(keyword, page: page);
    return [for (final item in items) _toManga(item)];
  }

  @override
  Future<List<MangaItem>> popular({int limit = 20, int page = 1}) async {
    final categories = novel.exploreCategories;
    if (categories.isEmpty) return const [];
    final items = await novel.explore(categories.first, page: page);
    return [for (final item in items) _toManga(item)];
  }

  @override
  Future<List<MangaItem>> updated({int limit = 20, int page = 1}) async {
    final categories = novel.exploreCategories;
    if (categories.isEmpty) return const [];
    // Prefer a category that advertises updates; otherwise
    // the first category doubles as the home feed.
    final category = categories.firstWhere(
      (c) => c.title.contains('更新'),
      orElse: () => categories.first,
    );
    final items = await novel.explore(category, page: page);
    return [for (final item in items) _toManga(item)];
  }

  @override
  Future<List<MangaChapter>> chapters(MangaItem manga) async {
    final chapters = await novel.chapters(_toNovel(manga));
    return [
      for (final chapter in chapters)
        MangaChapter(
          id: chapter.url,
          volume: null,
          chapter: _chapterNumber(chapter.title),
          title: chapter.title,
          language: '',
          pages: 0,
          publishedAt: null,
        ),
    ];
  }

  /// Chapter number out of titles like 第12话 / 第 3 章 /
  /// Vol.2 12.5 — display sugar only; unrecognized titles
  /// keep their full name as the label.
  static String? _chapterNumber(String title) {
    final match = RegExp(
      r'第\s*(\d+(?:\.\d+)?)\s*[话話章回]',
    ).firstMatch(title);
    return match?.group(1);
  }

  @override
  Future<List<MangaPage>> pages(
    MangaItem manga,
    MangaChapter chapter,
  ) async {
    final blocks = await novel.content(
      _toNovel(manga),
      NovelChapter(title: chapter.title, url: chapter.id),
    );
    return [
      for (final block in blocks)
        if (block is NovelImageBlock)
          MangaPage(
            block.url,
            headers: block.headers.isNotEmpty
                ? block.headers
                : novel.headers,
          ),
    ];
  }

  @override
  Future<MangaItem?> details(MangaItem manga) async {
    final enriched = await novel.bookInfo(_toNovel(manga));
    return _toManga(enriched);
  }
}
