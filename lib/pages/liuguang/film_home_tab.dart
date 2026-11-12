import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/bean/widget/anikumo_menu.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/pages/liuguang/film_discover_tab.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/liuguang/cms_api_source.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/liuguang/film_prefs.dart';

/// Batch 205: 首页 （精选）. The 电视剧 / 电影 toggle switches
/// the whole shelf: a rotating banner plus rails by 最新 /
/// 题材 / 地区 / 年份， all browsed from the first enabled
/// source that answers (multi-source merging lives in
/// search, where duplicates are grouped per source instead
/// of interleaved).
class FilmHomeTab extends StatefulWidget {
  const FilmHomeTab({super.key});

  @override
  State<FilmHomeTab> createState() => _FilmHomeTabState();
}

/// Batch 236: two rails are the same shelf in disguise
/// when the smaller one's ids sit almost entirely inside
/// the bigger one — a filter-deaf station feeds every
/// genre rail from the same unfiltered stream, and exact
/// sequence equality (Batch 216) missed near-identical
/// buffers scanned at different depths.
bool filmRailsOverlap(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return false;
  final smaller = a.length < b.length ? a.length : b.length;
  final overlap = a.intersection(b).length;
  return overlap / smaller >= 0.8;
}

class _Shelf {
  const _Shelf({
    required this.banner,
    required this.rails,
    required this.sourceName,
    required this.sourceId,
  });
  final List<MediaItem> banner;
  final List<_Rail> rails;
  final String sourceName;
  final String sourceId;
}

/// Batch 222: one home rail — a title, its items, and the
/// filter it stands for (what its 全部 entry opens).
class _Rail {
  const _Rail(this.title, this.items, {this.genre, this.area, this.year});
  final String title;
  final List<MediaItem> items;
  final String? genre;
  final String? area;
  final int? year;
}

class _FilmHomeTabState extends State<FilmHomeTab> {
  /// Batch 260: session shelf cache — leaving the film
  /// zone disposes this state, and every re-entry used
  /// to re-race the sources and re-sample the rails
  /// before anything painted. A shelf younger than
  /// five minutes (same source set) paints instantly on
  /// re-entry; pull-to-refresh still bypasses it.
  static final Map<String, (DateTime, _Shelf)> _sessionShelves = {};

  void _cacheShelf(FilmKindFilter kind, _Shelf shelf) {
    if (_sessionShelves.length > 8) _sessionShelves.clear();
    _sessionShelves['${kind.name}|$_lastSourceSignature'] = (
      DateTime.now(),
      shelf,
    );
  }

  FilmKindFilter _kind = FilmKindFilter.series;
  final Map<FilmKindFilter, _Shelf> _shelves = {};
  final Set<FilmKindFilter> _loading = {};
  final Map<FilmKindFilter, String> _errors = {};
  PageController? _bannerCtl;
  Timer? _bannerTimer;
  int _bannerIndex = 0;

  @override
  void initState() {
    super.initState();
    _lastSourceSignature = _sourceSignature();
    VideoEngineService.instance.addListener(_onRegistryChanged);
    // Batch 237: changing a channel's pinned source
    // rebuilds the shelves right away.
    FilmHomeSources.revision.addListener(_onPinsChanged);
    _ensureLoaded(_kind);
  }

  void _onPinsChanged() {
    if (!mounted) return;
    _sessionShelves.clear();
    _shelves.clear();
    _errors.clear();
    _ensureLoaded(_kind);
  }

  @override
  void dispose() {
    FilmHomeSources.revision.removeListener(_onPinsChanged);
    VideoEngineService.instance.removeListener(_onRegistryChanged);
    _bannerTimer?.cancel();
    _bannerCtl?.dispose();
    super.dispose();
  }

  String _lastSourceSignature = '';

  String _sourceSignature() {
    final service = VideoEngineService.instance;
    service.loadRegistry();
    return service.sources.map((s) => '${s.id}:${s.enabled}').join('|');
  }

