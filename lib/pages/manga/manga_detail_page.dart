import 'package:anikumo/services/novel/novel_api.dart';
import 'package:anikumo/pages/novel/novel_widgets.dart';
import 'package:anikumo/models/novel_item.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_categories_page.dart';
import 'package:anikumo/pages/manga/manga_search_page.dart';
import 'package:anikumo/pages/manga/manga_verification_page.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/manga/cross_media.dart';
import 'package:anikumo/services/manga/local_manga_source.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:anikumo/services/manga/manga_image_pipeline.dart';
import 'package:anikumo/services/manga/manga_page_cache.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/manga/manga_extras.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/utils/error_message.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

typedef MangaReaderArgs = ({
  MangaItem manga,
  List<MangaChapter> chapters,
  int chapterIndex,
  int initialPage,
});

/// Manga details: header, synopsis, favorite toggle and the chapter
/// list. The reader is one tap away from any chapter, and a saved
/// progress point offers one-tap resume.
class MangaDetailPage extends StatefulWidget {
  const MangaDetailPage({super.key, required this.manga});

  final MangaItem manga;

  @override
  State<MangaDetailPage> createState() => _MangaDetailPageState();
}

class _MangaDetailPageState extends State<MangaDetailPage> {
  List<MangaChapter> _chapters = const [];
  bool _showAllChapters = false;
  bool _loadingChapters = true;
  bool _descending = true;
  bool _expandedDescription = false;
  late bool _isFavorite;
  MangaProgress? _progress;

  /// Detail enrichment from the manga's own source (some sources
  /// only carry description/tags on their detail endpoint).
  MangaItem? _enriched;

  MangaItem get _manga => _enriched ?? _current;

  /// Batch 42: the edition this page is actually showing.
  /// Starts as the opened item; when its source serves no
  /// readable chapters, the readable-edition fallback swaps
  /// it for the same comic on another source (the global
  /// active source is never touched).
  late MangaItem _current;
  bool _autoSwitchTried = false;
  bool _switchingSource = false;
  String? _switchedFromName;

  // Cross-media sections at the bottom of the page: the anime
  // counterpart （配套动漫） and same-tag manga （相关漫画）.
  List<BangumiItem> _pairedAnime = const [];
  List<NovelItem> _pairedNovels = const [];

  // Batch 89: same-tag recommendations （你可能还喜欢）,
  // decided by this manga's tags on its own source.
  List<MangaItem> _tagRecs = const [];
  bool _tagRecsDone = false;

  // Batch 103: preview page urls from sources implementing
  // loadThumbnails; empty hides the strip.
  List<String> _thumbnails = const [];

