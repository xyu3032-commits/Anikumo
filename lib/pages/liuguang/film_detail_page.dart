import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/pages/liuguang/film_discover_tab.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/liuguang/bangumi_film.dart';
import 'package:anikumo/services/liuguang/film_accounts.dart';
import 'package:anikumo/services/liuguang/cms_api_source.dart';
import 'package:anikumo/services/liuguang/film_downloads.dart';
import 'package:anikumo/services/liuguang/tmdb_enrich.dart';
import 'package:anikumo/services/liuguang/film_playback_bridge.dart';
import 'package:anikumo/services/liuguang/tvmaze_covers.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/liuguang/film_probes.dart';
import 'package:anikumo/services/liuguang/film_features.dart';

/// Batch 205: 详情 — header with blurred poster backdrop,
/// meta / genres / cast, synopsis, favorite toggle (engine
/// favorites repository), resume entry (engine history),
/// and one tab per play line with its episode grid
/// （正序/倒序）. Episode taps hand off to the player route
/// (Batch 206).
class FilmDetailPage extends StatefulWidget {
  const FilmDetailPage({super.key, required this.item});

  final MediaItem item;

  @override
  State<FilmDetailPage> createState() => _FilmDetailPageState();
}

class _FilmDetailPageState extends State<FilmDetailPage>
    with TickerProviderStateMixin {
  MediaDetail? _detail;
  bool _probingLines = false;
  String? _lineProbeNote;
  bool _loading = true;
  String? _error;
  bool _favorite = false;

  /// Batch 254: the signed-in TMDB account's marks on
  /// this work (null = not loaded / not applicable) and
  /// the in-flight guard for mark writes.
  bool? _tmdbFav;
  bool? _tmdbWatch;
  bool _tmdbMarkBusy = false;
  bool _reversed = false;
  PlaybackHistory? _resume;
  TabController? _tabs;

  MediaItem get _item => _detail?.item ?? widget.item;

  /// Batch 211: the TVmaze cover for this series, once
  /// resolved (film zone only; movies never look one up).
  String? _tvmazePoster;

  /// Batch 229: the TMDB enrichment (cast / reviews /
  /// overview fallback), once resolved — absent entirely
  /// when there is no key or no confident match.
  TmdbEnrichment? _tmdb;

  /// Batch 244: TMDB episode names by episode number,
  /// once resolved (series only).
  Map<int, String> _tmdbEpisodeNames = const {};

  /// Batch 243: the TMDB poster for the header — TMDB is
  /// the zone's metadata priority, ahead of TVmaze.
  String? _tmdbPoster;

  /// Batch 245: the Bangumi data for this work (rating /
  /// characters / comments), once resolved — the second
  /// metadata source in the user's priority chain.
  BangumiFilmData? _bgm;

  /// Batch 247: 猜你喜欢 — same-source works ranked by
  /// shared tag keys with this one.
  List<MediaItem> _recommendations = const [];

  Future<void> _resolveRecommendations() async {
    try {
      final engine = VideoEngineService.instance;
      VideoSourceEntry? entry;
      for (final e in engine.sources) {
        if (e.id == _item.sourceId) {
          entry = e;
          break;
        }
      }
      if (entry == null) return;
      final provider = engine.providerFor(entry);
      if (provider is! CmsApiSource) return;
      final baseKeys = cmsItemTagKeys(
        _item,
        extra: [...?_bgm?.tags, ...?_tmdb?.genres, ...?_tmdb?.keywords],
      );
      if (baseKeys.isEmpty) return;
      final genres = <String>{
        for (final g in _item.genres) cmsGenreDisplay(g.name),
      }.take(2);
      final pool = <MediaItem>[];
      for (final genre in genres) {
        final page = await provider.browse(
          kind: _item.mediaType,
          genre: genre,
          page: 1,
        );
        pool.addAll(page.items);
      }
      final ranked = rankFilmRecommendations(
        base: _item,
        baseKeys: baseKeys,
        candidates: pool,
      );
      if (mounted && ranked.isNotEmpty) {
        setState(() => _recommendations = ranked);
      }
    } catch (_) {
      // Recommendations are decoration; silence is fine.
    }
  }

  /// Batch 247: a genre/tag chip opens the tag page —
  /// the discover wall across all sources, filtered to
  /// the tag.
  void _openTagPage(String tag) {
    context.pushNamed(
      '/film/all',
      arguments: FilmAllArgs(
        kind: FilmKindFilter.all,
        genre: tag,
        allSources: true,
        title: '标签：$tag',
      ),
    );
  }

  /// Batch 245: the Bangumi poster for the header —
  /// second in the cover chain, after TMDB.
  String? _bgmPoster;

  void _resolveBangumi() {
    final service = BangumiFilmService.instance;
    final cachedPoster = service.cachedPosterFor(_item);
    if (cachedPoster != null) _bgmPoster = cachedPoster;
    service.forItem(_item).then((data) {
      if (!mounted || data == null) return;
      setState(() {
        _bgm = data;
        _bgmPoster = data.posterUrl ?? _bgmPoster;
      });
    }).ignore();
  }

  void _resolveTmdb() {
    TmdbEnrichService.instance.forItem(_item).then((enrichment) {
      if (mounted && enrichment != null) {
        setState(() => _tmdb = enrichment);
        _loadTmdbAccountStates(enrichment);
      }
    }).ignore();
    final posterService = TmdbPosterService.instance;
    final cachedPoster = posterService.cachedPosterFor(_item);
    if (cachedPoster != null) {
      _tmdbPoster = cachedPoster;
    } else {
      posterService.posterFor(_item).then((url) {
        if (mounted && url != null) setState(() => _tmdbPoster = url);
      }).ignore();
    }
    if (_item.mediaType == MediaType.series) {
      TmdbEpisodeNamesService.instance
          .forItem(
            _item,
            episodeCount: _detail?.seasons.firstOrNull?.episodes.length,
          )
          .then((names) {
            if (mounted && names.isNotEmpty) {
              setState(() => _tmdbEpisodeNames = names);
            }
          })
          .ignore();
    }
  }

  /// Batch 244: an episode tile's label — TMDB's episode
  /// name when one was resolved, else the station's own
  /// title (or its bare number).
  String _episodeLabel(Episode episode) {
    final tmdbName = _tmdbEpisodeNames[episode.episodeNumber];
    if (tmdbName != null && tmdbName.isNotEmpty) return tmdbName;
    return episode.title.isEmpty ? '${episode.episodeNumber}' : episode.title;
  }

  String? get _coverPoster {
    // Batch 243/245 cover chain: TMDB → Bangumi → TVmaze
    // → the source's own poster.
    if (_tmdbPoster != null) return _tmdbPoster;
    if (_bgmPoster != null) return _bgmPoster;
    if (_item.mediaType == MediaType.series && _tvmazePoster != null) {
      return _tvmazePoster;
    }
    return _item.artwork.poster;
  }

  /// Batch 245: the header's score by the user's
  /// priority — Bangumi, then TMDB, then the source.
  ({double score, String source, int votes})? get _displayScore =>
      filmDisplayScore(
        bangumi: _bgm,
        tmdb: _tmdb,
        sourceScore: _item.rating.score,
      );

  /// Batch 245: the cast/character row's entries —
  /// Bangumi characters first (character name, played
  /// by), TMDB cast when Bangumi has none.
  List<({String name, String sub, String? imageUrl})> get _castMembers {
    final bgm = _bgm;
    if (bgm != null && bgm.characters.isNotEmpty) {
      return [
        for (final c in bgm.characters)
          (name: c.name, sub: c.actor, imageUrl: c.imageUrl),
      ];
    }
    if (_tmdb != null) {
      return [
        for (final m in _tmdb!.cast)
          (
            name: m.name,
            sub: m.character.isEmpty ? '' : '饰 ${m.character}',
            imageUrl: m.profileUrl,
          ),
      ];
    }
    return const [];
  }

  bool get _castFromBangumi => _bgm != null && _bgm!.characters.isNotEmpty;

  /// Batch 245: the combined comment stream — TMDB
  /// reviews + Bangumi comments, newest first.
  List<FilmReview> get _mergedReviews => mergeFilmReviews(
    tmdb: _tmdb?.reviews ?? const [],
    bangumi: _bgm?.comments ?? const [],
  );

  /// Batch 246: the overview by the user's priority —
  /// Bangumi's synopsis, then TMDB's, then the source's.
  String get _displayOverview => filmDisplayOverview(
    bangumiSummary: _bgm?.summary ?? '',
    tmdbOverview: _tmdb?.overview ?? '',
    sourceOverview: _item.overview,
  );

  /// Batch 246: genre/tag chips merged across Bangumi,
  /// TMDB (genres + keywords, translated) and the
  /// source, deduped.
  List<String> get _genreChips => mergeFilmGenreChips(
    bangumiTags: _bgm?.tags ?? const [],
    tmdbGenres: _tmdb?.genres ?? const [],
    tmdbKeywords: _tmdb?.keywords ?? const [],
    sourceGenres: [for (final g in _item.genres) g.name],
  );

  void _resolveTvmazeCover() {
    final item = _item;
    if (item.mediaType != MediaType.series) return;
    TvMazeCoverService.instance
        .posterFor(title: item.title, year: item.year)
        .then((url) {
          if (mounted && url != null) setState(() => _tvmazePoster = url);
        })
        .ignore();
  }

  @override
  void initState() {
    super.initState();
    _load();
    // Batch 250: 看剧取源 — settle on the strategy's
    // copy (fastest / pinned) when another interface
    // hosts a better one; runs alongside the load and
    // re-opens via the same replace the manual switcher
    // uses, never blocking first paint.
    _resolvePlaybackSource();
  }

  Future<void> _resolvePlaybackSource() async {
    final better = await resolveFilmPlaybackItem(widget.item);
    if (!mounted || better == null || better.id == widget.item.id) return;
    context.replace('/film/detail', arguments: better);
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final engine = await VideoEngineService.instance.engine();
      final detail = await engine.getDetail(widget.item.id);
      _favorite = await engine.favorites.isFavorite(widget.item.id);
      final history = await engine.history.list(limit: 200);
      for (final h in history) {
        if (h.mediaId == widget.item.id && !h.completed) {
          _resume = h;
          break;
        }
      }
      _detail = detail == null
          ? null
          : reorderDetailLines(
              detail,
              FilmFeatures.isInstalled(FilmFeatures.lineSpeedId)
                  ? FilmLineSpeed.orderFor(widget.item.sourceId)
                  : const <String>[],
            );
      final seasons = _detail?.seasons ?? const [];
      if (seasons.isNotEmpty) {
        _tabs = TabController(length: seasons.length, vsync: this);
      }
      _resolveTvmazeCover();
      _resolveTmdb();
      _resolveBangumi();
      _resolveRecommendations();
      _error = detail == null ? '没有取到详情，源可能暂时不可用。' : null;
    } catch (e) {
      _error = '加载失败：$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Batch 232 （线路测速优选 pack): probes the first
  /// episode of every line, saves the speed order for this
  /// source, and re-sorts the tabs to match.
  Future<void> _probeLines() async {
    final detail = _detail;
    if (detail == null || _probingLines) return;
    setState(() {
      _probingLines = true;
      _lineProbeNote = null;
    });
    try {
      final engine = await VideoEngineService.instance.engine();
      final results = <(String, int?)>[];
      for (final season in detail.seasons) {
        int? ms;
        if (season.episodes.isNotEmpty) {
          try {
            final sources = await engine.getPlaybackSources(
              PlaybackQuery(
                mediaId: detail.item.id,
                episodeId: season.episodes.first.id,
              ),
            );
            final own = sources.where((s) => s.quality == season.title);
            final pick = own.isNotEmpty
                ? own.first
                : (sources.isEmpty ? null : sources.first);
            final uri = pick == null ? null : Uri.tryParse(pick.url);
            if (uri != null) {
              ms = await probeFirstByteMs(uri, headers: pick!.headers);
            }
          } catch (_) {
            ms = null;
          }
        }
        results.add((season.title, ms));
      }
      final sorted = [...results]
        ..sort((a, b) {
          if (a.$2 == null && b.$2 == null) return 0;
          if (a.$2 == null) return 1;
          if (b.$2 == null) return -1;
          return a.$2!.compareTo(b.$2!);
        });
      await FilmLineSpeed.saveOrder(widget.item.sourceId, [
        for (final r in sorted) r.$1,
      ]);
      if (!mounted) return;
      final fastest = sorted.first;
      setState(() {
        _detail = reorderDetailLines(detail, [for (final r in sorted) r.$1]);
        final seasons = _detail?.seasons ?? const [];
        _tabs?.dispose();
        _tabs = seasons.isEmpty
            ? null
            : TabController(length: seasons.length, vsync: this);
        _lineProbeNote = fastest.$2 == null
            ? '测速完成，但线路都没有响应'
            : '测速完成：最快「${fastest.$1}」${fastest.$2}ms';
      });
    } finally {
      if (mounted) setState(() => _probingLines = false);
    }
  }

  /// Batch 254: pull the TMDB account's marks for this
  /// work once its TMDB id is known.
  void _loadTmdbAccountStates(TmdbEnrichment enrichment) {
    if (!TmdbAccount.connected || enrichment.tmdbId <= 0) return;
    TmdbAccount.accountStates(
      isSeries: enrichment.isSeries,
      tmdbId: enrichment.tmdbId,
    ).then((states) {
      if (!mounted || states == null) return;
      setState(() {
        _tmdbFav = states.favorite;
        _tmdbWatch = states.watchlist;
      });
    }).ignore();
  }

  Future<void> _toggleTmdbMark({required bool favorite}) async {
    final tmdb = _tmdb;
    if (tmdb == null || tmdb.tmdbId <= 0 || _tmdbMarkBusy) return;
    final current = favorite ? _tmdbFav : _tmdbWatch;
    if (current == null) return;
    setState(() => _tmdbMarkBusy = true);
    final ok = favorite
        ? await TmdbAccount.setFavorite(
            isSeries: tmdb.isSeries,
            tmdbId: tmdb.tmdbId,
            value: !current,
          )
        : await TmdbAccount.setWatchlist(
            isSeries: tmdb.isSeries,
            tmdbId: tmdb.tmdbId,
            value: !current,
          );
    if (!mounted) return;
    setState(() {
      _tmdbMarkBusy = false;
      if (ok) {
        if (favorite) {
          _tmdbFav = !current;
        } else {
          _tmdbWatch = !current;
        }
      }
    });
    AnikumoDialog.showToast(
      context: context,
      message: ok
          ? (current
                ? '已从 TMDB ${favorite ? '收藏' : '想看'}移除'
                : '已同步到 TMDB ${favorite ? '收藏' : '想看'}')
          : '同步到 TMDB 失败，请稍后重试',
    );
  }

  Future<void> _syncBangumiCollection() async {
    final bgm = _bgm;
    if (bgm == null || bgm.subjectId <= 0) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('同步到 Bangumi 收藏')),
            for (final entry in const [
              (2, '想看'),
              (1, '在看'),
              (4, '看过'),
              (3, '搁置'),
              (5, '抛弃'),
            ])
              ListTile(
                title: Text(entry.$2),
                onTap: () => Navigator.of(sheetContext).pop(entry.$1),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final ok = await BangumiAccount.setCollection(bgm.subjectId, picked);
    if (!mounted) return;
    AnikumoDialog.showToast(
      context: context,
      message: ok ? '已同步到 Bangumi 收藏' : '同步到 Bangumi 失败，请稍后重试',
    );
  }

  /// Batch 254: cloud sync chips under the main action
  /// row — visible only when the relevant account is
  /// connected and the work's id on that service is
  /// known.
  Widget _cloudSyncRow(BuildContext context) {
    final tmdbReady =
        TmdbAccount.connected && _tmdb != null && _tmdb!.tmdbId > 0;
    final bgmReady = BangumiAccount.connected && _bgm != null;
    if (!tmdbReady && !bgmReady) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (tmdbReady && _tmdbFav != null)
            FilterChip(
              label: const Text('TMDB 收藏'),
              selected: _tmdbFav!,
              showCheckmark: true,
              onSelected: _tmdbMarkBusy
                  ? null
                  : (_) => _toggleTmdbMark(favorite: true),
            ),
          if (tmdbReady && _tmdbWatch != null)
            FilterChip(
              label: const Text('TMDB 想看'),
              selected: _tmdbWatch!,
              showCheckmark: true,
              onSelected: _tmdbMarkBusy
                  ? null
                  : (_) => _toggleTmdbMark(favorite: false),
            ),
          if (bgmReady)
            ActionChip(
              avatar: const Icon(
                AnikumoIcons.collections_bookmark_rounded,
                size: 16,
              ),
              label: const Text('同步到 Bangumi'),
              onPressed: _syncBangumiCollection,
            ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    final engine = await VideoEngineService.instance.engine();
    if (_favorite) {
      await engine.favorites.remove(_item.id);
    } else {
      await engine.favorites.add(_item);
    }
    if (mounted) setState(() => _favorite = !_favorite);
  }

  /// Batch 214: display name of the interface this version
  /// of the work comes from.
  String get _sourceName {
    final service = VideoEngineService.instance;
    service.loadRegistry();
    for (final s in service.sources) {
      if (s.id == _item.sourceId) return s.name;
    }
    return '未知接口';
  }

  int get _sourceCount {
    final service = VideoEngineService.instance;
    service.loadRegistry();
    return service.sources.where((s) => s.enabled).length;
  }

  /// Batch 214: 切换接口 — the same work on the other
  /// installed interfaces, mirroring the anime detail
  /// page's source picking.
  Future<void> _showSourceSwitcher() async {
    final picked = await showModalBottomSheet<MediaItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FilmSourceSheet(current: _item),
    );
    if (picked == null || !mounted || picked.id == _item.id) return;
    context.replace('/film/detail', arguments: picked);
  }

  void _showDownloadSheet() {
    final seasons = _detail?.seasons ?? const <Season>[];
    if (seasons.isEmpty) return;
    var line = 0;
    final selected = <int>{};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final season = seasons[line];
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('选择要下载的集')),
                if (seasons.length > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 7,
                      children: [
                        for (var i = 0; i < seasons.length; i++)
                          ChoiceChip(
                            label: Text(
                              seasons[i].title.isEmpty
                                  ? '线路${seasons[i].seasonNumber}'
                                  : seasons[i].title,
                            ),
                            selected: line == i,
                            onSelected: (_) => setSheetState(() {
                              line = i;
                              selected.clear();
                            }),
                          ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setSheetState(() {
                        selected.addAll([
                          for (var i = 0; i < season.episodes.length; i++) i,
                        ]);
                      }),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () => setSheetState(selected.clear),
                      child: const Text('取消全选'),
                    ),
                  ],
                ),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 9,
                          mainAxisSpacing: 9,
                          childAspectRatio: 1.9,
                        ),
                    itemCount: season.episodes.length,
                    itemBuilder: (context, i) {
                      final episode = season.episodes[i];
                      final on = selected.contains(i);
                      return OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: on
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => setSheetState(() {
                          if (on) {
                            selected.remove(i);
                          } else {
                            selected.add(i);
                          }
                        }),
                        child: Text(
                          _episodeLabel(episode),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () async {
                              final picks = selected.toList()..sort();
                              Navigator.of(sheetContext).pop();
                              var added = 0;
                              for (final i in picks) {
                                final ok = await enqueueFilmDownload(
                                  item: _item,
                                  lineIndex: line,
                                  episode: season.episodes[i],
                                  episodeIndex: i,
                                );
                                if (ok) added++;
                              }
                              if (!mounted) return;
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    added == picks.length
                                        ? '已加入下载：${picks.length} 集'
                                        : '已加入下载：$added 集（其余已在下载列表中或没有地址）',
                                  ),
                                ),
                              );
                            },
                      child: Text('开始下载（${selected.length}）'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _starting = false;

  /// Batch 208: playback goes through the shared (anime
  /// zone) player page — the bridge builds its arguments
  /// (roads of direct URLs, resume offset, progress sink).
  Future<void> _play(int lineIndex, int episodeIndex) async {
    if (_starting) return;
    final seasons = _detail?.seasons ?? const [];
    if (lineIndex >= seasons.length ||
        episodeIndex >= seasons[lineIndex].episodes.length) {
      return;
    }
    _starting = true;
    try {
      final engine = await VideoEngineService.instance.engine();
      final episode = seasons[lineIndex].episodes[episodeIndex];
      final resume = await engine.history.resumePosition(
        _item.id,
        episodeId: episode.id,
      );
      // The player page's cover should be the same TVmaze
      // cover the detail header shows (series only).
      final cover = _item.mediaType == MediaType.series
          ? (_tvmazePoster ??
                await TvMazeCoverService.instance.posterFor(
                  title: _item.title,
                  year: _item.year,
                ))
          : null;
      final args = await buildFilmOnlineArgs(
        item: _item,
        lineIndex: lineIndex,
        episodeIndex: episodeIndex,
        resumeOffset: resume,
        posterOverride: cover,
      );
      if (!mounted) return;
      await context.pushNamed('/video/', arguments: args);
      // Refresh the resume entry for when the user returns.
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('播放失败：$e')));
      }
    } finally {
      _starting = false;
    }
  }

  void _playResume() {
    final resume = _resume;
    final seasons = _detail?.seasons ?? const [];
    if (resume == null) return;
    // Episode ids encode '<mediaId>::<lineIdx>::<epIdx>'.
    final parts = (resume.episodeId ?? '').split('::');
    var line = 0;
    var episode = 0;
    if (parts.length >= 2) {
      line = int.tryParse(parts[parts.length - 2]) ?? 0;
      episode = int.tryParse(parts.last) ?? 0;
    }
    if (line >= seasons.length) line = 0;
    _play(line, episode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 218,
            pinned: true,
            title: Text(
              _item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            flexibleSpace: FlexibleSpaceBar(background: _header(context)),
          ),
          SliverToBoxAdapter(child: _info(context)),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_detail == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: FilmEmptyState(
                icon: AnikumoIcons.movie_rounded,
                title: '详情',
                message: _error ?? '没有取到详情。',
                actionLabel: '重试',
                onAction: () {
                  setState(() => _loading = true);
                  _load();
                },
              ),
            )
          else
            SliverToBoxAdapter(child: _lines(context)),
          // Batch 247: 猜你喜欢 — ranked by shared tags.
          if (_recommendations.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: FilmRail(
                  title: '猜你喜欢',
                  items: _recommendations,
                  onTapItem: (item) =>
                      context.pushNamed('/film/detail', arguments: item),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final poster = _coverPoster;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (poster != null && poster.isNotEmpty)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: CachedNetworkImage(
              imageUrl: poster,
              fit: BoxFit.cover,
              cacheManager: filmCoverCacheManager,
              memCacheWidth: 720,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        Container(color: Colors.black.withValues(alpha: 0.35)),
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 86,
                  height: 115,
                  child: poster == null || poster.isEmpty
                      ? Container(color: Colors.white12)
                      : CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          cacheManager: filmCoverCacheManager,
                          memCacheWidth: 260,
                          errorWidget: (_, _, _) =>
                              Container(color: Colors.white12),
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        FilmKindTag(type: _item.mediaType, item: _item),
                        // Batch 245: the score follows the
                        // user's priority — Bangumi, then
                        // TMDB, then the source's rating.
                        if (_displayScore != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '★ ${_displayScore!.score.toStringAsFixed(1)}',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          if (_displayScore!.source.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              _displayScore!.votes > 0
                                  ? '${_displayScore!.source} · ${_displayScore!.votes}人评'
                                  : _displayScore!.source,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (_item.year != null) '${_item.year}',
                        if (_item.countries.isNotEmpty)
                          _item.countries.first.name,
                        if ((_item.raw['remarks']?.toString() ?? '').isNotEmpty)
                          _item.raw['remarks'].toString(),
                      ].join(' · '),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _info(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final directors = _item.people
        .where((p) => p.role == PersonRole.director)
        .toList();
    final actors = _item.people
        .where((p) => p.role == PersonRole.actor)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _resume != null ? _playResume : () => _play(0, 0),
                  icon: const Icon(AnikumoIcons.play_circle_rounded, size: 19),
                  label: Text(
                    _resume != null ? '继续播放 ${_resumeLabel()}' : '播放',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _toggleFavorite,
                icon: Icon(
                  _favorite
                      ? AnikumoIcons.favorite_rounded
                      : AnikumoIcons.favorite_outline_rounded,
                ),
                label: Text(_favorite ? '已收藏' : '收藏'),
              ),
              // Batch 226: a live channel has nothing to
              // download — the button leaves its row.
              if (!cmsItemIsLive(_item)) ...[
                const SizedBox(width: 6),
                IconButton.outlined(
                  tooltip: '下载',
                  onPressed: _detail == null ? null : _showDownloadSheet,
                  icon: const Icon(AnikumoIcons.download_rounded),
                ),
              ],
            ],
          ),
          _cloudSyncRow(context),
          const SizedBox(height: 8),
          // Batch 214: 选接口 — the anime detail page picks a
          // source before playing; here the same choice is a
          // switcher row: which installed interface this
          // version of the work comes from, and a jump to
          // the same work on another interface.
          Row(
            children: [
              Icon(
                AnikumoIcons.dns_rounded,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '接口：$_sourceName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _sourceCount > 1 ? _showSourceSwitcher : null,
                icon: const Icon(AnikumoIcons.swap_horiz_rounded, size: 17),
                label: const Text('切换接口'),
              ),
            ],
          ),
          // Batch 246: chips merge Bangumi tags, TMDB
          // genres/keywords and the source's genres.
          if (_genreChips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final chip in _genreChips)
                  ActionChip(
                    label: Text(chip),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openTagPage(chip),
                  ),
              ],
            ),
          ],
          if (directors.isNotEmpty ||
              (actors.isNotEmpty && _castMembers.isEmpty)) ...[
            const SizedBox(height: 10),
            if (directors.isNotEmpty)
              Text(
                '导演：${directors.map((p) => p.name).join(' / ')}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            // Batch 229: when TMDB cast arrives it replaces
            // this plain line with the photo row below.
            if (actors.isNotEmpty && _castMembers.isEmpty)
              Text(
                '主演：${actors.map((p) => p.name).join(' / ')}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
          ],
          // Batch 246: one overview, by priority —
          // Bangumi's synopsis, then TMDB's, then the
          // source's own (Batch 221's editorial header).
          if (_displayOverview.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '简介 · STORY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.outline,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _displayOverview,
              style: const TextStyle(fontSize: 13.5, height: 1.55),
            ),
          ],
          // Batch 245: the row is Bangumi characters when
          // Bangumi has them, TMDB cast otherwise.
          if (_castMembers.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _castFromBangumi ? '角色 · CHARACTERS' : '演员 · CAST',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.outline,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 8),
            _castRow(context, _castMembers),
          ],
          // Batch 245: comments combine TMDB reviews and
          // Bangumi comments into one stream.
          if (_mergedReviews.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '评论 · REVIEWS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.outline,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 8),
            for (final review in _mergedReviews.take(5)) ...[
              _reviewCard(context, review),
              const SizedBox(height: 8),
            ],
          ],
          if (_castMembers.isNotEmpty || _mergedReviews.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _castFromBangumi ||
                      _mergedReviews.any((r) => r.source == 'Bangumi')
                  ? '角色与评论数据来自 Bangumi 与 TMDB'
                  : '演员与评论数据来自 TMDB',
              style: TextStyle(color: scheme.outline, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  /// Batch 229/245: the cast/character photo row —
  /// avatar, name, and a subtitle line (the character
  /// played for TMDB cast, the performer for Bangumi
  /// characters).
  Widget _castRow(
    BuildContext context,
    List<({String name, String sub, String? imageUrl})> members,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: members.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final member = members[i];
          return SizedBox(
            width: 62,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.surfaceContainerHighest,
                  backgroundImage: member.imageUrl == null
                      ? null
                      : CachedNetworkImageProvider(
                          member.imageUrl!,
                          cacheManager: filmCoverCacheManager,
                        ),
                  child: member.imageUrl == null
                      ? Text(
                          member.name.isEmpty ? '?' : member.name[0],
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 5),
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (member.sub.isNotEmpty)
                  Text(
                    member.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.outline, fontSize: 10),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Batch 229/245: one combined-stream review — author,
  /// rating, date, source, and a four-line excerpt.
  Widget _reviewCard(BuildContext context, FilmReview review) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.author.isEmpty ? '匿名用户' : review.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (review.rating != null) ...[
                Icon(
                  AnikumoIcons.star_rounded,
                  size: 13,
                  color: scheme.primary,
                ),
                const SizedBox(width: 2),
                Text(
                  review.rating!.toStringAsFixed(
                    review.rating! % 1 == 0 ? 0 : 1,
                  ),
                  style: const TextStyle(fontSize: 11.5),
                ),
                const SizedBox(width: 8),
              ],
              if (review.date.isNotEmpty)
                Text(
                  review.date,
                  style: TextStyle(color: scheme.outline, fontSize: 11),
                ),
              const SizedBox(width: 6),
              Text(
                review.source,
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            review.content,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  String _resumeLabel() {
    final resume = _resume;
    if (resume == null) return '';
    final parts = (resume.episodeId ?? '').split('::');
    final ep = parts.length >= 2 ? int.tryParse(parts.last) : null;
    return ep == null ? '' : '· 第${ep + 1}集';
  }

  Widget _lines(BuildContext context) {
    final seasons = _detail?.seasons ?? const <Season>[];
    if (seasons.isEmpty || _tabs == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('该源没有返回可播放的线路。')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Batch 221: editorial section header (the 正倒序
        // toggle rides its action slot).
        EditorialSectionHeader(
          index: '01',
          label: 'EPISODES',
          title: '选集',
          actionLabel: _reversed ? '倒序' : '正序',
          onAction: () => setState(() => _reversed = !_reversed),
        ),
        if (seasons.length > 1 &&
            FilmFeatures.isInstalled(FilmFeatures.lineSpeedId))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _probingLines ? null : _probeLines,
                  icon: _probingLines
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AnikumoIcons.speed_rounded, size: 17),
                  label: Text(_probingLines ? '测速中…' : '线路测速'),
                ),
                if (_lineProbeNote != null)
                  Expanded(
                    child: Text(
                      _lineProbeNote!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (seasons.length > 1)
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final s in seasons)
                Tab(text: s.title.isEmpty ? '线路${s.seasonNumber}' : s.title),
            ],
          ),
        SizedBox(
          height: 320,
          child: TabBarView(
            controller: _tabs,
            children: [
              for (var li = 0; li < seasons.length; li++)
                _episodeGrid(context, li, seasons[li]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _episodeGrid(BuildContext context, int lineIndex, Season season) {
    var episodes = season.episodes;
    if (_reversed) episodes = episodes.reversed.toList();
    if (episodes.isEmpty) {
      return const Center(child: Text('该线路暂无剧集。'));
    }
    final isMovie = _item.mediaType == MediaType.movie;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMovie ? 2 : 4,
        crossAxisSpacing: 9,
        mainAxisSpacing: 9,
        childAspectRatio: isMovie ? 3.2 : 1.9,
      ),
      itemCount: episodes.length,
      itemBuilder: (context, i) {
        final episode = episodes[i];
        final realIndex = season.episodes.indexOf(episode);
        return OutlinedButton(
          onPressed: () => _play(lineIndex, realIndex),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            _episodeLabel(episode),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        );
      },
    );
  }
}