  void _onRegistryChanged() {
    // Batch 231: the service also notifies for health
    // checks and other bookkeeping — those must not wipe
    // the shelves (a 全部检测 in the 片源 tab used to reset
    // the home page and leave it spinning until the user
    // toggled 电影/电视剧 to force a reload).
    final signature = _sourceSignature();
    if (signature == _lastSourceSignature) {
      if (mounted) setState(() {});
      return;
    }
    _lastSourceSignature = signature;
    _shelves.clear();
    _errors.clear();
    if (mounted) {
      setState(() {});
      _ensureLoaded(_kind);
    }
  }

  /// Batch 256: load tokens are PER CHANNEL — a single
  /// global counter let one channel's load invalidate
  /// another's: 电影 loading, a detour to 电视剧 and
  /// back, and the 电影 load's publish was dropped as
  /// "stale" while its _loading guard blocked any fresh
  /// load — the shelf sat empty until a manual refresh.
  final Map<FilmKindFilter, int> _loadTokens = {};

  /// Batch 231: the first page of the shelf, raced across
  /// every enabled interface — the first source to answer
  /// with content wins, instead of paying each slow or
  /// dead source's full timeout in series before it.
  Future<(VideoSourceEntry, CmsApiSource, SearchPage)?> _raceFirstPage(
    List<(VideoSourceEntry, CmsApiSource)> providers,
    FilmKindFilter kind,
  ) async {
    if (providers.isEmpty) return null;
    final completer =
        Completer<(VideoSourceEntry, CmsApiSource, SearchPage)?>();
    var remaining = providers.length;
    for (final (entry, provider) in providers) {
      provider
          .browse(
            kind: kind.mediaType,
            variety: kind.varietyOnly,
            anime: kind.animeOnly,
            shortDrama: kind.shortDramaOnly,
            manju: kind.manjuOnly,
            page: 1,
          )
          .then((page) {
            if (completer.isCompleted) return;
            if (page.items.isNotEmpty) {
              completer.complete((entry, provider, page));
            } else if (--remaining == 0) {
              completer.complete(null);
            }
          })
          .catchError((Object _) {
            if (!completer.isCompleted && --remaining == 0) {
              completer.complete(null);
            }
          });
    }
    return completer.future;
  }

  /// Batch 237 (speed half): with fresh speed data on the
  /// table, the automatic mode stops racing and walks the
  /// sources fastest-first — the winner then also serves
  /// the channel's rails, and rails are the bulk of the
  /// traffic, so the measured order is what the user
  /// actually feels. A source that answers empty or dies
  /// hands over to the next fastest.
  Future<(VideoSourceEntry, CmsApiSource, SearchPage)?> _priorityFirstPage(
    List<(VideoSourceEntry, CmsApiSource)> providers,
    FilmKindFilter kind,
  ) async {
    for (final (entry, provider) in providers) {
      try {
        final page = await provider.browse(
          kind: kind.mediaType,
          variety: kind.varietyOnly,
          anime: kind.animeOnly,
          shortDrama: kind.shortDramaOnly,
          manju: kind.manjuOnly,
          page: 1,
        );
        if (page.items.isNotEmpty) return (entry, provider, page);
      } catch (_) {
        // Next fastest gets its turn.
      }
    }
    return null;
  }