  // Batch 15: local rating (M4), chapter downloads (M1), author
  // rail (M9).
  MangaRating? _rating;
  List<MangaItem> _authorWorks = const [];
  Set<String> _downloadedKeys = const {};
  final Map<String, double> _downloadProgress = {};
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _current = widget.manga;
    _isFavorite = MangaLibraryStore.isFavorite(
      _current.source,
      _current.id,
    );
    _progress =
        MangaLibraryStore.loadProgressMap()[_current.storageKey];
    _rating = MangaExtrasStore.loadRatings()[_current.storageKey];
    _noteController.text = _rating?.note ?? '';
    _loadChapters();
    _loadCrossMedia();
    _loadPairedNovels();
    _loadDetails();
    _loadDownloads();
    _loadAuthorWorks();
    _loadTagRecommendations();
    _loadThumbnails();
  }

  Future<void> _loadThumbnails() async {
    final source = MangaSources.byId(_current.source);
    if (source == null) return;
    final key = _current.storageKey;
    final urls = await source.loadThumbnails(_current);
    if (!mounted || _current.storageKey != key) return;
    setState(() => _thumbnails = urls);
  }

  Future<void> _loadDownloads() async {
    final entries = await MangaDownloadStore.loadIndex();
    if (!mounted) return;
    setState(() {
      _downloadedKeys = {
        for (final e in entries)
          if (e.mangaId == _current.id && e.source == _current.source)
            e.chapterId,
      };
    });
  }

  Future<void> _loadAuthorWorks() async {
    final author = _current.author.trim();
    if (author.isEmpty) return;
    final source = MangaSources.byId(_current.source);
    if (source == null) return;
    final results = await source.search(author);
    if (!mounted) return;
    setState(() {
      _authorWorks = rankMangaResults(results, author)
          .where((item) => item.id != _current.id)
          .take(10)
          .toList();
    });
  }

  /// Batch 89: the “你可能还喜欢” rail — manga on the SAME
  /// source sharing this manga's tags. Tag names on the item
  /// are display strings; the source's tag catalogue maps
  /// them to the ids byTag needs. The first two matched
  /// tags contribute listings; results merge and rank by
  /// shared-tag count. Sources without a tag catalogue fall
  /// back to searching the first tag name. Best-effort like
  /// the other companion rails: any failure leaves the
  /// section hidden.
  Future<void> _loadTagRecommendations() async {
    if (_tagRecsDone) return;
    final source = MangaSources.byId(_current.source);
    if (source == null) return;
    final base = _enriched ?? _current;
    if (base.tags.isEmpty) return;
    final forKey = base.storageKey;
    try {
      var candidates = <MangaItem>[];
      List<MangaTag> catalogue = const [];
      try {
        catalogue = await MangaApi.fetchTagsFor(source);
      } catch (_) {
        // No catalogue — the search fallback below applies.
      }
      final matched = matchTagsByName(base.tags, catalogue).take(2);
      for (final tag in matched) {
        try {
          candidates.addAll(await source.byTag(tag.id, limit: 20));
        } catch (_) {
          // One bad tag must not sink the whole rail.
        }
      }
      if (candidates.isEmpty) {
        try {
          candidates = await source.search(base.tags.first);
        } catch (_) {}
      }
      if (!mounted || _current.storageKey != forKey) return;
      final ranked = rankTagRecommendations(base, candidates);
      if (ranked.isEmpty) return;
      _tagRecsDone = true;
      setState(() => _tagRecs = ranked);
    } catch (_) {
      // Recommendations are best-effort.
    }
  }

  /// Batch 90: tapping a tag chip opens the tag's manga
  /// listing on this manga's own source. The display name
  /// resolves to a catalogue tag when the source has one;
  /// otherwise the tap falls back to a source search for
  /// the tag name — either way the tap now goes somewhere.
  Future<void> _openTag(String tagName) async {
    final source = MangaSources.byId(_current.source);
    if (source != null) {
      List<MangaTag> catalogue = const [];
      try {
        catalogue = await MangaApi.fetchTagsFor(source);
      } catch (_) {
        // No catalogue — the search fallback below applies.
      }
      final matched = matchTagsByName([tagName], catalogue);
      if (!mounted) return;
      if (matched.isNotEmpty) {
        context.pushNamed(
          '/manga/category',
          arguments: MangaCategoryArgs(source: source, tag: matched.first),
        );
        return;
      }
    }
    if (!mounted) return;
    // Batch 99: this fallback used to pass the tag name as
    // a plain keyword — source search matches titles, so
    // most tag taps landed on an empty results page. The
    // tag-search mode resolves the name through every
    // source's catalogue instead.
    context.pushNamed(
      '/manga/search',
      arguments: MangaSearchRouteArgs(
        query: tagName,
        tagSearch: true,
        // Batch 104/105: the tag belongs to THIS manga —
        // the tag search runs on its source alone (the
        // search page used to present the default source
        // and fan out to every source instead).
        originSourceId: _current.source,
      ),
    );
  }

  Future<void> _downloadChapter(MangaChapter chapter) async {
    setState(() => _downloadProgress[chapter.id] = 0);
    // Batch 30: fetchChapterPages inside the store throws on
    // source failure — without a guard here the chapter row
    // kept a stuck 0% progress forever and the error escaped
    // as an unhandled async exception. A throw now lands in
    // the same failure path as a null entry.
    MangaDownloadEntry? entry;
    try {
      entry = await MangaDownloadStore.downloadChapter(
        manga: _manga,
        chapter: chapter,
        onProgress: (done, total) {
          if (mounted) {
            setState(
              () => _downloadProgress[chapter.id] = done / total,
            );
          }
        },
      );
    } catch (_) {
      entry = null;
    }
    if (!mounted) return;
    setState(() {
      _downloadProgress.remove(chapter.id);
      if (entry != null) {
        _downloadedKeys = {..._downloadedKeys, chapter.id};
      }
    });
    AnikumoDialog.showToast(
      message: entry != null ? '下载完成，可离线阅读' : '下载失败，请检查网络后重试',
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    // Batch 27: enrichment is optional (the base item is
    // already on screen) — a failure must never surface as
    // an unhandled async error.
    try {
      final enriched = await MangaApi.fetchDetails(_current);
      if (!mounted || enriched == null) return;
      setState(() => _enriched = enriched);
      // Batch 89: the enriched item carries the full tag
      // list — if the tag rail found nothing from the
      // list-level item, retry with the richer tags.
      _loadTagRecommendations();
    } catch (_) {}
  }


  /// Batch 28: 配套小说 — the novel counterpart of this
  /// manga, matched on the Legado sources by title (strict
  /// relevance only, like the other companion rails).
  Future<void> _loadPairedNovels() async {
    try {
      for (final query in buildCrossQueries(primary: _current.title)) {
        final results = await NovelApi.searchAll(query);
        final ranked = rankNovels(query, results, strict: true);
        if (ranked.isNotEmpty) {
          if (mounted) {
            setState(() => _pairedNovels = ranked.take(10).toList());
          }
          break;
        }
      }
    } catch (_) {
      // Companions are best-effort.
    }
  }

  Future<void> _loadCrossMedia() async {
    final manga = _current;
    for (final query in buildCrossQueries(primary: manga.title)) {
      final page = await BangumiApi.bangumiSearch(query, limit: 12);
      if (page != null && page.items.isNotEmpty) {
        if (!mounted) return;
        setState(
          () => _pairedAnime = rankCrossAnime(page.items, manga.title),
        );
        break;
      }
    }
  }

  String? _chaptersError;

  /// Batch 198: the chapters failure was a verification
  /// wall — the error block offers the verification flow.
  bool _chaptersVerification = false;

  String? get _verificationUrl {
    if (!_chaptersVerification) return null;
    final source = MangaSources.byId(_current.source);
    if (source is JsBackedMangaSource) {
      final url = source.declaredUrl;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  /// Batch 42: when this edition's source serves nothing
  /// readable, swap the page to a verified edition on
  /// another source and reload. Runs at most once per page
  /// so a universally-unreadable comic still lands in the
  /// normal empty/error states.
  Future<bool> _tryAutoSwitch() async {
    if (_autoSwitchTried) return false;
    _autoSwitchTried = true;
    if (mounted) setState(() => _switchingSource = true);
    final fromName =
        MangaSources.byId(_current.source)?.name ?? _current.source;
    final found = await MangaApi.findReadableEdition(_current);
    if (!mounted) return true;
    if (found == null) {
      setState(() => _switchingSource = false);
      return false;
    }
    setState(() {
      _current = found;
      _enriched = null;
      _switchedFromName = fromName;
      _switchingSource = false;
      _isFavorite = MangaLibraryStore.isFavorite(found.source, found.id);
      _progress = MangaLibraryStore.loadProgressMap()[found.storageKey];
      _rating = MangaExtrasStore.loadRatings()[found.storageKey];
      _chapters = const [];
      _loadingChapters = true;
      _chaptersError = null;
      _tagRecs = const [];
      _tagRecsDone = false;
      _thumbnails = const [];
    });
    AnikumoDialog.showToast(
      message: '原源无可读章节，已自动切换到 '
          '${MangaSources.byId(found.source)?.name ?? found.source}',
    );
    _loadDetails();
    _loadDownloads();
    _loadTagRecommendations();
    _loadThumbnails();
    await _loadChapters();
    return true;
  }

  Future<void> _loadChapters() async {
    // Batch 27: a throwing chapter fetch previously left
    // _loadingChapters true forever — the chapter area spun
    // until the app restarted.
    List<MangaChapter> chapters;
    try {
      chapters = await MangaApi.fetchChapters(_current);
    } catch (e) {
      if (await _tryAutoSwitch()) return;
      if (!mounted) return;
      setState(() {
        _loadingChapters = false;
        _chaptersError = friendlyError(e);
        _chaptersVerification = MangaVerification.isVerificationError(e);
      });
      return;
    }
    if (chapters.isEmpty && await _tryAutoSwitch()) return;
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _loadingChapters = false;
      _chaptersError = null;
    });
    // Opening the detail re-baselines the 追新 check (M2).
    if (_isFavorite) {
      final counts = {...MangaExtrasStore.loadKnownChapterCounts()};
      counts[_current.storageKey] = chapters.length;
      await MangaExtrasStore.saveKnownChapterCounts(counts);
    }
  }

  Future<void> _toggleFavorite() async {
    final nowFavorite = await MangaLibraryStore.toggleFavorite(
      MangaFavorite(
        id: _current.id,
        title: _current.title,
        coverUrl: _current.coverUrl,
        source: _current.source,
      ),
    );
    if (!mounted) return;
    setState(() => _isFavorite = nowFavorite);
    AnikumoDialog.showToast(message: nowFavorite ? '已收藏' : '已取消收藏');
  }

  void _openReader(int chapterIndex, {int initialPage = 0}) {
    if (_chapters.isEmpty) return;
    context
        .pushNamed(
          '/manga/reader',
          arguments: (
            manga: _current,
            chapters: _chapters,
            chapterIndex: chapterIndex,
            initialPage: initialPage,
          ),
        )
        .then((_) {
      if (!mounted) return;
      setState(() {
        _progress =
        MangaLibraryStore.loadProgressMap()[_current.storageKey];
      });
    });
  }

  void _resume() {
    final progress = _progress;
    if (progress == null || _chapters.isEmpty) {
      if (_chapters.isNotEmpty) _openReader(0);
      return;
    }
    final index =
        _chapters.indexWhere((chapter) => chapter.id == progress.chapterId);
    _openReader(index >= 0 ? index : 0,
        initialPage: index >= 0 ? progress.page : 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manga = _manga;
    final displayedChapters =
        _descending ? _chapters.reversed.toList() : _chapters;
    // Batch 30: cap the eagerly built chapter rows — a
    // 1000+-chapter series used to build every row up front
    // and jank the page open. The rest is one tap away.
    final visibleChapters = _showAllChapters
        ? displayedChapters
        : displayedChapters.take(300).toList();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          0,
          0,
          0,
          StyleString.sectionSpace,
        ),
        children: [
          // ── Immersive hero (batch 38, Violet Glass): blurred
          // cover backdrop fading into the page background,
          // glass round buttons, cover + title overlaid.
          SizedBox(
            height: 264,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Batch 49: boundary — the blurred backdrop
                // rasterizes once, not per scroll frame.
                RepaintBoundary(
                  child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: MangaCover(
                    url: manga.coverUrl,
                    width: MediaQuery.sizeOf(context).width,
                    height: 264,
                    radius: 0,
                    headers: manga.coverHeaders,
                    transformOf: manga.coverTransformOf,
                    transform: coverTransformCallback(manga),
                  ),
                  ),
                ),
                ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        VioletGlass.background(context),
                      ],
                      stops: const [0.45, 1],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: '返回',
                            onPressed: () => context.pop(),
                            icon: const Icon(AnikumoIcons.arrow_back_rounded,
                                color: Colors.white),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _toggleFavorite,
                            icon: Icon(
                              _isFavorite
                                  ? AnikumoIcons.favorite_rounded
                                  : AnikumoIcons.favorite_border_rounded,
                              color: _isFavorite
                                  ? VioletGlass.lavender
                                  : Colors.white,
                            ),
                            tooltip: _isFavorite ? '取消收藏' : '收藏',
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          StyleString.pagePadding,
                          0,
                          StyleString.pagePadding,
                          14,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            MangaCover(
                              url: manga.coverUrl,
                              width: 96,
                              height: 148,
                              radius: 14,
                              headers: manga.coverHeaders,
                              transformOf: manga.coverTransformOf,
                              transform: coverTransformCallback(manga),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    manga.title,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge
                                        ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (manga.author.isNotEmpty)
                                    Text(
                                      '作者：${manga.author}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.white70),
                                    ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (manga.statusLabel.isNotEmpty)
                                        Chip(
                                          label: Text(manga.statusLabel),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ),
                                      if (manga.year != null)
                                        Chip(
                                          label: Text('${manga.year}'),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: StyleString.pagePadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          if (manga.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Batch 90: tags are tappable — a tap opens
                // that tag's manga on this source (previously
                // the chips were inert labels).
                for (final tag in manga.tags.take(10))
                  ActionChip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openTag(tag),
                  ),
              ],
            ),
          ],
          if (manga.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(
                () => _expandedDescription = !_expandedDescription,
              ),
              child: Text(
                manga.description,
                maxLines: _expandedDescription ? null : 4,
                overflow:
                    _expandedDescription ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          ],
          if (_thumbnails.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '内容预览',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _thumbnails.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: _chapters.isEmpty
                      ? null
                      : () => _openReader(0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: _thumbnails[index],
                      cacheManager: mangaPageCacheManager,
                      width: 106,
                      height: 150,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      errorWidget: (context, _, _) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _loadingChapters || _chapters.isEmpty ? null : _resume,
            icon: Icon(
              _progress == null
                  ? AnikumoIcons.menu_book_rounded
                  : AnikumoIcons.play_arrow_rounded,
            ),
            label: Text(
              _progress == null
                  ? '开始阅读'
                  : '继续阅读 · ${_progress!.chapterLabel} 第 ${_progress!.page + 1} 页',
            ),
          ),
          const SizedBox(height: 18),
          _ratingCard(context),
          if (_switchingSource)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '原源不可读，正在自动切换源…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          if (_switchedFromName != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                children: [
                  Icon(
                    AnikumoIcons.swap_horiz_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已从「$_switchedFromName」自动切换到'
                      '「${MangaSources.byId(_current.source)?.name ?? _current.source}」'
                      '（原源无可读章节）',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                '章节（${_chapters.length}）',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                      _descending = !_descending;
                      _showAllChapters = false;
                    }),
                icon: Icon(
                  _descending
                      ? AnikumoIcons.arrow_downward_rounded
                      : AnikumoIcons.arrow_upward_rounded,
                  size: 16,
                ),
                label: Text(_descending ? '最新在前' : '从头看起'),
              ),
            ],
          ),
          if (_loadingChapters)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_chaptersError != null && _chapters.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _chaptersError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (_verificationUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: MangaVerificationButton(
                          url: _verificationUrl!,
                          onSolved: () {
                            setState(() {
                              _loadingChapters = true;
                              _chaptersError = null;
                              _chaptersVerification = false;
                            });
                            _loadChapters();
                          },
                        ),
                      ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _loadingChapters = true;
                          _chaptersError = null;
                          _chaptersVerification = false;
                        });
                        _loadChapters();
                      },
                      child: const Text('章节加载失败，点这里重试'),
                    ),
                  ],
                ),
              ),
            )
          else if (_chapters.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('这个源暂时没有可读的章节')),
            )
          else
            for (final chapter in visibleChapters)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: _progress?.chapterId == chapter.id
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    fontWeight: _progress?.chapterId == chapter.id
                        ? FontWeight.w700
                        : FontWeight.w400,
                    fontSize: 15,
                  ),
                  child: Text(
                    chapter.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                subtitle: chapter.detailSubtitle.isEmpty
                    ? null
                    : Text(chapter.detailSubtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_downloadProgress.containsKey(chapter.id))
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          value: _downloadProgress[chapter.id],
                          strokeWidth: 2.5,
                        ),
                      )
                    else
                      // Batch 104: a local (CBZ-imported) book
                      // already lives on disk — its chapters
                      // ARE downloaded by definition, so the
                      // row shows the done state instead of
                      // offering a download that could only
                      // fail on file:// page urls.
                      Builder(builder: (context) {
                        final downloaded =
                            _current.source == LocalMangaSource.sourceId ||
                                _downloadedKeys.contains(chapter.id);
                        return IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              downloaded
                                  ? AnikumoIcons.download_done_rounded
                                  : AnikumoIcons.download_outlined,
                              key: ValueKey(downloaded),
                              size: 20,
                            ),
                          ),
                          tooltip: downloaded ? '已下载' : '下载本话（离线）',
                          onPressed:
                              downloaded ? null : () => _downloadChapter(chapter),
                        );
                      }),
                    const Icon(AnikumoIcons.chevron_right_rounded),
                  ],
                ),
                onTap: () =>
                    _openReader(_chapters.indexOf(chapter)),
              ),
          if (!_showAllChapters && displayedChapters.length > 300)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '展开全部 ${displayedChapters.length} 章',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
              trailing: const Icon(AnikumoIcons.expand_more),
              onTap: () => setState(() => _showAllChapters = true),
            ),
          if (_pairedAnime.isNotEmpty) ...[
            const SizedBox(height: 22),
            _railTitle('配套动漫'),
            const SizedBox(height: 10),
            SizedBox(
              height: 216,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pairedAnime.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 10),
                itemBuilder: (context, index) => SizedBox(
                  width: 104,
                  child: BangumiCardV(
                    bangumiItem: _pairedAnime[index],
                    canTap: true,
                  ),
                ),
              ),
            ),
          ],
          if (_pairedNovels.isNotEmpty) ...[
            const SizedBox(height: 22),
            _railTitle('配套小说'),
            const SizedBox(height: 10),
            SizedBox(
              height: 218,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pairedNovels.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 10),
                itemBuilder: (context, index) =>
                    NovelRailCard(item: _pairedNovels[index]),
              ),
            ),
          ],
          if (_authorWorks.isNotEmpty) ...[
            const SizedBox(height: 22),
            _railTitle('作者的其他作品'),
            const SizedBox(height: 10),
            SizedBox(
              height: 208,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _authorWorks.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 10),
                itemBuilder: (context, index) => MangaRailCard(
                  item: _authorWorks[index],
                  onTap: () => context.pushNamed(
                    '/manga/detail',
                    arguments: _authorWorks[index],
                  ),
                ),
              ),
            ),
          ],
          if (_tagRecs.isNotEmpty) ...[
            const SizedBox(height: 22),
            _railTitle('你可能还喜欢'),
            const SizedBox(height: 10),
            SizedBox(
              height: 208,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _tagRecs.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 10),
                itemBuilder: (context, index) => MangaRailCard(
                  item: _tagRecs[index],
                  onTap: () => context.pushNamed(
                    '/manga/detail',
                    arguments: _tagRecs[index],
                  ),
                ),
              ),
            ),
          ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  /// Batch 92: companion-rail titles share the zone's
  /// section look — the violet gradient bar used by the
  /// explore/categories tab headers and the home sections —
  /// instead of four bare text styles.
  Widget _railTitle(String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            gradient: VioletGlass.gradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  /// Batch 15 (M4): my rating (half-star steps) + a short note.
  Widget _ratingCard(BuildContext context) {
    final theme = Theme.of(context);
    final stars = _rating?.stars ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 0.6,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '我的评分',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (stars > 0)
                Text(
                  stars.toStringAsFixed(1),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  onTapDown: (details) {
                    // localPosition is relative to this star's
                    // own hit box (~34px wide): left half picks
                    // the half step.
                    final half = details.localPosition.dx < 17;
                    _setStars(half ? i - 0.5 : i.toDouble());
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedScale(
                      scale: stars >= i - 0.5 ? 1.12 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                      stars >= i
                          ? AnikumoIcons.star_rounded
                          : stars >= i - 0.5
                              ? AnikumoIcons.star_half_rounded
                              : AnikumoIcons.star_border_rounded,
                        color: theme.colorScheme.primary,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              if (stars > 0)
                TextButton(
                  onPressed: () => _setStars(0),
                  child: const Text('清除'),
                ),
            ],
          ),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              hintText: '写一句短评（仅本地保存）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: _setNote,
          ),
        ],
      ),
    );
  }

  Future<void> _setStars(double stars) async {
    final rating = MangaRating(
      key: _current.storageKey,
      stars: stars,
      note: _rating?.note ?? '',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await MangaExtrasStore.saveRating(rating);
    if (!mounted) return;
    setState(() => _rating = rating.stars <= 0 && rating.note.isEmpty
        ? null
        : rating);
  }

  Future<void> _setNote(String note) async {
    final rating = MangaRating(
      key: _current.storageKey,
      stars: _rating?.stars ?? 0,
      note: note.trim(),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await MangaExtrasStore.saveRating(rating);
    if (!mounted) return;
    setState(() => _rating = rating.stars <= 0 && rating.note.isEmpty
        ? null
        : rating);
    AnikumoDialog.showToast(message: '短评已保存');
  }
}
