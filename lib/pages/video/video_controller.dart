import 'dart:async';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/modules/roads/road_module.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/pages/history/history_controller.dart';
import 'package:anikumo/pages/player/player_controller.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/download/download_module.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/repositories/download_repository.dart';
import 'package:anikumo/services/anime/anime_features.dart';
import 'package:anikumo/services/download/download_manager.dart';
import 'package:anikumo/services/video_source/services.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:mobx/mobx.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/modules/bangumi/episode_item.dart';
import 'package:anikumo/modules/comments/comment_item.dart';
import 'package:anikumo/modules/comments/comment_response.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/pages/player/controller/player_danmaku_controller.dart';
import 'package:anikumo/services/player/danmaku_thinning.dart';
import 'package:anikumo/services/player/road_preference.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/episode_url.dart';
import 'package:anikumo/utils/http_headers.dart';
import 'package:anikumo/utils/media.dart';
import 'package:anikumo/utils/async_session.dart';
import 'package:anikumo/services/platform/display_mode_service.dart';
import 'package:anikumo/pages/video/video_fullscreen_controller.dart';

part 'video_controller.g.dart';

class VideoPageController = _VideoPageController with _$VideoPageController;

class VideoEpisodeSelection {
  const VideoEpisodeSelection({
    required this.episode,
    required this.road,
  });

  final int episode;
  final int road;

  @override
  bool operator ==(Object other) {
    return other is VideoEpisodeSelection &&
        other.episode == episode &&
        other.road == road;
  }

  @override
  int get hashCode => Object.hash(episode, road);

  @override
  String toString() {
    return 'VideoEpisodeSelection(episode: $episode, road: $road)';
  }
}

abstract class _VideoPageController with Store implements Disposable {
  _VideoPageController(
    this.historyController,
    this.downloadRepository,
    this.downloadManager,
  );

  late BangumiItem bangumiItem;
  EpisodeInfo episodeInfo = EpisodeInfo.fromTemplate();

  @observable
  var episodeCommentsList = ObservableList<EpisodeCommentItem>();

  // Resolution state machine: [_beginEpisodeSwitch] enters the loading state;
  // [_finishLoading] and [_failLoading] are the only terminal transitions.
  // [_errorMessage] is non-null only in the failed state.
  @readonly
  bool _loading = true;

  @readonly
  String? _errorMessage;

  @observable
  VideoEpisodeSelection selectedEpisode =
      const VideoEpisodeSelection(episode: 1, road: 0);

  @observable
  VideoEpisodeSelection? playingEpisode;

  @observable
  int commentsEpisode = 1;

  @action
  void resetEpisodeState({int episode = 1, int road = 0}) {
    final selection = VideoEpisodeSelection(episode: episode, road: road);
    selectedEpisode = selection;
    playingEpisode = null;
    commentsEpisode = commentEpisodeForSelection(selection);
  }

  VideoEpisodeSelection get playbackEpisode =>
      playingEpisode ?? selectedEpisode;

  final fullscreen = VideoFullscreenController(
    applyFullscreen: DisplayModeService.applyVideoFullscreen,
  );

  bool get isFullscreen => fullscreen.isFullscreen;

  @observable
  bool isCommentsAscending = false;

  // Playback, automatic danmaku loading, and comment loading have separate
  // owners. Manual danmaku selection can cancel auto danmaku without touching
  // playback; comment refreshes never cancel playback.
  final AsyncSessionOwner _playbackSessions = AsyncSessionOwner();
  final AsyncSessionOwner _danmakuSessions = AsyncSessionOwner();
  final AsyncSessionOwner _commentSessions = AsyncSessionOwner();

  @observable
  bool isPip = false;

  @observable
  int historyOffset = 0;

  @observable
  bool isOfflineMode = false;

  /// Batch 208: true while this page runs an external zone's
  /// session (see [OnlineVideoPlaybackArgs.externalPlayback]).
  /// External sessions skip the anime catalogue machinery:
  /// automatic danmaku, Bangumi comments, anime watch-history
  /// writes (progress goes to [_externalProgressSink]).
  bool isExternalPlayback = false;

  ExternalPlaybackProgress? _externalProgressSink;

  /// Batch 244: the external session's reviews loader for
  /// the 评论 tab (null for anime sessions and for external
  /// sessions that lend none).
  ExternalReviewsLoader? externalReviewsLoader;

