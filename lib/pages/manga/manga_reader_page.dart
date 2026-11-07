import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_detail_page.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_extras.dart';
import 'package:anikumo/services/manga/reader_spread.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_page_cache.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/manga/reader_settings.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  int _pageRetryNonce = 0;

  void _retryPage(String url) {
    unawaited(CachedNetworkImage.evictFromCache(url));
    setState(() => _pageRetryNonce++);
  }

  Widget _pageErrorWidget(double? height, VoidCallback onRetry) {
    return GestureDetector(
      onTap: onRetry,
      child: SizedBox(
        height: height,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.white54),
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

  late final List<MangaChapter> _chapters;
  late int _chapterIndex;
  List<MangaPage> _pages = const [];
  bool _loading = true;
  bool _failed = false;
  bool _overlayVisible = true;

  // Reading settings, (re)read when the settings page closes.
  String _mode = MangaReaderModes.galleryLtr;
  bool _tapToTurn = true;
  bool _reverseTap = false;
  bool _pageAnimation = true;
  bool _showPageNumber = true;
  int _autoPageSeconds = 0;
  bool _wakelockEnabled = false;
  Timer? _autoTimer;
  int _autoElapsed = 0;

  // Batch 15: in-app dim (M11), pinch-zoom lock (M3), reading
  // statistics accumulation (M6) and next-chapter prefetch (M7).
  double _dim = 0;
  bool _showDimPanel = false;
  bool _zoomLocked = false;
  DateTime _statsStamp = DateTime.now();
  int _pendingPages = 0;
  bool _chapterCounted = false;
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
  bool get _spreadActive =>
      !_isContinuous && _landscape && _pages.length > 1;

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
    imageCache.maximumSizeBytes = 256 * 1024 * 1024;
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
  }

  @override
  void dispose() {
    if (_previousImageCacheBytes != null) {
      PaintingBinding.instance.imageCache.maximumSizeBytes =
          _previousImageCacheBytes!;
    }
    _flushStats();
    _recordProgress(force: true);
    _autoTimer?.cancel();
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
    final local = cached ??
        await MangaDownloadStore.localPages(
          _manga.source,
          _manga.id,
          chapter.id,
        );
    // Batch 27: a throwing page fetch previously bypassed
    // the _failed state entirely — the reader spun forever
    // instead of showing its retry UI.
    List<MangaPage> pages;
    try {
      pages = local ?? await MangaApi.fetchChapterPages(_manga, chapter);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _pages = pages;
      _loading = false;
      _failed = pages.isEmpty;
      _pageNotifier.value = pages.isEmpty
          ? 0
          : initialPage.clamp(0, pages.length - 1);
    });
    _autoElapsed = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pages.isEmpty) return;
      _jumpToCurrentPage();
      _precacheAround(_page);
    });
    _recordProgress();
  }

  /// Pre-downloads the pages around the current one so page turns
  /// in gallery modes don't wait on the network.
  void _precacheAround(int realPage) {
    if (_pages.isEmpty || !mounted) return;
    for (final offset in [1, 2, -1]) {
      final index = realPage + offset;
      if (index < 0 || index >= _pages.length) continue;
      if (_pages[index].url.startsWith('file://')) continue;
      precacheImage(
        CachedNetworkImageProvider(
          _pages[index].url,
          headers: _pages[index].headers,
          maxWidth: _decodeWidth,
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
        _scrollController.jumpTo(max * _page / (_pages.length - 1));
      }
    } else if (_pageController.hasClients) {
      _pageController.jumpToPage(_displayIndexOf(_page));
    }
  }

  void _goToRealPage(int realPage) {
    if (_pages.isEmpty) return;
    final target = realPage.clamp(0, _pages.length - 1);
    _autoElapsed = 0;
    if (_isContinuous) {
      if (_scrollController.hasClients && _pages.length > 1) {
        final max = _scrollController.position.maxScrollExtent;
        final offset = max * target / (_pages.length - 1);
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
    if (_pages.isNotEmpty &&
        _page >= _pages.length - 1 &&
        !_chapterCounted) {
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
    final key = ChapterPrefetchCache.keyOf(
      _manga.source,
      _manga.id,
      next.id,
    );
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
    final due = force ||
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

  void _onScroll() {
    if (!_isContinuous || _pages.isEmpty || !_scrollController.hasClients) {
      return;
    }
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final estimated = ((_scrollController.offset / max) * _pages.length)
        .floor();
    final clamped = estimated.clamp(0, _pages.length - 1);
    if (clamped != _page) {
      _pageNotifier.value = clamped;
      _recordProgress();
      _onPageTurned();
    }
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
      setState(() => _overlayVisible = !_overlayVisible);
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    final dx = details.localPosition.dx;
    if (dx > width / 3 && dx < width * 2 / 3) {
      setState(() => _overlayVisible = !_overlayVisible);
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
    Widget image;
    if (page.url.startsWith('file://')) {
      // Downloaded chapter (M1): render from disk.
      image = Image.file(
        File(Uri.parse(page.url).toFilePath()),
        fit: BoxFit.contain,
        cacheWidth: _decodeWidth,
        errorBuilder: (context, _, _) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white54),
        ),
      );
    } else {
      image = CachedNetworkImage(
        key: ValueKey('${page.url}#$_pageRetryNonce'),
        imageUrl: page.url,
        httpHeaders: page.headers,
        cacheManager: mangaPageCacheManager,
        memCacheWidth: _decodeWidth,
        fit: BoxFit.contain,
        placeholder: (context, _) => const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
        errorWidget: (context, _, _) =>
            _pageErrorWidget(null, () => _retryPage(page.url)),
      );
    }
    if (_isContinuous) return image;
    // Pinch zoom (M3): pan/pinch on the page; while zoomed the
    // PageView stops swiping so panning the page wins.
    return _ZoomablePage(
      onZoomLockChanged: (locked) {
        if (locked != _zoomLocked && mounted) {
          setState(() => _zoomLocked = locked);
        }
      },
      child: image,
    );
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
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: _dim),
                ),
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
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                        onPressed: () => setState(
                          () => _showDimPanel = !_showDimPanel,
                        ),
                        icon: const Icon(
                          Icons.brightness_6_rounded,
                          color: Colors.white,
                        ),
                        tooltip: '亮度遮罩',
                      ),
                      IconButton(
                        onPressed: _openSettings,
                        icon: const Icon(
                          Icons.tune_rounded,
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
                          Icons.brightness_low_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        Expanded(
                          child: Slider(
                            value: _dim,
                            min: 0,
                            max: 0.7,
                            onChanged: (value) =>
                                setState(() => _dim = value),
                            onChangeEnd: (value) => GStorage.putSetting(
                              SettingsKeys.mangaReaderDim,
                              value,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.brightness_high_rounded,
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
                              Icons.skip_previous,
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
                              Icons.skip_next,
                              color: Colors.white,
                            ),
                            tooltip: '下一话',
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
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
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
        onTap: () => setState(() => _overlayVisible = !_overlayVisible),
        child: ListView.builder(
          controller: _scrollController,
          scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
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
            return Center(
              child: CachedNetworkImage(
              key: ValueKey('${_pages[index].url}#$_pageRetryNonce'),
              imageUrl: _pages[index].url,
              httpHeaders: _pages[index].headers,
              cacheManager: mangaPageCacheManager,
              width: width,
              memCacheWidth: _decodeWidth,
              fit: BoxFit.fitWidth,
              placeholder: (context, _) => SizedBox(
                width: width,
                height: width * 1.4,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
              ),
              errorWidget: (context, _, _) => _pageErrorWidget(
                width * 1.4,
                () => _retryPage(_pages[index].url),
              ),
              ),
            );
          },
        ),
      );
    }
    return PageView.builder(
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
