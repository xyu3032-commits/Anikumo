import 'package:flutter/material.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/search_stage.dart';
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
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/navigation.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Manga-zone search, unified with the anime search page: the
/// 全部 / 动漫 / 漫画 switch defaults to 全部， both kinds are
/// queried on submit, and switching panes is animated.
///
/// Batch 12 search pass: results are deduplicated and ranked by
/// title relevance; the manga side can search ONE chosen source
/// (with scroll pagination — batch 97 made the pick free, it
/// used to be the active source or nothing) or ALL sources at
/// once; and entries
/// a source lists but cannot actually serve — no information, or
/// no readable chapters — are verified in the background and
/// auto-hidden (with a toggle to reveal them).
/// Batch 99: route arguments for the search page. A plain
/// String still works (a keyword/title query); this form
/// additionally marks the query as a TAG name, which the
/// page resolves through source catalogues instead of
/// title keyword search.
class MangaSearchRouteArgs {
  const MangaSearchRouteArgs({
    required this.query,
    this.tagSearch = false,
    this.originSourceId,
  });

  final String query;
  final bool tagSearch;

  /// Batch 104/105: for a tag search, the source of the
  /// manga whose tag was tapped — the tag search runs on
  /// that source alone.
  final String? originSourceId;
}

class MangaSearchPage extends StatefulWidget {
  const MangaSearchPage({
    super.key,
    this.initialQuery = '',
    this.initialTagSearch = false,
    this.initialOriginSourceId,
  });

  /// Batch 32: companion sections in the other zones deep-link
  /// here with a title to search for.
  final String initialQuery;

  /// Batch 99: the initial query is a tag name, not a title
  /// keyword (set when arriving from a detail-page tag tap
  /// whose tag is not in its own source's catalogue).
  final bool initialTagSearch;

  /// Batch 104: for a tag search, the source of the manga
  /// the tag came from (see MangaSearchRouteArgs).
  final String? initialOriginSourceId;

  @override
  State<MangaSearchPage> createState() => _MangaSearchPageState();
}

class _MangaSearchPageState extends State<MangaSearchPage> with RouteAware {
  static const _pageSize = 30;

  final _controller = TextEditingController();

  /// Batch 94: the field gets an explicit focus node so
  /// leaving for a result (and coming back) can drop focus
  /// deterministically — see didPushNext/didPopNext.
  final _searchFocus = FocusNode();

  /// Batch 99: tag-search mode — the query is a tag name
  /// and the manga side resolves it through source
  /// catalogues (fetchMangaByTagName) instead of title
  /// keyword search. Only the initial auto-search from a
  /// tag tap runs in this mode; any manual submit or scope
  /// switch returns to keyword semantics.
  bool _tagMode = false;

  /// Batch 104: the source of the manga whose tag opened
  /// this page (tag searches only) — its results lead.
  String? _tagOriginSourceId;