  /// Batch 208: external offline downloads' local paths,
  /// keyed '<originalRoad>:<episodeNumber>'.
  Map<String, String>? _externalLocalPaths;

  /// Batch 208: forwards a playback position tick to the
  /// owning zone's history (external sessions only).
  void reportExternalProgress(Duration position, Duration duration) {
    if (!isExternalPlayback) return;
    final sink = _externalProgressSink;
    if (sink == null) return;
    final selection = playbackEpisode;
    sink(selection.episode, selection.road, position, duration);
  }

  int _savedHistoryOffset() {
    final identity = _playbackHistoryIdentity;
    if (identity == null) return 0;
    return getHistoryOffsetFor(identity);
  }

  PlaybackHistoryIdentity? _playbackHistoryIdentity;
  final Map<int, DownloadEpisode> _offlineEpisodesByNumber = {};
  final Map<int, int> _offlineDisplayRoadToOriginalRoad = {};
  final Map<int, int> _offlineOriginalRoadToDisplayRoad = {};

  /// Title reported by the video source; may differ from [bangumiItem]'s.
  String title = '';

  String src = '';

  @observable
  var roadList = ObservableList<Road>();

  late Plugin currentPlugin;

  String _offlinePluginName = '';

  final HistoryController historyController;
  final IDownloadRepository downloadRepository;
  final IDownloadManager downloadManager;

  WebViewVideoSourceService? _videoSourceService;

  /// Dedicated resolver for next-episode prefetching. It must not share an
  /// instance with [_videoSourceService]: resolving on an instance cancels
  /// its in-flight request.
  WebViewVideoSourceService? _prefetchVideoSourceService;

  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();

  Stream<String> get logStream => _logStreamController.stream;

  StreamSubscription<String>? _logSubscription;

  /// Applies the route arguments exactly once, from [VideoPage.initState].
  @action
  void applyPlaybackArgs(VideoPlaybackArgs args) {
    switch (args) {
      case OnlineVideoPlaybackArgs():
        bangumiItem = args.bangumiItem;
        currentPlugin = args.plugin;
        title = args.title;
        src = args.src;
        isExternalPlayback = args.externalPlayback;
        _externalProgressSink = args.onProgress;
        externalReviewsLoader = args.externalReviews;
        roadList.clear();
        roadList.addAll(args.roads);
      case OfflineVideoPlaybackArgs():
        _initForOfflinePlayback(
          bangumiItem: args.bangumiItem,
          pluginName: args.pluginName,
          episodeNumber: args.episodeNumber,
          road: args.road,
          downloadedEpisodes: args.downloadedEpisodes,
          externalPlayback: args.externalPlayback,
          localPathsByKey: args.localPathsByKey,
          externalReviews: args.externalReviews,
        );
    }
  }

  @action
  void _initForOfflinePlayback({
    required BangumiItem bangumiItem,
    required String pluginName,
    required int episodeNumber,
    required int road,
    required List<DownloadEpisode> downloadedEpisodes,
    bool externalPlayback = false,
    Map<String, String>? localPathsByKey,
    ExternalReviewsLoader? externalReviews,
  }) {
    this.bangumiItem = bangumiItem;
    _offlinePluginName = pluginName;
    isExternalPlayback = externalPlayback;
    _externalLocalPaths = localPathsByKey;
    externalReviewsLoader = externalReviews;
    title =
        bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;
    isOfflineMode = true;
    _loading = false;

    _buildOfflineRoadList(downloadedEpisodes);

    final target = _findOfflineEpisodeByNumber(
      episodeNumber,
      preferredOriginalRoad: road,
    );
    final selected = VideoEpisodeSelection(
      episode: target?.listIndex ?? 1,
      road: target?.roadIndex ?? 0,
    );
    selectedEpisode = selected;
    playingEpisode = null;
    commentsEpisode = commentEpisodeForSelection(selected);
    final resolvedEpisode = _resolveOfflineEpisode(
      selected.episode,
      road: selected.road,
    );
    if (resolvedEpisode != null) {
      _setOfflineHistoryIdentity(resolvedEpisode);
    } else {
      _playbackHistoryIdentity = null;
    }
    AnikumoLogger().i(
        'VideoPageController: initialized for offline playback, episode $episodeNumber (position: ${selected.episode})');
  }

