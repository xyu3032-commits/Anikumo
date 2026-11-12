import 'package:flutter/material.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/liuguang/cms_api_source.dart';
import 'package:anikumo/services/liuguang/film_prefs.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 205: 发现 — the five-dimension filter wall the
/// user specified, all combinable:
///   电视剧/电影 · 分类（源的分类树） · 标签（题材） ·
///   年代 · 地区（日本 / 中国 / 美国 …）
/// Browsing fanned out to one selected source at a time
/// until Batch 238 added the aggregated 全部接口 mode;
/// Batch 243 removed the source chips at the user's
/// word — the tab is aggregated-only now, fanning out to
/// every enabled source in parallel and merging with
/// same-work de-duplication.
/// Batch 248: runs one browse job per source in parallel
/// and reports the merged wall after EVERY job settles —
/// the grid paints with the fastest source instead of
/// waiting for the slowest (the pre-248 Future.wait over
/// all sources). [onUpdate] receives the items merged so
/// far (in provider order), how many jobs returned a
/// page, and the largest totalPages seen. A failed job
/// contributes nothing. The returned future completes
/// when every job has settled.
Future<void> runProgressiveBrowse(
  List<Future<SearchPage?> Function()> jobs, {
  required void Function(List<MediaItem> merged, int landed, int totalPages)
  onUpdate,
}) async {
  if (jobs.isEmpty) {
    onUpdate(const [], 0, 1);
    return;
  }
  final perJob = List<List<MediaItem>?>.filled(jobs.length, null);
  var landed = 0;
  var totalPages = 1;
  await Future.wait([
    for (var i = 0; i < jobs.length; i++)
      () async {
        SearchPage? result;
        try {
          result = await jobs[i]();
        } catch (_) {
          result = null;
        }
        if (result != null) {
          landed++;
          perJob[i] = result.items;
          if (result.totalPages > totalPages) {
            totalPages = result.totalPages;
          }
        } else {
          perJob[i] = const [];
        }
        onUpdate(
          mergeFilmBrowseItems([for (final l in perJob) ?l]),
          landed,
          totalPages,
        );
      }(),
  ]);
}

class FilmDiscoverTab extends StatefulWidget {
  const FilmDiscoverTab({
    super.key,
    this.standalone = false,
    this.initialKind,
    this.initialGenre,
    this.initialArea,
    this.initialYear,
    this.initialSourceId,
    this.forceAllSources = false,
  });

  /// Batch 247: a standalone page that still browses
  /// every source (the tag page — a tag's works live
  /// across sources, unlike a home rail's own shelf).
  final bool forceAllSources;

  /// Batch 222: standalone mode hosts this filter wall as
  /// its own page — a home rail's 全部 entry opens it with
  /// the rail's filter pre-applied (the user's words:
  /// 相当于自动输入）, and the headline names the seeded
  /// tag （爱情 · 电视剧） instead of 发现. Every chip
  /// stays editable, so other tags are one tap away.
  final bool standalone;
  final FilmKindFilter? initialKind;
  final String? initialGenre;
  final String? initialArea;
  final int? initialYear;
  final String? initialSourceId;

  @override
  State<FilmDiscoverTab> createState() => _FilmDiscoverTabState();
}

/// Batch 222: arguments for the standalone browse page.
class FilmAllArgs {
  const FilmAllArgs({
    required this.kind,
    this.genre,
    this.area,
    this.year,
    this.sourceId,
    this.allSources = false,
    this.title,
  });

  final FilmKindFilter kind;
  final String? genre;
  final String? area;
  final int? year;
  final String? sourceId;

  /// Batch 247: browse every source instead of one
  /// (the tag page).
  final bool allSources;

  /// Batch 247: an optional AppBar title for the page
  /// (the tag page names its tag; rail pages stay bare).
  final String? title;
}

/// Batch 222: the standalone page hosting [FilmDiscoverTab]
/// pre-filtered by a home rail.
class FilmAllPage extends StatelessWidget {
  const FilmAllPage({super.key, required this.args});

  final FilmAllArgs args;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: args.title == null
          ? null
          : AppBar(title: Text(args.title!), titleSpacing: 4),
      body: SafeArea(
        child: FilmDiscoverTab(
          standalone: true,
          initialKind: args.kind,
          initialGenre: args.genre,
          initialArea: args.area,
          initialYear: args.year,
          initialSourceId: args.sourceId,
          forceAllSources: args.allSources,
        ),
      ),
    );
  }
}

