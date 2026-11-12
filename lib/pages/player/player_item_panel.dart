import 'dart:async';
import 'dart:io';

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:anikumo/bean/widget/anikumo_menu.dart';
import 'package:anikumo/bean/widget/play_pause_icon.dart';
import 'package:anikumo/pages/player/player_adjustment_hud.dart';
import 'package:anikumo/pages/player/danmaku_destination_sheet.dart';
import 'package:anikumo/pages/player/controller/player_aspect_ratio.dart';
import 'package:anikumo/pages/player/controller/player_super_resolution.dart';
import 'package:anikumo/bean/widget/embedded_native_control_area.dart';
import 'package:anikumo/pages/player/player_panel_hold.dart';
import 'package:anikumo/pages/player/pip_settings_sheet.dart';
import 'package:anikumo/services/player/pip_utils.dart';
import 'package:anikumo/services/player/skip_settings.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/pages/video/video_controller.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/pages/player/player_controller.dart';
import 'package:flutter/services.dart';
import 'package:anikumo/services/player/remote.dart';
import 'package:anikumo/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:anikumo/pages/settings/danmaku/danmaku_settings_sheet.dart';
import 'package:anikumo/pages/settings/player_enhance_page.dart';
import 'package:anikumo/services/player/player_enhance.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/utils/device.dart';
import 'package:anikumo/services/player/timed_shutdown_service.dart';
import 'package:anikumo/utils/format.dart';
import 'package:anikumo/pages/player/player_transport_bar.dart';
import 'package:anikumo/pages/player/player_screenshot_controls.dart';
import 'package:anikumo/pages/player/player_progress_bar.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class PlayerItemPanel extends StatefulWidget {
  const PlayerItemPanel({
    super.key,
    required this.playerController,
    required this.videoPageController,
    required this.fillsWindow,
    required this.onBackPressed,
    required this.setPlaybackSpeed,
    required this.showDanmakuSwitch,
    required this.handleFullscreen,
    required this.enterAndroidPictureInPicture,
    required this.handleScreenShot,
    required this.showScreenshotCandidates,
    required this.onNextEpisode,
    required this.handleProgressBarDragStart,
    required this.handleProgressBarDragEnd,
    required this.handleSuperResolutionChange,
    required this.panelVisibilityController,
    this.onToggleSidePanel,
    required this.keyboardFocus,
    required this.acquirePlayerPanelHold,
    required this.onMenuVisibilityChanged,
    required this.handleDanmaku,
    required this.skipOP,
    required this.showVideoInfo,
    required this.showSyncPlayPanel,
    required this.pauseForTimedShutdown,
    this.disableAnimations = false,
    this.showSourceSwitch,
  });

  final PlayerController playerController;
  final VideoPageController videoPageController;
  final bool fillsWindow;
  final VoidCallback onBackPressed;
  final Future<void> Function(double) setPlaybackSpeed;
  final VoidCallback showDanmakuSwitch;
  final VoidCallback? onToggleSidePanel;
  final VoidCallback handleFullscreen;
  final Future<void> Function() enterAndroidPictureInPicture;
  final VoidCallback handleScreenShot;
  final VoidCallback showScreenshotCandidates;
  final VoidCallback handleProgressBarDragStart;
  final void Function(bool cancelled) handleProgressBarDragEnd;
  final Future<void> Function(SuperResolutionMode mode)
      handleSuperResolutionChange;
  final AnimationController panelVisibilityController;
  final FocusNode keyboardFocus;
  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final ValueChanged<bool> onMenuVisibilityChanged;
  final VoidCallback handleDanmaku;
  final VoidCallback onNextEpisode;
  final VoidCallback skipOP;
  final VoidCallback showVideoInfo;
  final VoidCallback showSyncPlayPanel;
  final VoidCallback pauseForTimedShutdown;
  final bool disableAnimations;

  /// Batch 116: switch the playback source from inside the player
  /// (not just the current source's lines). Null hides the entry
  /// (offline playback has no sources to switch between).
  final VoidCallback? showSourceSwitch;

  @override
  State<PlayerItemPanel> createState() => _PlayerItemPanelState();
}

class _PlayerItemPanelState extends State<PlayerItemPanel> {
  late final Animation<Offset> _topOffsetAnimation;
  late final Animation<Offset> _bottomOffsetAnimation;
  late final Animation<Offset> _rightOffsetAnimation;
  late final VideoPageController videoPageController =
      widget.videoPageController;
  late final PlayerController playerController;
  final TextEditingController textController = TextEditingController();
  final FocusNode textFieldFocus = FocusNode();
  int? _danmakuPauseTick;