  void _buildOfflineRoadList(List<DownloadEpisode> episodes) {
    final snapshot = buildOfflineRoadListSnapshot(episodes);
    roadList.clear();
    roadList.addAll(snapshot.roads);
    _offlineEpisodesByNumber.clear();
    _offlineEpisodesByNumber.addAll(snapshot.episodesByNumber);
    _offlineDisplayRoadToOriginalRoad.clear();
    _offlineDisplayRoadToOriginalRoad
        .addAll(snapshot.displayRoadToOriginalRoad);
    _offlineOriginalRoadToDisplayRoad.clear();
    _offlineOriginalRoadToDisplayRoad
        .addAll(snapshot.originalRoadToDisplayRoad);
  }

  String get offlinePluginName => _offlinePluginName;

  PlaybackHistoryIdentity? get currentHistoryIdentity =>
      _playbackHistoryIdentity;

  ({int listIndex, int roadIndex})? _findOfflineEpisodeByNumber(
    int episodeNumber, {
    required int preferredOriginalRoad,
  }) {
    if (episodeNumber <= 0 || roadList.isEmpty) {
      return null;
    }
    final preferredDisplayRoad =
        _offlineOriginalRoadToDisplayRoad[preferredOriginalRoad];
    final roadIndices = <int>[
      if (preferredDisplayRoad != null) preferredDisplayRoad,
      for (var i = 0; i < roadList.length; i++)
        if (i != preferredDisplayRoad) i,
    ];
    for (final roadIndex in roadIndices) {
      final match = _findOfflineEpisodeInDisplayRoad(episodeNumber, roadIndex);
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  ({int listIndex, int roadIndex})? _findOfflineEpisodeInDisplayRoad(
    int episodeNumber,
    int roadIndex,
  ) {
    if (roadIndex < 0 || roadIndex >= roadList.length) {
      return null;
    }
    final index = roadList[roadIndex].data.indexOf(episodeNumber.toString());
    if (index < 0) {
      return null;
    }
    return (listIndex: index + 1, roadIndex: roadIndex);
  }

  int getHistoryOffsetFor(PlaybackHistoryIdentity identity) {
    final playResume = GStorage.getSetting(SettingsKeys.playResume);
    if (playResume != true) {
      return 0;
    }
    return historyController
            .findProgress(
              identity.bangumiItem,
              identity.pluginName,
              identity.episodeNumber,
              entryKind: identity.entryKind,
            )
            ?.progress
            .inSeconds ??
        0;
  }

  void _setOnlineHistoryIdentity(EpisodeRef episode) {
    // Batch 208: external sessions keep their own history.
    if (isExternalPlayback) {
      _playbackHistoryIdentity = null;
      return;
    }
    _playbackHistoryIdentity = PlaybackHistoryIdentity.online(
      bangumiItem: bangumiItem,
      pluginName: currentPlugin.name,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      onlineBangumiSrc: src,
      episodePageUrl: episode.pageUrl,
    );
  }

  void _setOfflineHistoryIdentity(EpisodeRef episode) {
    // Batch 208: external sessions keep their own history.
    if (isExternalPlayback) {
      _playbackHistoryIdentity = null;
      return;
    }
    _playbackHistoryIdentity = PlaybackHistoryIdentity.offline(
      bangumiItem: bangumiItem,
      pluginName: _offlinePluginName,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      episodePageUrl: episode.pageUrl,
    );
  }

  EpisodeRef? _resolveOnlineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final displayTitle = roadData.identifier[index];
    return EpisodeRef.online(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: displayTitle,
      pageUrl: roadData.data[index],
    );
  }

  EpisodeRef? _resolveOfflineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final episodeNumber = int.tryParse(roadData.data[index]);
    if (episodeNumber == null) {
      return null;
    }
    final downloadEpisode = _offlineEpisodesByNumber[episodeNumber];
    final titleFromRoad = roadData.identifier[index];
    final episodeTitle = downloadEpisode?.episodeName.isNotEmpty == true
        ? downloadEpisode!.episodeName
        : (titleFromRoad.isNotEmpty ? titleFromRoad : '第$episodeNumber集');
    return EpisodeRef.offline(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: episodeTitle,
      pageUrl: downloadEpisode?.episodePageUrl ?? '',
      episodeNumber: episodeNumber,
      originalRoadIndex: downloadEpisode?.road ??
          _offlineDisplayRoadToOriginalRoad[targetRoad] ??
          targetRoad,
    );
  }

