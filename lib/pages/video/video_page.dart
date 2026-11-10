import 'dart:async';
import 'dart:io';

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:window_manager/window_manager.dart';

import 'package:anikumo/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:anikumo/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:anikumo/bean/widget/embedded_native_control_area.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/bean/widget/media_error_widget.dart';
import 'package:anikumo/modules/download/download_module.dart';
import 'package:anikumo/navigation.dart';
import 'package:anikumo/pages/download/download_controller.dart';
import 'package:anikumo/pages/download/download_episode_sheet.dart';
import 'package:anikumo/pages/collect/collect_controller.dart';
import 'package:anikumo/pages/history/history_controller.dart';
import 'package:anikumo/pages/info/info_controller.dart';
import 'package:anikumo/pages/info/source_sheet.dart';
import 'package:anikumo/pages/player/episode_comments_sheet.dart';
import 'package:anikumo/pages/player/player_controller.dart';
import 'package:anikumo/pages/player/player_item.dart';
import 'package:anikumo/pages/video/episode_selection_panel.dart';
import 'package:anikumo/pages/video/player_content_tabs.dart';
import 'package:anikumo/pages/video/video_controller.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/pages/video/video_page_layout.dart';
import 'package:anikumo/pages/video/video_side_panel.dart';
import 'package:anikumo/pages/video/video_system_bars.dart';
import 'package:anikumo/services/player/mini_player_session.dart';
import 'package:anikumo/services/player/pip_utils.dart';
import 'package:anikumo/services/player/timed_shutdown_service.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/device.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.args,
    required this.playerController,
    required this.videoPageController,
    required this.historyController,
    required this.downloadController,
    this.resumeFromMini = false,
  });

  final VideoPlaybackArgs args;
  final PlayerController playerController;
  final VideoPageController videoPageController;
  final HistoryController historyController;
  final DownloadController downloadController;

  /// Batch 113: this visit reattaches to the pair the in-app mini
  /// player kept alive — playback is already running, so the page
  /// must not resolve or restart the episode.
  final bool resumeFromMini;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with SingleTickerProviderStateMixin, WindowListener {
  PlayerController get playerController => widget.playerController;
  VideoPageController get videoPageController => widget.videoPageController;
  bool _didInitializePlayback = false;
  bool _isExiting = false;
  // Batch 113: exit handover to the in-app mini player.
  bool _exitSettled = false;
  bool _exitToMini = false;
  // Batch 120: a failed system-PiP entry on exit lets the next
  // back press leave normally instead of looping.
  bool _pipExitAttempted = false;
  HistoryController get historyController => widget.historyController;
  DownloadController get downloadController => widget.downloadController;
  late bool playResume;
  bool showDebugLog = false;
  List<String> webviewLogLines = [];
  StreamSubscription<String>? _logSubscription;
  final FocusNode keyboardFocus =
      FocusNode(debugLabel: 'Video player shortcut scope');

  final _episodePanelKey = GlobalKey<EpisodeSelectionPanelState>();
  final _sidePanelKey = GlobalKey<VideoSidePanelState>();
  late TabController tabController;

  late final bool disableAnimations;

  StreamSubscription<SyncPlayChatMessage>? _syncChatSubscription;
  late final mobx.ReactionDisposer _pipModeListener;
  LocalHistoryEntry? _desktopPipEntry;
  late ModalRoute<Object?> _route;

  static const Duration _offlinePlayerInitDelay = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    // Batch 116: the page reports itself to the mini session so
    // the floating window hides reliably — route observation alone
    // missed pushes landing in nested navigators.
    MiniPlayerSession.instance.setPlayerPageOpen(true);
    videoPageController.applyPlaybackArgs(widget.args);
    windowManager.addListener(this);

    tabController = TabController(length: 2, vsync: this);

    playResume = GStorage.getSetting(SettingsKeys.playResume);
    disableAnimations =
        GStorage.getSetting(SettingsKeys.playerDisableAnimations);
    _pipModeListener = mobx.reaction<bool>(
      (_) => videoPageController.isPip,
      _syncDesktopPipHistory,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitializePlayback) {
      return;
    }
    _didInitializePlayback = true;
    _route = ModalRoute.of(context)!;
    closeOnExternalNavigation(_route);
    videoPageController.fullscreen.attach(_route);
    if (isDesktop()) {
      unawaited(videoPageController.fullscreen
          .initializeDesktop(windowManager.isFullScreen));
    }
    _initializePlayback();
  }

  void _initializePlayback() {
    if (widget.resumeFromMini) {
      // Reattached from the mini window: the episode is already
      // loaded and playing on this pair — only the UI comes back.
      _revealCurrentEpisode();
    } else if (videoPageController.isOfflineMode) {
      _initOfflineMode();
    } else {
      _initOnlineMode();
    }

    _syncChatSubscription =
        playerController.syncplay.chatStream.listen((event) {
      final localUsername =
          playerController.syncplay.syncplayController?.username ?? '';
      final String displayText = '${event.username}：${event.message}';

      if (playerController.danmaku.danmakuOn &&
          event.username != localUsername &&
          event.fromRemote) {
        playerController.danmaku.canvasController.addDanmaku(
          DanmakuContentItem(
            displayText,
            color: Colors.orange,
            isColorful: true,
            type: DanmakuItemType.bottom,
            extra: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    });
  }

  /// Batch 116: switch the playback SOURCE from inside the player
  /// (the panel menu's 切换片源). Reuses the info page's source
  /// sheet with a throwaway info controller for the current anime;
  /// a pick is applied in place (see [_applySourceSwitch]) instead
  /// of navigating to a second player page.
  void _openSourceSwitcher() {
    if (videoPageController.isOfflineMode) return;
    final infoController = InfoController(inject<CollectController>())
      ..bangumiItem = videoPageController.bangumiItem;
    showAdaptiveBottomSheet<void>(
      context: context,
      maxHeightFactor: 0.88,
      builder: (_) => SourceSheet(
        infoController: infoController,
        onPicked: _applySourceSwitch,
      ),
    );
  }

  /// Applies a source pick in place: same episode number and
  /// playback position carry over when the new source has them.
  void _applySourceSwitch(OnlineVideoPlaybackArgs newArgs) {
    if (!mounted) return;
    final keepEpisode = videoPageController.selectedEpisode.episode;
    final keepOffset = playerController.playback.playerPosition.inSeconds;
    videoPageController.applyPlaybackArgs(newArgs);
    var road = 0;
    var episode = 1;
    var offset = 0;
    final roads = videoPageController.roadList;
    for (var i = 0; i < roads.length; i++) {
      if (roads[i].data.length >= keepEpisode) {
        road = i;
        episode = keepEpisode;
        offset = keepOffset;
        break;
      }
    }
    videoPageController.resetEpisodeState(episode: episode, road: road);
    videoPageController.historyOffset = offset;
    _revealCurrentEpisode();
    // If this pair is the mini session's, the session now plays
    // the new source — refresh its stored args so leaving and
    // returning keeps the switch.
    final session = MiniPlayerSession.instance;
    if (identical(playerController, session.playerController)) {
      session.adopt(
        playerController: playerController,
        videoPageController: videoPageController,
        args: newArgs,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      changeEpisode(episode, currentRoad: road, offset: offset);
    });
  }

  void _initOfflineMode() {
    final identity = videoPageController.currentHistoryIdentity;
    videoPageController.historyOffset = identity == null
        ? 0
        : videoPageController.getHistoryOffsetFor(identity);
    _revealCurrentEpisode();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(_offlinePlayerInitDelay);
      if (!mounted) {
        return;
      }

      await changeEpisode(
        videoPageController.selectedEpisode.episode,
        currentRoad: videoPageController.selectedEpisode.road,
        offset: videoPageController.historyOffset,
      );
    });
  }

  void _initOnlineMode() {
    videoPageController.historyOffset = 0;

    // Batch 127: an explicit episode pick from the info page
    // beats history resume — start exactly there, from 0.
    final args = widget.args;
    var explicitPick = false;
    if (args is OnlineVideoPlaybackArgs) {
      final resolved = resolveInitialEpisode(
        initialEpisode: args.initialEpisode,
        initialRoad: args.initialRoad,
        roadLengths: [
          for (final road in videoPageController.roadList) road.data.length,
        ],
      );
      if (resolved != null) {
        videoPageController.resetEpisodeState(
          episode: resolved.episode,
          road: resolved.road,
        );
        explicitPick = true;
      }
    }

    if (!explicitPick) {
      var progress = historyController.lastWatching(
          videoPageController.bangumiItem,
          videoPageController.currentPlugin.name);
      if (progress != null) {
        if (videoPageController.roadList.length > progress.road) {
          if (videoPageController.roadList[progress.road].data.length >=
              progress.episode) {
            videoPageController.resetEpisodeState(
              episode: progress.episode,
              road: progress.road,
            );
            if (playResume) {
              videoPageController.historyOffset = progress.progress.inSeconds;
            }
          }
        }
      }
    }
    _revealCurrentEpisode();

    _logSubscription = videoPageController.logStream.listen((log) {
      if (mounted) {
        setState(() {
          webviewLogLines.add(log);
          if (webviewLogLines.length > 100) {
            webviewLogLines.removeAt(0);
          }
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      changeEpisode(videoPageController.selectedEpisode.episode,
          currentRoad: videoPageController.selectedEpisode.road,
          offset: videoPageController.historyOffset);
    });
  }

  @override
  void dispose() {
    _settleExit();
    // Batch 116: page gone — the mini window may show again (the
    // exit settle above decides whether the pair was parked in it).
    MiniPlayerSession.instance.setPlayerPageOpen(false);
    clearExternalNavigationMark(_route);
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    try {
      _syncChatSubscription?.cancel();
    } catch (_) {}
    try {
      _logSubscription?.cancel();
    } catch (_) {}
    _pipModeListener();
    _desktopPipEntry?.remove();
    _desktopPipEntry = null;
    if (!isDesktop()) {
      try {
        ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
      } catch (_) {}
    }
    unawaited(videoPageController.fullscreen.close());
    keyboardFocus.dispose();
    tabController.dispose();
    TimedShutdownService().cancel();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    videoPageController.fullscreen.onDesktopFullscreenChanged(true);
  }

  @override
  void onWindowLeaveFullScreen() {
    videoPageController.fullscreen.onDesktopFullscreenChanged(false);
  }

  void _toggleDebugConsole() {
    setState(() {
      showDebugLog = !showDebugLog;
    });
  }

  Future<void> changeEpisode(int episode,
      {int currentRoad = 0, int offset = 0}) async {
    if (!mounted || _isExiting) {
      return;
    }
    setState(() {
      webviewLogLines.clear();
      showDebugLog = false;
    });
    await videoPageController.changeEpisode(episode,
        currentRoad: currentRoad,
        offset: offset,
        playerController: playerController);
  }

  void _revealCurrentEpisode() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _episodePanelKey.currentState?.revealCurrentEpisode();
    });
  }

  void _toggleSidePanel() => _sidePanelKey.currentState?.toggle();

  void _closeSidePanel() => _sidePanelKey.currentState?.close();

  // Only desktop PiP participates in local navigation.
  void _syncDesktopPipHistory(bool isPip) {
    if (!isDesktop()) return;
    if (isPip && _desktopPipEntry == null) {
      _desktopPipEntry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          _desktopPipEntry = null;
          if (videoPageController.isPip) {
            videoPageController.isPip = false;
            unawaited(PipUtils.exitDesktopPIPWindow());
          }
        },
      );
      ModalRoute.of(context)!.addLocalHistoryEntry(_desktopPipEntry!);
    } else if (!isPip) {
      _desktopPipEntry?.remove();
      _desktopPipEntry = null;
    }
  }

  void _onBackPressed() {
    unawaited(Navigator.of(context).maybePop());
  }

  /// Batch 113: decides once, synchronously, what happens to the
  /// controller pair as this page goes away — park it in the in-app
  /// mini window (the mobile default), end an adopted session for
  /// real, or fall through to the normal shutdown. Runs from the
  /// PopScope callback (ahead of route teardown) and again from
  /// dispose as a fallback for non-pop removals.
  void _settleExit() {
    if (_exitSettled) {
      return;
    }
    _exitSettled = true;
    final session = MiniPlayerSession.instance;
    final isSessionPair =
        identical(playerController, session.playerController);
    final canMini = MiniPlayerSession.shouldExitToMini(
          isDesktopPlatform: isDesktop(),
          playerController: playerController,
        ) &&
        videoPageController.errorMessage == null &&
        !videoPageController.loading;
    if (canMini) {
      _exitToMini = true;
      session.adopt(
        playerController: playerController,
        videoPageController: videoPageController,
        args: widget.args,
      );
    } else if (isSessionPair) {
      unawaited(session.close());
    }
  }

  void pauseForTimedShutdown() {
    if (playerController.playback.playing) {
      playerController.pause();
    }
  }

  /// Batch 120: in the external (system) PiP mode, backing out
  /// of a playing video should switch into system PiP instead of
  /// ending playback — the mirror of the in-app mode's exit
  /// handover. The pop is intercepted (canPop false), PiP entry
  /// is attempted, and only a failure lets the exit proceed.
  bool get _shouldInterceptExitForPip =>
      Platform.isAndroid &&
      !GStorage.getSetting(SettingsKeys.pipInAppMode) &&
      playerController.playback.playing &&
      videoPageController.errorMessage == null &&
      !videoPageController.loading &&
      !_pipExitAttempted;

  Future<void> _enterPipInsteadOfExit() async {
    final entered = await PipUtils.enterAndroidPIPWindow(
      width: playerController.debug.playerWidth,
      height: playerController.debug.playerHeight,
    );
    if (entered || !mounted) return;
    _pipExitAttempted = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Batch 120: the Observer wraps the PopScope so canPop can
    // react to playback state — in external PiP mode a back
    // press on a playing video is intercepted and routed into
    // system PiP instead of ending playback.
    return Observer(builder: (context) {
      final bool isPip = videoPageController.isPip;
      final bool interceptPipExit = _shouldInterceptExitForPip;
      return PopScope(
        canPop: !interceptPipExit,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) {
            setState(() => _isExiting = true);
            _settleExit();
            if (!_exitToMini) {
              playerController.beginShutdown();
            }
          } else if (interceptPipExit) {
            unawaited(_enterPipInsteadOfExit());
          }
        },
        child: VideoSystemBars(
          fullscreen: videoPageController.isFullscreen,
          isPip: isPip,
          child: Scaffold(
            body: VideoPageLayout(
              fullscreen: videoPageController.isFullscreen,
              isPip: isPip,
              playerBuilder: (context, layout) => ColoredBox(
                color: Colors.black,
                child: Focus(
                  focusNode: keyboardFocus,
                  autofocus: true,
                  // Cleanup resets loading while the route is still visible.
                  child: _isExiting
                      ? const SizedBox.expand()
                      : Observer(builder: (_) => _buildPlayerBody(layout)),
                ),
              ),
              tabs: tabBody,
              sidePanel: VideoSidePanel(
                key: _sidePanelKey,
                fullscreen: videoPageController.isFullscreen,
                disableAnimations: disableAnimations,
                onOpened: _revealCurrentEpisode,
                onClosed: keyboardFocus.requestFocus,
                child: tabBody,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildPlayerBody(VideoPlayerLayout layout) {
    final bool playerLoading = playerController.playback.loading;
    return Stack(
      children: [
        Positioned.fill(
          child: Stack(
            children: [
              if (videoPageController.loading ||
                  playerLoading ||
                  videoPageController.errorMessage != null)
                Container(
                  color: Colors.black,
                  child: Observer(builder: (context) {
                    final errorMessage = videoPageController.errorMessage;
                    if (errorMessage != null) {
                      return MediaErrorWidget(
                        title: '暂时无法播放',
                        errMsg: errorMessage,
                        icon: AnikumoIcons.videocam_off_outlined,
                      );
                    }
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LoadingIndicator(
                              color: Theme.of(context)
                                  .colorScheme
                                  .tertiaryContainer),
                          const SizedBox(height: 10),
                          Text(
                            videoPageController.loading
                                ? '视频资源解析中'
                                : '视频资源解析成功, 播放器加载中',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              Visibility(
                visible: (videoPageController.loading || playerLoading) &&
                    showDebugLog,
                child: Container(
                  color: Colors.black,
                  child: Align(
                    alignment: Alignment.center,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: webviewLogLines.length,
                      itemBuilder: (context, index) {
                        return Text(
                          webviewLogLines[index],
                          style: const TextStyle(
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                ),
              ),
              Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: EmbeddedNativeControlArea(
                      requireOffset: !videoPageController.isFullscreen,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(AnikumoIcons.arrow_back,
                                color: Colors.white),
                            onPressed: _onBackPressed,
                          ),
                          const Expanded(
                              child: dtb.DragToMoveArea(
                                  child: SizedBox(height: 40))),
                          IconButton(
                            icon: const Icon(AnikumoIcons.refresh_outlined,
                                color: Colors.white),
                            onPressed: () {
                              changeEpisode(
                                  videoPageController.selectedEpisode.episode,
                                  currentRoad:
                                      videoPageController.selectedEpisode.road);
                            },
                          ),
                          if (layout.hasSidePanel)
                            IconButton(
                              onPressed: _toggleSidePanel,
                              icon: const Icon(
                                AnikumoIcons.menu_open_rounded,
                                color: Colors.white,
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                                showDebugLog
                                    ? AnikumoIcons.bug_report
                                    : AnikumoIcons.bug_report_outlined,
                                color: Colors.white),
                            onPressed: _toggleDebugConsole,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: playerLoading
              ? const SizedBox.shrink()
              : PlayerItem(
                  fillsWindow: layout.fillsWindow,
                  playerController: playerController,
                  videoPageController: videoPageController,
                  onToggleSidePanel:
                      layout.hasSidePanel ? _toggleSidePanel : null,
                  changeEpisode: changeEpisode,
                  onBackPressed: _onBackPressed,
                  keyboardFocus: keyboardFocus,
                  disableAnimations: disableAnimations,
                  pauseForTimedShutdown: pauseForTimedShutdown,
                  onSwitchSource: videoPageController.isOfflineMode
                      ? null
                      : _openSourceSwitcher,
                ),
        ),
      ],
    );
  }

  Widget get episodePanel => Observer(builder: (context) {
        final downloads = <String, DownloadEpisode>{};
        if (!videoPageController.isOfflineMode) {
          for (final record in downloadController.records) {
            if (record.bangumiId != videoPageController.bangumiItem.id ||
                record.pluginName != videoPageController.currentPlugin.name) {
              continue;
            }
            for (final episode in record.episodes.values) {
              if (episode.episodePageUrl.isNotEmpty) {
                downloads[episode.episodePageUrl] = episode;
              } else if (episode.road >= 0 &&
                  episode.road < videoPageController.roadList.length) {
                // Older records have no URL; only match within their own road.
                final urls = videoPageController.roadList[episode.road].data;
                if (episode.episodeNumber > 0 &&
                    episode.episodeNumber <= urls.length) {
                  downloads[urls[episode.episodeNumber - 1]] = episode;
                }
              }
            }
          }
        }
        return EpisodeSelectionPanel(
          key: _episodePanelKey,
          title: videoPageController.title,
          roads: videoPageController.roadList,
          selectedRoad: videoPageController.selectedEpisode.road,
          selectedEpisode: videoPageController.selectedEpisode.episode,
          downloads: downloads,
          isOffline: videoPageController.isOfflineMode,
          isPlaying: playerController.playback.playing &&
              !playerController.playback.loading &&
              !videoPageController.loading,
          disableAnimations: disableAnimations,
          onEpisodeSelected: (episode, road) {
            if (episode == videoPageController.selectedEpisode.episode &&
                road == videoPageController.selectedEpisode.road) {
              return;
            }
            _closeSidePanel();
            changeEpisode(episode, currentRoad: road);
          },
          onDownload: (road) => showAdaptiveBottomSheet<void>(
            context: context,
            builder: (context) => DownloadEpisodeSheet(
              road: road,
              videoPageController: videoPageController,
            ),
          ),
        );
      });

  Widget get tabBody {
    final colors = Theme.of(context).colorScheme;
    final int episodeNum = videoPageController.commentsEpisode;

    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlayerContentTabs(
            controller: tabController,
            onEpisodesSelected: _revealCurrentEpisode,
          ),
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: [
                episodePanel,
                EpisodeCommentsSheet(
                  episode: episodeNum,
                  selection: videoPageController.selectedEpisode,
                  videoPageController: videoPageController,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