  @override
  void initState() {
    super.initState();
    _tagMode = widget.initialTagSearch;
    _tagOriginSourceId = widget.initialOriginSourceId;
    // Batch 97: the default scope is the active source, as
    // before — it is now a pick the user can change freely.
    _scopeId = MangaApi.activeOrNull?.id ?? '';
    if (_tagMode) {
      // Batch 105 (user correction of batch 104's reading):
      // a tag search searches the tagged manga's OWN
      // source — not every source, and not the default
      // source either (presenting the default as the scope
      // was the original bug). The origin source becomes
      // the selected scope; with no origin recorded the
      // page keeps the all-source scope as a fallback.
      final origin = _tagOriginSourceId;
      _scopeId = (origin != null && origin.isNotEmpty) ? origin : '';
    }
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

  // Search scope for the manga side (batch 97): '' means
  // all sources aggregated; otherwise the id of ONE chosen
  // source. The old toggle only offered the active source
  // or everything — now any installed source can be picked
  // and switched freely without leaving the page. Defaults
  // to the active source (see initState).
  String _scopeId = '';
  bool get _allSources => _scopeId.isEmpty;

  /// The single source the current scope searches, falling
  /// back to the active source when the pick is stale (its
  /// source was removed) — null only with no sources at all.
  MangaSource? get _scopeSource =>
      MangaSources.byId(_scopeId) ?? MangaApi.activeOrNull;
  // Auto-hide bookkeeping.
  final Set<String> _hiddenKeys = {};
  bool _showHidden = false;
  // Pagination for the active-source scope.
  int _mangaPage = 1;
  bool _mangaHasMore = false;
  bool _loadingMore = false;
  String _lastQuery = '';

  // Batch 112: the visible list and hidden count are
  // memoized — the panes read them several times per
  // build, and the availability checker rebuilds this
  // page per verified item while results stream in;
  // re-filtering the whole result set on every read was
  // pure churn. The stamp covers every input: the
  // results list identity, the hidden set's size and
  // mutation counter, and the show-hidden flag.
  int _hiddenStamp = 0;
  List<MangaItem>? _visibleCache;
  int _visibleCacheStamp = -1;
  int _hiddenCountCache = 0;

  void _touchHidden() => _hiddenStamp++;

  List<MangaItem> get _visibleManga {
    final stamp = Object.hash(_mangaResults, _hiddenStamp, _showHidden);
    if (_visibleCache != null && _visibleCacheStamp == stamp) {
      return _visibleCache!;
    }
    final visible = [
      for (final item in _mangaResults)
        if (_showHidden || !_hiddenKeys.contains(item.storageKey)) item,
    ];
    _visibleCache = visible;
    _visibleCacheStamp = stamp;
    _hiddenCountCache = _mangaResults
        .where((i) => _hiddenKeys.contains(i.storageKey))
        .length;
    return visible;
  }

  int get _hiddenCount {
    _visibleManga; // ensure the cache pair is current
    return _hiddenCountCache;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  /// Batch 94: opening a result pushes the detail route
  /// over this page. The search field (autofocus, no
  /// explicit node before this batch) kept its focus
  /// membership while covered, so on return the platform
  /// reconnected the IME — the keyboard popped back up over
  /// the results and the page looked like it was searching
  /// again. Drop the field's focus as soon as anything is
  /// pushed over us, and again when we resurface, so a
  /// return always lands on a quiet results list. Nothing
  /// here re-runs the search: the results are state, they
  /// simply stay.
  @override
  void didPushNext() {
    _searchFocus.unfocus();
  }

  @override
  void didPopNext() {
    _searchFocus.unfocus();
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Batch 78: long source names are truncated so a chip
  /// cannot stretch off the screen edge.
  static String _shortSourceName(String name) =>
      name.length > 8 ? '${name.substring(0, 8)}…' : name;

  /// Batch 97: the scope picker — 全部源 plus one chip per
  /// installed source, freely switchable. Picking a chip
  /// re-runs the current search in the new scope at once.
  Widget _buildScopeChips() {
    final sources = MangaSources.sortForDisplay(MangaSources.all());
    final activeId = MangaApi.activeOrNull?.id;
    final effectiveId = _allSources ? '' : (_scopeSource?.id ?? '');
    Widget chip(String id, String label) {
      // Batch 110: pill chips — gradient-tinted selection
      // matching the mode capsule above.
      final selected = effectiveId == id;
      final colors = Theme.of(context).colorScheme;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) {
          if (_scopeId == id) return;
          setState(() => _scopeId = id);
          if (_searched) _searchFromUser();
        },
        visualDensity: VisualDensity.compact,
        shape: const StadiumBorder(),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
        backgroundColor: colors.surfaceContainerHigh,
        selectedColor: colors.primary,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? colors.onPrimary : null,
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
        children: [
          chip('', '全部源'),
          for (final source in sources)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: chip(
                source.id,
                source.id == activeId
                    ? '${_shortSourceName(source.name)}·当前源'
                    : _shortSourceName(source.name),
              ),
            ),
        ],
      ),
    );
  }

