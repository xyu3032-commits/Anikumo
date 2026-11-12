import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_discover_tab.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/liuguang/cms_api_source.dart';
import 'package:anikumo/services/liuguang/tmdb_enrich.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

/// Batch 205: 搜索 — the engine's aggregated search across
/// every enabled source, presented grouped by source (the
/// house pattern from the novel/manga zones), with a
/// 电视剧 / 电影 quick filter on top.
class FilmSearchPage extends StatefulWidget {
  const FilmSearchPage({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<FilmSearchPage> createState() => _FilmSearchPageState();
}

class _FilmSearchPageState extends State<FilmSearchPage> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );

  bool _searching = false;
  String? _error;
  List<MediaItem> _results = [];
  FilmKindFilter _kindFilter = FilmKindFilter.all;
  bool _searched = false;

  /// Batch 230: TMDB mode — works from TMDB, playability
  /// matched against the installed sources per work.
  bool _tmdbMode = false;
  List<TmdbWork> _works = [];
  TmdbWorkMatcher? _matcher;

  /// Work index → matched items (null while resolving).
  final Map<int, List<MediaItem>?> _matchesByIndex = {};
  int _searchGen = 0;
  bool _openingWork = false;

  bool get _tmdbAvailable => TmdbEpisodeService.hasKey;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty || _searching) return;
    if (_tmdbMode) {
      await _searchTmdb(keyword);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final engine = await VideoEngineService.instance.engine();
      final page = await engine.search(SearchRequest(keyword: keyword));
      _results = page.items;
      _searched = true;
    } catch (e) {
      _error = '搜索失败：$e';
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Batch 230: TMDB mode search — fetch the works, then
  /// resolve each one's playable sources in the
  /// background (three at a time), badging cards as the
  /// answers land.
  Future<void> _searchTmdb(String keyword) async {
    final gen = ++_searchGen;
    setState(() {
      _searching = true;
      _error = null;
      _works = [];
      _matchesByIndex.clear();
      _matcher = null;
    });
    final works = await TmdbEnrichService.instance.searchWorks(keyword);
    if (!mounted || gen != _searchGen) return;
    final engine = await VideoEngineService.instance.engine();
    if (!mounted || gen != _searchGen) return;
    _matcher = TmdbWorkMatcher(
      (kw) async => (await engine.search(SearchRequest(keyword: kw))).items,
    );
    setState(() {
      _works = works;
      _searched = true;
      _searching = false;
    });
    var next = 0;
    Future<void> worker() async {
      while (next < works.length) {
        final index = next++;
        final matches = await _matcher!.matchesFor(works[index]);
        if (!mounted || gen != _searchGen) return;
        setState(() => _matchesByIndex[index] = matches);
      }
    }

    await Future.wait([worker(), worker(), worker()]);
  }

  void _setMode(bool tmdb) {
    if (_tmdbMode == tmdb) return;
    setState(() {
      _tmdbMode = tmdb;
      _searched = false;
      _results = [];
      _works = [];
      _matchesByIndex.clear();
    });
    if (_controller.text.trim().isNotEmpty) _search();
  }

  /// Best-first ranking for matched items: sources whose
  /// last health check passed lead (fastest first),
  /// unchecked sources follow, failed ones trail.
  int _sourceRank(String sourceId) {
    final health = VideoEngineService.instance.healthById[sourceId];
    if (health == null) return 1000000;
    final latency = health.latencyMs.clamp(0, 999999);
    return health.ok ? latency : 2000000 + latency;
  }

  /// Batch 230: tapping a TMDB work lands on the best
  /// playable version; with none, it falls back to a
  /// source search for the same title.
  Future<void> _openWork(int index, TmdbWork work) async {
    if (_openingWork) return;
    _openingWork = true;
    try {
      var matches = _matchesByIndex[index];
      if (matches == null && _matcher != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在为你找可用线路…'),
            duration: Duration(seconds: 2),
          ),
        );
        matches = await _matcher!.matchesFor(work);
        if (mounted) setState(() => _matchesByIndex[index] = matches);
      }
      if (!mounted) return;
      final ranked = rankTmdbMatches(matches ?? const [], _sourceRank);
      if (ranked.isNotEmpty) {
        openFilmDetail(context, ranked.first);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已装的源里还没找到《${work.title}》，转到源内搜索看看')),
      );
      _controller.text = work.title;
      _setMode(false);
    } finally {
      _openingWork = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Batch 221: the AppBar gives way to the editorial
    // masthead pattern — eyebrow over the search field,
    // hairline below.
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回',
                      icon: const Icon(AnikumoIcons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: widget.initialQuery.isEmpty,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: '搜索电视剧 / 电影',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    IconButton(
                      tooltip: '搜索',
                      icon: const Icon(AnikumoIcons.search_rounded),
                      onPressed: _search,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_tmdbAvailable) _modeRow(context),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  /// Batch 230: the search-mode switch — source search
  /// (default, complete) vs TMDB works (rich metadata,
  /// auto-matched to playable sources).
  Widget _modeRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('源内搜索'),
            selected: !_tmdbMode,
            onSelected: (_) => _setMode(false),
          ),
          const SizedBox(width: 7),
          ChoiceChip(
            label: const Text('TMDB 作品'),
            selected: _tmdbMode,
            onSelected: (_) => _setMode(true),
          ),
          const Spacer(),
          if (_tmdbMode)
            Text(
              '作品数据来自 TMDB',
              style: TextStyle(color: scheme.outline, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (!VideoEngineService.instance.hasSources) {
      return const FilmEmptyState(
        icon: AnikumoIcons.dns_rounded,
        title: '还没有可用的数据源',
        message: '先到「源」页添加仓库或接口，再回来搜索。',
      );
    }
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return FilmEmptyState(
        icon: AnikumoIcons.search_rounded,
        title: '搜索',
        message: _error!,
        actionLabel: '重试',
        onAction: _search,
      );
    }
    if (!_searched) {
      return FilmEmptyState(
        icon: AnikumoIcons.search_rounded,
        title: '搜索',
        message: _tmdbMode
            ? '输入片名，先看 TMDB 的作品资料，再自动为你匹配可播的源。'
            : '输入片名，同时在全部已启用的源里查找。',
      );
    }
    if (_tmdbMode) return _tmdbBody(context);
    final filtered = _results.where((i) => _kindFilter.matches(i)).toList();
    // Batch 247: when the keyword names a genre, offer
    // the tag page — title search alone cannot express
    // "everything with this tag".
    final tagGenre = _searched ? filmTagForKeyword(_controller.text) : null;
    if (filtered.isEmpty) {
      final empty = FilmEmptyState(
        icon: AnikumoIcons.search_rounded,
        title: '没有找到结果',
        message: _kindFilter == FilmKindFilter.all
            ? '换个片名试试，或检查源是否可用。'
            : '当前分类下没有结果，试试切换到「全部」。',
      );
      if (tagGenre == null) return empty;
      return Column(
        children: [
          _tagBanner(context, tagGenre),
          Expanded(child: empty),
        ],
      );
    }
    final service = VideoEngineService.instance;
    final names = {for (final s in service.sources) s.id: s.name};
    final groups = <String, List<MediaItem>>{};
    for (final item in filtered) {
      groups.putIfAbsent(item.sourceId, () => []).add(item);
    }
    return Column(
      children: [
        if (tagGenre != null) _tagBanner(context, tagGenre),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              for (final filter in FilmKindFilter.values) ...[
                ChoiceChip(
                  label: Text(filter.label),
                  selected: _kindFilter == filter,
                  onSelected: (_) => setState(() => _kindFilter = filter),
                ),
                const SizedBox(width: 7),
              ],
              const Spacer(),
              Text(
                '共 ${filtered.length} 部',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        names[entry.key] ?? '未知来源',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.value.length} 部',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.56,
                  ),
                  itemCount: entry.value.length,
                  itemBuilder: (context, i) => FilmPosterCard(
                    item: entry.value[i],
                    onTap: () => openFilmDetail(context, entry.value[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Batch 230: TMDB mode results — work cards with a
  /// playable-source badge once matching lands.
  /// Batch 247: the browse-by-tag entry shown when a
  /// search keyword names a genre.
  Widget _tagBanner(BuildContext context, String tag) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.pushNamed(
            '/film/all',
            arguments: FilmAllArgs(
              kind: FilmKindFilter.all,
              genre: tag,
              allSources: true,
              title: '标签：$tag',
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '按标签浏览「$tag」',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  AnikumoIcons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tmdbBody(BuildContext context) {
    if (_works.isEmpty) {
      return FilmEmptyState(
        icon: AnikumoIcons.search_rounded,
        title: 'TMDB 没有找到',
        message: 'TMDB 未收录这个片名时有发生，源内搜索可能有。',
        actionLabel: '转到源内搜索',
        onAction: () => _setMode(false),
      );
    }
    final variant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Text(
                '共 ${_works.length} 部作品',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: variant),
              ),
              const Spacer(),
              Text(
                '点开自动落到可播的源',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: variant),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
              childAspectRatio: 0.56,
            ),
            itemCount: _works.length,
            itemBuilder: (context, i) => _workCard(context, i, _works[i]),
          ),
        ),
      ],
    );
  }

  Widget _workCard(BuildContext context, int index, TmdbWork work) {
    final scheme = Theme.of(context).colorScheme;
    final matches = _matchesByIndex[index];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openWork(index, work),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (work.posterUrl != null)
                    CachedNetworkImage(
                      imageUrl: work.posterUrl!,
                      cacheManager: filmCoverCacheManager,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          ColoredBox(color: scheme.surfaceContainerHighest),
                    )
                  else
                    ColoredBox(color: scheme.surfaceContainerHighest),
                  if (matches != null)
                    Positioned(
                      left: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: matches.isNotEmpty
                              ? scheme.primary
                              : scheme.surfaceContainerHighest.withValues(
                                  alpha: 0.92,
                                ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          matches.isNotEmpty
                              ? '${matches.length} 个源可播'
                              : '暂无可播源',
                          style: TextStyle(
                            color: matches.isNotEmpty
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            work.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Text(
            [
              if (work.year != null) '${work.year}',
              work.isSeries ? '剧' : '影',
              if (work.score > 0) '★ ${work.score.toStringAsFixed(1)}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.outline, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}
