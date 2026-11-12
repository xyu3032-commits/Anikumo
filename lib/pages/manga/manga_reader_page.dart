import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_detail_page.dart';
import 'package:anikumo/services/manga/manga_features.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_extras.dart';
import 'package:anikumo/services/manga/reader_spread.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/reader_chrome_prefs.dart';
import 'package:anikumo/services/manga/manga_image_pipeline.dart';
import 'package:anikumo/services/manga/manga_page_cache.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/storage/cache_budget_trimmer.dart';
import 'package:anikumo/services/manga/reader_settings.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// The manga reader, driven by the Venera-style reading settings:
/// gallery modes left-to-right and right-to-left (RTL), continuous
/// scroll, tap-to-turn with optional reversal, page animation,
/// a page-number chip, auto page turning and keep-screen-on.
class MangaReaderPage extends StatefulWidget {
  const MangaReaderPage({super.key, required this.args});

  final MangaReaderArgs args;

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  // Batch 21: failed pages used to be dead ends (a broken
  // icon forever). Tapping one evicts its cached entry and
  // rebuilds the image under a fresh key.
  // Batch 90: the nonce is per page — retrying one failed
  // page no longer re-keys (and reloads) every page on
  // screen.
  final Map<String, int> _pageRetryNonces = {};

  int _nonceFor(String url) => _pageRetryNonces[url] ?? 0;

  void _retryPage(String url) {
    unawaited(CachedNetworkImage.evictFromCache(url));
    // Batch 112: the reader's images live in the page
    // cache manager, not CachedNetworkImage's default
    // store — evict there too, or a poisoned entry is
    // served again and the retry can never succeed.
    unawaited(mangaPageCacheManager.removeFile(url));
    setState(() => _pageRetryNonces[url] = _nonceFor(url) + 1);
  }

  /// Batch 90: pages that already spent their one automatic
  /// retry in this chapter (see _PageError below). Cleared
  /// whenever a chapter's pages land.
  final Set<String> _autoRetriedUrls = {};

  Widget _pageErrorWidget(String url, double? height) {
    return _PageError(
      height: height,
      canAutoRetry: !_autoRetriedUrls.contains(url),
      onAutoRetry: () {
        _autoRetriedUrls.add(url);
        _retryPage(url);
      },
      onRetry: () => _retryPage(url),
    );
  }

  late final List<MangaChapter> _chapters;
  late int _chapterIndex;
  List<MangaPage> _pages = const [];
  bool _loading = true;
  bool _failed = false;
  bool _overlayVisible = true;

  // Batch 251: chrome auto-hide timer (see _armChromeTimer)
  // and the strip's measured page aspects (see
  // _notePageAspect).
  Timer? _chromeTimer;
  final Map<String, double> _pageAspects = {};
  double _stripFallbackAspect = 1.4;

  // Batch 234: reader-filter pack state + auto-scroll
  // pack state.
  ColorFilter? _readerFilter;
  bool _autoScrolling = false;
  Timer? _autoScrollTimer;

  // Reading settings, (re)read when the settings page closes.
  String _mode = MangaReaderModes.galleryLtr;
  bool _tapToTurn = true;
  bool _reverseTap = false;
  bool _pageAnimation = true;
  bool _showPageNumber = true;
  int _autoPageSeconds = 0;
  bool _wakelockEnabled = false;
  Timer? _autoTimer;
  // Batch 186: scroll-to-load-next-chapter state. The
  // chapter-end button stays (tap to load); reaching the
  // end by scrolling now loads the next chapter too —
  // armed once per chapter so it can never chain-fire.
  bool _autoNextArmed = true;
  Timer? _bottomDwell;
  int _autoElapsed = 0;

  // Batch 15: in-app dim (M11), pinch-zoom lock (M3), reading
  // statistics accumulation (M6) and next-chapter prefetch (M7).
  double _dim = 0;
  bool _showDimPanel = false;
  bool _zoomLocked = false;
  DateTime _statsStamp = DateTime.now();
  int _pendingPages = 0;
  bool _chapterCounted = false;
  // Batch 185: chapter-load ticket — a slow chapter fetch
  // must not land after a newer chapter was requested
  // (the novel reader's batch-30 guard, which this reader
  // never had: fast chapter hops could paint the old
  // chapter's pages under the new chapter's title and
  // record progress against the wrong chapter).
  int _loadTicket = 0;
  final Set<String> _prefetching = {};

  final ValueNotifier<int> _pageNotifier = ValueNotifier<int>(0);
  late final PageController _pageController;
  final ScrollController _scrollController = ScrollController();

  MangaItem get _manga => widget.args.manga;
  MangaChapter get _chapter => _chapters[_chapterIndex];
  int get _page => _pageNotifier.value;
  bool get _isContinuous => _mode == MangaReaderModes.continuous;
  bool get _isRtl => _mode == MangaReaderModes.galleryRtl;

  /// Landscape paged reading shows two-page spreads (batch 14).
  bool _landscape = false;
  bool get _spreadActive => !_isContinuous && _landscape && _pages.length > 1;

  /// Gallery modes lay pages out in display order: RTL reverses
  /// it. In spread mode the unit is a spread, not a page: the
  /// display index addresses spreads and the real page is the
  /// spread's first page.
  int _displayIndexOf(int realPage) {
    if (_spreadActive) {
      final spread = spreadIndexOfPage(realPage);
      final total = spreadCount(_pages.length);
      return _isRtl ? total - 1 - spread : spread;
    }
    return _isRtl ? _pages.length - 1 - realPage : realPage;
  }

  int _realPageOf(int displayIndex) {
    if (_spreadActive) {
      final total = spreadCount(_pages.length);
      final spread = _isRtl ? total - 1 - displayIndex : displayIndex;
      return spreadFirstPage(spread).clamp(0, _pages.length - 1);
    }
    return _isRtl ? _pages.length - 1 - displayIndex : displayIndex;
  }

  /// Batch 51: the framework image cache defaults to
  /// 100MB; a long chapter at full decode width holds more
  /// than that, so late-chapter scrolling kept evicting and
  /// re-decoding pages. The reader raises the ceiling while
  /// it is open and restores it on exit.
  int? _previousImageCacheBytes;