  /// Whether this editor currently owns a pause. The sleep timer bumps
  /// [TimedShutdownService.expiryTicks] when it actually expires, which revokes
  /// the ownership even if the panel was rebuilt in between.
  bool get _pausedByDanmakuEdit =>
      _danmakuPauseTick == TimedShutdownService().expiryTicks.value;
  bool _holdResumeForDestinationSheet = false;

  String? _cachedDanmakuColorHex;
  late Widget _cachedDanmakuOnIcon;
  late final Widget _cachedDanmakuOffIcon;
  late final Widget _cachedDanmakuSettingsIcon;

  static const double _danmakuIconSize = 24.0;
  static const double _loadingIndicatorStrokeWidth = 2.0;

  @override
  void dispose() {
    textFieldFocus.removeListener(_onDanmakuEditFocusChanged);
    textController.dispose();
    textFieldFocus.dispose();
    super.dispose();
  }

  Future<void> _submitDanmakuText(String message) async {
    _holdResumeForDestinationSheet = true;
    textFieldFocus.unfocus();

    if (message.trim().isEmpty) {
      AnikumoDialog.showToast(message: '弹幕内容为空');
      _holdResumeForDestinationSheet = false;
      _onDanmakuEditFocusChanged();
      return;
    }

    final destination = await showDanmakuDestinationSheet(context);
    _holdResumeForDestinationSheet = false;
    if (!mounted) {
      return;
    }
    _onDanmakuEditFocusChanged();
    if (destination == null) {
      return;
    }

    widget.keyboardFocus.requestFocus();
    if (message.length > 100) {
      AnikumoDialog.showToast(message: '弹幕内容过长');
      return;
    }

    if (destination == DanmakuDestination.chatRoom) {
      if (playerController.syncplay.syncplayRoom.isEmpty) {
        AnikumoDialog.showToast(message: '你还没有加入一起看，无法发送聊天室弹幕');
        return;
      }

      final sender =
          playerController.syncplay.syncplayController?.username ?? '我';
      playerController.danmaku.canvasController.addDanmaku(
        DanmakuContentItem(
          '$sender：$message',
          color: Colors.orange,
          isColorful: true,
          type: DanmakuItemType.bottom,
          extra: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      unawaited(playerController.sendSyncPlayChatMessage(message));
    } else {
      // The danmaku providers have no send API (batch
      // 182): echo on screen now, and persist the item
      // locally so it is still here on the next load of
      // this episode instead of vanishing with the echo.
      playerController.danmaku.canvasController
          .addDanmaku(DanmakuContentItem(message, selfSend: true));
      playerController.danmaku.recordSentDanmaku(
        message,
        playbackPosition: playerController.playback.currentPosition,
      );
    }
    textController.clear();
  }

  // A SyncPlay room is left alone: a local pause there is either broadcast to
  // everyone or undone by the next server state message.
  void _onDanmakuEditFocusChanged() {
    if (playerController.syncplay.hasSession) return;
    if (textFieldFocus.hasFocus) {
      if (GStorage.getSetting<bool>(SettingsKeys.pauseOnDanmakuEdit) &&
          playerController.playback.playing) {
        _danmakuPauseTick = TimedShutdownService().expiryTicks.value;
        unawaited(playerController.pause(enableSync: false));
      }
    } else if (_canResumeAfterDanmakuEdit) {
      _danmakuPauseTick = null;
      unawaited(playerController.play(enableSync: false));
    }
  }

  /// Only undoes a pause this editor created, and only when nothing else owns
  /// playback: no destination sheet, no app in the background (desktop window
  /// switches report inactive), and no dialog on top.
  bool get _canResumeAfterDanmakuEdit =>
      _pausedByDanmakuEdit &&
      !_holdResumeForDestinationSheet &&
      (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
          AppLifecycleState.resumed &&
      (ModalRoute.of(context)?.isCurrent ?? false);


  // Keeps the tap that dismisses the composer away from the video and the play
  // button. The region must stay in the text field's group, or the paste/copy/
  // select-all toolbar stops responding.
  Widget _danmakuEditBarrier(Widget child) {
    return ListenableBuilder(
      listenable: textFieldFocus,
      builder: (context, _) => TextFieldTapRegion(
        consumeOutsideTaps: textFieldFocus.hasFocus && _pausedByDanmakuEdit,
        child: child,
      ),
    );
  }

  Widget get _danmakuTextField {
    return Observer(builder: (context) {
      return PlayerPanelHoldFocusRegion(
          acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
          child: Container(
            constraints: isDesktop()
                ? const BoxConstraints(maxWidth: 500, maxHeight: 33)
                : const BoxConstraints(maxHeight: 33),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              focusNode: textFieldFocus,
              style: TextStyle(
                  fontSize: isDesktop() ? 15 : 13, color: Colors.white),
              controller: textController,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                enabled: playerController.danmaku.danmakuOn,
                filled: true,
                fillColor: Colors.white38,
                floatingLabelBehavior: FloatingLabelBehavior.never,
                hintText: playerController.danmaku.danmakuOn
                    ? '发个友善的弹幕见证当下'
                    : '已关闭弹幕',
                hintStyle: TextStyle(
                    fontSize: isDesktop() ? 15 : 13, color: Colors.white60),
                alignLabelWithHint: true,
                contentPadding: EdgeInsets.symmetric(
                    vertical: 8, horizontal: isDesktop() ? 8 : 12),
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius:
                      BorderRadius.all(Radius.circular(isDesktop() ? 8 : 20)),
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 0),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () {
                        unawaited(_submitDanmakuText(textController.text));
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: playerController.danmaku.danmakuOn
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Colors.white60,
                        backgroundColor: playerController.danmaku.danmakuOn
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).disabledColor,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(isDesktop() ? 8 : 20),
                        ),
                      ),
                      child: const Text('发送'),
                    ),
                  ],
                ),
              ),
              onSubmitted: (msg) {
                unawaited(_submitDanmakuText(msg));
              },
              onTapOutside: (_) {
                textFieldFocus.unfocus();
                widget.keyboardFocus.requestFocus();
              },
            ),
          ));
    });
  }

  void _showForwardChange() {
    AnikumoDialog.show(builder: (context) {
      var input = '';
      return AlertDialog(
        title: const Text('跳过秒数'),
        content: TextField(
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            floatingLabelBehavior: FloatingLabelBehavior.never,
            labelText: playerController.playback.buttonSkipTime.toString(),
          ),
          onChanged: (value) {
            input = value;
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => AnikumoDialog.dismiss(),
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () {
              if (input.isNotEmpty) {
                playerController.setButtonForwardTime(int.parse(input));
              }
              AnikumoDialog.dismiss();
            },
            child: const Text('确定'),
          ),
        ],
      );
    });
  }

  @override
  void initState() {
    super.initState();
    playerController = widget.playerController;
    textFieldFocus.addListener(_onDanmakuEditFocusChanged);
    final visibility = widget.panelVisibilityController
        .drive(CurveTween(curve: Curves.easeInOut));
    _topOffsetAnimation = visibility.drive(Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ));
    _bottomOffsetAnimation = visibility.drive(Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ));
    _rightOffsetAnimation = visibility.drive(Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ));
    _cachedDanmakuOffIcon = RepaintBoundary(
      child: SvgPicture.asset(
        'assets/images/danmaku_off.svg',
        height: _danmakuIconSize,
      ),
    );

    _cachedDanmakuSettingsIcon = RepaintBoundary(
      child: SvgPicture.asset(
        'assets/images/danmaku_setting.svg',
        height: _danmakuIconSize,
      ),
    );
  }

  Widget _danmakuOnIcon(BuildContext context) {
    final colorHex = Theme.of(context)
        .colorScheme
        .primary
        .toARGB32()
        .toRadixString(16)
        .substring(2);

    if (_cachedDanmakuColorHex != colorHex) {
      _cachedDanmakuColorHex = colorHex;
      final svgString = danmakuOnSvg.replaceFirst('00AEEC', colorHex);
      _cachedDanmakuOnIcon = RepaintBoundary(
        child: SvgPicture.string(
          svgString,
          height: _danmakuIconSize,
        ),
      );
    }

    return _cachedDanmakuOnIcon;
  }

  Widget _buildDanmakuToggleButton(BuildContext context) {
    return Observer(builder: (context) {
      final danmakuLoading = playerController.danmaku.danmakuLoading;
      final danmakuOn = playerController.danmaku.danmakuOn;
      return IconButton(
        color: Colors.white,
        icon: danmakuLoading
            ? SizedBox(
                width: _danmakuIconSize,
                height: _danmakuIconSize,
                child: CircularProgressIndicator(
                  strokeWidth: _loadingIndicatorStrokeWidth,
                ),
              )
            : (danmakuOn ? _danmakuOnIcon(context) : _cachedDanmakuOffIcon),
        onPressed: danmakuLoading ? null : widget.handleDanmaku,
        tooltip: danmakuLoading ? '弹幕加载中...' : (danmakuOn ? '关闭弹幕' : '打开弹幕'),
      );
    });
  }

  Widget _forwardButton() {
    return Tooltip(
      message: '快进${playerController.playback.buttonSkipTime}秒，长按修改时间',
      child: GestureDetector(
        onLongPress: _showForwardChange,
        child: IconButton(
          icon: Image.asset(
            'assets/images/forward_80.png',
            color: Colors.white,
            height: 24,
          ),
          onPressed: widget.skipOP,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => _buildPanel(
          constraints.maxWidth < MediaQuery.textScalerOf(context).scale(600),
        ),
      );

  Widget _buildPanel(bool compact) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildScrim(
            height: 50,
            colors: const [Colors.black45, Colors.transparent],
            offset: _topOffsetAnimation,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildScrim(
            height: 100,
            colors: const [Colors.transparent, Colors.black45],
            offset: _bottomOffsetAnimation,
          ),
        ),
        Positioned(
          top: 25,
          child: Observer(builder: (context) {
            // Hidden HUDs must not observe playback ticks.
            final visible = playerController.panel.showSeekTime;
            return PlayerSeekHud(
              visible: visible,
              currentPosition: visible
                  ? playerController.playback.currentPosition
                  : Duration.zero,
              playerPosition: visible
                  ? playerController.playback.playerPosition
                  : Duration.zero,
              duration:
                  visible ? playerController.playback.duration : Duration.zero,
              direction: playerController.panel.seekDirection,
              cancelPending: playerController.panel.seekCancelPending,
              disableAnimations: widget.disableAnimations,
            );
          }),
        ),
        Positioned(
          top: 25,
          child: Observer(builder: (context) {
            return PlayerSpeedHud(
              visible: playerController.panel.showPlaySpeed,
              speed: playerController.playback.playerSpeed,
              disableAnimations: widget.disableAnimations,
            );
          }),
        ),
        Positioned(
          top: 25,
          child: Observer(builder: (context) {
            final showVolume = playerController.panel.showVolume;
            final showBrightness = playerController.panel.showBrightness;
            return PlayerAdjustmentHud(
              visible: showVolume || showBrightness,
              type: showVolume
                  ? PlayerAdjustmentHudType.volume
                  : PlayerAdjustmentHudType.brightness,
              value: showVolume
                  ? playerController.playback.volume
                  : playerController.panel.brightness,
              disableAnimations: widget.disableAnimations,
            );
          }),
        ),
        if (!isDesktop())
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Observer(builder: (context) {
              if ((compact || !widget.fillsWindow) &&
                  !playerController.panel.lockPanel) {
                return const SizedBox.shrink();
              }
              return Visibility(
                visible: widget.disableAnimations
                    ? playerController.panel.showVideoController
                    : true,
                child: widget.disableAnimations
                    ? _rightControls
                    : SlideTransition(
                        position: _rightOffsetAnimation,
                        child: _rightControls),
              );
            }),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Observer(builder: (context) {
            return Visibility(
              visible: !playerController.panel.lockPanel &&
                  (widget.disableAnimations
                      ? playerController.panel.showVideoController
                      : true),
              child: widget.disableAnimations
                  ? _buildTopControls(compact)
                  : SlideTransition(
                      position: _topOffsetAnimation,
                      child: _buildTopControls(compact)),
            );
          }),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Observer(builder: (context) {
            return Visibility(
              visible: !playerController.panel.lockPanel &&
                  (widget.disableAnimations
                      ? playerController.panel.showVideoController
                      : true),
              child: widget.disableAnimations
                  ? _buildBottomControls(compact)
                  : SlideTransition(
                      position: _bottomOffsetAnimation,
                      child: _buildBottomControls(compact)),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildScrim({
    required double height,
    required List<Color> colors,
    required Animation<Offset> offset,
  }) =>
      Observer(builder: (context) {
        final scrim = Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
          ),
        );
        return Visibility(
          visible: !playerController.panel.lockPanel &&
              (!widget.disableAnimations ||
                  playerController.panel.showVideoController),
          child: widget.disableAnimations
              ? scrim
              : SlideTransition(position: offset, child: scrim),
        );
      });

  void _showDanmakuSettings() {
    showDanmakuSettingsSheet(
      context: context,
      danmakuController: playerController.danmaku.canvasController,
      onUpdateDanmakuSpeed: playerController.updateDanmakuSpeed,
      onTimelineOffsetChanged:
          playerController.danmaku.clearAndInvalidateScheduledDanmakus,
    );
  }

  List<Widget> _choiceItems<T>(
    Iterable<T> values, {
    required String Function(T) label,
    required bool Function(T) selected,
    required void Function(T) onSelected,
  }) =>
      [
        for (final value in values)
          AnikumoMenuItem(
            onPressed: () => onSelected(value),
            label: label(value),
            selected: selected(value),
          ),
      ];

  List<Widget> get _aspectRatioItems => _choiceItems(
        PlayerAspectRatio.values,
        label: (value) => value.label,
        selected: (value) => value == playerController.panel.aspectRatioMode,
        onSelected: (value) => playerController.panel.aspectRatioMode = value,
      );

  List<Widget> get _speedItems => _choiceItems(
        defaultPlaySpeedList,
        label: (value) => '${value}x',
        selected: (value) => value == playerController.playback.playerSpeed,
        onSelected: widget.setPlaybackSpeed,
      );

  List<Widget> get _superResolutionItems => _choiceItems(
        SuperResolutionMode.values,
        label: (value) => value.label,
        selected: (value) =>
            value == playerController.playback.superResolutionMode,
        onSelected: widget.handleSuperResolutionChange,
      );

  Widget _menuButton(
          {required Widget child,
          required List<Widget> items,
          String? tooltip}) =>
      PlayerPanelHoldMenuAnchor(
        acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
        onVisibilityChanged: widget.onMenuVisibilityChanged,
        builder: (context, toggle) => tooltip == null
            ? TextButton(onPressed: toggle, child: child)
            : IconButton(onPressed: toggle, icon: child, tooltip: tooltip),
        menuChildren: items,
      );

  Widget get _danmakuSettingsButton => IconButton(
        onPressed: _showDanmakuSettings,
        color: Colors.white,
        icon: _cachedDanmakuSettingsIcon,
        tooltip: '弹幕设置',
      );

  Widget get _desktopDanmakuControls => LayoutBuilder(
        builder: (context, constraints) => Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDanmakuToggleButton(context),
              _danmakuSettingsButton,
              if (constraints.maxWidth > 600)
                _danmakuEditBarrier(_danmakuTextField),
            ],
          ),
        ),
      );

  Widget get _syncPlayMenuItem => AnikumoMenuItem(
        onPressed: widget.showSyncPlayPanel,
        label: '一起看',
      );

  Widget get _danmakuSettingsMenuItem => AnikumoMenuItem(
        onPressed: _showDanmakuSettings,
        label: '弹幕设置',
      );

  // Batch 18: the 播放增强 profile used to live only in
  // 设置 → anikumo 增强； users asked to reach it while watching.
  // Opening it here applies the profile to the RUNNING player
  // on return (turning something off still needs the next
  // playback start, since mpv properties persist per player).
  Future<void> _openPlayerEnhance() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PlayerEnhancePage(),
        // Batch 251: named as a settings route so the
        // mini player treats it as one (see
        // miniPlayerZoneForRoute).
        settings: const RouteSettings(name: '/settings/player-enhance'),
      ),
    );
    if (!mounted) return;
    final runningPlayer = playerController.playback.mediaPlayer;
    if (runningPlayer != null) {
      await PlayerEnhance.applyTo(runningPlayer);
    }
    if (!mounted) return;
    AnikumoDialog.showToast(message: '播放增强已应用到当前播放');
  }

  Widget get _playerEnhanceMenuItem => AnikumoMenuItem(
        onPressed: _openPlayerEnhance,
        label: '播放增强',
      );

  Widget get _wideControls => Row(children: [
        if (isDesktop()) Expanded(child: _desktopDanmakuControls),
        if (!isDesktop()) ...[
          IconButton(
            color: Colors.white,
            icon: playerController.danmaku.danmakuOn
                ? _danmakuOnIcon(context)
                : _cachedDanmakuOffIcon,
            onPressed: widget.handleDanmaku,
            tooltip: playerController.danmaku.danmakuOn ? '关闭弹幕' : '打开弹幕',
          ),
          if (playerController.danmaku.danmakuOn) ...[
            _danmakuSettingsButton,
            Expanded(child: _danmakuEditBarrier(_danmakuTextField)),
          ] else
            const Spacer(),
        ],
        _menuButton(
          child: const Text('超分辨率', style: TextStyle(color: Colors.white)),
          items: _superResolutionItems,
        ),
        _menuButton(
          child: Text(
              playerController.playback.playerSpeed == 1
                  ? '倍速'
                  : '${playerController.playback.playerSpeed}x',
              style: const TextStyle(color: Colors.white)),
          items: _speedItems,
        ),
        _menuButton(
          child: const Icon(AnikumoIcons.aspect_ratio_rounded, color: Colors.white),
          tooltip: '视频比例',
          items: _aspectRatioItems,
        ),
        if (widget.onToggleSidePanel != null)
          IconButton(
            color: Colors.white,
            icon: const Icon(AnikumoIcons.menu_open_rounded),
            tooltip: '选集面板',
            onPressed: widget.onToggleSidePanel,
          ),
      ]);

  Widget _buildBottomControls(bool compact) => SafeArea(
        top: false,
        bottom: !compact && widget.fillsWindow,
        left: !compact && widget.fillsWindow,
        right: !compact && widget.fillsWindow,
        child: PlayerPanelHoldMouseRegion(
          acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
          cursor: (videoPageController.isFullscreen &&
                  !playerController.panel.showVideoController)
              ? SystemMouseCursors.none
              : SystemMouseCursors.basic,
          child: PlayerTransportBar(
            compact: compact,
            timePlacement: PlayerTimeLabelPlacement.forViewport(
              MediaQuery.sizeOf(context),
              desktop: isDesktop(),
            ),
            playPause: IconButton(
              tooltip: playerController.playback.playing ? '暂停' : '播放',
              onPressed: () => playerController.playOrPause(),
              icon: PlayPauseIcon(
                iconColor: Colors.white,
                playing: playerController.playback.playing,
              ),
            ),
            nextEpisode: IconButton(
              color: Colors.white,
              icon: const Icon(AnikumoIcons.skip_next_rounded),
              tooltip: '下一集',
              onPressed: widget.onNextEpisode,
            ),
            // Playback ticks only rebuild the progress bar and its time labels.
            progressBuilder: ({required sideLabels}) => Observer(
                builder: (context) => PlayerProgressBar(
                      sideLabels: sideLabels,
                      progress: playerController.playback.currentPosition,
                      buffered: playerController.playback.buffer,
                      total: playerController.playback.duration,
                      onDragStart: widget.handleProgressBarDragStart,
                      onDragUpdate: (position) => playerController.seeking
                          .updateInteractiveSeek(position),
                      onDragEnd: widget.handleProgressBarDragEnd,
                      onSeek: playerController.seek,
                    )),
            timeLabel: Observer(
                builder: (context) => Text(
                      '${compact ? '    ' : ''}${durationToString(playerController.playback.currentPosition)} / ${durationToString(playerController.playback.duration)}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: !compact && isDesktop() ? 16 : 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    )),
            controls: compact ? const SizedBox.shrink() : _wideControls,
            fullscreen: _buildFullscreenButton(compact),
          ),
        ),
      );

  Widget _buildFullscreenButton(bool compact) {
    if (videoPageController.isPip) {
      return compact ? const Text('    ') : const SizedBox.shrink();
    }
    if (!isDesktop() &&
        widget.fillsWindow &&
        !videoPageController.isFullscreen) {
      return const SizedBox.shrink();
    }
    return IconButton(
      color: Colors.white,
      icon: Icon(videoPageController.isFullscreen
          ? AnikumoIcons.fullscreen_exit_rounded
          : AnikumoIcons.fullscreen_rounded),
      tooltip: videoPageController.isFullscreen ? '退出全屏' : '全屏',
      onPressed: widget.handleFullscreen,
    );
  }

  Widget _buildTopControls(bool compact) {
    return EmbeddedNativeControlArea(
      requireOffset: compact || !videoPageController.isFullscreen,
      child: SafeArea(
        top: false,
        bottom: false,
        left: !compact && widget.fillsWindow,
        right: !compact && widget.fillsWindow,
        child: PlayerPanelHoldMouseRegion(
          acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
          cursor: (videoPageController.isFullscreen &&
                  !playerController.panel.showVideoController)
              ? SystemMouseCursors.none
              : SystemMouseCursors.basic,
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: const Icon(AnikumoIcons.arrow_back_rounded),
                tooltip: '返回',
                onPressed: widget.onBackPressed,
              ),
              Expanded(
                child: dtb.DragToMoveArea(
                  child: compact
                      ? const SizedBox(height: 40)
                      : Text(
                          ' ${videoPageController.title} [${videoPageController.roadList[videoPageController.selectedEpisode.road].identifier[videoPageController.selectedEpisode.episode - 1]}]',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: Theme.of(context)
                                .textTheme
                                .titleMedium!
                                .fontSize,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                ),
              ),
              _forwardButton(),
              if (isDesktop())
                PlayerScreenshotControls(
                  controller: playerController.screenshots,
                  onCapture: widget.handleScreenShot,
                  onReview: widget.showScreenshotCandidates,
                ),
              if ((isDesktop() &&
                      (compact || !videoPageController.isFullscreen)) ||
                  Platform.isAndroid)
                // Batch 113: long-press opens the PiP settings (mode,
                // zone hiding, mute) without leaving the player.
                // Batch 116: the long-press lives on the button
                // itself — a GestureDetector wrapped around it lost
                // the gesture arena to the player's own recognizers,
                // so the settings often never opened.
                IconButton(
                    onLongPress: () => showPipSettingsSheet(context),
                    onPressed: () async {
                      if (isDesktop()) {
                        if (videoPageController.isPip) {
                          await PipUtils.exitDesktopPIPWindow();
                        } else {
                          await PipUtils.enterDesktopPIPWindow(
                            width: playerController.debug.playerWidth,
                            height: playerController.debug.playerHeight,
                          );
                        }
                        videoPageController.isPip = !videoPageController.isPip;
                        return;
                      }
                      if (GStorage.getSetting(SettingsKeys.pipInAppMode)) {
                        // In-app mini player: leaving the page parks
                        // playback in the floating window (the page's
                        // exit path performs the handover).
                        widget.onBackPressed();
                        return;
                      }
                      await widget.enterAndroidPictureInPicture();
                    },
                    tooltip: '画中画',
                    icon: const Icon(
                      AnikumoIcons.picture_in_picture,
                      color: Colors.white,
                    ),
                  ),
              if (compact) _buildDanmakuToggleButton(context),
              PlayerPanelHoldCollectButton(
                acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
                bangumiItem: videoPageController.bangumiItem,
              ),
              PlayerPanelHoldMenuAnchor(
                acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
                onVisibilityChanged: widget.onMenuVisibilityChanged,
                builder: (context, toggle) {
                  return IconButton(
                    onPressed: toggle,
                    tooltip: '更多选项',
                    icon: const Icon(
                      AnikumoIcons.more_vert,
                      color: Colors.white,
                    ),
                  );
                },
                menuChildren: [
                  if (compact) ...[
                    SubmenuButton(
                        menuChildren: _aspectRatioItems,
                        child: const Text('视频比例')),
                    SubmenuButton(
                        menuChildren: _speedItems, child: const Text('倍速')),
                    SubmenuButton(
                        menuChildren: _superResolutionItems,
                        child: const Text('超分辨率')),
                    _syncPlayMenuItem,
                  ],
                  AnikumoMenuItem(
                    onPressed: widget.showDanmakuSwitch,
                    label: '弹幕切换',
                  ),
                  if (widget.showSourceSwitch != null)
                    AnikumoMenuItem(
                      onPressed: widget.showSourceSwitch!,
                      label: '切换片源',
                    ),
                  _playerEnhanceMenuItem,
                  if (compact) _danmakuSettingsMenuItem,
                  AnikumoMenuItem(
                    onPressed: widget.showVideoInfo,
                    label: '视频详情',
                  ),
                  AnikumoMenuItem(
                    onPressed: () {
                      // Renderers fetch the URL themselves: they cannot reach
                      // a file on this device or send the rule's Referer.
                      if (playerController.isLocalPlayback) {
                        AnikumoDialog.showToast(message: '暂不支持离线视频');
                        return;
                      }
                      if (playerController.referer.isNotEmpty) {
                        AnikumoDialog.showToast(message: '暂不支持该规则');
                        return;
                      }
                      final needRestart = playerController.playback.playing;
                      playerController.pause();
                      RemotePlay()
                          .castVideo(playerController.videoUrl,
                              title: playerController.mediaTitle)
                          .whenComplete(() {
                        if (mounted && needRestart) {
                          playerController.play();
                        }
                      });
                    },
                    label: '远程投屏',
                  ),
                  AnikumoMenuItem(
                    onPressed: playerController.launchExternalPlayer,
                    label: '外部播放',
                  ),
                  SubmenuButton(
                    menuChildren: [
                      AnikumoMenuItem(
                        onPressed: TimedShutdownService().cancel,
                        label: '不开启',
                        selected: !TimedShutdownService().isActive,
                      ),
                      for (final int minutes in [15, 30, 60])
                        AnikumoMenuItem(
                          onPressed: () {
                            TimedShutdownService().start(minutes,
                                onExpired: widget.pauseForTimedShutdown);
                            AnikumoDialog.showToast(
                                message:
                                    '已设置 ${TimedShutdownService().formatMinutesToDisplay(minutes)} 后定时关闭');
                          },
                          label: '$minutes 分钟',
                          selected:
                              TimedShutdownService().setMinutes == minutes,
                        ),
                      AnikumoMenuItem(
                        onPressed: () {
                          TimedShutdownService.showCustomTimerDialog(
                            onExpired: widget.pauseForTimedShutdown,
                          );
                        },
                        label: '自定义',
                      ),
                    ],
                    child: ValueListenableBuilder<int>(
                      valueListenable:
                          TimedShutdownService().remainingSecondsNotifier,
                      builder: (context, remainingSeconds, _) => Text(
                        remainingSeconds > 0
                            ? "定时关闭 (${TimedShutdownService().formatRemainingTime()})"
                            : "定时关闭",
                      ),
                    ),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      AnikumoMenuItem(
                        onPressed: () => GStorage.putSetting<String>(
                            SettingsKeys.playbackMode, 'next'),
                        label: '顺序连播',
                        selected: GStorage.getSetting<String>(
                                SettingsKeys.playbackMode) ==
                            'next',
                      ),
                      AnikumoMenuItem(
                        onPressed: () => GStorage.putSetting<String>(
                            SettingsKeys.playbackMode, 'loop'),
                        label: '单集循环',
                        selected: GStorage.getSetting<String>(
                                SettingsKeys.playbackMode) ==
                            'loop',
                      ),
                      AnikumoMenuItem(
                        onPressed: () => GStorage.putSetting<String>(
                            SettingsKeys.playbackMode, 'stop'),
                        label: '播完暂停',
                        selected: GStorage.getSetting<String>(
                                SettingsKeys.playbackMode) ==
                            'stop',
                      ),
                    ],
                    child: const Text('播放模式'),
                  ),
                  AnikumoMenuItem(
                    onPressed: _showSkipSettingsSheet,
                    label: '跳过片头片尾',
                  ),
                  if (!compact) _syncPlayMenuItem,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Per-bangumi OP/ED skip editor. Values are the effective ones
  /// (override or global default); saving writes an override through
  /// [SkipSettings].
  void _showSkipSettingsSheet() {
    final bangumiId = videoPageController.bangumiItem.id;
    var lengths = SkipSettings.effectiveFor(bangumiId);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget stepper(
              String label,
              int value,
              ValueChanged<int> onChanged,
            ) {
              return ListTile(
                title: Text(label),
                subtitle: Text(value <= 0 ? '关闭' : '$value 秒'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(AnikumoIcons.remove_circle_outline),
                      onPressed: value <= 0
                          ? null
                          : () => onChanged(value - 5 < 0 ? 0 : value - 5),
                    ),
                    IconButton(
                      icon: const Icon(AnikumoIcons.add_circle_outline),
                      onPressed: () =>
                          onChanged(value + 5 > 180 ? 180 : value + 5),
                    ),
                  ],
                ),
              );
            }

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    title: Text('跳过片头片尾（本番）'),
                    subtitle: Text('只对这部番生效，播放时自动跳过'),
                  ),
                  stepper(
                    '片头',
                    lengths.opSeconds,
                    (value) => setSheetState(() => lengths = (
                          opSeconds: value,
                          edSeconds: lengths.edSeconds,
                        )),
                  ),
                  stepper(
                    '片尾',
                    lengths.edSeconds,
                    (value) => setSheetState(() => lengths = (
                          opSeconds: lengths.opSeconds,
                          edSeconds: value,
                        )),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              await SkipSettings.saveOverride(
                                  bangumiId, lengths);
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                              AnikumoDialog.showToast(
                                  message: '已保存本番跳过设置');
                            },
                            child: const Text('保存'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget get _rightControls {
    return SafeArea(
      top: false,
      bottom: false,
      left: widget.fillsWindow,
      right: widget.fillsWindow,
      child: PlayerPanelHoldMouseRegion(
        acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
        cursor: SystemMouseCursors.basic,
        child: Column(
          children: [
            const Spacer(),
            if (!playerController.panel.lockPanel)
              IconButton(
                icon: const Icon(
                  AnikumoIcons.photo_camera_outlined,
                  color: Colors.white,
                ),
                tooltip: '截图',
                onPressed: widget.handleScreenShot,
              ),
            IconButton(
              icon: Icon(
                playerController.panel.lockPanel
                    ? AnikumoIcons.lock_outline
                    : AnikumoIcons.lock_open,
                color: Colors.white,
              ),
              tooltip: playerController.panel.lockPanel ? '解锁面板' : '锁定面板',
              onPressed: () {
                playerController.panel.lockPanel =
                    !playerController.panel.lockPanel;
              },
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
