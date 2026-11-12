import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liuguang_core/liuguang_core.dart' hide DownloadStatus;

import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/modules/download/download_module.dart';
import 'package:anikumo/modules/roads/road_module.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/services/liuguang/bangumi_film.dart';
import 'package:anikumo/services/liuguang/film_downloads.dart';
import 'package:anikumo/services/liuguang/film_features.dart';
import 'package:anikumo/services/liuguang/tmdb_enrich.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/video_source/direct_media_registry.dart';

/// Batch 208: plays 影视 content through the anime zone's
/// player page instead of a zone-specific player, as the
/// user asked ("跟动漫区播放页面一样，不要自己设计").
///
/// The bridge translates the engine's detail model into the
/// player's argument shape:
///   * lines （线路） become roads of direct stream URLs, and
///     every URL is registered in [DirectMediaRegistry] so
///     the player's resolver returns it untouched (no WebView
///     sniffing round for a playlist file);
///   * the item becomes a synthetic [BangumiItem] whose id
///     lives far above any real Bangumi id — display metadata
///     only; the session is flagged external, so no anime
///     danmaku/comments/history machinery ever touches it;
///   * playback progress is reported back through the args'
///     progress sink into the engine's own history, throttled
///     to one write per 5 seconds per episode.

/// Deterministic synthetic Bangumi id for a film media id
/// (FNV-1a; stable across runs unlike [String.hashCode]).
int filmBangumiIdFor(String mediaId) {
  var hash = 0x811c9dc5;
  for (final unit in mediaId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 1000000000 + hash % 100000000;
}

BangumiItem filmBangumiItem({
  required String mediaId,
  required String title,
  String posterUrl = '',
  String overview = '',
  int? year,
  double ratingScore = 0,
}) {
  return BangumiItem(
    id: filmBangumiIdFor(mediaId),
    // Bangumi type 6 = 三次元 (live action).
    type: 6,
    name: title,
    nameCn: title,
    summary: overview,
    airDate: year?.toString() ?? '',
    airWeekday: 0,
    rank: 0,
    images: {
      'large': posterUrl,
      'medium': posterUrl,
      'common': posterUrl,
      'small': posterUrl,
      'grid': posterUrl,
    },
    tags: const [],
    alias: const [],
    ratingScore: ratingScore,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

BangumiItem filmBangumiItemFor(MediaItem item, {String? posterOverride}) =>
    filmBangumiItem(
      mediaId: item.id,
      title: item.title,
      posterUrl: posterOverride ?? item.artwork.poster ?? '',
      overview: item.overview,
      year: item.year,
      ratingScore: item.rating.score,
    );

/// A inert rule-plugin shell carrying the source's display
/// name and origin. External sessions never run its search /
/// chapter rules — it exists because the player's arguments
/// require one (road preference keys, header derivation).
Plugin filmPluginFor(VideoSourceEntry? entry) {
  final api = entry?.api ?? '';
  final uri = Uri.tryParse(api);
  final origin = uri != null && uri.hasScheme
      ? '${uri.scheme}://${uri.authority}'
      : '';
  return Plugin.fromJson({
    'name': entry?.name ?? '影视',
    'type': 'video',
    'baseURL': origin,
    'referer': origin,
  });
}

/// Batch 244: the episode labels one road carries into
/// the player's episode panel — TMDB's name for the
/// episode number when one was resolved, else the
/// station's own title. Pure, for tests.
List<String> filmRoadIdentifiers(
  Season season,
  Map<int, String> episodeNames,
) => [
  for (final e in season.episodes)
    if ((episodeNames[e.episodeNumber]?.trim() ?? '').isNotEmpty)
      episodeNames[e.episodeNumber]!
    else
      e.title,
];

/// Builds the roads (one per line, direct URLs in episode
/// order) for [detail], registering every URL as direct
/// media. Episodes whose source is missing keep an empty
/// slot so indexes stay aligned with the detail page's grid.
Future<List<Road>> filmRoadsFor(
  LiuGuangMediaEngine engine,
  MediaDetail detail, {
  Map<int, String> episodeNames = const {},
}) async {
  // Batch 232 （极速解析 pack): with the pack installed the
  // per-episode source resolution runs concurrently
  // (six at a time per line) instead of one await at a
  // time — on a 72-episode title the serial walk was the
  // player page's whole opening wait.
  final parallel = FilmFeatures.isInstalled(FilmFeatures.fastResolveId);

  Future<String> resolveEpisode(Season season, Episode episode) async {
    var url = '';
    try {
      final sources = await engine.getPlaybackSources(
        PlaybackQuery(mediaId: detail.item.id, episodeId: episode.id),
      );
      if (sources.isNotEmpty) {
        final own = sources.where((s) => s.quality == season.title);
        url = (own.isNotEmpty ? own.first : sources.first).url;
      }
    } catch (_) {
      url = '';
    }
    // Batch 223: only true media files are registered as
    // direct. Page-style links (a station's /share/ line)
    // stay unregistered so the player's resolver treats
    // them as episode pages and sniffs the real stream,
    // exactly like anime episode pages.
    if (url.isNotEmpty && DirectMediaRegistry.isDirectMediaUrl(url)) {
      DirectMediaRegistry.register(url);
    }
    return url;
  }

  final roads = <Road>[];
  for (var line = 0; line < detail.seasons.length; line++) {
    final season = detail.seasons[line];
    final data = List<String>.filled(season.episodes.length, '');
    if (parallel) {
      for (var at = 0; at < season.episodes.length; at += 6) {
        final chunk = <Future<void>>[
          for (var i = at; i < season.episodes.length && i < at + 6; i++)
            resolveEpisode(season, season.episodes[i]).then((url) {
              data[i] = url;
            }),
        ];
        await Future.wait(chunk);
      }
    } else {
      for (var i = 0; i < season.episodes.length; i++) {
        data[i] = await resolveEpisode(season, season.episodes[i]);
      }
    }
    roads.add(
      Road(
        name: season.title.isEmpty ? '线路${line + 1}' : season.title,
        data: data,
        identifier: filmRoadIdentifiers(season, episodeNames),
      ),
    );
  }
  return roads;
}

/// The engine-history progress sink for one title. Writes
/// are throttled (5s per episode, immediate on episode
/// change); >95% watched marks the episode completed, the
/// same rule the zone's own player used.
ExternalPlaybackProgress filmProgressSink(
  LiuGuangMediaEngine engine,
  MediaDetail detail,
) {
  var lastKey = '';
  var lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  return (episode, road, position, duration) {
    if (road < 0 || road >= detail.seasons.length) return;
    final episodes = detail.seasons[road].episodes;
    if (episode < 1 || episode > episodes.length) return;
    final key = '$road:$episode';
    final now = DateTime.now();
    if (key == lastKey && now.difference(lastWrite).inSeconds < 5) return;
    lastKey = key;
    lastWrite = now;
    final completed =
        duration.inMilliseconds > 0 &&
        position.inMilliseconds >= duration.inMilliseconds * 0.95;
    unawaited(
      engine.history.record(
        PlaybackHistory(
          mediaId: detail.item.id,
          episodeId: episodes[episode - 1].id,
          title: detail.item.title,
          position: position,
          duration: duration,
          lastPlayedAt: now,
          completed: completed,
        ),
      ),
    );
  };
}

/// Full online arguments for playing [item] at
/// ([lineIndex], [episodeIndex]) in the shared player page.
/// [resumeOffset] is the episode's saved position in the
/// engine history, when the caller resolved one.
Future<OnlineVideoPlaybackArgs> buildFilmOnlineArgs({
  required MediaItem item,
  required int lineIndex,
  required int episodeIndex,
  Duration? resumeOffset,
  String? posterOverride,
}) async {
  final service = VideoEngineService.instance;
  final engine = await service.engine();
  final detail = await engine.getDetail(item.id);
  if (detail == null || detail.seasons.isEmpty) {
    throw StateError('没有取到播放信息，源可能暂时不可用。');
  }
  VideoSourceEntry? entry;
  for (final e in service.sources) {
    if (e.id == item.sourceId) {
      entry = e;
      break;
    }
  }
  // Batch 232 （线路测速优选 pack): the roads and the
  // progress sink run on the speed-preferred line order;
  // the caller's line index (in the station's own order)
  // is remapped by line title so the same line opens.
  final pref = FilmFeatures.isInstalled(FilmFeatures.lineSpeedId)
      ? FilmLineSpeed.orderFor(item.sourceId)
      : const <String>[];
  final ordered = reorderDetailLines(detail, pref);
  final requestedTitle = lineIndex < detail.seasons.length
      ? detail.seasons[lineIndex].title
      : null;
  var initialRoad = lineIndex;
  if (pref.isNotEmpty && requestedTitle != null) {
    final at = ordered.seasons.indexWhere((s) => s.title == requestedTitle);
    if (at >= 0) initialRoad = at;
  }
  // Batch 244: TMDB episode names for the player's
  // episode panel. The wait is capped — a slow metadata
  // call must never hold playback hostage; a timed-out
  // fetch keeps running and warms the cache for next time.
  var episodeNames = const <int, String>{};
  if (detail.item.mediaType == MediaType.series) {
    try {
      episodeNames = await TmdbEpisodeNamesService.instance
          .forItem(
            detail.item,
            episodeCount: ordered.seasons.firstOrNull?.episodes.length,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      episodeNames = const {};
    }
  }
  final roads = await filmRoadsFor(
    engine,
    ordered,
    episodeNames: episodeNames,
  );
  final offset = (resumeOffset != null && resumeOffset.inSeconds > 0)
      ? resumeOffset.inSeconds
      : null;
  return OnlineVideoPlaybackArgs(
    bangumiItem: filmBangumiItemFor(
      detail.item,
      posterOverride: posterOverride,
    ),
    plugin: filmPluginFor(entry),
    title: detail.item.title,
    src: detail.item.id,
    roads: roads,
    initialEpisode: episodeIndex + 1,
    initialRoad: initialRoad,
    externalPlayback: true,
    initialOffsetSeconds: offset,
    onProgress: filmProgressSink(engine, ordered),
    // Batch 244/245: the player's 评论 tab shows this
    // work's combined comment stream — TMDB reviews and
    // Bangumi comments merged, like the detail page.
    externalReviews: () async {
      final results = await Future.wait([
        TmdbEnrichService.instance.forItem(detail.item),
        BangumiFilmService.instance.forItem(detail.item),
      ]);
      final enrichment = results[0] as TmdbEnrichment?;
      final bgm = results[1] as BangumiFilmData?;
      return [
        for (final r in mergeFilmReviews(
          tmdb: enrichment?.reviews ?? const [],
          bangumi: bgm?.comments ?? const [],
        ))
          (
            author: r.author,
            content: r.content,
            date: r.date,
            rating: r.rating,
            source: r.source,
          ),
      ];
    },
    // Batch 219: the player's source-switch entry opens the
    // film zone's own interface picker; a pick rebuilds
    // args for that version and the page applies them in
    // place (same episode + position).
    externalSourceSwitcher: (context) async {
      final picked = await showModalBottomSheet<MediaItem>(
        context: context,
        isScrollControlled: true,
        builder: (_) => FilmSourceSheet(current: detail.item),
      );
      if (picked == null) return null;
      return buildFilmOnlineArgs(item: picked, lineIndex: 0, episodeIndex: 0);
    },
  );
}

/// Offline arguments for playing a title's finished film
/// downloads in the shared player page. [files] pairs every
/// completed download ref with its local file path.
OfflineVideoPlaybackArgs buildFilmOfflineArgs({
  required String mediaId,
  required String title,
  required String pluginName,
  required List<({FilmDownloadRef ref, String filePath})> files,
  required int startLineIndex,
  required int startEpisodeIndex,
}) {
  final downloaded = <DownloadEpisode>[];
  final paths = <String, String>{};
  for (final f in files) {
    downloaded.add(
      DownloadEpisode(
        f.ref.episodeIndex + 1,
        f.ref.episodeTitle,
        f.ref.lineIndex,
        DownloadStatus.completed,
        100,
        0,
        0,
        f.filePath,
        '',
        '',
        null,
        '',
        0,
        '',
      ),
    );
    paths['${f.ref.lineIndex}:${f.ref.episodeIndex + 1}'] = f.filePath;
  }
  return OfflineVideoPlaybackArgs(
    bangumiItem: filmBangumiItem(mediaId: mediaId, title: title),
    pluginName: pluginName,
    episodeNumber: startEpisodeIndex + 1,
    road: startLineIndex,
    downloadedEpisodes: downloaded,
    externalPlayback: true,
    localPathsByKey: paths,
    // Batch 244/245: the combined comment stream for the
    // player's 评论 tab. The offline builder only knows
    // the title, so both sources are probed as a series
    // first and then as a movie; both are cached lookups.
    externalReviews: () async {
      for (final stub in <MediaItem>[
        TVSeries(id: mediaId, title: title),
        Movie(id: mediaId, title: title),
      ]) {
        final results = await Future.wait([
          TmdbEnrichService.instance.forItem(stub),
          BangumiFilmService.instance.forItem(stub),
        ]);
        final enrichment = results[0] as TmdbEnrichment?;
        final bgm = results[1] as BangumiFilmData?;
        final merged = mergeFilmReviews(
          tmdb: enrichment?.reviews ?? const [],
          bangumi: bgm?.comments ?? const [],
        );
        if (merged.isNotEmpty) {
          return [
            for (final r in merged)
              (
                author: r.author,
                content: r.content,
                date: r.date,
                rating: r.rating,
                source: r.source,
              ),
          ];
        }
      }
      return const [];
    },
  );
}