  @override
  void initState() {
    super.initState();
    final imageCache = PaintingBinding.instance.imageCache;
    _previousImageCacheBytes = imageCache.maximumSizeBytes;
    // Batch 145: 256 -> 160 MB while reading. Pages decode
    // width-capped, so ~160 MB still keeps a generous
    // window of pages resident around the reading position;
    // the old cap let a long session hold hundreds of MB of
    // long-past pages in RAM.
    // Batch 239: 160 -> 128 MB in the "less cache" pass;
    // the window around the reading position is unaffected.
    imageCache.maximumSizeBytes = 128 * 1024 * 1024;
    _chapters = widget.args.chapters;
    _chapterIndex = widget.args.chapterIndex;
    _pageController = PageController();
    _pageNotifier.value = widget.args.initialPage;
    _scrollController.addListener(_onScroll);
    _applySettings();
    _autoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_autoPageSeconds <= 0 ||
          _isContinuous ||
          _loading ||
          _pages.isEmpty) {
        return;
      }
      _autoElapsed++;
      if (_autoElapsed >= _autoPageSeconds) {
        _autoElapsed = 0;
        if (_page < _pages.length - 1) {
          _goToRealPage(_page + 1);
        }
      }
    });
    _loadChapter(_chapterIndex, initialPage: widget.args.initialPage);
    _armChromeTimer();
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _autoScrollTimer?.cancel();
    if (_previousImageCacheBytes != null) {
      PaintingBinding.instance.imageCache.maximumSizeBytes =
          _previousImageCacheBytes!;
    }
    // Batch 145: leaving the reader is when the page store
    // has just grown the most — trim it back to its byte
    // budget in the background.
    unawaited(trimMangaPageCache());
    _flushStats();
    _recordProgress(force: true);
    _autoTimer?.cancel();
    _bottomDwell?.cancel();
    if (_wakelockEnabled) {
      WakelockPlus.disable();
    }
    _pageController.dispose();
    _scrollController.dispose();
    _pageNotifier.dispose();
    super.dispose();
  }

  void _applySettings() {
    _mode = normalizeMangaReaderMode(
      GStorage.getSetting(SettingsKeys.mangaReaderMode),
    );
    _tapToTurn = GStorage.getSetting(SettingsKeys.mangaTapToTurn);
    _reverseTap = GStorage.getSetting(SettingsKeys.mangaReverseTap);
    _pageAnimation = GStorage.getSetting(SettingsKeys.mangaPageAnimation);
    _showPageNumber = GStorage.getSetting(SettingsKeys.mangaShowPageNumber);
    _autoPageSeconds = GStorage.getSetting(SettingsKeys.mangaAutoPageSeconds);
    _dim = GStorage.getSetting(SettingsKeys.mangaReaderDim);
    // Batch 234: the filter follows the pack + choice.
    _readerFilter = MangaFeatures.isInstalled(MangaFeatures.readerFiltersId)
        ? MangaReaderFilters.filterFor(
            GStorage.getSetting(SettingsKeys.mangaReaderFilter),
          )
        : null;
    if (!MangaFeatures.isInstalled(MangaFeatures.autoScrollId) &&
        _autoScrolling) {
      _stopAutoScroll();
    }
    final keepOn = GStorage.getSetting(SettingsKeys.mangaKeepScreenOn);
    if (keepOn && !_wakelockEnabled) {
      _wakelockEnabled = true;
      WakelockPlus.enable();
    } else if (!keepOn && _wakelockEnabled) {
      _wakelockEnabled = false;
      WakelockPlus.disable();
    }
  }

  Future<void> _loadChapter(int index, {int initialPage = 0}) async {
    final ticket = ++_loadTicket;
    _autoNextArmed = true;
    _bottomDwell?.cancel();
    _flushStats();
    _chapterCounted = false;
    setState(() {
      _chapterIndex = index;
      _loading = true;
      _failed = false;
    });
    // Batch 15: prefetched page lists and downloaded chapters
    // open instantly, without touching the network.
    final chapter = _chapters[index];
    final cacheKey = ChapterPrefetchCache.keyOf(
      _manga.source,
      _manga.id,
      chapter.id,
    );
    final cached = ChapterPrefetchCache.peek(cacheKey);
    final local =
        cached ??
        await MangaDownloadStore.localPages(
          _manga.source,
          _manga.id,
          chapter.id,
        );
    if (ticket != _loadTicket) return;
    // Batch 27: a throwing page fetch previously bypassed
    // the _failed state entirely — the reader spun forever
    // instead of showing its retry UI.
    List<MangaPage> pages;
    try {
      pages = local ?? await MangaApi.fetchChapterPages(_manga, chapter);
    } catch (_) {
      if (!mounted || ticket != _loadTicket) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    if (!mounted || ticket != _loadTicket) return;
    setState(() {
      _pages = pages;
      _autoRetriedUrls.clear();
      _loading = false;
      _failed = pages.isEmpty;
      _pageNotifier.value = pages.isEmpty
          ? 0
          : initialPage.clamp(0, pages.length - 1);
    });
    _autoElapsed = 0;
    _showChrome();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pages.isEmpty) return;
      _jumpToCurrentPage();
      _precacheAround(_page);
      _probeStripAspectsAround(_page);
      _warmStripDownloads(_page);
    });
    _recordProgress();
  }

  /// Pre-downloads the pages around the current one so page turns
  /// in gallery modes don't wait on the network.
  void _precacheAround(int realPage) {
    if (_pages.isEmpty || !mounted) return;
    // Batch 88: one more page ahead — on slow sources the
    // third page was regularly still in flight when reached,
    // which showed up as a loading stall mid-chapter.
    for (final offset in [1, 2, 3, -1]) {
      final index = realPage + offset;
      if (index < 0 || index >= _pages.length) continue;
      if (_pages[index].url.startsWith('file://')) continue;
      // Batch 102/103: pages with a load spec (transform,
      // modifyImage, fallback) warm their cache through the
      // pipeline instead of the image provider.
      final aroundSpec = mangaPageLoadSpec(
        manga: _manga,
        chapter: _chapter,
        page: _pages[index],
      );
      if (aroundSpec != null) {
        prefetchProcessedImage(
          cacheManager: mangaPageCacheManager,
          spec: aroundSpec,
        );
        continue;
      }
      precacheImage(
        CachedNetworkImageProvider(
          _pages[index].url,
          headers: _pages[index].headers,
          // Batch 192: warm the decode size the current
          // mode will actually request (the image cache
          // keys on it), or the precache misses.
          maxWidth: _isContinuous ? _stripDecodeWidth : _decodeWidth,
          cacheManager: mangaPageCacheManager,
        ),
        context,
      ).ignore();
    }
  }

  void _jumpToCurrentPage() {
    if (_isContinuous) {
      if (_scrollController.hasClients && _pages.length > 1) {
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(
          stripOffsetForPage(_page, _stripWidth(context)).clamp(0.0, max),
        );
      }
    } else if (_pageController.hasClients) {
      _pageController.jumpToPage(_displayIndexOf(_page));
    }
  }

  void _goToRealPage(int realPage) {
    if (_pages.isEmpty) return;
    _pokeChrome();
    final target = realPage.clamp(0, _pages.length - 1);
    _autoElapsed = 0;
    if (_isContinuous) {
      if (_scrollController.hasClients && _pages.length > 1) {
        final max = _scrollController.position.maxScrollExtent;
        final offset = stripOffsetForPage(
          target,
          _stripWidth(context),
        ).clamp(0.0, max);
        if (_pageAnimation) {
          _scrollController.animateTo(
            offset,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(offset);
        }
      }
      _pageNotifier.value = target;
      _recordProgress();
      return;
    }
    final display = _displayIndexOf(target);
    if (_pageAnimation) {
      _pageController.animateToPage(
        display,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _pageController.jumpToPage(display);
    }
  }

  /// Batch 15 (M6/M7): page-turn bookkeeping — statistics
  /// accumulation, chapter-finished detection and the 70%
  /// next-chapter prefetch trigger.
  void _onPageTurned() {
    _pendingPages++;
    if (_pages.isNotEmpty && _page >= _pages.length - 1 && !_chapterCounted) {
      _chapterCounted = true;
      MangaStatsStore.recordChapterFinished();
    }
    _maybePrefetchNext();
    final now = DateTime.now();
    if (now.difference(_statsStamp).inSeconds >= 30) _flushStats();
  }

  void _flushStats() {
    final now = DateTime.now();
    final seconds = now.difference(_statsStamp).inSeconds;
    _statsStamp = now;
    if (_pendingPages > 0) {
      MangaStatsStore.recordPages(_pendingPages);
      _pendingPages = 0;
    }
    if (seconds > 0) MangaStatsStore.recordSeconds(seconds, now);
  }

  Future<void> _maybePrefetchNext() async {
    if (_pages.isEmpty) return;
    if (_page < (_pages.length * 0.7).floor()) return;
    final nextIndex = _chapterIndex + 1;
    if (nextIndex >= _chapters.length) return;
    final next = _chapters[nextIndex];
    // Batch 234 （深度预读 pack): also warm the chapter
    // after next, so a three-chapter run never waits at a
    // boundary.
    if (MangaFeatures.isInstalled(MangaFeatures.deepPrefetchId)) {
      final deepIndex = nextIndex + 1;
      if (deepIndex < _chapters.length) {
        unawaited(_prefetchChapterAt(deepIndex));
      }
    }
    final key = ChapterPrefetchCache.keyOf(_manga.source, _manga.id, next.id);
    if (ChapterPrefetchCache.peek(key) != null) return;
    if (!_prefetching.add(key)) return;
    final downloaded = await MangaDownloadStore.localPages(
      _manga.source,
      _manga.id,
      next.id,
    );
    if (downloaded != null) return;
    final pages = await MangaApi.fetchChapterPages(_manga, next);
    if (pages.isEmpty) return;
    ChapterPrefetchCache.put(key, pages);
    if (!mounted) return;
    for (final page in pages.take(2)) {
      if (page.url.startsWith('file://')) continue;
      // Batch 102/103: same spec warm-up for the next
      // chapter's first pages.
      final nextSpec = mangaPageLoadSpec(
        manga: _manga,
        chapter: next,
        page: page,
      );
      if (nextSpec != null) {
        prefetchProcessedImage(
          cacheManager: mangaPageCacheManager,
          spec: nextSpec,
        );
        continue;
      }
      precacheImage(
        CachedNetworkImageProvider(
          page.url,
          headers: page.headers,
          maxWidth: _decodeWidth,
          cacheManager: mangaPageCacheManager,
        ),
        context,
      ).ignore();
    }
  }

  /// Batch 234 （深度预读 pack): the page-list + first-pages
  /// warm-up for an arbitrary chapter index (used for the
  /// chapter after next; the next chapter itself keeps
  /// the original path above).
  Future<void> _prefetchChapterAt(int index) async {
    final chapter = _chapters[index];
    final key = ChapterPrefetchCache.keyOf(
      _manga.source,
      _manga.id,
      chapter.id,
    );
    if (ChapterPrefetchCache.peek(key) != null) return;
    if (!_prefetching.add(key)) return;
    try {
      final downloaded = await MangaDownloadStore.localPages(
        _manga.source,
        _manga.id,
        chapter.id,
      );
      if (downloaded != null) return;
      final pages = await MangaApi.fetchChapterPages(_manga, chapter);
      if (pages.isEmpty) return;
      ChapterPrefetchCache.put(key, pages);
      if (!mounted) return;
      for (final page in pages.take(2)) {
        if (page.url.startsWith('file://')) continue;
        final spec = mangaPageLoadSpec(
          manga: _manga,
          chapter: chapter,
          page: page,
        );
        if (spec != null) {
          prefetchProcessedImage(
            cacheManager: mangaPageCacheManager,
            spec: spec,
          );
          continue;
        }
        precacheImage(
          CachedNetworkImageProvider(
            page.url,
            headers: page.headers,
            maxWidth: _decodeWidth,
            cacheManager: mangaPageCacheManager,
          ),
          context,
        ).ignore();
      }
    } catch (_) {
      // Prefetch is speculative; failures stay silent.
    } finally {
      _prefetching.remove(key);
    }
  }

  /// Batch 16: page images used to decode at full original
  /// resolution (multi-megapixel) — the reader's biggest memory
  /// and jank cost. Decode at display width instead (capped;
  /// tighter under SmoothMode).
  int get _decodeWidth {
    final mq = MediaQuery.of(context);
    var width = (mq.size.width * mq.devicePixelRatio).round();
    if (SmoothMode.notifier.value) width = width.clamp(320, 900);
    return width.clamp(320, 1600);
  }

  /// Batch 192: strip (continuous) mode never pinch-zooms
  /// a single page, so its pages decode tighter than the
  /// paged modes'. At the 1600px cap a tall page is a
  /// ~30MB bitmap and the cache extent holds several —
  /// on mid-range phones that memory churn is the scroll
  /// jank. Paged modes keep the sharper cap for zooming.
  int get _stripDecodeWidth {
    final mq = MediaQuery.of(context);
    var width = (mq.size.width * mq.devicePixelRatio).round();
    if (SmoothMode.notifier.value) width = width.clamp(320, 900);
    return width.clamp(320, 1200);
  }

  int _lastRecordedPage = -1;
  String _lastRecordedChapter = '';
  DateTime _lastRecordedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Progress writes re-encode the whole library JSON; during
  /// continuous scrolling this fired per estimated page change.
  /// Coalesce: persist on chapter change, every 3 pages, every
  /// 5 seconds, or when forced (dispose).
  void _recordProgress({bool force = false}) {
    if (_pages.isEmpty) return;
    final now = DateTime.now();
    final due =
        force ||
        _chapter.id != _lastRecordedChapter ||
        (_page - _lastRecordedPage).abs() >= 3 ||
        now.difference(_lastRecordedAt) >= const Duration(seconds: 5);
    if (!due) return;
    _lastRecordedPage = _page;
    _lastRecordedChapter = _chapter.id;
    _lastRecordedAt = now;
    MangaLibraryStore.recordProgress(
      MangaProgress(
        mangaId: _manga.id,
        mangaTitle: _manga.title,
        coverUrl: _manga.coverUrl,
        chapterId: _chapter.id,
        chapterLabel: _chapter.displayLabel,
        page: _page,
        totalPages: _pages.length,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        mangaSource: _manga.source,
      ),
    );
  }

  // Batch 251: the reader chrome used to stay on screen
  // until the next tap, so most reading happened with the
  // bars up. It now fades by itself: visible on entry and
  // whenever the user calls it up, hidden again after a
  // few idle seconds. Scrolling and page turns restart
  // the countdown while it is visible (auto-scroll's own
  // ticks do not — the reader is meant to disappear under
  // the reader's eye, not stay up for the whole chapter).
  // The system bars follow the chrome (immersive while
  // hidden), restored on exit.
  // Batch 252: the idle delay is the user's
  // readerChromeHideSeconds preference now (0.5–5 s,
  // default 1.5), read live in _armChromeTimer.

  void _armChromeTimer() {
    _chromeTimer?.cancel();
    if (!_overlayVisible) return;
    _chromeTimer = Timer(readerChromeHideDelay(), () {
      if (!mounted || !_overlayVisible) return;
      setState(() => _overlayVisible = false);
      _syncSystemUi();
    });
  }

  void _toggleOverlay() {
    setState(() => _overlayVisible = !_overlayVisible);
    _syncSystemUi();
    _armChromeTimer();
  }

  void _showChrome() {
    if (!_overlayVisible) {
      setState(() => _overlayVisible = true);
      _syncSystemUi();
    }
    _armChromeTimer();
  }

  void _pokeChrome() {
    if (_overlayVisible) _armChromeTimer();
  }

  void _syncSystemUi() {
    SystemChrome.setEnabledSystemUIMode(
      _overlayVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  // Batch 251 (strip smoothness): remember every page's
  // measured aspect ratio. Placeholders for unmeasured
  // pages use the chapter's running median instead of a
  // flat 1.4 guess, and the scroll-position <-> page
  // mapping sums measured heights instead of assuming
  // all pages are equally tall — the old proportional
  // estimate drifted further with every page that
  // finished loading at a different height, which read
  // as worsening judder over a long reading session.
  void _notePageAspect(String url, double aspect) {
    if (aspect <= 0 || !aspect.isFinite) return;
    if (_pageAspects[url] == aspect) return;
    _pageAspects[url] = aspect;
    if (_pageAspects.length > 800) {
      for (final key in _pageAspects.keys.take(200).toList()) {
        _pageAspects.remove(key);
      }
    }
    final known = [
      for (final page in _pages)
        if (_pageAspects[page.url] != null) _pageAspects[page.url]!,
    ]..sort();
    if (known.isNotEmpty) {
      _stripFallbackAspect = known[known.length ~/ 2];
    }
  }

  double _stripPageHeight(String url, double width) =>
      width * (_pageAspects[url] ?? _stripFallbackAspect);

  double _stripWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return screenWidth > 640 ? 640.0 : screenWidth;
  }

  /// Scroll offset where [page] starts, from measured
  /// page heights (fallback aspect for unmeasured ones).
  double stripOffsetForPage(int page, double width) => stripOffsetForPageIn(
    [for (final p in _pages) p.url],
    _pageAspects,
    _stripFallbackAspect,
    page,
    width,
  );

  /// The page under the reading line (viewport middle)
  /// at [offset], from measured page heights.
  int stripPageAtOffset(double offset, double width, double viewportHeight) =>
      stripPageAtOffsetIn(
        [for (final p in _pages) p.url],
        _pageAspects,
        _stripFallbackAspect,
        offset,
        width,
        viewportHeight,
      );

  final Set<String> _aspectProbesInFlight = {};

  /// Batch 252: URLs whose bytes this session already
  /// warmed (or is warming) for the strip download-ahead.
  final Set<String> _warmedStripUrls = {};

  /// Batch 252: pull the BYTES of the pages beyond the
  /// aspect probe's decode window (probe covers +6)
  /// into the page cache, so a steady scroll on a slow
  /// source stops outrunning the network — the widget
  /// then reads from disk instead of waiting on a
  /// download that only started when it scrolled in.
  /// Bytes only, no decode; failures are silent (the
  /// widget retries on its own when it gets there).
  void _warmStripDownloads(int fromPage) {
    if (!_isContinuous || !mounted || _pages.isEmpty) return;
    for (var i = fromPage + 6; i < _pages.length && i < fromPage + 14; i++) {
      final page = _pages[i];
      final url = page.url;
      if (url.startsWith('file://')) continue;
      if (!_warmedStripUrls.add(url)) continue;
      if (_warmedStripUrls.length > 800) {
        _warmedStripUrls.removeAll(_warmedStripUrls.take(200).toList());
      }
      final spec = mangaPageLoadSpec(
        manga: _manga,
        chapter: _chapter,
        page: page,
      );
      unawaited(() async {
        try {
          if (spec != null) {
            await loadProcessedImageBytes(
              cacheManager: mangaPageCacheManager,
              spec: spec,
            );
          } else {
            await mangaPageCacheManager.getSingleFile(
              url,
              headers: page.headers,
            );
          }
        } catch (_) {
          // Silent: the page widget loads it for real
          // when it scrolls into view.
        }
      }());
    }
  }

  /// Measure the pages just ahead of the reading position
  /// (decode only — the bytes land in the same caches the
  /// widgets read from), so their placeholders are sized
  /// correctly before they scroll into view.
  void _probeStripAspectsAround(int fromPage) {
    if (!_isContinuous || !mounted || _pages.isEmpty) return;
    for (var i = fromPage; i < _pages.length && i < fromPage + 6; i++) {
      final page = _pages[i];
      final url = page.url;
      if (_pageAspects.containsKey(url) || url.startsWith('file://')) {
        continue;
      }
      if (!_aspectProbesInFlight.add(url)) continue;
      final spec = mangaPageLoadSpec(
        manga: _manga,
        chapter: _chapter,
        page: page,
      );
      unawaited(() async {
        try {
          double aspect;
          if (spec != null) {
            final bytes = await loadProcessedImageBytes(
              cacheManager: mangaPageCacheManager,
              spec: spec,
            );
            final codec = await ui.instantiateImageCodec(bytes);
            final frame = await codec.getNextFrame();
            aspect = frame.image.height / frame.image.width;
            frame.image.dispose();
            codec.dispose();
          } else {
            final provider = ResizeImage(
              CachedNetworkImageProvider(
                url,
                headers: page.headers,
                cacheManager: mangaPageCacheManager,
              ),
              width: _stripDecodeWidth,
            );
            final completer = Completer<ImageInfo>();
            final stream = provider.resolve(ImageConfiguration.empty);
            late final ImageStreamListener listener;
            listener = ImageStreamListener(
              (info, _) {
                stream.removeListener(listener);
                if (!completer.isCompleted) completer.complete(info);
              },
              onError: (error, _) {
                stream.removeListener(listener);
                if (!completer.isCompleted) {
                  completer.completeError(error);
                }
              },
            );
            stream.addListener(listener);
            final info = await completer.future;
            aspect = info.image.height / info.image.width;
            info.image.dispose();
          }
          if (mounted) _notePageAspect(url, aspect);
        } catch (_) {
          // A failed probe just leaves the fallback aspect.
        } finally {
          _aspectProbesInFlight.remove(url);
        }
      }());
    }
  }

  void _onScroll() {
    if (!_isContinuous || _pages.isEmpty || !_scrollController.hasClients) {
      return;
    }
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    // Batch 186: resting at the very bottom of a chapter
    // loads the next one (the pull-past-the-end gesture
    // fires it immediately via the overscroll handler).
    // The dwell keeps a fast flick that merely passes the
    // end from triggering it.
    final nearBottom = _scrollController.position.pixels >= max - 240;
    if (nearBottom && _autoNextArmed && !_loading) {
      _bottomDwell ??= Timer(const Duration(milliseconds: 600), () {
        _bottomDwell = null;
        if (!mounted || !_scrollController.hasClients) return;
        final m = _scrollController.position.maxScrollExtent;
        if (_scrollController.position.pixels >= m - 240) {
          _maybeAutoNextChapter();
        }
      });
    } else if (!nearBottom) {
      _bottomDwell?.cancel();
      _bottomDwell = null;
    }
    if (!_autoScrolling) _pokeChrome();
    final clamped = stripPageAtOffset(
      _scrollController.offset,
      _stripWidth(context),
      _scrollController.position.viewportDimension,
    );
    if (clamped != _page) {
      _pageNotifier.value = clamped;
      _recordProgress();
      _onPageTurned();
      _probeStripAspectsAround(clamped);
      _warmStripDownloads(clamped);
    }
  }

  /// Batch 186: fires the next-chapter load at most once
  /// per chapter, only when a next chapter exists.
  void _maybeAutoNextChapter() {
    if (!_autoNextArmed || _loading || _pages.isEmpty) return;
    if (_chapterIndex >= _chapters.length - 1) return;
    _autoNextArmed = false;
    _bottomDwell?.cancel();
    _nextChapter();
  }

  /// Whether the paged view sits on its last display unit
  /// (in RTL the reading end is display index 0).
  bool get _atReadingEnd {
    if (_pages.isEmpty) return false;
    final count = _spreadActive ? spreadCount(_pages.length) : _pages.length;
    final display = _displayIndexOf(_page);
    return _isRtl ? display <= 0 : display >= count - 1;
  }

  void _nextChapter() {
    if (_chapterIndex >= _chapters.length - 1) {
      AnikumoDialog.showToast(message: '已经是最后一话了');
      return;
    }
    _loadChapter(_chapterIndex + 1);
  }

  void _prevChapter() {
    if (_chapterIndex <= 0) {
      AnikumoDialog.showToast(message: '已经是第一话了');
      return;
    }
    _loadChapter(_chapterIndex - 1);
  }

  void _forward() {
    final step = _spreadActive ? 2 : 1;
    if (_page < _pages.length - 1) {
      _goToRealPage(_page + step);
    } else {
      _nextChapter();
    }
  }

  void _backward() {
    final step = _spreadActive ? 2 : 1;
    if (_page > 0) {
      _goToRealPage(_page - step);
    } else {
      _prevChapter();
    }
  }

  void _handlePagedTap(TapUpDetails details) {
    if (!_tapToTurn) {
      _toggleOverlay();
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    final dx = details.localPosition.dx;
    if (dx > width / 3 && dx < width * 2 / 3) {
      _toggleOverlay();
      return;
    }
    // Forward sits on the right for LTR, on the left for RTL;
    // the reverse-tap setting flips it again.
    final forwardOnRight = (!_isRtl) ^ _reverseTap;
    final tappedRight = dx >= width * 2 / 3;
    if (tappedRight == forwardOnRight) {
      _forward();
    } else {
      _backward();
    }
  }

  Widget _pageImage(int realIndex) {
    final page = _pages[realIndex];
    // Batch 103: the page's load spec (transform / modify /
    // fallback), or null for the ordinary provider path.
    final spec = mangaPageLoadSpec(
      manga: _manga,
      chapter: _chapter,
      page: page,
    );
    Widget image;
    if (page.url.startsWith('file://')) {
      // Downloaded chapter (M1): render from disk.
      image = Image.file(
        File(Uri.parse(page.url).toFilePath()),
        fit: BoxFit.contain,
        cacheWidth: _decodeWidth,
        gaplessPlayback: true,
        errorBuilder: (context, _, _) => const Center(
          child: Icon(
            AnikumoIcons.broken_image_outlined,
            color: Colors.white54,
          ),
        ),
      );
    } else if (spec != null) {
      // Batch 102/103: pages the pipeline must process
      // (onResponse transform, modifyImage edit) or rescue
      // (onLoadFailed fallback) before they can display.
      image = MangaTransformedImage(
        key: ValueKey('${page.url}#${_nonceFor(page.url)}'),
        url: page.url,
        headers: page.headers,
        cacheManager: mangaPageCacheManager,
        spec: spec,
        memCacheWidth: _decodeWidth,
        fit: BoxFit.contain,
        placeholder: const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
        errorWidget: _pageErrorWidget(page.url, null),
      );
    } else {
      image = CachedNetworkImage(
        key: ValueKey('${page.url}#${_nonceFor(page.url)}'),
        imageUrl: page.url,
        httpHeaders: page.headers,
        cacheManager: mangaPageCacheManager,
        memCacheWidth: _decodeWidth,
        fit: BoxFit.contain,
        // Batch 88: same anti-flash settings as the
        // continuous strip (no fade from black, keep the
        // old frame while a re-resolution is in flight).
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        useOldImageOnUrlChange: true,
        placeholder: (context, _) => const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
        errorWidget: (context, _, _) => _pageErrorWidget(page.url, null),
      );
    }
    if (_isContinuous) return _filtered(image);
    // Pinch zoom (M3): pan/pinch on the page; while zoomed the
    // PageView stops swiping so panning the page wins.
    return _ZoomablePage(
      onZoomLockChanged: (locked) {
        if (locked != _zoomLocked && mounted) {
          setState(() => _zoomLocked = locked);
        }
      },
      child: _filtered(image),
    );
  }

  /// Batch 234 （阅读滤镜 pack): wraps a page image in
  /// the active filter, or returns it untouched.
  Widget _filtered(Widget child) => _readerFilter == null
      ? child
      : ColorFiltered(colorFilter: _readerFilter!, child: child);

  /// Batch 234 （自动滚动 pack): start/stop the continuous
  /// mode auto-scroll. The timer nudges the strip's scroll
  /// position at the configured speed and stops at the
  /// end of the chapter.
  void _toggleAutoScroll() {
    if (_autoScrolling) {
      _stopAutoScroll();
      return;
    }
    if (!_scrollController.hasClients) return;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || !_scrollController.hasClients) {
        _stopAutoScroll();
        return;
      }
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - 1) {
        _stopAutoScroll();
        return;
      }
      // Batch 251: the speed is read per tick, so the
      // in-reader speed control (and the settings page)
      // retunes a RUNNING scroll immediately instead of
      // only the next start.
      final speed = GStorage.getSetting(
        SettingsKeys.mangaAutoScrollSpeed,
      ).toDouble();
      _scrollController.jumpTo(
        (position.pixels + speed * 0.05).clamp(0.0, position.maxScrollExtent),
      );
    });
    setState(() => _autoScrolling = true);
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (_autoScrolling && mounted) {
      setState(() => _autoScrolling = false);
    } else {
      _autoScrolling = false;
    }
  }

  /// Batch 251: feature settings live next to the
  /// feature's own control. The auto-scroll speed used to
  /// exist only on the settings page — using the feature
  /// meant leaving the reader to tune it. This sheet is
  /// the feature's own settings button: same key, same
  /// range as the settings page, applied live.
  Future<void> _showAutoScrollSpeedSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final speed = GStorage.getSetting(SettingsKeys.mangaAutoScrollSpeed);
          final theme = Theme.of(context);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('自动滚动速度', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '$speed 像素/秒 · 调整立即生效',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  Slider(
                    value: speed.toDouble(),
                    min: 20,
                    // Batch 252: same 1500 px/s top as
                    // the settings page.
                    max: 1500,
                    divisions: 148,
                    label: '$speed',
                    onChanged: (value) {
                      GStorage.putSetting(
                        SettingsKeys.mangaAutoScrollSpeed,
                        value.round(),
                      );
                      setSheetState(() {});
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('慢', style: theme.textTheme.bodySmall),
                      Text('快', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    _pokeChrome();
  }

  void _openSettings() {
    context.pushNamed('/manga/settings').then((_) {
      if (!mounted) return;
      setState(_applySettings);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.isNotEmpty) _jumpToCurrentPage();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (landscape != _landscape) {
      _landscape = landscape;
      // The display-index math changes with orientation (spread
      // on/off); re-anchor on the current page next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToCurrentPage();
      });
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildContent()),
          if (_dim > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: _dim)),
              ),
            ),
          if (_showPageNumber && !_loading && _pages.isNotEmpty)
            Positioned(
              right: 12,
              bottom: 12,
              child: ValueListenableBuilder<int>(
                valueListenable: _pageNotifier,
                builder: (context, page, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 120),
                      child: Text(
                        '${page + 1} / ${_pages.length}',
                        key: ValueKey(page),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_overlayVisible) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFB7A6FF).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          AnikumoIcons.arrow_back,
                          color: Colors.white,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _manga.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _chapter.displayLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => _showDimPanel = !_showDimPanel),
                        icon: const Icon(
                          AnikumoIcons.brightness_6_rounded,
                          color: Colors.white,
                        ),
                        tooltip: '亮度遮罩',
                      ),
                      IconButton(
                        onPressed: _openSettings,
                        icon: const Icon(
                          AnikumoIcons.tune_rounded,
                          color: Colors.white,
                        ),
                        tooltip: '阅读设置',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_showDimPanel)
              Positioned(
                bottom: 76,
                left: 16,
                right: 16,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        const Icon(
                          AnikumoIcons.brightness_low_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        Expanded(
                          child: Slider(
                            value: _dim,
                            min: 0,
                            max: 0.7,
                            onChanged: (value) => setState(() => _dim = value),
                            onChangeEnd: (value) => GStorage.putSetting(
                              SettingsKeys.mangaReaderDim,
                              value,
                            ),
                          ),
                        ),
                        const Icon(
                          AnikumoIcons.brightness_high_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFB7A6FF).withValues(alpha: 0.25),
                    ),
                  ),
                  child: ValueListenableBuilder<int>(
                    valueListenable: _pageNotifier,
                    builder: (context, page, _) {
                      return Row(
                        children: [
                          IconButton(
                            onPressed: _prevChapter,
                            icon: const Icon(
                              AnikumoIcons.skip_previous,
                              color: Colors.white,
                            ),
                            tooltip: '上一话',
                          ),
                          Expanded(
                            child: _isContinuous
                                ? Text(
                                    '第 ${page + 1} / ${_pages.length} 页（滚动）',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : Slider(
                                    value: _pages.isEmpty ? 0 : page.toDouble(),
                                    min: 0,
                                    max: _pages.isEmpty
                                        ? 0
                                        : (_pages.length - 1).toDouble(),
                                    onChanged: _pages.isEmpty
                                        ? null
                                        : (value) =>
                                              _goToRealPage(value.round()),
                                  ),
                          ),
                          if (!_isContinuous)
                            Text(
                              '${page + 1} / ${_pages.length}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          IconButton(
                            onPressed: _nextChapter,
                            icon: const Icon(
                              AnikumoIcons.skip_next,
                              color: Colors.white,
                            ),
                            tooltip: '下一话',
                          ),
                          if (_isContinuous &&
                              MangaFeatures.isInstalled(
                                MangaFeatures.autoScrollId,
                              ))
                            IconButton(
                              onPressed: _toggleAutoScroll,
                              icon: Icon(
                                _autoScrolling
                                    ? AnikumoIcons.pause_rounded
                                    : AnikumoIcons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                              tooltip: _autoScrolling ? '停止自动滚动' : '自动滚动',
                            ),
                          if (_isContinuous &&
                              MangaFeatures.isInstalled(
                                MangaFeatures.autoScrollId,
                              ))
                            IconButton(
                              onPressed: _showAutoScrollSpeedSheet,
                              icon: const Icon(
                                AnikumoIcons.speed_rounded,
                                color: Colors.white,
                              ),
                              tooltip: '自动滚动速度',
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      // Batch 188: name the chapter being loaded. A bare
      // spinner on black read as a frozen black screen
      // when a chapter switch took a while.
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(_chapter.title, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('这一话加载失败', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _loadChapter(_chapterIndex),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_isContinuous) {
      return GestureDetector(
        onTapDown: (_) {
          if (_autoScrolling) _stopAutoScroll();
        },
        onTap: _toggleOverlay,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // Batch 186: pulling past the last page is a
            // deliberate "give me the next chapter".
            if (notification is OverscrollNotification &&
                notification.overscroll > 0) {
              _maybeAutoNextChapter();
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            // Batch 88: a taller cache extent keeps pages that
            // just scrolled off alive a little longer, so a
            // small scroll back doesn't rebuild (and re-flash)
            // them.
            scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
            itemCount: _pages.length + 1,
            itemBuilder: (context, index) {
              if (index == _pages.length) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: FilledButton(
                        onPressed: _nextChapter,
                        child: const Text('下一话'),
                      ),
                    ),
                  ),
                );
              }
              // Batch 73: in landscape the strip no longer
              // stretches edge to edge — pages stay at a
              // readable width and sit centered. Portrait
              // widths are below the cap and unchanged.
              final screenWidth = MediaQuery.sizeOf(context).width;
              final width = screenWidth > 640 ? 640.0 : screenWidth;
              final stripPage = _pages[index];
              // Batch 251: reserve the page's measured
              // height (or the chapter median) while it
              // loads — a flat 1.4 guess snapped to the
              // real height on every arrival.
              final stripHeight = _stripPageHeight(stripPage.url, width);
              final stripSpec = mangaPageLoadSpec(
                manga: _manga,
                chapter: _chapter,
                page: stripPage,
              );
              return RepaintBoundary(
                child: Center(
                  child: _filtered(
                    stripSpec != null
                        // Batch 102/103: pipeline pages in the strip
                        // (see _pageImage).
                        ? MangaTransformedImage(
                            key: ValueKey(
                              '${stripPage.url}#${_nonceFor(stripPage.url)}',
                            ),
                            url: stripPage.url,
                            headers: stripPage.headers,
                            cacheManager: mangaPageCacheManager,
                            spec: stripSpec,
                            width: width,
                            memCacheWidth: _stripDecodeWidth,
                            fit: BoxFit.fitWidth,
                            placeholder: SizedBox(
                              width: width,
                              height: stripHeight,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            errorWidget: _pageErrorWidget(
                              stripPage.url,
                              stripHeight,
                            ),
                          )
                        : CachedNetworkImage(
                            key: ValueKey(
                              '${_pages[index].url}#${_nonceFor(_pages[index].url)}',
                            ),
                            imageUrl: _pages[index].url,
                            httpHeaders: _pages[index].headers,
                            cacheManager: mangaPageCacheManager,
                            width: width,
                            memCacheWidth: _stripDecodeWidth,
                            fit: BoxFit.fitWidth,
                            // Batch 88: no fade-in here. The default 500ms
                            // fade cross-fades FROM the transparent
                            // placeholder — i.e. from the black scaffold —
                            // so every page entering during a scroll flashed
                            // as a black bar that then "disappeared".
                            // Keeping the old frame on re-resolution stops
                            // the same flash when an item is rebuilt.
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            useOldImageOnUrlChange: true,
                            placeholder: (context, _) => SizedBox(
                              width: width,
                              height: stripHeight,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            errorWidget: (context, _, _) => _pageErrorWidget(
                              _pages[index].url,
                              stripHeight,
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Batch 186: swiping past the last page loads the
        // next chapter (the tap zones already did). The
        // reading-end edge flips with direction: trailing
        // in LTR, leading in RTL.
        if (notification is OverscrollNotification &&
            _atReadingEnd &&
            ((_isRtl && notification.overscroll < 0) ||
                (!_isRtl && notification.overscroll > 0))) {
          _maybeAutoNextChapter();
        }
        return false;
      },
      child: PageView.builder(
        controller: _pageController,
        physics: _zoomLocked ? const NeverScrollableScrollPhysics() : null,
        itemCount: _spreadActive ? spreadCount(_pages.length) : _pages.length,
        onPageChanged: (displayIndex) {
          _pageNotifier.value = _realPageOf(displayIndex);
          _autoElapsed = 0;
          _recordProgress();
          _precacheAround(_page);
          _onPageTurned();
        },
        itemBuilder: (context, displayIndex) {
          if (_spreadActive) {
            final total = spreadCount(_pages.length);
            final spread = _isRtl ? total - 1 - displayIndex : displayIndex;
            final visual = spreadVisualPages(
              spread,
              _pages.length,
              rtl: _isRtl,
            );
            return GestureDetector(
              onTapUp: _handlePagedTap,
              child: Row(
                children: [
                  for (final realIndex in visual)
                    Expanded(child: _pageImage(realIndex)),
                ],
              ),
            );
          }
          final realIndex = _realPageOf(displayIndex);
          return GestureDetector(
            onTapUp: _handlePagedTap,
            child: _pageImage(realIndex),
          );
        },
      ),
    );
  }
}

/// Batch 90: a failed page's error tile. When an automatic
/// retry is still available it shows a brief "retrying"
/// state and fires that retry once after a short delay —
/// transient CDN drops (a reset connection, a rate-limit
/// blip while neighbouring pages prefetch) used to leave a
/// dead tile until the user noticed and tapped it. Once
/// the automatic attempt is spent, the tile is the classic
/// tap-to-retry.
class _PageError extends StatefulWidget {
  const _PageError({
    required this.height,
    required this.canAutoRetry,
    required this.onAutoRetry,
    required this.onRetry,
  });

  final double? height;
  final bool canAutoRetry;
  final VoidCallback onAutoRetry;
  final VoidCallback onRetry;

  @override
  State<_PageError> createState() => _PageErrorState();
}

class _PageErrorState extends State<_PageError> {
  Timer? _timer;
  bool _autoFired = false;

  @override
  void initState() {
    super.initState();
    if (widget.canAutoRetry) {
      _timer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        setState(() => _autoFired = true);
        widget.onAutoRetry();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.canAutoRetry && !_autoFired) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white54),
              SizedBox(height: 8),
              Text(
                '加载失败，自动重试中…',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: widget.onRetry,
      child: SizedBox(
        height: widget.height,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AnikumoIcons.broken_image_outlined, color: Colors.white54),
              SizedBox(height: 8),
              Text(
                '加载失败，点按重试',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinch-zoom wrapper for one reader page (batch 15, M3).
/// Reports zoom state upward so the PageView can stop swiping
/// while the user pans a zoomed page.
class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({required this.child, required this.onZoomLockChanged});

  final Widget child;
  final void Function(bool locked) onZoomLockChanged;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _controller = TransformationController();
  bool _locked = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onInteraction() {
    final scale = _controller.value.getMaxScaleOnAxis();
    final locked = scale > 1.02;
    if (locked != _locked) {
      _locked = locked;
      widget.onZoomLockChanged(locked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return InteractiveViewer(
          transformationController: _controller,
          minScale: 1,
          maxScale: 4,
          onInteractionUpdate: (_) => _onInteraction(),
          onInteractionEnd: (_) => _onInteraction(),
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Batch 251: strip geometry over measured page aspects
/// (pure; the reader state delegates). [urls] are the
/// chapter's pages in order; a url missing from
/// [aspects] uses [fallbackAspect].
double stripOffsetForPageIn(
  List<String> urls,
  Map<String, double> aspects,
  double fallbackAspect,
  int page,
  double width,
) {
  var sum = 0.0;
  final end = page.clamp(0, urls.length);
  for (var i = 0; i < end; i++) {
    sum += width * (aspects[urls[i]] ?? fallbackAspect);
  }
  return sum;
}

/// The page under the reading line (viewport middle) at
/// [offset]; the last page when the line runs past the
/// end, 0 for an empty chapter.
int stripPageAtOffsetIn(
  List<String> urls,
  Map<String, double> aspects,
  double fallbackAspect,
  double offset,
  double width,
  double viewportHeight,
) {
  if (urls.isEmpty) return 0;
  final line = offset + viewportHeight * 0.5;
  var acc = 0.0;
  for (var i = 0; i < urls.length; i++) {
    acc += width * (aspects[urls[i]] ?? fallbackAspect);
    if (line < acc) return i;
  }
  return urls.length - 1;
}