  Future<void> _ensureLoaded(
    FilmKindFilter kind, {
    bool refresh = false,
  }) async {
    if (_loading.contains(kind)) return;
    if (!refresh && _shelves.containsKey(kind)) return;
    if (!refresh) {
      final hit = _sessionShelves['${kind.name}|$_lastSourceSignature'];
      if (hit != null &&
          DateTime.now().difference(hit.$1) < const Duration(minutes: 5)) {
        _shelves[kind] = hit.$2;
        if (mounted) setState(() {});
        return;
      }
    }
    final service = VideoEngineService.instance;
    service.loadRegistry();
    final enabled = service.sources.where((s) => s.enabled).toList();
    if (enabled.isEmpty) return;
    _loading.add(kind);
    final token = _loadTokens[kind] = (_loadTokens[kind] ?? 0) + 1;
    if (mounted) setState(() {});
    try {
      var providers = <(VideoSourceEntry, CmsApiSource)>[
        for (final entry in enabled)
          if (service.providerFor(entry) case final CmsApiSource cms)
            (entry, cms),
      ];
      if (refresh) {
        for (final (_, provider) in providers) {
          provider.invalidateBrowseCache();
        }
      }
      // Batch 237: consumption order for this channel —
      // the user's pin first when one is set, then the
      // speed table's fastest-first order (unmeasured
      // sources keep registry order). The live path below
      // consumes providers in this order; the race path
      // handles the pin separately.
      final pinnedId = FilmHomeSources.preferredId(kind.name);
      providers = FilmSourceSpeeds.orderBySpeed(
        providers,
        (p) => p.$1.id,
        DateTime.now(),
      );
      if (pinnedId != null) {
        providers = [
          ...providers.where((p) => p.$1.id == pinnedId),
          ...providers.where((p) => p.$1.id != pinnedId),
        ];
      }
      // Batch 226: the 直播 shelf is category-driven —
      // live channels sit in the station's own 直播
      // categories (their catalogue rows are old and
      // sparse in the update-ordered flow, so kind
      // streams would never reach them). One rail of
      // channels, no genre split.
      if (kind == FilmKindFilter.live) {
        for (final (entry, provider) in providers) {
          final cats = await provider.categories();
          final liveCats = [
            for (final c in cats)
              if (cmsIsLiveName(c.name)) c,
          ];
          if (liveCats.isEmpty) continue;
          final seen = <String>{};
          final channels = <MediaItem>[];
          for (final cat in liveCats.take(6)) {
            try {
              final page = await provider.browse(typeId: cat.id, page: 1);
              for (final item in page.items) {
                if (seen.add(item.id)) channels.add(item);
              }
            } catch (_) {
              // One dead category must not sink the shelf.
            }
          }
          if (channels.isEmpty) continue;
          final liveShelf = _Shelf(
            banner: channels.take(5).toList(),
            rails: [_Rail('直播频道', channels)],
            sourceName: entry.name,
            sourceId: entry.id,
          );
          _shelves[kind] = liveShelf;
          _cacheShelf(kind, liveShelf);
          _errors.remove(kind);
          return;
        }
        _errors[kind] = '暂时没有取到内容，请下拉重试或检查源是否可用。';
        return;
      }
      // Batch 237: a pinned source serves its channel
      // alone; only when it answers empty (or dies) do
      // the others race — a dead pin must not blank the
      // shelf it was meant to improve.
      (VideoSourceEntry, CmsApiSource, SearchPage)? winner;
      if (pinnedId != null) {
        final pinned = providers.where((p) => p.$1.id == pinnedId).firstOrNull;
        if (pinned != null) {
          try {
            final page = await pinned.$2.browse(
              kind: kind.mediaType,
              variety: kind.varietyOnly,
              anime: kind.animeOnly,
              shortDrama: kind.shortDramaOnly,
              manju: kind.manjuOnly,
              page: 1,
            );
            if (page.items.isNotEmpty) {
              winner = (pinned.$1, pinned.$2, page);
            }
          } catch (_) {
            // Fall through to the race.
          }
        }
      }
      if (winner == null) {
        if (pinnedId == null &&
            FilmSourceSpeeds.hasFreshSuccess(
              providers.map((p) => p.$1.id),
              DateTime.now(),
            )) {
          winner = await _priorityFirstPage(providers, kind);
        } else {
          winner = await _raceFirstPage(
            pinnedId == null
                ? providers
                : providers.where((p) => p.$1.id != pinnedId).toList(),
            kind,
          );
        }
      }
      if (winner == null) {
        _errors[kind] = '暂时没有取到内容，请下拉重试或检查源是否可用。';
        return;
      }
      final (entry, provider, first) = winner;
      final year = DateTime.now().year;
      Future<List<MediaItem>> rail(Future<SearchPage> f) async {
        try {
          return (await f).items;
        } catch (_) {
          return const [];
        }
      }

      final fetched = <List<MediaItem>>[];
      var specs = filmRailSpecsFor(first.items, year: year);

      // Batch 231: the shelf goes up as soon as the first
      // page lands (banner + 最新上线), and each wave of
      // rails is published as it completes — entering the
      // zone no longer waits on nineteen browses before
      // anything renders.
      void publish() {
        if (!mounted || token != _loadTokens[kind]) return;
        List<_Rail> railsAtLeast(int minimum) => [
          for (var i = 0; i < fetched.length; i++)
            if (fetched[i].length >= minimum)
              _Rail(
                specs[i].$1,
                fetched[i],
                genre: specs[i].$2,
                area: specs[i].$3,
                year: specs[i].$4,
              ),
        ];
        var content = railsAtLeast(3);
        if (content.length < 4) content = railsAtLeast(1);
        content.sort((a, b) => b.items.length.compareTo(a.items.length));
        final rails = <_Rail>[_Rail('最新上线', first.items), ...content.take(11)];
        // Batch 216/236: a rail that repeats an earlier
        // rail (a station that ignored every filter) is
        // dropped — seven identical shelves are worse than
        // three honest ones. Batch 236 widens the test
        // from exact sequence equality to near-total
        // overlap (see filmRailsOverlap).
        final seenRailKeys = <String>{};
        final keptIdSets = <Set<String>>[];
        rails.removeWhere((r) {
          final key = r.items.map((i) => i.id).join(',');
          if (!seenRailKeys.add(key)) return true;
          final ids = r.items.map((i) => i.id).toSet();
          if (keptIdSets.any((kept) => filmRailsOverlap(kept, ids))) {
            return true;
          }
          keptIdSets.add(ids);
          return false;
        });
        setState(() {
          final shelf = _Shelf(
            banner: first.items.take(5).toList(),
            rails: rails,
            sourceName: entry.name,
            sourceId: entry.id,
          );
          _shelves[kind] = shelf;
          _cacheShelf(kind, shelf);
        });
        _errors.remove(kind);
      }

      publish();

      // Batch 255: the rail menu is derived from the
      // winning interface's OWN catalogue for this
      // channel — the genre/area words its items
      // actually carry (the fixed twelve-genre menu left
      // the 电影 shelf with no rails at all on sources
      // whose movie metadata speaks a different
      // vocabulary). Two extra catalogue pages widen the
      // sample; the rails themselves are fetched in
      // waves of seven as before.
      // Batch 256: the shelf paints banner + 最新上线
      // from page one right away (batch 231's promise,
      // which the batch-255 sampling had quietly moved
      // behind two extra page fetches); the sampled
      // rebuild below only decides the rail menu.
      var sample = first.items;
      if (first.totalPages > 1) {
        final more = await Future.wait([
          rail(
            provider.browse(
              kind: kind.mediaType,
              variety: kind.varietyOnly,
              anime: kind.animeOnly,
              shortDrama: kind.shortDramaOnly,
              manju: kind.manjuOnly,
              page: 2,
            ),
          ),
          rail(
            provider.browse(
              kind: kind.mediaType,
              variety: kind.varietyOnly,
              anime: kind.animeOnly,
              shortDrama: kind.shortDramaOnly,
              manju: kind.manjuOnly,
              page: 3,
            ),
          ),
        ]);
        sample = [...sample, for (final pageItems in more) ...pageItems];
      }
      specs = filmRailSpecsFor(sample, year: year);
      publish();
      for (var at = 0; at < specs.length; at += 7) {
        fetched.addAll(
          await Future.wait([
            for (final s in specs.skip(at).take(7))
              rail(
                provider.browse(
                  kind: kind.mediaType,
                  variety: kind.varietyOnly,
                  anime: kind.animeOnly,
                  shortDrama: kind.shortDramaOnly,
                  manju: kind.manjuOnly,
                  genre: s.$2,
                  area: s.$3,
                  year: s.$4,
                ),
              ),
          ]),
        );
        publish();
      }
    } catch (e) {
      _errors[kind] = '加载失败：$e';
    } finally {
      _loading.remove(kind);
      if (mounted) {
        setState(() {});
        _restartBannerTimer();
      }
    }
  }