  EpisodeRef? resolveEpisode(VideoEpisodeSelection selection) {
    return isOfflineMode
        ? _resolveOfflineEpisode(selection.episode, road: selection.road)
        : _resolveOnlineEpisode(selection.episode, road: selection.road);
  }

  int commentEpisodeForSelection(VideoEpisodeSelection selection) {
    final resolvedEpisode = resolveEpisode(selection);
    return resolvedEpisode?.danmakuEpisodeNumber ?? selection.episode;
  }

  /// Resets pre-switch state as a single transaction so observers see one
  /// notification instead of one per field.
  @action
  void _beginEpisodeSwitch(VideoEpisodeSelection selection) {
    final targetCommentsEpisode = commentEpisodeForSelection(selection);
    selectedEpisode = selection;
    playingEpisode = null;
    // The comments sheet only re-queries when [commentsEpisode] changes, so
    // resetting comment state here without changing it would blank the sheet
    // permanently.
    if (targetCommentsEpisode != commentsEpisode) {
      commentsEpisode = targetCommentsEpisode;
      _resetEpisodeComments();
    }
    _loading = true;
    _errorMessage = null;
  }

  @action
  void _applyResolvedSelection(EpisodeRef resolvedEpisode) {
    selectedEpisode = VideoEpisodeSelection(
      episode: resolvedEpisode.listIndex,
      road: resolvedEpisode.roadIndex,
    );
    commentsEpisode = commentEpisodeForSelection(selectedEpisode);
  }

  @action
  void _finishLoading() {
    _loading = false;
  }