  /// Batch 99: a search the user explicitly runs (submit
  /// button, keyboard enter, scope chip) is a KEYWORD
  /// search — tag mode belongs to the initial landing from
  /// a tag tap only.
  Future<void> _searchFromUser() {
    _tagMode = false;
    return _search();
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
      _touchHidden();
      _showHidden = false;
      _mangaPage = 1;
      _mangaHasMore = false;
      _lastQuery = query;
    });
    setState(() => _novelLoading = true);
    final novelFuture = NovelApi.searchAll(query)
        .then((all) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _novelResults = rankNovels(query, all, strict: true);
            _novelResultsAll = rankNovels(query, all);
            _novelLoading = false;
          });
        })
        .catchError((_) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _novelResults = const [];
            _novelResultsAll = const [];
            _novelLoading = false;
          });
        });
    final mangaFuture = _fetchManga(query, generation);
    final animeFuture = BangumiApi.bangumiSearch(query, limit: 18).then((page) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _animeResults = page == null
            ? const []
            : rankCrossAnime(page.items, query);
        _animeLoading = false;
      });
    });
    await Future.wait([mangaFuture, animeFuture, novelFuture]);
  }

  Future<void> _fetchManga(String query, int generation) async {
    // Batch 95: this future used to have NO failure path —
    // if the manga search threw (a source rejecting an
    // unusual keyword, a timeout, an engine reset), the
    // error escaped into _search's Future.wait and
    // _mangaLoading stayed true forever: the page spun
    // indefinitely, which is exactly what some tag searches
    // (the detail page's tag fallback lands here) hit. Any
    // failure now resolves the spinner into the empty state.
    try {
      await _fetchMangaInner(query, generation);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _mangaResults = const [];
        _mangaLoading = false;
      });
    }
  }

  Future<void> _fetchMangaInner(String query, int generation) async {
    List<MangaItem> results;
    if (_tagMode) {
      // Batch 99: resolve the tag name through source
      // catalogues and merge byTag results — a keyword
      // search here returned nothing, because source
      // search matches titles, not tags.
      // Batch 105: restricted to the tagged manga's own
      // source (the batch 99/104 all-source fan-out was
      // the user's complaint — a tag belongs to its
      // manga's source). A stale origin (source removed)
      // falls back to the unscoped resolution.
      final origin = _tagOriginSourceId;
      final originSource = origin == null ? null : MangaSources.byId(origin);
      results = await fetchMangaByTagName(
        query,
        limit: _pageSize,
        sources: originSource == null ? null : [originSource],
      );
    } else if (_allSources) {
      // Batch 104: the default (active) source is searched
      // and merged FIRST — under the stable relevance
      // ranking its results lead their score tier, and its
      // copy wins the cross-source title dedupe. (User's
      // rule: 普通搜索默认在前。)
      final activeId = MangaApi.activeOrNull?.id;
      final orderedSources = [
        for (final source in MangaSources.all())
          if (source.id == activeId) source,
        for (final source in MangaSources.all())
          if (source.id != activeId) source,
      ];
      final perSource = await Future.wait([
        for (final source in orderedSources)
          source
              .search(query, limit: _pageSize)
              // Batch 95: one slow or wedged source must
              // not hold the aggregated search hostage.
              .timeout(
                const Duration(seconds: 25),
                onTimeout: () => const <MangaItem>[],
              )
              .catchError((_) => const <MangaItem>[]),
      ]);
      results = dedupeMangaItems([for (final list in perSource) ...list]);
    } else {
      // Batch 97: the picked source, not always the active
      // one.
      final scope = _scopeSource;
      results = scope == null
          ? const []
          : await MangaApi.searchMangaFor(scope, query, limit: _pageSize);
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
          _touchHidden();
        }
      }
      // Batch 26: drop the unrelated tail, and in
      // all-source mode collapse the same manga arriving
      // from several sources into one entry.
      // Batch 99: tag-mode results are relevant by
      // construction (they arrived via byTag); the title
      // relevance machinery would bury or drop them —
      // titles rarely contain the tag word — so they only
      // get the cross-source title dedupe.
      // Batch 105: tag results come from ONE source now
      // (the tagged manga's own), so there is no cross-
      // source ordering to apply — just the title dedupe.
      var ranked = _tagMode
          ? dedupeMangaByTitle(withInfo)
          : filterRelevantMangaResults(
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
  ///
  /// Batch 91: the pass is capped (batch 72's rule on the
  /// cross-zone page) and, more importantly, STOPS as soon
  /// as this page is no longer the visible one. Each verdict
  /// costs a full chapter fetch on the shared JS engine;
  /// the pass used to grind through every result long after
  /// the user opened a manga — competing with that manga's
  /// own chapter/page loads — and kept hiding entries under
  /// the user when they came back ("退出了还在继续搜索").
  /// Verdicts that land while the page is covered are
  /// dropped, not applied (unproven stays visible, batch
  /// 26's rule); items never reached simply stay visible.
  void _verifyAvailability(List<MangaItem> items, int generation) {
    MangaAvailabilityChecker.checkAll(
      items.take(12).toList(),
      shouldContinue: () => _checksActive(generation),
      onResult: (item, readable) {
        if (!_checksActive(generation) || readable) return;
        setState(() {
          _hiddenKeys.add(item.storageKey);
          _touchHidden();
        });
      },
    );
  }

  bool _checksActive(int generation) =>
      mounted &&
      generation == _generation &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _loadMoreManga() async {
    if (_allSources ||
        _tagMode ||
        !_mangaHasMore ||
        _loadingMore ||
        _mangaLoading) {
      return;
    }
    final generation = _generation;
    setState(() => _loadingMore = true);
    final nextPage = _mangaPage + 1;
    // Batch 97: pagination follows the picked scope too.
    final scope = _scopeSource;
    if (scope == null) {
      setState(() {
        _loadingMore = false;
        _mangaHasMore = false;
      });
      return;
    }
    // Batch 95: same missing failure path as _fetchManga —
    // a throwing page fetch left _loadingMore true forever.
    final List<MangaItem> results;
    try {
      results = await MangaApi.searchMangaFor(
        scope,
        _lastQuery,
        limit: _pageSize,
        page: nextPage,
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _mangaHasMore = false;
      });
      return;
    }
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
          _touchHidden();
        } else if (!known.contains(item.storageKey)) {
          fresh.add(item);
        }
      }
      _mangaResults = [..._mangaResults, ...fresh];
    });
    _verifyAvailability(
      _mangaResults.sublist(
        _mangaResults.length - results.length.clamp(0, _mangaResults.length),
      ),
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
                    icon: const Icon(AnikumoIcons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: SearchHeroShell(
                      focusNode: _searchFocus,
                      child: Row(
                        children: [
                          Icon(
                            AnikumoIcons.search_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _searchFocus,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                hintText: '搜索动漫 / 漫画',
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _searchFromUser(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _searchFromUser,
                    icon: const Icon(AnikumoIcons.search_rounded),
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
                // Batch 231: five modes now — the switch
                // scrolls horizontally on narrow screens
                // instead of overflowing the portrait row.
                final modeSwitch = SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: CrossSearchModeSwitch(
                    mode: _mode,
                    onChanged: (mode) => setState(() => _mode = mode),
                  ),
                );
                if (_mode != CrossSearchMode.manga &&
                    _mode != CrossSearchMode.all) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: modeSwitch,
                  );
                }
                // Batch 97: the old two-way toggle （当前源 /
                // 全部源） is now a horizontally scrolling
                // chip row — every installed source is
                // directly pickable. It always stacks under
                // the mode switch: the chips need the full
                // width (the batch-78 side-by-side layout
                // clipped even the two-segment toggle).
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    modeSwitch,
                    const SizedBox(height: 8),
                    _buildScopeChips(),
                  ],
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
                key: ValueKey('$_mode|$_scopeId|$_searched'),
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
      // Batch 231: the film zone's aggregated search,
      // hosted by the shared cross-search pane.
      CrossSearchMode.film => FilmCrossSearchPane(
        query: _controller.text.trim(),
      ),
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
                avatar: const Icon(AnikumoIcons.history_rounded, size: 16),
                label: Text(keyword),
                shape: const StadiumBorder(),
                onPressed: () {
                  _controller.text = keyword;
                  _searchFromUser();
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
            icon: AnikumoIcons.search_off_rounded,
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
        icon: AnikumoIcons.search_off_rounded,
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
        icon: AnikumoIcons.auto_stories_outlined,
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
            icon: AnikumoIcons.search_off_rounded,
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
                  child: CrossSectionHeader(title: '漫画', count: visible.length),
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
                NovelResultsSliver(items: _novelResults.take(10).toList()),
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
