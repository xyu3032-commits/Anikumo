import 'package:flutter/material.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/violet_components.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/search/cross_search_widgets.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/manga/cross_media.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/novel_api.dart';
import 'package:anikumo/services/manga/manga_extras.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/utils/constants.dart';

/// Manga-zone search, unified with the anime search page: the
/// 全部 / 动漫 / 漫画 switch defaults to 全部， both kinds are
/// queried on submit, and switching panes is animated.
///
/// Batch 12 search pass: results are deduplicated and ranked by
/// title relevance; the manga side can search the active source
/// (with scroll pagination) or ALL sources at once; and entries
/// a source lists but cannot actually serve — no information, or
/// no readable chapters — are verified in the background and
/// auto-hidden (with a toggle to reveal them).
class MangaSearchPage extends StatefulWidget {
  const MangaSearchPage({super.key, this.initialQuery = ''});

  /// Batch 32: companion sections in the other zones deep-link
  /// here with a title to search for.
  final String initialQuery;

  @override
  State<MangaSearchPage> createState() => _MangaSearchPageState();
}

class _MangaSearchPageState extends State<MangaSearchPage> {
  static const _pageSize = 30;

  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      _controller.text = widget.initialQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }
  // Batch 64: default to THIS zone (manga), not 全部 —
  // same fix as the anime search page.
  CrossSearchMode _mode = CrossSearchMode.manga;
  List<MangaItem> _mangaResults = const [];
  List<BangumiItem> _animeResults = const [];
  // Batch 48: novel side of this page's cross search.
  // Batch 64: _novelResults stays strict for the 全部-mode
  // section; _novelResultsAll (ranked, unfiltered) feeds
  // the dedicated novel mode, like the novel zone itself.
  List<NovelItem> _novelResults = const [];
  List<NovelItem> _novelResultsAll = const [];
  bool _novelLoading = false;
  bool _mangaLoading = false;
  bool _animeLoading = false;
  bool _searched = false;
  int _generation = 0;

  // Search scope for the manga side: active source or all sources.
  bool _allSources = false;
  // Auto-hide bookkeeping.
  final Set<String> _hiddenKeys = {};
  bool _showHidden = false;
  // Pagination for the active-source scope.
  int _mangaPage = 1;
  bool _mangaHasMore = false;
  bool _loadingMore = false;
  String _lastQuery = '';

  List<MangaItem> get _visibleManga => [
        for (final item in _mangaResults)
          if (_showHidden || !_hiddenKeys.contains(item.storageKey)) item,
      ];

  int get _hiddenCount =>
      _mangaResults.where((i) => _hiddenKeys.contains(i.storageKey)).length;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Batch 78: the 当前源 toggle label — the active source's
  /// name, truncated so a long-named source cannot stretch
  /// the toggle past the screen edge.
  String _scopeSourceLabel() {
    final source = MangaApi.activeOrNull;
    if (source == null) return '当前源';
    final name = source.name;
    return '当前源·${name.length > 8 ? '${name.substring(0, 8)}…' : name}';
  }

  Future<void> _search() async {
    MangaExtrasStore.addSearchKeyword(_controller.text);
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    setState(() {
      _searched = true;
      _mangaLoading = true;
      _animeLoading = true;
      _hiddenKeys.clear();
      _showHidden = false;
      _mangaPage = 1;
      _mangaHasMore = false;
      _lastQuery = query;
    });
    setState(() => _novelLoading = true);
    final novelFuture = NovelApi.searchAll(query).then((all) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _novelResults = rankNovels(query, all, strict: true);
        _novelResultsAll = rankNovels(query, all);
        _novelLoading = false;
      });
    }).catchError((_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _novelResults = const [];
        _novelResultsAll = const [];
        _novelLoading = false;
      });
    });
    final mangaFuture = _fetchManga(query, generation);
    final animeFuture = BangumiApi.bangumiSearch(query, limit: 18)
        .then((page) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _animeResults =
            page == null ? const [] : rankCrossAnime(page.items, query);
        _animeLoading = false;
      });
    });
    await Future.wait([mangaFuture, animeFuture, novelFuture]);
  }

  Future<void> _fetchManga(String query, int generation) async {
    List<MangaItem> results;
    if (_allSources) {
      final perSource = await Future.wait([
        for (final source in MangaSources.all())
          source
              .search(query, limit: _pageSize)
              .catchError((_) => const <MangaItem>[]),
      ]);
      results = dedupeMangaItems([
        for (final list in perSource) ...list,
      ]);
    } else {
      results = await MangaApi.searchManga(query, limit: _pageSize);
      _mangaHasMore = results.length >= _pageSize;
    }
    if (!mounted || generation != _generation) return;
    final withInfo = <MangaItem>[];
    setState(() {
      for (final item in results) {
        if (mangaHasInfo(item)) {
          withInfo.add(item);
        } else {
          _hiddenKeys.add(item.storageKey);
        }
      }
      // Batch 26: drop the unrelated tail, and in
      // all-source mode collapse the same manga arriving
      // from several sources into one entry.
      var ranked = filterRelevantMangaResults(
        rankMangaResults(withInfo, query),
        query,
      );
      if (_allSources) ranked = dedupeMangaByTitle(ranked);
      _mangaResults = ranked;
      _mangaLoading = false;
    });
    _verifyAvailability(_mangaResults, generation);
  }

  /// Background pass: entries with no readable chapters from
  /// their source get hidden as the verdicts land.
  void _verifyAvailability(List<MangaItem> items, int generation) {
    MangaAvailabilityChecker.checkAll(
      items,
      onResult: (item, readable) {
        if (!mounted || generation != _generation || readable) return;
        setState(() => _hiddenKeys.add(item.storageKey));
      },
    );
  }

  Future<void> _loadMoreManga() async {
    if (_allSources || !_mangaHasMore || _loadingMore || _mangaLoading) {
      return;
    }
    final generation = _generation;
    setState(() => _loadingMore = true);
    final nextPage = _mangaPage + 1;
    final results = await MangaApi.searchManga(
      _lastQuery,
      limit: _pageSize,
      page: nextPage,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _mangaPage = nextPage;
      _mangaHasMore = results.length >= _pageSize;
      _loadingMore = false;
      final known = _mangaResults.map((i) => i.storageKey).toSet();
      final fresh = <MangaItem>[];
      for (final item in results) {
        if (!mangaHasInfo(item)) {
          _hiddenKeys.add(item.storageKey);
        } else if (!known.contains(item.storageKey)) {
          fresh.add(item);
        }
      }
      _mangaResults = [..._mangaResults, ...fresh];
    });
    _verifyAvailability(
      _mangaResults.sublist(_mangaResults.length - results.length.clamp(0, _mangaResults.length)),
      generation,
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 320) {
      _loadMoreManga();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Glass search header (batch 39, Violet Glass):
          // back button + glass pill field, replacing the
          // stock AppBar. Field behaviour is unchanged.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 2),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: VioletGlassCard(
                      radius: 999,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                hintText: '搜索动漫 / 漫画',
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _search(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _search,
                    icon: const Icon(Icons.search_rounded),
                    tooltip: '搜索',
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final modeSwitch = CrossSearchModeSwitch(
                  mode: _mode,
                  onChanged: (mode) => setState(() => _mode = mode),
                );
                if (_mode != CrossSearchMode.manga &&
                    _mode != CrossSearchMode.all) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: modeSwitch,
                  );
                }
                final scopeToggle = SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      // Batch 62: activeOrNull — with zero
                      // sources this label used to throw in
                      // build() (grey screen). Batch 78: long
                      // source names are truncated so the
                      // toggle cannot stretch off-screen.
                      label: Text(_scopeSourceLabel()),
                    ),
                    const ButtonSegment(value: true, label: Text('全部源')),
                  ],
                  selected: {_allSources},
                  onSelectionChanged: (selection) {
                    setState(() => _allSources = selection.first);
                    if (_searched) _search();
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontSize: 12),
                    ),
                  ),
                );
                // Batch 78: the switch (~272dp) and the toggle
                // (~200dp) side by side need ~480dp; portrait
                // phones give ~360-410, which clipped the
                // toggle at the right edge (device report).
                // Stack them on narrow widths instead.
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      modeSwitch,
                      const SizedBox(height: 8),
                      scopeToggle,
                    ],
                  );
                }
                return Row(
                  children: [modeSwitch, const Spacer(), scopeToggle],
                );
              },
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.015),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey('$_mode|$_allSources|$_searched'),
                child: _buildPane(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Loading placeholder (batch 39): a grid of pulsing
  /// cover blocks in the results geometry, replacing the
  /// lone spinner.
  Widget _skeletonGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: StyleString.pagePadding,
        vertical: 12,
      ),
      child: GridView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 14,
          crossAxisSpacing: 10,
          childAspectRatio: 0.52,
        ),
        itemCount: 12,
        itemBuilder: (context, index) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: VioletSkeleton(radius: 14)),
            SizedBox(height: 6),
            VioletSkeleton(height: 10, radius: 5),
            SizedBox(height: 4),
            VioletSkeleton(height: 10, width: 44, radius: 5),
          ],
        ),
      ),
    );
  }

  Widget _buildPane() {
    if (!_searched) {
      return _historyPane();
    }
    return switch (_mode) {
      CrossSearchMode.manga => _mangaPane(),
      CrossSearchMode.anime => _animePane(),
      CrossSearchMode.novel => _novelPane(),
      CrossSearchMode.all => _allPane(),
    };
  }

  /// Pre-search pane (M8): recent manga search keywords.
  Widget _historyPane() {
    final history = MangaExtrasStore.loadSearchHistory();
    if (history.isEmpty) {
      return const Center(child: Text('输入名称，同时搜索动漫、漫画与小说'));
    }
    return ListView(
      scrollCacheExtent: const ScrollCacheExtent.pixels(700),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        VioletSectionHeader(
          title: '搜索历史',
          actionLabel: '清空',
          onAction: () async {
            await MangaExtrasStore.clearSearchHistory();
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final keyword in history)
              ActionChip(
                label: Text(keyword),
                onPressed: () {
                  _controller.text = keyword;
                  _search();
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _hiddenNote() {
    if (_hiddenCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '已自动隐藏 $_hiddenCount 部（源里没有信息或无可读章节）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(
            onPressed: () => setState(() => _showHidden = !_showHidden),
            child: Text(_showHidden ? '重新隐藏' : '显示出来'),
          ),
        ],
      ),
    );
  }

  Widget _mangaPane() {
    if (_mangaLoading) {
      return _skeletonGrid();
    }
    final visible = _visibleManga;
    if (visible.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GeneralEmptyState(
            icon: Icons.search_off_rounded,
            title: '没有找到能观看的漫画，换个关键词试试',
            compact: true,
          ),
          _hiddenNote(),
        ],
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Column(
        children: [
          _hiddenNote(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: StyleString.pagePadding,
              ),
              child: MangaResultsGrid(
                items: visible,
                showSourceBadge: _allSources,
              ),
            ),
          ),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _animePane() {
    if (_animeLoading) {
      return _skeletonGrid();
    }
    if (_animeResults.isEmpty) {
      return const GeneralEmptyState(
        icon: Icons.search_off_rounded,
        title: '没有找到相关动漫，换个关键词试试',
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: StyleString.pagePadding),
      child: AnimeResultsGrid(items: _animeResults),
    );
  }

  /// Batch 48: the novel mode pane — all novel sources,
  /// strict-ranked, rows into the novel zone's detail.
  Widget _novelPane() {
    if (_novelLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_novelResultsAll.isEmpty) {
      return const GeneralEmptyState(
        icon: Icons.auto_stories_outlined,
        title: '没有找到小说，换个关键词试试',
      );
    }
    return CustomScrollView(
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: StyleString.pagePadding,
          ),
          sliver: NovelResultsSliver(items: _novelResultsAll),
        ),
      ],
    );
  }

  Widget _allPane() {
    if (_mangaLoading && _animeLoading) {
      return _skeletonGrid();
    }
    final visible = _visibleManga;
    if (visible.isEmpty && _animeResults.isEmpty && _novelResults.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GeneralEmptyState(
            icon: Icons.search_off_rounded,
            title: '动漫、漫画和小说都没有找到能看的，换个关键词试试',
            compact: true,
          ),
          _hiddenNote(),
        ],
      );
    }
    // Sliver-based (batch 14): the old shrinkWrap grids built every
    // card up front, which hitched on long result lists.
    return CustomScrollView(
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: StyleString.pagePadding,
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              if (_animeResults.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: CrossSectionHeader(
                    title: '动漫',
                    count: _animeResults.length,
                  ),
                ),
                AnimeResultsSliver(items: _animeResults),
              ] else if (_animeLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (visible.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: CrossSectionHeader(
                    title: '漫画',
                    count: visible.length,
                  ),
                ),
                MangaResultsSliver(
                  items: visible,
                  showSourceBadge: _allSources,
                ),
              ] else if (_mangaLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (_novelResults.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: CrossSectionHeader(
                    title: '小说',
                    count: _novelResults.length,
                  ),
                ),
                NovelResultsSliver(
                  items: _novelResults.take(10).toList(),
                ),
              ] else if (_novelLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              SliverToBoxAdapter(child: _hiddenNote()),
              const SliverToBoxAdapter(
                child: SizedBox(height: StyleString.sectionSpace),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