  void _restartBannerTimer() {
    _bannerTimer?.cancel();
    final shelf = _shelves[_kind];
    if (shelf == null || shelf.banner.length < 2) return;
    _bannerCtl?.dispose();
    _bannerCtl = PageController();
    _bannerIndex = 0;
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final ctl = _bannerCtl;
      final current = _shelves[_kind];
      if (ctl == null || current == null || !ctl.hasClients) return;
      final next = (_bannerIndex + 1) % current.banner.length;
      ctl.animateToPage(
        next,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = VideoEngineService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Batch 221: the anime home's title pattern — an
        // eyebrow over a headline that IS the kind switch
        // (a menu hangs off it, like 热门番组's tag menu),
        // replacing the 精选 label + segmented control.
        // Batch 224: a 历史记录 entry rides at the top
        // right of the headline row, as the user asked.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FilmEditorialTitle(
                eyebrow: 'FEATURED · 影视精选',
                title: AnikumoMenuButton(
                  animated: true,
                  style: const MenuStyle(
                    maximumSize: WidgetStatePropertyAll(Size(240, 350)),
                  ),
                  menuChildren: [
                    for (final kind in const [
                      FilmKindFilter.series,
                      FilmKindFilter.movie,
                      FilmKindFilter.variety,
                      FilmKindFilter.anime,
                      FilmKindFilter.shortDrama,
                      FilmKindFilter.manju,
                      FilmKindFilter.live,
                    ])
                      AnikumoMenuItem(
                        label: kind.label,
                        selected: kind == _kind,
                        onPressed: () {
                          setState(() => _kind = kind);
                          _ensureLoaded(kind);
                          _restartBannerTimer();
                        },
                      ),
                  ],
                  builder: (context, toggle) => InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: toggle,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        filmHeadline(context, _kind.label),
                        const SizedBox(width: 4),
                        Icon(
                          AnikumoIcons.keyboard_arrow_down,
                          size: 26,
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, right: 8),
              child: TextButton.icon(
                onPressed: () => context.pushNamed('/film/history'),
                icon: const Icon(AnikumoIcons.history_rounded, size: 19),
                label: const Text('历史记录'),
              ),
            ),
          ],
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: service,
            builder: (context, _) {
              if (!service.hasSources) {
                return const FilmEmptyState(
                  icon: AnikumoIcons.dns_rounded,
                  title: '还没有可用的数据源',
                  message:
                      '影视区与其它专区一样不内置内容来源。'
                      '到「源」页添加仓库地址或单个接口后，'
                      '这里会按电视剧 / 电影分别展示精选。',
                );
              }
              return _shelfView(context);
            },
          ),
        ),
      ],
    );
  }

  /// Batch 221: the latin eyebrow for a rail title.
  /// Batch 222: labels for the widened tag menu.
  String _railLabel(String title) {
    if (title.endsWith('新作')) return 'NEW THIS YEAR';
    return switch (title) {
      '最新上线' => 'JUST IN',
      '爱情' => 'ROMANCE',
      '喜剧' => 'COMEDY',
      '动作' => 'ACTION',
      '剧情' => 'DRAMA',
      '悬疑' => 'SUSPENSE',
      '科幻' => 'SCI-FI',
      '犯罪' => 'CRIME',
      '古装' => 'COSTUME',
      '武侠' => 'WUXIA',
      '恐怖' => 'HORROR',
      '家庭' => 'FAMILY',
      '动画' => 'ANIMATION',
      '日本' => 'JAPAN',
      '韩国' => 'KOREA',
      '中国' => 'CHINA',
      '台湾' => 'TAIWAN',
      '香港' => 'HONG KONG',
      '美国' => 'USA',
      _ => 'MORE',
    };
  }

  /// Batch 222: a rail's 全部 — the discover wall as its
  /// own page, pre-filtered to this rail and this shelf's
  /// source; tags stay switchable there.
  void _openAll(_Rail rail) {
    context.pushNamed(
      '/film/all',
      arguments: FilmAllArgs(
        kind: _kind,
        genre: rail.genre,
        area: rail.area,
        year: rail.year,
        sourceId: _shelves[_kind]?.sourceId,
      ),
    );
  }

  Widget _shelfView(BuildContext context) {
    final shelf = _shelves[_kind];
    if (shelf == null) {
      if (_errors.containsKey(_kind)) {
        return FilmEmptyState(
          icon: AnikumoIcons.movie_rounded,
          title: '${_kind.label}精选',
          message: _errors[_kind]!,
          actionLabel: '重试',
          onAction: () => _ensureLoaded(_kind, refresh: true),
        );
      }
      // Batch 231: self-heal — a shelf that is neither
      // loaded, loading, nor errored is a dead state (the
      // "must toggle 电影/电视剧 to make it render" the
      // user reported); restart its load instead of
      // spinning forever.
      if (!_loading.contains(_kind)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureLoaded(_kind);
        });
      }
      return const Center(child: CircularProgressIndicator());
    }
    final hasBanner = shelf.banner.isNotEmpty;
    return RefreshIndicator(
      onRefresh: () => _ensureLoaded(_kind, refresh: true),
      // Batch 231: lazy sections — only the rails near the
      // viewport build, instead of all twelve at once on
      // entry (a first-frame jank source).
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: shelf.rails.length + (hasBanner ? 1 : 0),
        itemBuilder: (context, index) {
          if (hasBanner && index == 0) return _banner(context, shelf);
          final i = hasBanner ? index - 1 : index;
          final rail = shelf.rails[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EditorialSectionHeader(
                index: (i + 1).toString().padLeft(2, '0'),
                label: _railLabel(rail.title),
                title: rail.title,
                subtitle: i == 0 ? '来自「${shelf.sourceName}」' : null,
                actionLabel: '全部',
                onAction: () => _openAll(rail),
              ),
              FilmRail(
                items: rail.items,
                onTapItem: (item) => openFilmDetail(context, item),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _banner(BuildContext context, _Shelf shelf) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 16 / 8.2,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _bannerCtl,
                itemCount: shelf.banner.length,
                onPageChanged: (i) => setState(() => _bannerIndex = i),
                itemBuilder: (context, i) {
                  final item = shelf.banner[i];
                  return GestureDetector(
                    onTap: () => openFilmDetail(context, item),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Batch 215: same cover resolution as the
                        // poster cards (TVmaze / own / backfill) —
                        // the raw poster field alone stays blank
                        // for slim-payload stations.
                        FilmCoverImage(
                          item: item,
                          decodeWidth: 1080,
                          placeholder: Container(color: Colors.black26),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  FilmKindTag(type: item.mediaType, item: item),
                                  if (item.rating.score > 0) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '★ ${item.rating.score.toStringAsFixed(1)}',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (item.overview.isNotEmpty)
                                Text(
                                  item.overview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (shelf.banner.length > 1)
                Positioned(
                  right: 12,
                  bottom: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < shelf.banner.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.only(left: 5),
                          width: i == _bannerIndex ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _bannerIndex
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
