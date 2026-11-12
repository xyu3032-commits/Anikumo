import 'package:anikumo/utils/tap_debouncer.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:anikumo/bean/dialog/material_bottom_sheet.dart';
import 'package:anikumo/bean/widget/anikumo_menu.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/state_presentation.dart';
import 'package:anikumo/bean/theme/signature.dart';
import 'package:anikumo/bean/widget/violet_components.dart';

import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/search/cross_search_widgets.dart';
import 'package:anikumo/pages/search/search_controller.dart';
import 'package:anikumo/services/cross_search_trio.dart';
import 'package:anikumo/services/manga/cross_media.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/novel_api.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:liuguang_core/liuguang_core.dart' as lg;
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/utils/date_time.dart';
import 'package:anikumo/utils/search_parser.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

part 'search_filter_sheet.dart';
part 'search_widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.controller,
    this.initialQuery = '',
  });

  final SearchPageController controller;
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  // Preserve the input subtree when the header moves in or out of the scroll view.
  final _searchHeaderKey = GlobalKey();
  String? _submittedQuery;
  bool _managingHistory = false;

  // Unified search: anime, manga and novels in one page.
  // Batch 64: the mode defaults to THIS zone (anime) — it
  // used to default to 全部， so an anime-zone search opened
  // on a mixed page. Batch 72: submits fetch only the
  // visible mode's backends; the rest load lazily on the
  // first switch to them (see _ensureModeData).
  CrossSearchMode _searchMode = CrossSearchMode.anime;

  // Batch 72: which query each zone's backend was last
  // fetched for. Submits only fetch the visible mode's
  // backend; the others load lazily on the first switch to
  // a mode that shows them (_ensureModeData), so an anime
  // search no longer pays for the manga JS bridge and the
  // novel fan-out it will never display.
  String? _animeFetchedFor;
  String? _mangaFetchedFor;
  String? _novelFetchedFor;
  String? _filmFetchedFor;
  List<MangaItem> _mangaResults = const [];

  /// Batch 64: the manga-mode list — the same results the
  /// manga zone's own search would show (ranked, not
  /// strict-filtered). _mangaResults above stays the
  /// precision-filtered companion-section list.
  List<MangaItem> _mangaResultsAll = const [];

  /// Batch 75: cross-search bookkeeping — the raw merged
  /// list behind the ranked views (「更多搜索」 unions onto
  /// it so the original results stay), the sources the
  /// default trio search already covered, and the keyword
  /// they were searched with.
  List<MangaItem> _mangaRawMerged = const [];
  Set<String> _mangaSearchedIds = {};
  String _mangaKeyword = '';
  bool _mangaExpanding = false;

  /// Manga entries auto-hidden because the source has no
  /// readable chapters for them (batch 12).
  final Set<String> _hiddenMangaKeys = {};

  List<MangaItem> get _visibleMangaResults => [
    for (final item in _mangaResults)
      if (!_hiddenMangaKeys.contains(item.storageKey)) item,
  ];

  List<MangaItem> get _visibleMangaModeResults => [
    for (final item in _mangaResultsAll)
      if (!_hiddenMangaKeys.contains(item.storageKey)) item,
  ];
  bool _mangaLoading = false;
  int _mangaGeneration = 0;

  SearchPageController get _controller => widget.controller;
  bool get _hasSearched => _submittedQuery != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadMoreOnScroll);
    _controller.loadSearchHistories();
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(widget.initialQuery);
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _writeInput(String value) {
    _input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _submit(String value) async {
    final filters = SearchParser(value).toFilterState();
    final query = SearchParser.fromFilterState(filters);
    _inputFocus.unfocus();
    _writeInput(query);
    setState(() {
      _submittedQuery = query;
      // Batch 72: a new query invalidates the other zones'
      // results — clear them so a later mode switch can
      // never show the previous query's manga/novels.
      _mangaResults = const [];
      _mangaResultsAll = const [];
      _mangaLoading = false;
      _novelResults = const [];
      _novelResultsAll = const [];
      _novelLoading = false;
      _filmResults = const [];
      _filmLoading = false;
      _animeFetchedFor = null;
      _mangaFetchedFor = null;
      _novelFetchedFor = null;
      _filmFetchedFor = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    // Batch 72: only the visible mode's backends run (plus
    // anime, this page's primary). The rest are fetched by
    // _ensureModeData when the user switches to them.
    _animeFetchedFor = query;
    final request = _controller.searchBangumi(query, type: 'init');
    switch (_searchMode) {
      case CrossSearchMode.anime:
        break;
      case CrossSearchMode.manga:
        _mangaFetchedFor = filters.keyword;
        _searchManga(filters.keyword);
      case CrossSearchMode.novel:
        _novelFetchedFor = filters.keyword;
        _searchNovel(filters.keyword);
      case CrossSearchMode.film:
        _filmFetchedFor = filters.keyword;
        _searchFilm(filters.keyword);
      case CrossSearchMode.all:
        _mangaFetchedFor = filters.keyword;
        _searchManga(filters.keyword);
        _novelFetchedFor = filters.keyword;
        _searchNovel(filters.keyword);
        _filmFetchedFor = filters.keyword;
        _searchFilm(filters.keyword);
    }
    await request;
  }

  /// Batch 72: lazy per-mode fetching — called when the
  /// mode switch changes what is visible. Anything already
  /// fetched for the current query is left alone.
  void _ensureModeData(CrossSearchMode mode) {
    final query = _submittedQuery;
    if (query == null) return;
    final keyword = SearchParser(query).toFilterState().keyword;
    if ((mode == CrossSearchMode.anime || mode == CrossSearchMode.all) &&
        _animeFetchedFor != query) {
      _animeFetchedFor = query;
      _controller.searchBangumi(query, type: 'init');
    }
    if ((mode == CrossSearchMode.manga || mode == CrossSearchMode.all) &&
        _mangaFetchedFor != keyword) {
      _mangaFetchedFor = keyword;
      _searchManga(keyword);
    }
    if ((mode == CrossSearchMode.novel || mode == CrossSearchMode.all) &&
        _novelFetchedFor != keyword) {
      _novelFetchedFor = keyword;
      _searchNovel(keyword);
    }
    if ((mode == CrossSearchMode.film || mode == CrossSearchMode.all) &&
        _filmFetchedFor != keyword) {
      _filmFetchedFor = keyword;
      _searchFilm(keyword);
    }
  }

  Future<void> _searchManga(String keyword) async {
    final generation = ++_mangaGeneration;
    if (keyword.trim().isEmpty) {
      setState(() {
        _mangaResults = const [];
        _mangaLoading = false;
      });
      return;
    }
    // Batch 75: a fresh search starts again from the trio.
    _mangaKeyword = keyword;
    _mangaSearchedIds = {
      for (final source in MangaApi.crossSearchSources()) source.id,
    };
    _mangaRawMerged = const [];
    _mangaExpanding = false;
    setState(() {
      _mangaLoading = true;
      _hiddenMangaKeys.clear();
    });
    // Multi-source (batch 14): the manga section follows the
    // manga zone's active source instead of hard-coding
    // MangaDex. Items carry their source, so detail routing and
    // the availability check below resolve per-source as usual.
    // Batch 37: this await had no failure path — a throwing
    // manga source (the broken-JS case) left _mangaLoading
    // true and the page sat on 正在搜索 forever. Settle to the
    // empty state on error; the anime side is unaffected.
    // Batch 72: results are applied through one funnel for
    // both the progressive partial merges and the final
    // list, so the section fills in as sources land instead
    // of waiting for the slowest one.
    void apply(List<MangaItem> results) {
      if (!mounted || generation != _mangaGeneration) return;
      _mangaRawMerged = results;
      // Batch 64: keep two views of the same results. The
      // dedicated manga mode must behave like the manga
      // zone's own search — ranked results as the sources
      // returned them. The batch-26 strict filter stays ONLY
      // on the companion section (全部 mode), where precision
      // matters; applied to the dedicated mode it emptied
      // the page whenever titles didn't literally contain
      // the keyword (alternate/translated names), while the
      // same search worked fine inside the manga zone.
      final ranked = rankMangaResults(results, keyword);
      for (final item in ranked) {
        if (!mangaHasInfo(item)) _hiddenMangaKeys.add(item.storageKey);
      }
      setState(() {
        _mangaResultsAll = ranked;
        _mangaResults = [
          for (final item in filterRelevantMangaResults(
            ranked,
            keyword,
            strict: true,
          ))
            if (mangaHasInfo(item)) item,
        ];
      });
    }

    List<MangaItem> results;
    try {
      // Batch 72: parallel multi-source merge with partial
      // emissions (see MangaApi.searchMangaMulti).
      results = await MangaApi.searchMangaMulti(
        keyword,
        limit: 24,
        onPartial: apply,
      );
    } catch (_) {
      results = const [];
    }
    if (!mounted || generation != _mangaGeneration) return;
    apply(results);
    setState(() => _mangaLoading = false);
    _checkMangaAvailability(_mangaResultsAll, generation);
  }

  // Batch 72: the availability probe costs one source
  // call per item; cap it at the first 12 ranked results
  // (the rest stay visible, matching the checker's
  // failed-check-stays-visible rule) so it stops competing
  // with cover loads for the bridge and the network.
  void _checkMangaAvailability(List<MangaItem> items, int generation) {
    // Batch 91: same stop-when-covered rule as the manga
    // search page — the probe must not keep fetching
    // chapters (and hiding results) after the user has
    // opened a manga or left search.
    bool active() =>
        mounted &&
        generation == _mangaGeneration &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    MangaAvailabilityChecker.checkAll(
      items.take(12).toList(),
      shouldContinue: active,
      onResult: (item, readable) {
        if (!active() || readable) return;
        setState(() => _hiddenMangaKeys.add(item.storageKey));
      },
    );
  }

  /// Batch 75: 「更多搜索」 — widen the manga search to every
  /// source the trio did not cover, keeping the results
  /// already on screen (the union re-ranks as one list).
  Future<void> _expandMangaSearch() async {
    final keyword = _mangaKeyword;
    if (keyword.trim().isEmpty || _mangaExpanding || _mangaLoading) return;
    final generation = _mangaGeneration;
    setState(() => _mangaExpanding = true);
    List<MangaItem> rest;
    try {
      rest = await MangaApi.searchMangaRest(
        keyword,
        excludeIds: _mangaSearchedIds,
      );
    } catch (_) {
      rest = const [];
    }
    if (!mounted || generation != _mangaGeneration) return;
    _mangaSearchedIds = {for (final source in MangaSources.all()) source.id};
    setState(() => _mangaExpanding = false);
    if (rest.isEmpty) {
      AnikumoDialog.showToast(message: '其他源也没有找到更多结果');
      return;
    }
    // Re-apply through the same funnel _searchManga uses:
    // ranked view + strict companion view over the union.
    final ranked = rankMangaResults([..._mangaRawMerged, ...rest], keyword);
    for (final item in ranked) {
      if (!mangaHasInfo(item)) _hiddenMangaKeys.add(item.storageKey);
    }
    setState(() {
      _mangaRawMerged = [..._mangaRawMerged, ...rest];
      _mangaResultsAll = ranked;
      _mangaResults = [
        for (final item in filterRelevantMangaResults(
          ranked,
          keyword,
          strict: true,
        ))
          if (mangaHasInfo(item)) item,
      ];
    });
    _checkMangaAvailability(rest, generation);
  }

  // Batch 48: novel side of the cross search — every novel
  // source at once (NovelApi.searchAll), strict-ranked like
  // the companion rails.
  // Batch 64: two views, same split as the manga side —
  // _novelResults stays strict for the 全部-mode section,
  // while _novelResultsAll (ranked, unfiltered) feeds the
  // dedicated novel mode, matching the novel zone's own
  // search which never strict-filters.
  List<NovelItem> _novelResults = const [];
  List<NovelItem> _novelResultsAll = const [];
  bool _novelLoading = false;
  int _novelGeneration = 0;

  /// Batch 75: same trio bookkeeping as the manga side —
  /// the raw list behind the ranked views, the covered
  /// sources, and the keyword.
  List<NovelItem> _novelRawAll = const [];
  Set<String> _novelSearchedIds = {};
  String _novelKeyword = '';
  bool _novelExpanding = false;

  Future<void> _searchNovel(String keyword) async {
    final generation = ++_novelGeneration;
    if (keyword.trim().isEmpty) {
      setState(() {
        _novelResults = const [];
        _novelResultsAll = const [];
        _novelLoading = false;
      });
      return;
    }
    // Batch 75: the cross search starts from the trio,
    // like the manga side; the novel zone's own search page
    // still fans out to every source via searchAll.
    _novelKeyword = keyword;
    _novelSearchedIds = {
      for (final source in NovelApi.crossSearchSources()) source.id,
    };
    _novelRawAll = const [];
    _novelExpanding = false;
    setState(() => _novelLoading = true);
    List<NovelItem> strictResults;
    List<NovelItem> allResults;
    try {
      final all = await NovelApi.searchCross(keyword);
      _novelRawAll = all;
      strictResults = rankNovels(keyword, all, strict: true);
      allResults = rankNovels(keyword, all);
    } catch (_) {
      strictResults = const [];
      allResults = const [];
    }
    if (!mounted || generation != _novelGeneration) return;
    setState(() {
      _novelResults = strictResults;
      _novelResultsAll = allResults;
      _novelLoading = false;
    });
  }

  // Batch 231: film side of the cross search — the film
  // zone's aggregated search over its installed sources,
  // with the 全部/电影/电视剧/其他 sub-filter the user
  // asked for on the film mode.
  List<lg.MediaItem> _filmResults = const [];
  bool _filmLoading = false;
  int _filmGeneration = 0;
  FilmCrossFilter _filmFilter = FilmCrossFilter.all;

  Future<void> _searchFilm(String keyword) async {
    final generation = ++_filmGeneration;
    if (keyword.trim().isEmpty) {
      setState(() {
        _filmResults = const [];
        _filmLoading = false;
      });
      return;
    }
    final service = VideoEngineService.instance;
    service.loadRegistry();
    if (!service.hasSources) {
      setState(() {
        _filmResults = const [];
        _filmLoading = false;
      });
      return;
    }
    setState(() => _filmLoading = true);
    List<lg.MediaItem> results;
    try {
      final engine = await service.engine();
      final page = await engine.search(lg.SearchRequest(keyword: keyword));
      results = page.items;
    } catch (_) {
      results = const [];
    }
    if (!mounted || generation != _filmGeneration) return;
    setState(() {
      _filmResults = results;
      _filmLoading = false;
    });
  }

  List<Widget> _filmSectionSlivers() {
    if (_filmLoading && _filmResults.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: LoadingIndicator(size: 28)),
          ),
        ),
      ];
    }
    if (_filmResults.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: CrossSectionHeader(title: '影视', count: _filmResults.length),
      ),
      SliverToBoxAdapter(
        child: FilmRail(
          items: _filmResults.take(12).toList(),
          onTapItem: (item) => openFilmDetail(context, item),
        ),
      ),
    ];
  }

  List<Widget> _filmResultSlivers() {
    if (_filmLoading) {
      return const [SliverToBoxAdapter(child: _SearchLoadingState())];
    }
    final service = VideoEngineService.instance;
    service.loadRegistry();
    if (!service.hasSources) {
      return const [
        SliverToBoxAdapter(
          child: GeneralEmptyState(
            icon: AnikumoIcons.movie_rounded,
            title: '影视区还没有数据源',
          ),
        ),
      ];
    }
    final filtered = _filmResults.where(_filmFilter.matches).toList();
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in FilmCrossFilter.values) ...[
                  ChoiceChip(
                    label: Text(filter.label),
                    selected: _filmFilter == filter,
                    onSelected: (_) => setState(() => _filmFilter = filter),
                  ),
                  const SizedBox(width: 7),
                ],
                const SizedBox(width: 6),
                Text(
                  '${filtered.length} 部影视 · 点开进入影视专区',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (filtered.isEmpty)
        const SliverToBoxAdapter(
          child: GeneralEmptyState(
            icon: AnikumoIcons.movie_rounded,
            title: '没有找到影视',
          ),
        )
      else
        SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            childAspectRatio: 0.56,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) => FilmPosterCard(
            item: filtered[index],
            onTap: () => openFilmDetail(context, filtered[index]),
          ),
        ),
    ];
  }

  /// Batch 75: 「更多搜索」 for novels — every source the
  /// trio did not cover, unioned with the results already
  /// on screen.
  Future<void> _expandNovelSearch() async {
    final keyword = _novelKeyword;
    if (keyword.trim().isEmpty || _novelExpanding || _novelLoading) return;
    final generation = _novelGeneration;
    setState(() => _novelExpanding = true);
    List<NovelItem> rest;
    try {
      rest = await NovelApi.searchCrossRest(
        keyword,
        excludeIds: _novelSearchedIds,
      );
    } catch (_) {
      rest = const [];
    }
    if (!mounted || generation != _novelGeneration) return;
    _novelSearchedIds = {for (final source in NovelSources.all()) source.id};
    setState(() => _novelExpanding = false);
    if (rest.isEmpty) {
      AnikumoDialog.showToast(message: '其他源也没有找到更多结果');
      return;
    }
    final union = [..._novelRawAll, ...rest];
    _novelRawAll = union;
    setState(() {
      _novelResults = rankNovels(keyword, union, strict: true);
      _novelResultsAll = rankNovels(keyword, union);
    });
  }

  /// Batch 75: the dedicated manga/novel modes' footer —
  /// 「更多搜索」 widening plus the trio picker entry.
  List<Widget> _crossSearchFooter({required bool manga}) {
    final installedIds = manga
        ? {for (final source in MangaSources.all()) source.id}
        : {for (final source in NovelSources.all()) source.id};
    if (installedIds.isEmpty) return const [];
    final keyword = manga ? _mangaKeyword : _novelKeyword;
    if (keyword.trim().isEmpty) return const [];
    final searched = manga ? _mangaSearchedIds : _novelSearchedIds;
    final remaining = installedIds.difference(searched).length;
    final expanding = manga ? _mangaExpanding : _novelExpanding;
    final loading = manga ? _mangaLoading : _novelLoading;
    final theme = Theme.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
          child: Row(
            children: [
              if (expanding) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  '正在搜索更多源…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else if (remaining > 0)
                FilledButton.tonalIcon(
                  onPressed: loading
                      ? null
                      : (manga ? _expandMangaSearch : _expandNovelSearch),
                  icon: const Icon(
                    AnikumoIcons.manage_search_outlined,
                    size: 18,
                  ),
                  label: Text('更多搜索（还有 $remaining 个源）'),
                )
              else
                Text(
                  '已搜索全部 ${installedIds.length} 个源',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _pickCrossSources(manga: manga),
                icon: const Icon(AnikumoIcons.tune, size: 18),
                label: const Text('搜索源'),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Batch 75: pick which sources the default cross search
  /// uses (at most [maxCrossSearchSources]). Saving re-runs
  /// that zone's search with the new trio; an empty pick
  /// means "automatic", same as 恢复默认.
  Future<void> _pickCrossSources({required bool manga}) async {
    final options = manga
        ? [
            for (final source in MangaSources.sortForDisplay(
              MangaSources.all(),
            ))
              (id: source.id, name: source.name),
          ]
        : [
            for (final source in NovelSources.sortForDisplay(
              NovelSources.all(),
            ))
              (id: source.id, name: source.name),
          ];
    if (options.isEmpty) return;
    final selected = <String>{
      if (manga)
        for (final source in MangaApi.crossSearchSources()) source.id
      else
        for (final source in NovelApi.crossSearchSources()) source.id,
    };
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(manga ? '选择漫画搜索源' : '选择小说搜索源'),
        content: SizedBox(
          width: double.maxFinite,
          child: StatefulBuilder(
            builder: (context, setLocal) => ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '默认同时搜索的源，最多 $maxCrossSearchSources 个；'
                    '想一次搜全部源，用结果下方的「更多搜索」。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final option in options)
                  CheckboxListTile(
                    value: selected.contains(option.id),
                    title: Text(option.name),
                    onChanged: (checked) {
                      if (checked == true &&
                          !selected.contains(option.id) &&
                          selected.length >= maxCrossSearchSources) {
                        AnikumoDialog.showToast(
                          message: '最多选 $maxCrossSearchSources 个源',
                        );
                        return;
                      }
                      setLocal(() {
                        if (checked == true) {
                          selected.add(option.id);
                        } else {
                          selected.remove(option.id);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, const <String>[]),
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, selected.toList()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await GStorage.putSetting(
      manga
          ? SettingsKeys.mangaCrossSearchSourceIds
          : SettingsKeys.novelCrossSearchSourceIds,
      jsonEncode(result),
    );
    if (!mounted) return;
    if (manga) {
      if (_mangaKeyword.isNotEmpty) _searchManga(_mangaKeyword);
    } else {
      if (_novelKeyword.isNotEmpty) _searchNovel(_novelKeyword);
    }
  }

  List<Widget> _novelSectionSlivers() {
    if (_novelLoading) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: LoadingIndicator(size: 28)),
          ),
        ),
      ];
    }
    if (_novelResults.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: CrossSectionHeader(title: '小说', count: _novelResults.length),
      ),
      NovelResultsSliver(items: _novelResults.take(10).toList()),
    ];
  }

  List<Widget> _novelResultSlivers() {
    if (_novelLoading) {
      return const [SliverToBoxAdapter(child: _SearchLoadingState())];
    }
    if (_novelResultsAll.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: GeneralEmptyState(
            icon: AnikumoIcons.auto_stories_outlined,
            title: '没有找到小说',
          ),
        ),
        ..._crossSearchFooter(manga: false),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '${_novelResultsAll.length} 本小说 · 点一行进入小说专区',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      NovelResultsSliver(items: _novelResultsAll),
      ..._crossSearchFooter(manga: false),
    ];
  }

  List<Widget> _mangaSectionSlivers() {
    // Batch 72: partial merges render under the loading
    // state; the spinner only owns the section while
    // nothing has landed yet.
    if (_mangaLoading && _mangaResults.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: LoadingIndicator(size: 28)),
          ),
        ),
      ];
    }
    if (_mangaResults.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(
              '没有找到相关漫画',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: CrossSectionHeader(
          title: '漫画',
          count: _visibleMangaResults.length,
        ),
      ),
      MangaResultsSliver(items: _visibleMangaResults),
    ];
  }

  List<Widget> _mangaResultSlivers() {
    if (_mangaLoading && _mangaResultsAll.isEmpty) {
      return const [SliverToBoxAdapter(child: _SearchLoadingState())];
    }
    // Batch 64: the dedicated manga mode renders the
    // zone-faithful list, not the strict section list.
    final visible = _visibleMangaModeResults;
    if (visible.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: GeneralEmptyState(
            icon: AnikumoIcons.menu_book_outlined,
            title: _mangaResultsAll.isEmpty ? '没有找到漫画' : '找到的漫画都无法观看，已自动隐藏',
          ),
        ),
        ..._crossSearchFooter(manga: true),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '${visible.length} 部漫画 · 点封面进入漫画专区',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      MangaResultsSliver(items: visible),
      ..._crossSearchFooter(manga: true),
    ];
  }

  Future<void> _applyFilters(SearchFilterState filters) =>
      _submit(SearchParser.fromFilterState(filters));

  void _loadMoreOnScroll() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 360) return;
    _loadMore();
  }

  void _loadMore() {
    final query = _submittedQuery;
    if (query != null) _controller.searchBangumi(query);
  }

  Future<void> _showFilters() async {
    _inputFocus.unfocus();
    final result = await showAdaptiveBottomSheet<_SearchFilterResult>(
      context: context,
      maxHeightFactor: 0.9,
      builder: (_) => _SearchFilterSheet(
        initialState: SearchParser(_input.text).toFilterState(),
        initialNotShowWatched: _controller.notShowWatchedBangumis,
        initialNotShowAbandoned: _controller.notShowAbandonedBangumis,
      ),
    );
    if (!mounted || result == null) return;
    await _controller.setNotShowWatchedBangumis(result.notShowWatched);
    await _controller.setNotShowAbandonedBangumis(result.notShowAbandoned);
    if (!mounted) return;
    await _applyFilters(result.filterState);
  }

  void _clearSearch() {
    _inputFocus.unfocus();
    _writeInput('');
    _mangaGeneration++;
    setState(() {
      _submittedQuery = null;
      _managingHistory = false;
      _mangaResults = const [];
      _mangaLoading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _searchField() {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (context, value, child) => SearchBar(
        controller: _input,
        focusNode: _inputFocus,
        hintText: '搜索番剧名称',
        textInputAction: TextInputAction.search,
        constraints: const BoxConstraints(minHeight: 64),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        leading: IconButton(
          tooltip: '搜索',
          onPressed: () => _submit(_input.text),
          icon: const Icon(AnikumoIcons.search_rounded),
        ),
        trailing: [
          if (value.text.isNotEmpty || _hasSearched)
            IconButton(
              tooltip: '清空搜索',
              onPressed: _clearSearch,
              icon: const Icon(AnikumoIcons.close_rounded),
            ),
          if (value.text.trim().isNotEmpty)
            IconButton(
              tooltip: '保存这次搜索',
              onPressed: () async {
                await SavedSearchStore.add(value.text);
                if (context.mounted) {
                  AnikumoDialog.showToast(message: '已保存到「我保存的搜索」');
                }
              },
              icon: const Icon(AnikumoIcons.bookmark_add_outlined),
            ),
        ],
        onSubmitted: _submit,
      ),
    );
  }

  /// Batch 110: discovery section label — signature
  /// accent bar + bold title, the same voice as the
  /// result section bars.
  Widget _sectionLabel(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Row(
        children: [
          const SectionAccentBar(height: 15),
          const SizedBox(width: 8),
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  /// Batch 15 (G8): saved search keywords, one tap to re-run,
  /// long-press to remove.
  Widget _savedSearchesSection(ThemeData theme) {
    final saved = SavedSearchStore.load();
    if (saved.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('我保存的搜索'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in saved)
                GestureDetector(
                  onLongPress: () async {
                    await SavedSearchStore.remove(keyword);
                    if (mounted) setState(() {});
                  },
                  child: ActionChip(
                    avatar: const Icon(AnikumoIcons.bookmark_rounded, size: 16),
                    label: Text(keyword),
                    onPressed: () {
                      _input.text = keyword;
                      _submit(keyword);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _header() => Padding(
    key: _searchHeaderKey,
    padding: EdgeInsets.only(top: _hasSearched ? 8 : 24, bottom: 16),
    child: _searchField(),
  );

  Widget _discovery() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _savedSearchesSection(theme),
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: const Icon(AnikumoIcons.tune_rounded),
            title: const Text('按条件查找'),
            subtitle: const Text('题材、放送时间与评分'),
            trailing: const Icon(AnikumoIcons.chevron_right_rounded),
            onTap: _showFilters,
          ),
        ),
        const SizedBox(height: 28),
        Observer(
          builder: (_) {
            final histories = _controller.searchHistories.toList();
            if (histories.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4, bottom: 4),
                  child: Row(
                    children: [
                      const SectionAccentBar(height: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '最近搜索',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (_managingHistory)
                        TextButton(
                          onPressed: () async {
                            await _controller.clearSearchHistory();
                            if (mounted) {
                              setState(() => _managingHistory = false);
                            }
                          },
                          child: const Text('清空'),
                        ),
                      TextButton(
                        onPressed: () => setState(
                          () => _managingHistory = !_managingHistory,
                        ),
                        child: Text(_managingHistory ? '完成' : '管理'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final history in histories.take(10))
                        InputChip(
                          avatar: const Icon(
                            AnikumoIcons.history_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _readableQuery(history.keyword),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          shape: const StadiumBorder(),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHigh,
                          onPressed: () => _submit(history.keyword),
                          onDeleted: _managingHistory
                              ? () => _controller.deleteSearchHistory(history)
                              : null,
                          deleteIcon: const Icon(
                            AnikumoIcons.close_rounded,
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<Widget> _resultSlivers(double width) {
    final allItems = _controller.bangumiList.toList();
    final watched = _controller.notShowWatchedBangumis
        ? _controller.loadWatchedBangumiIds()
        : <int>{};
    final abandoned = _controller.notShowAbandonedBangumis
        ? _controller.loadAbandonedBangumiIds()
        : <int>{};
    final items = allItems
        .where(
          (item) => !watched.contains(item.id) && !abandoned.contains(item.id),
        )
        .toList();
    final busy = _controller.isLoading;
    final failed = _controller.isTimeOut || _controller.isSearchError;
    final submitted = SearchParser(_submittedQuery!).toFilterState();
    final summary = _filterSummary(submitted);

    final modeSwitchSliver = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          // Batch 231: five modes — scroll on narrow
          // screens rather than overflow.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: CrossSearchModeSwitch(
              mode: _searchMode,
              onChanged: (mode) {
                setState(() => _searchMode = mode);
                _ensureModeData(mode);
              },
            ),
          ),
        ),
      ),
    );
    if (_searchMode == CrossSearchMode.manga) {
      return [modeSwitchSliver, ..._mangaResultSlivers()];
    }
    if (_searchMode == CrossSearchMode.novel) {
      return [modeSwitchSliver, ..._novelResultSlivers()];
    }
    if (_searchMode == CrossSearchMode.film) {
      return [modeSwitchSliver, ..._filmResultSlivers()];
    }

    final animeSlivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '搜索结果',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!submitted.isIdSearch)
                    _SearchSortMenu(
                      value: submitted.sort,
                      onChanged: (sort) =>
                          _applyFilters(submitted.copyWith(sort: sort)),
                    ),
                  IconButton(
                    tooltip: '筛选番剧',
                    onPressed: _showFilters,
                    icon: Badge(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      isLabelVisible:
                          submitted.hasAdvancedFilters ||
                          _controller.notShowWatchedBangumis ||
                          _controller.notShowAbandonedBangumis,
                      smallSize: 6,
                      child: const Icon(AnikumoIcons.tune_rounded),
                    ),
                  ),
                ],
              ),
              Text(
                busy
                    ? '正在搜索…'
                    : '${items.length} 部番剧${items.length < allItems.length ? ' · 隐藏 ${allItems.length - items.length} 部' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_controller.fallbackKeywordUsed.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '原关键词无结果，已改用「${_controller.fallbackKeywordUsed}」搜索',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      if (busy && allItems.isEmpty)
        const SliverToBoxAdapter(child: _SearchLoadingState())
      else if (allItems.isEmpty)
        SliverToBoxAdapter(
          child: _controller.isSearchError
              ? GeneralEmptyState(
                  icon: AnikumoIcons.cloud_off_rounded,
                  title: '网络开小差了，搜索没能完成',
                  actions: [
                    StateActionButton.tonal(
                      onPressed: () => _submit(_submittedQuery!),
                      icon: AnikumoIcons.refresh_rounded,
                      text: '重试',
                    ),
                  ],
                )
              : const GeneralEmptyState(
                  icon: AnikumoIcons.search_off_rounded,
                  title: '没有找到番剧',
                ),
        )
      else if (items.isEmpty)
        SliverToBoxAdapter(
          child: GeneralEmptyState(
            icon: AnikumoIcons.filter_alt_off_rounded,
            title: '这些番剧被筛选隐藏了',
            actions: [
              StateActionButton.tonal(
                onPressed: () async {
                  await _controller.setNotShowWatchedBangumis(false);
                  await _controller.setNotShowAbandonedBangumis(false);
                },
                icon: AnikumoIcons.visibility_outlined,
                text: '显示全部',
              ),
            ],
          ),
        )
      else
        _SearchResultGrid(
          items: items,
          width: width,
          showRating: GStorage.getSetting(SettingsKeys.showRating),
        ),
      if (allItems.isNotEmpty || !failed)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: busy
                  ? (allItems.isEmpty
                        ? const SizedBox.shrink()
                        : const LoadingIndicator(size: 32))
                  : _controller.hasMoreSearchResults
                  ? TextButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(AnikumoIcons.expand_more_rounded),
                      label: const Text('加载更多'),
                    )
                  : Text(
                      '已经看到全部结果',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
        ),
    ];

    if (_searchMode == CrossSearchMode.all) {
      if (allItems.isEmpty && !_mangaLoading && _mangaResults.isNotEmpty) {
        // Anime found nothing but manga did: don't lead with the
        // anime empty state.
        return [modeSwitchSliver, ..._mangaSectionSlivers()];
      }
      return [
        modeSwitchSliver,
        ...animeSlivers,
        ..._mangaSectionSlivers(),
        ..._novelSectionSlivers(),
        ..._filmSectionSlivers(),
      ];
    }
    return [modeSwitchSliver, ...animeSlivers];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(
        backgroundColor: Colors.transparent,
        title: Text('番剧搜索'),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 700 ? 32.0 : 20.0;
            final width = math.min(
              _hasSearched ? 1120.0 : 760.0,
              constraints.maxWidth - horizontal * 2,
            );
            final inset = (constraints.maxWidth - width) / 2;
            final pinSearch =
                _hasSearched &&
                constraints.maxHeight >= 420 &&
                MediaQuery.textScalerOf(context).scale(16) <= 24;
            Widget scrollView(List<Widget> slivers) => CustomScrollView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, 24),
                  sliver: SliverMainAxisGroup(slivers: slivers),
                ),
              ],
            );
            return Column(
              children: [
                if (pinSearch)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: _header(),
                  ),
                Expanded(
                  child: _hasSearched
                      ? AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOut,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
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
                            key: ValueKey('$_searchMode|$_submittedQuery'),
                            child: Observer(
                              builder: (_) => scrollView([
                                if (!pinSearch)
                                  SliverToBoxAdapter(child: _header()),
                                ..._resultSlivers(width),
                              ]),
                            ),
                          ),
                        )
                      : scrollView([
                          SliverToBoxAdapter(child: _header()),
                          SliverToBoxAdapter(child: _discovery()),
                        ]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