  @action
  void _failLoading(String message) {
    _loading = false;
    _errorMessage = message;
  }

  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
    required PlayerController playerController,
  }) async {
    final session = _playbackSessions.begin();
    final selection = VideoEpisodeSelection(
      episode: episode,
      road: currentRoad,
    );
    _beginEpisodeSwitch(selection);
    _danmakuSessions.cancel();
    playerController.danmaku.finishDanmakuLoad();
    _videoSourceService?.cancel();

    await playerController.stop();
    if (session.isStale) {
      return;
    }

    if (isOfflineMode) {
      await _changeOfflineEpisode(
        selection,
        offset,
        session: session,
        playerController: playerController,
      );
      return;
    }

    // Road attempts: the remembered road first (it played last
    // time), then the requested one, then the rest. With auto-switch
    // enabled, a failed resolve walks the list instead of failing
    // the episode on the first dead road.
    final autoSwitch = GStorage.getSetting(SettingsKeys.autoSwitchRoad);
    final roadOrder = RoadPreference.order(
      totalRoads: roadList.length,
      preferred: RoadPreference.preferredRoad(currentPlugin.name),
      current: currentRoad,
    );
    String? lastError;
    var attempted = 0;
    for (final roadIndex in roadOrder) {
      final resolvedEpisode = _resolveOnlineEpisode(episode, road: roadIndex);
      if (resolvedEpisode == null) {
        continue;
      }
      attempted += 1;
      _applyResolvedSelection(resolvedEpisode);
      _setOnlineHistoryIdentity(resolvedEpisode);

      // Batch 143: mirror the offline path — when the caller
      // passed no offset (history entries, episode picks, a
      // plain re-entry), fall back to this episode's saved
      // progress. Resume used to depend entirely on the page
      // layer computing historyOffset up front; any path that
      // arrived with 0 started from the beginning even though
      // the progress was on record.
      final effectiveOffset = offset > 0
          ? offset
          : _savedHistoryOffset();

      AnikumoLogger().i(
          'VideoPageController: changed to ${resolvedEpisode.displayTitle}');
      final urlItem = normalizeEpisodeUrl(
        currentPlugin.baseUrl,
        resolvedEpisode.pageUrl,
      );

      final result = await _resolveWithVideoSourceService(
        urlItem,
        effectiveOffset,
        resolvedEpisode: resolvedEpisode,
        session: session,
        playerController: playerController,
      );
      if (session.isStale) {
        return;
      }
      if (result.ok) {
        unawaited(RoadPreference.save(currentPlugin.name, roadIndex));
        if (roadIndex != currentRoad) {
          AnikumoDialog.showToast(message: '已自动切换到线路 ${roadIndex + 1}');
        }
        return;
      }
      lastError = result.error;
      if (!autoSwitch) {
        break;
      }
      AnikumoLogger().w(
          'VideoPageController: road ${roadIndex + 1} failed (${lastError ?? 'player init'}), trying next road');
    }
    if (attempted == 0) {
      AnikumoLogger().e(
          'VideoPageController: failed to resolve online episode. road=$currentRoad, episode=$episode');
      _failLoading('集数解析失败');
    } else if (lastError != null) {
      _failLoading(lastError);
    } else {
      // Player initialisation failed without a resolve error on every
      // road: keep the previous silent-cancel behaviour.
      _playbackSessions.cancel();
    }
  }

  Future<void> _changeOfflineEpisode(
    VideoEpisodeSelection selection,
    int offset, {
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    final resolvedEpisode =
        _resolveOfflineEpisode(selection.episode, road: selection.road);
    if (resolvedEpisode == null) {
      AnikumoLogger().e(
          'VideoPageController: failed to resolve offline episode. road=${selection.road}, episode=${selection.episode}');
      _failLoading('集数解析失败');
      return;
    }

    final localPath = _getLocalVideoPath(
      bangumiItem.id,
      _offlinePluginName,
      resolvedEpisode.historyEpisodeNumber,
      originalRoad: resolvedEpisode.originalRoadIndex,
    );
    if (localPath == null) {
      _failLoading('该集数未下载');
      return;
    }
    _applyResolvedSelection(resolvedEpisode);
    _setOfflineHistoryIdentity(resolvedEpisode);
    if (session.isStale) {
      return;
    }
    _finishLoading();
    final resolvedOffset =
        offset > 0 ? offset : _savedHistoryOffset();

    AnikumoLogger().i(
        'VideoPageController: offline episode changed to ${resolvedEpisode.historyEpisodeNumber} (index: ${selection.episode}), path: $localPath');

    final params = PlaybackInitParams(
      videoUrl: localPath,
      offset: resolvedOffset,
      isLocalPlayback: true,
      bangumiId: bangumiItem.id,
      pluginName: _offlinePluginName,
      episode: resolvedEpisode.listIndex,
      danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
      pageUrl: resolvedEpisode.pageUrl,
      sortNumber: resolvedEpisode.sortNumber,
      httpHeaders: {},
      adBlockerEnabled: false,
      episodeTitle: resolvedEpisode.displayTitle,
      referer: '',
      currentRoad: resolvedEpisode.roadIndex,
      coverUrl: bangumiItem.images['large'],
      bangumiName:
          bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name,
    );

    final initialized = await playerController.init(params);
    if (session.isActive && initialized) {
      playingEpisode = selection;
      unawaited(_loadPlaybackDanmaku(playerController, params, session));
    } else if (session.isActive) {
      _playbackSessions.cancel();
    }
  }

  Future<void> _loadPlaybackDanmaku(
    PlayerController playerController,
    PlaybackInitParams params,
    AsyncSession session,
  ) async {
    // Batch 208: external sessions never touch the anime
    // danmaku services — the owning zone brings its own
    // danmaku source (the 影视 zone adds one separately).
    if (isExternalPlayback) {
      playerController.danmaku.finishDanmakuLoad(disableDanmaku: true);
      return;
    }
    final danmakuSession = _danmakuSessions.begin();
    playerController.danmaku.beginDanmakuLoad();
    try {
      final result = await playerController.danmaku.fetchDanmaku(
        params.bangumiId,
        params.pluginName,
        params.danmakuEpisodeNumber,
        animeTitle:
            bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name,
      );
      if (session.isActive && danmakuSession.isActive) {
        if (result.hasDanmakus) {
          // Batch 233 （弹幕个性化 pack): a remembered
          // per-anime choice wins over the global default.
          final bool enableDanmaku =
              (AnimeFeatures.isInstalled(AnimeFeatures.danmakuStyleId)
                      ? AnimeDanmakuPrefs.enabledFor(params.bangumiId)
                      : null) ??
                  GStorage.getSetting(SettingsKeys.danmakuEnabledByDefault);
          // Flood control: episodes with extreme danmaku counts are
          // uniformly thinned before they reach the renderer.
          final effectiveResult = DanmakuLoadResult(
            danmakus: thinDanmaku(result.danmakus),
            bangumiID: result.bangumiID,
            status: result.status,
          );
          playerController.danmaku.applyDanmakuLoad(
            effectiveResult,
            enableDanmaku: enableDanmaku,
          );
        } else {
          playerController.danmaku.applyUnavailableDanmakuLoad(result);
          if (result.isFailed) {
            AnikumoDialog.showToast(message: '弹幕加载失败，可手动检索');
          }
        }
      }
    } catch (e) {
      if (session.isActive && danmakuSession.isActive) {
        playerController.danmaku.finishDanmakuLoad(disableDanmaku: true);
        AnikumoDialog.showToast(message: '弹幕加载失败，可手动检索');
      }
      AnikumoLogger().w('VideoPageController: failed to load danmaku', error: e);
    }
  }

  void cancelAutomaticDanmakuLoad() {
    _danmakuSessions.cancel();
  }

  /// Re-runs the next-episode prefetch for the currently playing
  /// episode. The player calls this mid-playback: if the initial
  /// prefetch (fired at episode start) failed on a flaky network,
  /// this gives the resolved-source cache a second chance before the
  /// episode actually ends.
  void ensureNextEpisodePrefetch() {
    final current = playingEpisode;
    if (current == null) return;
    final ref = _resolveOnlineEpisode(current.episode, road: current.road);
    if (ref != null) {
      unawaited(_prefetchNextEpisode(ref));
    }
  }

  String? _getLocalVideoPath(
      int bangumiId, String pluginName, int episodeNumber,
      {int? originalRoad}) {
    // Batch 208: external downloads live in the owning zone's
    // store; their paths arrive with the route arguments.
    final external = _externalLocalPaths;
    if (external != null && originalRoad != null) {
      final path = external['$originalRoad:$episodeNumber'];
      if (path != null) return path;
    }
    final episode =
        downloadRepository.getEpisode(bangumiId, pluginName, episodeNumber);
    return downloadManager.getLocalVideoPath(episode);
  }

  /// Speculatively resolves the next episode on the same road so that
  /// switching to it hits the shared resolved-source cache instead of
  /// paying a full WebView resolve. Best-effort: failures are ignored.
  Future<void> _prefetchNextEpisode(EpisodeRef current) async {
    if (isOfflineMode) return;
    final next = _resolveOnlineEpisode(
      current.listIndex + 1,
      road: current.roadIndex,
    );
    if (next == null ||
        next.pageUrl.isEmpty ||
        next.pageUrl == current.pageUrl) {
      return;
    }
    _prefetchVideoSourceService ??= WebViewVideoSourceService();
    await _prefetchVideoSourceService!.prefetch(
      next.pageUrl,
      useLegacyParser: currentPlugin.useLegacyParser,
    );
  }

  /// Resolves and starts playback on one road. Returns whether
  /// playback started; `error` carries the user-facing failure when
  /// resolution failed, and is null for silent failures (cancelled,
  /// player init failed) so the caller can decide between switching
  /// to another road and failing the episode.
  Future<({bool ok, String? error})> _resolveWithVideoSourceService(
    String url,
    int offset, {
    required EpisodeRef resolvedEpisode,
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    _videoSourceService ??= WebViewVideoSourceService();

    await _logSubscription?.cancel();
    _logSubscription = _videoSourceService!.onLog.listen((log) {
      if (!_logStreamController.isClosed) {
        _logStreamController.add(log);
      }
    });

    try {
      final source = await _videoSourceService!.resolve(
        url,
        useLegacyParser: currentPlugin.useLegacyParser,
        offset: offset,
      );

      if (session.isStale) {
        return (ok: false, error: null);
      }
      _finishLoading();
      AnikumoLogger()
          .i('VideoPageController: resolved video URL: ${source.url}');

      final bool forceAdBlocker =
          GStorage.getSetting(SettingsKeys.forceAdBlocker);

      final params = PlaybackInitParams(
        videoUrl: source.url,
        offset: source.offset,
        isLocalPlayback: false,
        videoSourceFormat: source.format,
        bangumiId: bangumiItem.id,
        pluginName: currentPlugin.name,
        episode: resolvedEpisode.listIndex,
        danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
        pageUrl: resolvedEpisode.pageUrl,
        sortNumber: resolvedEpisode.sortNumber,
        httpHeaders: {
          'user-agent': currentPlugin.userAgent.isEmpty
              ? getRandomUA()
              : currentPlugin.userAgent,
          if (currentPlugin.referer.isNotEmpty)
            'referer': currentPlugin.referer,
        },
        adBlockerEnabled: forceAdBlocker || currentPlugin.adBlocker,
        episodeTitle: resolvedEpisode.displayTitle,
        referer: currentPlugin.referer,
        currentRoad: resolvedEpisode.roadIndex,
        coverUrl: bangumiItem.images['large'],
        bangumiName: bangumiItem.nameCn.isNotEmpty
            ? bangumiItem.nameCn
            : bangumiItem.name,
      );

      final initialized = await playerController.init(params);
      if (session.isActive && initialized) {
        playingEpisode = VideoEpisodeSelection(
          episode: resolvedEpisode.listIndex,
          road: resolvedEpisode.roadIndex,
        );
        unawaited(_loadPlaybackDanmaku(playerController, params, session));
        unawaited(_prefetchNextEpisode(resolvedEpisode));
        return (ok: true, error: null);
      }
      return (ok: false, error: null);
    } on VideoSourceTimeoutException {
      if (session.isStale) {
        return (ok: false, error: null);
      }
      return (ok: false, error: '视频解析超时，请重试');
    } on VideoSourceCancelledException {
      AnikumoLogger().i('VideoPageController: video URL resolution cancelled');
    } catch (e) {
      if (session.isStale) {
        return (ok: false, error: null);
      }
      return (ok: false, error: '视频解析失败：${e.toString()}');
    }
    return (ok: false, error: null);
  }

  void _resetEpisodeComments() {
    _commentSessions.cancel();
    episodeInfo.reset();
    episodeCommentsList.clear();
  }

  Future<bool> queryBangumiEpisodeCommentsByID(int id, int episode) async {
    // Batch 208: external sessions have no Bangumi entry to
    // hang comments on.
    if (isExternalPlayback) return false;
    final session = _commentSessions.begin();
    final EpisodeInfo latestEpisodeInfo;
    try {
      latestEpisodeInfo = await BangumiApi.getBangumiEpisodeByID(id, episode);
    } catch (_) {
      if (session.isStale) {
        return false;
      }
      rethrow;
    }
    if (session.isStale) {
      return false;
    }
    final EpisodeCommentResponse value;
    try {
      value =
          await BangumiApi.getBangumiCommentsByEpisodeID(latestEpisodeInfo.id);
    } catch (_) {
      if (session.isStale) {
        return false;
      }
      rethrow;
    }
    if (session.isStale) {
      return false;
    }
    final commentsList = value.commentList;
    if (!isCommentsAscending) {
      commentsList
          .sort((a, b) => b.comment.createdAt.compareTo(a.comment.createdAt));
    } else {
      commentsList
          .sort((a, b) => a.comment.createdAt.compareTo(b.comment.createdAt));
    }
    _applyEpisodeComments(episode, latestEpisodeInfo, commentsList);
    AnikumoLogger().i(
        'VideoPageController: loaded comments list length ${episodeCommentsList.length}');
    return true;
  }

  @action
  void _applyEpisodeComments(
    int episode,
    EpisodeInfo info,
    List<EpisodeCommentItem> comments,
  ) {
    commentsEpisode = episode;
    episodeInfo = info;
    episodeCommentsList = ObservableList.of(comments);
  }

  @action
  void toggleSortOrder() {
    isCommentsAscending = !isCommentsAscending;
    episodeCommentsList.sort(
      (a, b) => isCommentsAscending
          ? a.comment.createdAt.compareTo(b.comment.createdAt)
          : b.comment.createdAt.compareTo(a.comment.createdAt),
    );
  }

  /// Batch 113: while the in-app mini player session owns this
  /// controller, route-scope disposal must not tear it down; the
  /// session runs the real teardown via [disposeAfterMini].
  bool adoptedByMiniPlayer = false;

  /// Called by Modular when the '/video' route scope is disposed.
  @override
  void dispose() {
    if (adoptedByMiniPlayer) {
      return;
    }
    disposeAfterMini();
  }

  /// Real teardown for a controller the mini session adopted.
  void disposeAfterMini() {
    adoptedByMiniPlayer = false;
    unawaited(fullscreen.close());
    _playbackSessions.cancel();
    _danmakuSessions.cancel();
    _commentSessions.cancel();
    _logSubscription?.cancel();
    _logSubscription = null;
    if (!_logStreamController.isClosed) {
      _logStreamController.close();
    }
    final videoSourceService = _videoSourceService;
    _videoSourceService = null;
    if (videoSourceService != null) {
      unawaited(videoSourceService.dispose());
    }
    final prefetchService = _prefetchVideoSourceService;
    _prefetchVideoSourceService = null;
    if (prefetchService != null) {
      unawaited(prefetchService.dispose());
    }
  }
}

class OfflineRoadListSnapshot {
  const OfflineRoadListSnapshot({
    required this.roads,
    required this.episodesByNumber,
    required this.displayRoadToOriginalRoad,
    required this.originalRoadToDisplayRoad,
  });

  final List<Road> roads;
  final Map<int, DownloadEpisode> episodesByNumber;
  final Map<int, int> displayRoadToOriginalRoad;
  final Map<int, int> originalRoadToDisplayRoad;
}

OfflineRoadListSnapshot buildOfflineRoadListSnapshot(
  List<DownloadEpisode> episodes,
) {
  final groupedEpisodes = <int, List<DownloadEpisode>>{};
  final episodesByNumber = <int, DownloadEpisode>{};

  for (final episode in episodes) {
    episodesByNumber[episode.episodeNumber] = episode;
    groupedEpisodes.putIfAbsent(episode.road, () => []).add(episode);
  }

  final originalRoads = groupedEpisodes.keys.toList()..sort();
  final roads = <Road>[];
  final displayRoadToOriginalRoad = <int, int>{};
  final originalRoadToDisplayRoad = <int, int>{};

  for (final originalRoad in originalRoads) {
    final roadEpisodes = groupedEpisodes[originalRoad]!
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final displayRoad = roads.length;
    displayRoadToOriginalRoad[displayRoad] = originalRoad;
    originalRoadToDisplayRoad[originalRoad] = displayRoad;
    roads.add(Road(
      name: originalRoad >= 0
          ? '播放列表${originalRoad + 1}'
          : '播放列表${displayRoad + 1}',
      data: roadEpisodes.map((e) => e.episodeNumber.toString()).toList(),
      identifier: roadEpisodes
          .map((e) =>
              e.episodeName.isNotEmpty ? e.episodeName : '第${e.episodeNumber}集')
          .toList(),
    ));
  }

  return OfflineRoadListSnapshot(
    roads: roads,
    episodesByNumber: episodesByNumber,
    displayRoadToOriginalRoad: displayRoadToOriginalRoad,
    originalRoadToDisplayRoad: originalRoadToDisplayRoad,
  );
}

class EpisodeRef {
  const EpisodeRef({
    required this.listIndex,
    required this.roadIndex,
    required this.displayTitle,
    required this.pageUrl,
    required this.sortNumber,
    required this.historyEpisodeNumber,
    required this.danmakuEpisodeNumber,
    required this.originalRoadIndex,
  });

  final int listIndex;
  final int roadIndex;
  final String displayTitle;
  final String pageUrl;

  /// Episode sort number.
  /// - Online: parsed from [displayTitle] via [extractEpisodeNumber];
  ///   null when unparsable.
  /// - Offline: always the download record's episodeNumber.
  final int? sortNumber;
  final int historyEpisodeNumber;
  final int danmakuEpisodeNumber;
  final int originalRoadIndex;

  factory EpisodeRef.online({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
  }) {
    final parsedEpisodeNumber = extractEpisodeNumber(displayTitle);
    return EpisodeRef(
      listIndex: listIndex,
      roadIndex: roadIndex,
      displayTitle: displayTitle,
      pageUrl: pageUrl,
      sortNumber: parsedEpisodeNumber > 0 ? parsedEpisodeNumber : null,
      historyEpisodeNumber: listIndex,
      danmakuEpisodeNumber:
          parsedEpisodeNumber > 0 ? parsedEpisodeNumber : listIndex,
      originalRoadIndex: roadIndex,
    );
  }

  const factory EpisodeRef.offline({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
    required int episodeNumber,
    required int originalRoadIndex,
  }) = _OfflineEpisodeRef;
}

class _OfflineEpisodeRef extends EpisodeRef {
  const _OfflineEpisodeRef({
    required super.listIndex,
    required super.roadIndex,
    required super.displayTitle,
    required super.pageUrl,
    required int episodeNumber,
    required super.originalRoadIndex,
  }) : super(
          sortNumber: episodeNumber,
          historyEpisodeNumber: episodeNumber,
          danmakuEpisodeNumber: episodeNumber,
        );
}