/// Batch 259: the genre/area chips are the FIXED
/// taxonomy (kFilmGenres / kFilmAreas) plus 其他 — the
/// user's standing rule, re-affirmed after batch 255's
/// interface-harvested vocabularies put area words
/// （土耳其） in the genre row on device. Interface
/// words only map works onto the fixed table (the
/// browse matchers fold them); TMDB/Bangumi words
/// never reach these chips.
class _FilmDiscoverTabState extends State<FilmDiscoverTab> {
  final ScrollController _scroll = ScrollController();

  VideoSourceEntry? _entry;
  CmsApiSource? _provider;
  List<CmsCategory> _categories = [];

  FilmKindFilter _kindFilter = FilmKindFilter.all;
  CmsCategory? _root;
  int? _typeId;
  String? _genre;
  int? _year;
  String? _area;

  /// The fixed genre chips; a legacy active value from
  /// a deep link stays pinned at the head so the current
  /// filter never renders unselected.
  List<String> get _genreVocab {
    final active = _genre;
    if (active != null && active != '其他' && !kFilmGenres.contains(active)) {
      return [active, ...kFilmGenres];
    }
    return kFilmGenres;
  }

  List<(String, String)> get _areaVocab {
    final pairs = [for (final a in kFilmAreas) (a, a)];
    final active = _area;
    if (active != null && active != '其他' && !pairs.any((p) => p.$2 == active)) {
      pairs.insert(0, (cmsAreaChip(active).$1, active));
    }
    return pairs;
  }

  /// Batch 222: the source a standalone page was opened
  /// for; consumed by the first bind only.
  String? _preferredSourceId;

  /// Batch 238/243: 全部接口 mode — every enabled source
  /// is browsed in parallel and the pages merged with
  /// same-work de-duplication. Batch 243 made it the
  /// discover tab's only mode (the source chips were
  /// removed at the user's word); standalone pages keep
  /// their single bound source.
  bool get _allSources => !widget.standalone || widget.forceAllSources;

