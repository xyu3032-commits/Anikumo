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

class OnlineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OnlineVideoPlaybackArgs({
    required super.bangumiItem,
    required this.plugin,
    required this.title,
    required this.src,
    required this.roads,
    this.initialEpisode,
    this.initialRoad,
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
  });

  final String pluginName;
  final int episodeNumber;
  final int road;
  final List<DownloadEpisode> downloadedEpisodes;
}
