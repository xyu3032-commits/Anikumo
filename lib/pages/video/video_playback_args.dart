import 'package:flutter/widgets.dart' show BuildContext;

import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/download/download_module.dart';
import 'package:anikumo/modules/roads/road_module.dart';
import 'package:anikumo/plugins/plugins.dart';

/// Route arguments for '/video/'. Entry points hand playback context over
/// through the route instead of pre-filling a shared controller, which lets
/// [VideoPageController] live and die with the route.
sealed class VideoPlaybackArgs {
  const VideoPlaybackArgs({required this.bangumiItem});

  final BangumiItem bangumiItem;
}

/// Batch 208: progress callback for external playback
/// sessions (see [OnlineVideoPlaybackArgs.externalPlayback]).
/// Fired from the player's 1-second timer with the current
/// selection so the owning zone can keep its own history.
typedef ExternalPlaybackProgress =
    void Function(int episode, int road, Duration position, Duration duration);

/// Batch 219: shows an external zone's source picker and
/// returns the picked work's playback args (see
/// [OnlineVideoPlaybackArgs.externalSourceSwitcher]).
typedef ExternalSourceSwitcher =
    Future<OnlineVideoPlaybackArgs?> Function(BuildContext context);

/// Batch 244: one review an external zone lends the
/// player's 评论 tab (the film zone lends its TMDB
/// reviews; external sessions have no Bangumi entry to
/// hang per-episode comments on).
/// Batch 245: [source] names where a review came from
/// ('' when unattributed).
typedef ExternalReview = ({String author, String content, String date, double? rating, String source});

/// Batch 244: loads an external session's reviews on
/// demand (see [OnlineVideoPlaybackArgs.externalReviews]).
typedef ExternalReviewsLoader = Future<List<ExternalReview>> Function();

class OnlineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OnlineVideoPlaybackArgs({
    required super.bangumiItem,
    required this.plugin,
    required this.title,
    required this.src,
    required this.roads,
    this.initialEpisode,
    this.initialRoad,
    this.externalPlayback = false,
    this.initialOffsetSeconds,
    this.onProgress,
    this.externalSourceSwitcher,
    this.externalReviews,
  });

  final Plugin plugin;
  final String title;
  final String src;
  final List<Road> roads;

  /// Batch 127: an explicit episode pick (the info page's
  /// quick episode selector). When set, the player starts at
  /// this episode instead of resuming history, and the mini
  /// session never resumes over it — the pick is deliberate.
  final int? initialEpisode;
  final int? initialRoad;

  /// Batch 208: marks a session owned by another zone (the
  /// 影视 zone plays its direct stream URLs through this page).
  /// External sessions skip everything tied to the anime
  /// catalogue: no automatic danmaku load (that zone brings
  /// its own danmaku source later), no Bangumi episode
  /// comments, no episode-panel downloads, and no writes to
  /// the anime watch history — progress is reported through
  /// [onProgress] instead. (Batch 219: source switching
  /// exists for external sessions too, via their own picker
  /// in [externalSourceSwitcher].)
  final bool externalPlayback;

  /// Batch 208: start offset (seconds) applied together with
  /// an explicit episode pick. External sessions resume from
  /// their own history store, which the anime history lookup
  /// knows nothing about.
  final int? initialOffsetSeconds;

  /// Batch 208: see [ExternalPlaybackProgress].
  final ExternalPlaybackProgress? onProgress;

  /// Batch 219: in-player source switching for external
  /// sessions. The anime flow picks a new source through
  /// its own sheet; an external zone brings its own picker
  /// here — the callback shows it and returns the picked
  /// work's playback args (or null when cancelled). The
  /// player page applies the pick in place, keeping the
  /// episode number and position. The callback needs a
  /// [BuildContext] to present its picker, hence the
  /// import below.
  final ExternalSourceSwitcher? externalSourceSwitcher;

  /// Batch 244: reviews for the player's 评论 tab in an
  /// external session. Anime sessions leave this null —
  /// their tab keeps loading Bangumi episode comments.
  final ExternalReviewsLoader? externalReviews;
}

/// Batch 127: resolves an explicit episode pick against the
/// loaded roads' episode counts. Returns null when there is
/// no pick or the pick is out of range — the caller then
/// falls back to history resume.
({int episode, int road})? resolveInitialEpisode({
  required int? initialEpisode,
  required int? initialRoad,
  required List<int> roadLengths,
}) {
  if (initialEpisode == null || roadLengths.isEmpty) return null;
  final road = (initialRoad ?? 0).clamp(0, roadLengths.length - 1);
  if (initialEpisode < 1 || initialEpisode > roadLengths[road]) {
    return null;
  }
  return (episode: initialEpisode, road: road);
}

class OfflineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OfflineVideoPlaybackArgs({
    required super.bangumiItem,
    required this.pluginName,
    required this.episodeNumber,
    required this.road,
    required this.downloadedEpisodes,
    this.externalPlayback = false,
    this.localPathsByKey,
    this.externalReviews,
  });

  final String pluginName;
  final int episodeNumber;
  final int road;
  final List<DownloadEpisode> downloadedEpisodes;

  /// Batch 208: an external zone's downloads (the 影视 zone)
  /// live in its own download store, not the anime download
  /// repository the offline resolver consults. Same contract
  /// as the online flag: no anime danmaku, no anime history.
  final bool externalPlayback;

  /// Batch 208: local file paths keyed by
  /// '<originalRoad>:<episodeNumber>', consulted before the
  /// anime download repository when [externalPlayback] is set.
  final Map<String, String>? localPathsByKey;

  /// Batch 244: same contract as the online args' field —
  /// reviews for the 评论 tab of an external session.
  final ExternalReviewsLoader? externalReviews;
}