  List<MediaItem> _items = [];
  int _page = 0;
  int _totalPages = 1;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  /// Batch 210: load generation. Filter changes reset the
  /// list and bump this; a slower response from the previous
  /// filter that lands afterwards must not append its items
  /// into the new filter's grid (the "same title twice, one
  /// without info" mix the user reported).
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    // Batch 222: seed the standalone page's filters.
    // Batch 256: the kind row is 全部/电影/电视剧/综艺/
    // 漫剧/其他 — an incoming 动漫/短剧/直播 kind (a home
    // channel's 全部, a tag page) lands in the residual
    // 其他 bucket, which is where those kinds live now.
    if (widget.initialKind != null) {
      _kindFilter = switch (widget.initialKind!) {
        FilmKindFilter.anime ||
        FilmKindFilter.shortDrama ||
        FilmKindFilter.live => FilmKindFilter.other,
        final k => k,
      };
    }
    _genre = widget.initialGenre;
    _area = widget.initialArea;
    _year = widget.initialYear;
    _preferredSourceId = widget.initialSourceId;
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) {
        _loadMore();
      }
    });
    VideoEngineService.instance.addListener(_onRegistryChanged);
    _bindSource();
  }

  @override
  void dispose() {
    VideoEngineService.instance.removeListener(_onRegistryChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onRegistryChanged() {
    if (mounted) _bindSource();
  }

  /// Batch 226: whether the category tree has arrived —
  /// the 直播 filter can only bind (or report missing)
  /// once it has.
  bool _categoriesLoaded = false;

  /// Batch 226: the 直播 kind filter is category-driven —
  /// bind it to the source's first live category. Returns
  /// true when a binding exists. A live LEAF is preferred
  /// over its root: items carry leaf ids, and not every
  /// station aggregates children under a root query.
  bool _bindLiveCategory() {
    if (_kindFilter != FilmKindFilter.live || _typeId != null) {
      return _typeId != null;
    }
    final live = [
      for (final cat in _categories)
        if (cmsIsLiveName(cat.name)) cat,
    ];
    if (live.isEmpty) return false;
    final cat = live.firstWhere((c) => !c.isRoot, orElse: () => live.first);
    _typeId = cat.id;
    _root = _categories.where((c) => c.id == cat.parentId).firstOrNull;
    return true;
  }

  /// After categories land, a pending 直播 filter binds
  /// and reloads (or reports the source has no live shelf).
  void _afterCategories() {
    if (_kindFilter == FilmKindFilter.live && _typeId == null) {
      _bindLiveCategory();
      _resetAndLoad();
    }
  }

  /// Batch 260: the category-tree root that shares a
  /// kind button's label （电视剧 / 电影 / 综艺 / 漫剧）.
  /// The two used to render as duplicate chips with
  /// different meanings; now the kind button also
  /// expands that root's children, and the root itself
  /// gets no second chip.
  CmsCategory? _rootForKind(FilmKindFilter kind) {
    for (final c in _categories) {
      if (c.isRoot && c.name == kind.label) return c;
    }
    return null;
  }

  void _bindSource() {
    final service = VideoEngineService.instance;
    service.loadRegistry();
    final enabled = service.sources.where((s) => s.enabled).toList();
    // Batch 243: the tab always aggregates every enabled
    // source (Batch 238's source chips are gone at the
    // user's word); the entry bound here only supplies
    // the category tree. Standalone pages still bind
    // their own argument.
    final wantedId = _preferredSourceId ?? _entry?.id;
    _preferredSourceId = null;
    final entry = enabled.isEmpty
        ? null
        : enabled.firstWhere(
            (e) => e.id == wantedId,
            orElse: () => enabled.first,
          );
    if (entry?.id == _entry?.id && _provider != null) return;
    _entry = entry;
    final provider = entry == null ? null : service.providerFor(entry);
    _provider = provider is CmsApiSource ? provider : null;
    _categories = [];
    _categoriesLoaded = false;
    _root = null;
    _typeId = null;
    _resetAndLoad();
    _provider?.categories().then((cats) {
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _categoriesLoaded = true;
        if (_root == null && _typeId == null) {
          _root = _rootForKind(_kindFilter);
        }
      });
      _afterCategories();
    }).ignore();
  }

  Future<void> _resetAndLoad() async {
    final gen = ++_loadGen;
    _items = [];
    _page = 0;
    _totalPages = 1;
    _error = null;
    _loadingMore = false;
    await _loadPage(1, gen);
  }

  Future<void> _loadPage(int page, int gen) async {
    if (page == 1) {
      _loading = true;
    } else {
      _loadingMore = true;
    }
    if (mounted) setState(() {});
    // Batch 238: the aggregated mode has its own loader
    // (parallel fan-out + merge) and does not depend on
    // the single bound provider; the single-source path
    // below is untouched.
    if (_allSources) {
      await _loadPageAll(page, gen);
      return;
    }
    final provider = _provider;
    if (provider == null) {
      _loading = false;
      _loadingMore = false;
      if (mounted) setState(() {});
      return;
    }
    // Batch 226: 直播 without a bound category must not
    // fall back to browsing the whole catalogue — wait for
    // the category tree, then either bind or report that
    // this source has no live shelf.
    if (_kindFilter == FilmKindFilter.live && _typeId == null) {
      _loading = false;
      _loadingMore = false;
      if (_categoriesLoaded && page == 1) {
        _error = '当前数据源没有直播分类。';
      }
      if (mounted) setState(() {});
      return;
    }
    try {
      // Batch 256: the residual 其他 kind browses the
      // unconstrained catalogue and post-filters by the
      // marker match — a filtered page can come back
      // empty while later pages still hold residual
      // works, so an empty page walks forward (at most
      // three extra pages per load).
      final residual = _kindFilter == FilmKindFilter.other && _typeId == null;
      var pageItems = <MediaItem>[];
      var totalPages = 0;
      var at = page;
      while (true) {
        final result = await provider.browse(
          page: at,
          typeId: _typeId,
          kind: _typeId == null ? _kindFilter.mediaType : null,
          genre: _genre,
          year: _year,
          area: _area,
          variety: _typeId == null ? _kindFilter.varietyOnly : null,
          anime: _typeId == null ? _kindFilter.animeOnly : null,
          shortDrama: _typeId == null ? _kindFilter.shortDramaOnly : null,
          manju: _typeId == null ? _kindFilter.manjuOnly : null,
        );
        // Batch 210: a stale response (the filter changed
        // while this was in flight) is discarded wholesale.
        if (gen != _loadGen) return;
        totalPages = result.totalPages;
        pageItems = residual
            ? result.items.where(_kindFilter.matches).toList()
            : result.items;
        if (!residual || pageItems.isNotEmpty || at >= totalPages) break;
        if (at - page >= 3) break;
        at++;
      }
      // The accumulated display list is also de-duplicated
      // as a whole: a poster-less stub twin of a title that
      // arrived complete on another page leaves the grid.
      _items = dedupeBrowseItems(
        page == 1 ? pageItems : [..._items, ...pageItems],
      );
      _page = at;
      _totalPages = totalPages;
      _error = null;
    } catch (e) {
      if (gen == _loadGen && page == 1) _error = '加载失败：$e';
    } finally {
      if (gen == _loadGen) {
        _loading = false;
        _loadingMore = false;
      }
      if (mounted) setState(() {});
    }
  }

  /// Batch 238: one page of the 全部接口 mode. Every
  /// enabled interface is asked in parallel (each source
  /// keeps its own request gate, so a wall of sources
  /// does not turn into a wall of connections per source),
  /// in measured-speed order; the pages merge with
  /// same-work de-duplication, fastest source winning a
  /// duplicate. A source that errors or lacks the picked
  /// category simply contributes nothing — one dead
  /// interface must not sink the aggregate.
  Future<void> _loadPageAll(int page, int gen) async {
    final service = VideoEngineService.instance;
    final enabled = service.sources.where((s) => s.enabled).toList();
    // Batch 250: under a 自定义 playback pin, the
    // pinned interface leads the merge so its copies
    // win aggregation.
    final providers = FilmPlaybackSource.pinnedFirst(
      FilmSourceSpeeds.orderBySpeed(
        [
          for (final entry in enabled)
            if (service.providerFor(entry) case final CmsApiSource cms)
              (entry, cms),
        ],
        (p) => p.$1.id,
        DateTime.now(),
      ),
      (p) => p.$1.id,
    );
    try {
      if (_kindFilter == FilmKindFilter.live) {
        // Live is category-driven per source: each station
        // contributes its own 直播 categories' first page.
        if (page > 1) return;
        // Batch 248: progressive — each station's
        // channels paint as they land.
        await runProgressiveBrowse(
          [
            for (final (_, provider) in providers)
              () async {
                try {
                  final cats = await provider.categories();
                  final liveCats = [
                    for (final c in cats)
                      if (cmsIsLiveName(c.name)) c,
                  ];
                  final items = <MediaItem>[];
                  final seen = <String>{};
                  for (final cat in liveCats.take(6)) {
                    try {
                      final pg = await provider.browse(typeId: cat.id, page: 1);
                      for (final item in pg.items) {
                        if (seen.add(item.id)) items.add(item);
                      }
                    } catch (_) {}
                  }
                  return SearchPage(items: items, totalResults: items.length);
                } catch (_) {
                  return null;
                }
              },
          ],
          onUpdate: (merged, landed, totalPages) {
            if (gen != _loadGen || !mounted) return;
            _items = merged;
            _page = 1;
            _totalPages = 1;
            setState(() {});
          },
        );
        if (gen != _loadGen) return;
        _error = _items.isEmpty ? '全部接口都没有取到直播内容。' : null;
        return;
      }
      // A picked category is identified by NAME across
      // sources — category ids are per-station and never
      // line up. A source without that category sits this
      // query out.
      final catName = _typeId == null
          ? null
          : _categories.where((c) => c.id == _typeId).firstOrNull?.name;
      // Batch 248: progressive merge — each source's
      // page merges and paints as it lands (in speed
      // order) instead of the whole wall waiting for
      // the slowest source.
      final baseItems = page == 1 ? const <MediaItem>[] : List.of(_items);
      var landedCount = 0;
      await runProgressiveBrowse(
        [
          for (final (_, provider) in providers)
            () async {
              try {
                if (catName != null) {
                  final cats = await provider.categories();
                  final local = cats
                      .where((c) => c.name == catName)
                      .firstOrNull;
                  if (local == null) return null;
                  // Batch 259: the explicit 题材/地区/
                  // 年份 filters ride along — a bound
                  // category must not silently drop them.
                  return await provider.browse(
                    typeId: local.id,
                    page: page,
                    genre: _genre,
                    area: _area,
                    year: _year,
                  );
                }
                return await provider.browse(
                  page: page,
                  kind: _kindFilter.mediaType,
                  genre: _genre,
                  year: _year,
                  area: _area,
                  variety: _kindFilter.varietyOnly,
                  anime: _kindFilter.animeOnly,
                  shortDrama: _kindFilter.shortDramaOnly,
                  manju: _kindFilter.manjuOnly,
                );
              } catch (_) {
                return null;
              }
            },
        ],
        onUpdate: (merged, landed, totalPages) {
          if (gen != _loadGen || !mounted) return;
          landedCount = landed;
          if (landed == 0) return;
          // Batch 256: residual kind post-filter, same
          // as the single-source path.
          final shown = _kindFilter == FilmKindFilter.other && _typeId == null
              ? merged.where(_kindFilter.matches).toList()
              : merged;
          _items = page == 1 ? shown : mergeFilmBrowseItems([baseItems, shown]);
          _page = page;
          _totalPages = totalPages;
          _error = null;
          setState(() {});
        },
      );
      if (gen != _loadGen) return;
      if (landedCount == 0) {
        if (page == 1) _error = '全部接口都没有返回内容，请稍后重试。';
        return;
      }
    } finally {
      if (gen == _loadGen) {
        _loading = false;
        _loadingMore = false;
      }
      if (mounted) setState(() {});
    }
  }

  void _loadMore() {
    if (_loading || _loadingMore || _page >= _totalPages) return;
    _loadPage(_page + 1, _loadGen);
  }

  void _changed() {
    setState(() {});
    _resetAndLoad();
  }

  /// Batch 222: the standalone page's headline — the tag
  /// the page is currently filtered to.
  String get _standaloneTitle {
    if (_genre != null) return _genre!;
    if (_area != null) {
      for (final (label, value) in _areaVocab) {
        if (value == _area) return label;
      }
      return _area!;
    }
    if (_year != null) return '$_year 新作';
    return '全部内容';
  }

  String get _standaloneEyebrow {
    final dimension = _genre != null
        ? '题材'
        : _area != null
        ? '地区'
        : _year != null
        ? '年份'
        : '全部';
    return '${_kindFilter.label} · $dimension';
  }

  @override
  Widget build(BuildContext context) {
    final service = VideoEngineService.instance;
    if (!service.hasSources) {
      return const FilmEmptyState(
        icon: AnikumoIcons.travel_explore_rounded,
        title: '还没有可用的数据源',
        message:
            '添加仓库或接口后，这里可以按电视剧 / 电影、'
            '分类、题材标签、年代和地区筛选浏览。',
      );
    }
    final roots = _categories.where((c) => c.isRoot).toList();
    final children = _root == null
        ? <CmsCategory>[]
        : _categories.where((c) => c.parentId == _root!.id).toList();
    final years = [for (var y = DateTime.now().year; y >= 2017; y--) y];
    // Batch 227: the header is no longer a fixed block
    // eating the top of the screen — title and filter
    // chips ride slivers and scroll away with the grid,
    // the way the anime pages are built (their title bars
    // are SliverToBoxAdapters too). Standalone pages keep
    // their back-button title row pinned so the way back
    // never scrolls off.
    final titleWidget = widget.standalone
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 10),
                child: IconButton(
                  icon: const Icon(AnikumoIcons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: FilmEditorialTitle(
                  eyebrow: _standaloneEyebrow,
                  title: filmHeadline(context, _standaloneTitle),
                  padding: const EdgeInsets.fromLTRB(4, 14, 20, 10),
                ),
              ),
            ],
          )
        : FilmEditorialTitle(
            eyebrow: 'DISCOVER · 发现',
            title: filmHeadline(context, '发现'),
          );
    final chipsWidget = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chipRow([
            // Batch 256: exactly six kind buttons — the
            // rest of the old kinds live in 其他 (and in
            // 题材, when the interface tags items so).
            for (final filter in const [
              FilmKindFilter.all,
              FilmKindFilter.movie,
              FilmKindFilter.series,
              FilmKindFilter.variety,
              FilmKindFilter.manju,
              FilmKindFilter.other,
            ])
              ChoiceChip(
                label: Text(filter.label),
                selected:
                    _kindFilter == filter &&
                    (_typeId == null || filter == FilmKindFilter.live),
                onSelected: (_) {
                  _kindFilter = filter;
                  // Batch 260: a kind whose label names a
                  // tree root expands that root's children
                  // (no duplicate root chip is rendered).
                  _root = _rootForKind(filter);
                  _typeId = null;
                  // Batch 226: 直播 binds to its category
                  // right away when the tree is loaded.
                  if (filter == FilmKindFilter.live) {
                    _bindLiveCategory();
                  }
                  _changed();
                },
              ),
            // Batch 260: roots named 电影/电视剧/综艺/漫剧/
            // 动漫/短剧/直播/其他 are already kind buttons
            // above — never render the same label twice.
            for (final root in roots)
              if (!FilmKindFilter.values.any((f) => f.label == root.name))
                ChoiceChip(
                  label: Text(root.name),
                  selected: _root?.id == root.id && _typeId == root.id,
                  onSelected: (_) {
                    _root = root;
                    _typeId = root.id;
                    _changed();
                  },
                ),
          ]),
          if (children.isNotEmpty)
            _chipRow([
              for (final child in children)
                ChoiceChip(
                  label: Text(child.name),
                  selected: _typeId == child.id,
                  onSelected: (_) {
                    _typeId = child.id;
                    _changed();
                  },
                ),
            ]),
          _chipRow([
            ChoiceChip(
              label: const Text('全部题材'),
              selected: _genre == null,
              onSelected: (_) {
                _genre = null;
                _changed();
              },
            ),
            for (final g in [..._genreVocab, '其他'])
              ChoiceChip(
                label: Text(g),
                selected: _genre == g,
                onSelected: (_) {
                  _genre = g;
                  _changed();
                },
              ),
          ]),
          _chipRow([
            ChoiceChip(
              label: const Text('全部年代'),
              selected: _year == null,
              onSelected: (_) {
                _year = null;
                _changed();
              },
            ),
            for (final y in years)
              ChoiceChip(
                label: Text('$y'),
                selected: _year == y,
                onSelected: (_) {
                  _year = y;
                  _changed();
                },
              ),
          ]),
          _chipRow([
            ChoiceChip(
              label: const Text('全部地区'),
              selected: _area == null,
              onSelected: (_) {
                _area = null;
                _changed();
              },
            ),
            for (final (label, value) in [..._areaVocab, ('其他', '其他')])
              ChoiceChip(
                label: Text(label),
                selected: _area == value,
                onSelected: (_) {
                  _area = value;
                  _changed();
                },
              ),
          ]),
        ],
      ),
    );
    final scrollView = RefreshIndicator(
      onRefresh: () async {
        _provider?.invalidateBrowseCache();
        await _resetAndLoad();
      },
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (!widget.standalone) SliverToBoxAdapter(child: titleWidget),
          SliverToBoxAdapter(child: chipsWidget),
          ..._contentSlivers(context),
        ],
      ),
    );
    if (widget.standalone) {
      return Column(
        children: [
          titleWidget,
          Expanded(child: scrollView),
        ],
      );
    }
    return scrollView;
  }

  Widget _chipRow(List<Widget> chips) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            chips[i],
          ],
        ],
      ),
    );
  }

  /// Batch 227: the grid as slivers under the scrolling
  /// header (loading / error / empty states fill the rest
  /// of the viewport below the header).
  List<Widget> _contentSlivers(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const [
        SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
      ];
    }
    if (_error != null && _items.isEmpty) {
      return [
        SliverFillRemaining(
          child: FilmEmptyState(
            icon: AnikumoIcons.travel_explore_rounded,
            title: '发现',
            message: _error!,
            actionLabel: '重试',
            onAction: _resetAndLoad,
          ),
        ),
      ];
    }
    if (_items.isEmpty) {
      return const [
        SliverFillRemaining(
          child: FilmEmptyState(
            icon: AnikumoIcons.travel_explore_rounded,
            title: '没有符合条件的内容',
            message: '换一组筛选条件试试。',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: 0.56,
          ),
          delegate: SliverChildBuilderDelegate((context, i) {
            if (i >= _items.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final item = _items[i];
            return FilmPosterCard(
              item: item,
              onTap: () => openFilmDetail(context, item),
            );
          }, childCount: _items.length + (_loadingMore ? 1 : 0)),
        ),
      ),
    ];
  }
}
