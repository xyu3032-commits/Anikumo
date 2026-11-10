import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

import 'package:anikumo/navigation.dart';
import 'package:anikumo/pages/player/pip_settings_sheet.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/services/player/mini_player_session.dart';
import 'package:anikumo/services/player/pip_utils.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// The in-app picture-in-picture floating window (batch 113),
/// reworked in batch 116 (bigger, pinchable, seek controls,
/// geometry notifier) and batch 117 (the "ultimate" pass):
/// adaptive three-tier layout, glass control bar with auto-hide,
/// themes, gesture system with HUD feedback, position/size
/// memory, and a window aspect that follows the video.
///
/// Stability rules kept from earlier batches: the video subtree is
/// built once per session and reused across geometry changes (the
/// Positioned listens to a ChangeNotifier), and the window fully
/// unmounts while the full player page is open so one controller
/// never feeds two video widgets.

/// Default window width for a screen.
double miniPlayerBaseWidth(double screenWidth) =>
    (screenWidth * 0.68).clamp(260.0, 420.0);

/// Progress fraction for the seek bar, guarded against unknown or
/// zero durations.
double miniPlayerSeekFraction(Duration position, Duration duration) {
  if (duration <= Duration.zero) return 0;
  return (position.inMicroseconds / duration.inMicroseconds)
      .clamp(0.0, 1.0);
}

/// Where a seek-bar drag lands, clamped into the media.
Duration miniPlayerSeekTarget(double fraction, Duration duration) {
  if (duration <= Duration.zero) return Duration.zero;
  final f = fraction.clamp(0.0, 1.0);
  return Duration(microseconds: (duration.inMicroseconds * f).round());
}

/// Horizontal snap target when a drag ends: the nearest side edge
/// (8px margin), decided by the window's centre.
double miniPlayerSnapDx({
  required double dx,
  required double width,
  required double screenWidth,
}) {
  final maxDx = screenWidth - width - 8;
  if (maxDx <= 8) return 8;
  return (dx + width / 2) < screenWidth / 2 ? 8.0 : maxDx;
}

/// Layout tier — 0 compact, 1 standard, 2 full.
///
/// Batch 118: the size thresholds dropped (260/340 → 210/320) so
/// the default window lands in the standard tier.
///
/// Batch 119: the control-mode setting is a FLOOR, not a cap —
/// as a cap, choosing "full" changed nothing at the default
/// window size, which read as "the setting does nothing". Simple
/// stays a hard cap (choosing simple means simple); standard
/// guarantees at least the standard set; full always asks for
/// the full set, and the bar sheds its widest extras first when
/// the window is genuinely too small (see _buildControlBar).
int miniPlayerTier({required double width, required int controlMode}) {
  final bySize = width < 210 ? 0 : (width < 320 ? 1 : 2);
  return switch (controlMode) {
    0 => 0,
    2 => 2,
    _ => bySize > 1 ? bySize : 1,
  };
}

/// Batch 121/136: the window drag's direction lock. Moving
/// the window is the drag's only job — batch 136 (user call)
/// removed the horizontal scrub entirely, because sideways
/// window moves kept yanking the playback position; seeking
/// lives on the progress bar. The side (volume/brightness)
/// mode still needs a decisive, committed vertical drag
/// (steeper than 2.6:1 past 26dp) so an ordinary diagonal
/// drag never drops the volume by accident; inside that
/// cone, before commitment, this returns null (keep waiting).
String? miniPlayerDragMode({
  required Offset cumDelta,
  required bool hasSideCandidate,
}) {
  final dx = cumDelta.dx.abs();
  final dy = cumDelta.dy.abs();
  if (hasSideCandidate && dy > dx * 2.6) {
    return dy > 26 ? 'side' : null;
  }
  return 'move';
}

/// Batch 147: where the pan trail begins when a drag commits —
/// back at the touch-down point, so the travel the direction-
/// lock dead zone absorbed is applied to the window instead of
/// being swallowed. Dropping it made every first drag feel
/// like it needed a second try before the window followed.
Offset miniPlayerTrailAtCommit(Offset focalPoint, Offset cumDelta) =>
    focalPoint - cumDelta;

/// Batch 117: the window follows the video's aspect (portrait
/// videos get a portrait window), clamped to sane bounds.
double miniPlayerAspect({required int videoWidth, required int videoHeight}) {
  if (videoWidth <= 0 || videoHeight <= 0) return 16 / 9;
  return (videoWidth / videoHeight).clamp(0.5, 2.2);
}

/// Batch 117: the scale a fresh window starts with, from the
/// default-size setting (0 small, 1 standard, 2 large).
double miniPlayerDefaultScale(int sizeSetting) => switch (sizeSetting) {
      0 => 0.9,
      2 => 1.25,
      _ => 1.0,
    };

/// Batch 117: glass panel colours per theme. [opacity] is the
/// user's control-bar opacity multiplier.
class MiniPlayerThemeData {
  const MiniPlayerThemeData({
    required this.panelTop,
    required this.panelBottom,
    required this.foreground,
    required this.accent,
    required this.isLight,
  });

  final Color panelTop;
  final Color panelBottom;
  final Color foreground;
  final Color accent;
  final bool isLight;
}

MiniPlayerThemeData miniPlayerTheme(int theme, double opacity) {
  final o = opacity.clamp(0.4, 1.0);
  // Batch 121: the bar reads as a clean bottom scrim, not a
  // translucent box — the gradient now fades in from (near)
  // transparent at the top and lands deep and neutral at the
  // bottom, so controls sit on a calm, even ground instead of a
  // muddy see-through panel.
  return switch (theme) {
    1 => MiniPlayerThemeData(
        // Moon white: a light glass bar, dark ink on top.
        panelTop: Color.fromRGBO(250, 250, 252, 0.40 * o),
        panelBottom: Color.fromRGBO(238, 240, 246, 0.95 * o),
        foreground: const Color(0xFF23242B),
        accent: const Color(0xFF5B6ABF),
        isLight: true,
      ),
    2 => MiniPlayerThemeData(
        // Fog blue.
        panelTop: Color.fromRGBO(30, 44, 68, 0.12 * o),
        panelBottom: Color.fromRGBO(11, 17, 29, 0.88 * o),
        foreground: Colors.white,
        accent: const Color(0xFF9CC4FF),
        isLight: false,
      ),
    3 => MiniPlayerThemeData(
        // Light purple.
        panelTop: Color.fromRGBO(46, 36, 74, 0.12 * o),
        panelBottom: Color.fromRGBO(17, 12, 32, 0.88 * o),
        foreground: Colors.white,
        accent: const Color(0xFFCDB4FF),
        isLight: false,
      ),
    _ => MiniPlayerThemeData(
        // Dark glass (default).
        panelTop: Color.fromRGBO(0, 0, 0, 0.0),
        panelBottom: Color.fromRGBO(0, 0, 0, 0.82 * o),
        foreground: Colors.white,
        accent: Colors.white,
        isLight: false,
      ),
  };
}

/// Batch 121: opens the player page from the overlay.
///
/// The overlay lives in MaterialApp's builder, ABOVE the Router:
/// `context.pushNamed` there finds no RouterOutlet and no Router
/// ancestor and throws (silently, inside an unawaited future) —
/// this is why tapping "expand" never left the mini window.
/// Navigating through the root navigator's own context (the
/// deep-link handler's proven pattern) reaches the router.
void pushPlayerPageFromOverlay(VideoPlaybackArgs args) {
  final navContext = rootNavigatorKey.currentState?.context;
  if (navContext == null) return;
  unawaited(navContext.pushNamed('/video/', arguments: args));
}

/// Batch 120/121: whether a finished drag docks the window into
/// the edge circle. The decision uses the PUSH-OUT amount: how
/// far the drag tried to carry the window past its on-screen
/// clamp. Parking against an edge produces almost no push-out
/// (the finger stops with the window), pushing the window out
/// produces a lot — regardless of where on the window the user
/// grabbed it. (Batch 120 used the window centre's position,
/// which docked when merely parking a wide window and failed
/// when the grab point limited finger travel.)
bool miniPlayerShouldDock({
  required double overshootDx,
  double threshold = 56,
}) {
  return overshootDx.abs() > threshold;
}

/// Window geometry (position + user scale). Dragging and pinching
/// write here; only the Positioned listens, so the video subtree
/// is not rebuilt (batch 116's stutter fix).
class _MiniGeometry extends ChangeNotifier {
  Offset? offset;
  double? scale;

  /// Batch 120: docked into the small edge circle. Playback
  /// continues; the video surface unmounts until restored.
  bool docked = false;
  double dockFractionY = 0.5;

  void update(Offset nextOffset, double nextScale) {
    offset = nextOffset;
    scale = nextScale;
    notifyListeners();
  }

  void setDocked(bool value, {double? fractionY}) {
    docked = value;
    if (fractionY != null) {
      dockFractionY = fractionY.clamp(0.08, 0.92);
    }
    notifyListeners();
  }

  void updateDockY(double fractionY) {
    dockFractionY = fractionY.clamp(0.08, 0.92);
    notifyListeners();
  }
}

class MiniPlayerHost extends StatefulWidget {
  const MiniPlayerHost({super.key});

  @override
  State<MiniPlayerHost> createState() => _MiniPlayerHostState();
}

class _MiniPlayerHostState extends State<MiniPlayerHost>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _MiniGeometry _geometry = _MiniGeometry();

  /// Set once the appear fade has been kicked off after a mount.
  bool _appeared = false;

  /// One auto-system-PiP handover per app leave (batch 116).
  bool _leaveHandled = false;

  /// Batch 121: drives the window ⇄ dock-circle morph. 0 is the
  /// full window, 1 is the circle; docking plays it forward,
  /// restoring reverses it.
  late final AnimationController _dockAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  void _onDockChanged() {
    if (_geometry.docked) {
      _dockAnim.forward();
    } else {
      _dockAnim.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _geometry.addListener(_onDockChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _geometry.removeListener(_onDockChanged);
    _dockAnim.dispose();
    _geometry.dispose();
    super.dispose();
  }

  // --- Leave-the-app handover to system PiP (batch 116) ----------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _leaveHandled = false;
      return;
    }
    if (state != AppLifecycleState.inactive || _leaveHandled) return;
    _leaveHandled = true;
    _maybeHandOverToSystemPip();
  }

  void _maybeHandOverToSystemPip() {
    if (!Platform.isAndroid) return;
    if (!GStorage.getSetting(SettingsKeys.pipAutoSystemOnLeave)) return;
    final session = MiniPlayerSession.instance;
    final args = session.args;
    final playerController = session.playerController;
    if (!session.hasSession || !session.visible || args == null) return;
    if (playerController == null) return;
    pushPlayerPageFromOverlay(args);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PipUtils.enterAndroidPIPWindow(
        width: playerController.debug.playerWidth,
        height: playerController.debug.playerHeight,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MiniPlayerSession.instance,
      builder: (context, _) {
        final session = MiniPlayerSession.instance;
        final playerController = session.playerController;
        if (!session.hasSession ||
            session.playerPageOpen ||
            playerController == null) {
          _appeared = false;
          return const SizedBox.shrink();
        }
        final videoController = playerController.playback.videoController;
        if (videoController == null) {
          return const SizedBox.shrink();
        }
        if (!_appeared) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _appeared = true);
          });
        }
        final visible = session.visible;
        final animations = GStorage.getSetting(SettingsKeys.pipAnimations) &&
            !MediaQuery.disableAnimationsOf(context);
        final fadeDuration = animations
            ? const Duration(milliseconds: 180)
            : Duration.zero;
        return LayoutBuilder(
          builder: (context, constraints) {
            final screen =
                Size(constraints.maxWidth, constraints.maxHeight);
            final baseWidth = miniPlayerBaseWidth(screen.width);
            return Stack(
              children: [
                Observer(builder: (context) {
                  // Reading the video size here re-runs only this
                  // positioning when the aspect changes.
                  final aspect = miniPlayerAspect(
                    videoWidth: playerController.debug.playerWidth,
                    videoHeight: playerController.debug.playerHeight,
                  );
                  return ListenableBuilder(
                    listenable: Listenable.merge([_geometry, _dockAnim]),
                    child: _MiniPlayerWindow(
                      key: ValueKey(session.args?.bangumiItem.id),
                      session: session,
                      geometry: _geometry,
                    ),
                    builder: (context, child) {
                      // Batch 121: docked / morphing rendering is
                      // decided below, once the window rect is
                      // known (the morph lerps between the rects).
                      final savedScale =
                          GStorage.getSetting<double>(SettingsKeys.pipScale);
                      final double scale = _geometry.scale ??
                          (savedScale > 0
                              ? savedScale
                              : miniPlayerDefaultScale(GStorage.getSetting(
                                  SettingsKeys.pipDefaultSize)));
                      final width = (baseWidth * scale)
                          .clamp(0.0, screen.width - 16)
                          .toDouble();
                      final height = width / aspect;
                      final mediaPadding = MediaQuery.of(context).padding;
                      final topPadding = mediaPadding.top;
                      // Keep the window clear of the system
                      // navigation area at the bottom (batch 118).
                      final bottomLimit = screen.height -
                          height -
                          (mediaPadding.bottom + 4 > 8
                              ? mediaPadding.bottom + 4
                              : 8.0);
                      final savedX =
                          GStorage.getSetting(SettingsKeys.pipOffsetX);
                      final savedY =
                          GStorage.getSetting(SettingsKeys.pipOffsetY);
                      final offset = _geometry.offset ??
                          (savedX >= 0 && savedY >= 0
                              ? Offset(savedX * screen.width,
                                  savedY * screen.height)
                              : Offset(
                                  screen.width - width - 12,
                                  screen.height - height - 100,
                                ));
                      final dx = offset.dx
                          .clamp(8.0, screen.width - width - 8)
                          .toDouble();
                      final dyMax =
                          bottomLimit > topPadding + 8
                              ? bottomLimit
                              : topPadding + 8;
                      final dy = offset.dy
                          .clamp(topPadding + 8, dyMax)
                          .toDouble();
                      // Batch 121: docked state and the
                      // window ⇄ circle morph. The morph lerps
                      // the window rect into the bubble rect
                      // (easeInOut), fading the video out and
                      // the restore icon in; at rest docked, the
                      // plain bubble renders and the video
                      // surface stays unmounted.
                      if (_dockAnim.value > 0) {
                        const bubbleSize = 46.0;
                        final bubbleTop = (_geometry.dockFractionY *
                                    screen.height -
                                bubbleSize / 2)
                            .clamp(topPadding + 4,
                                screen.height - bubbleSize - 12)
                            .toDouble();
                        if (_geometry.docked && _dockAnim.value >= 1) {
                          return Positioned(
                            right: 10,
                            top: bubbleTop,
                            width: bubbleSize,
                            height: bubbleSize,
                            child: IgnorePointer(
                              ignoring: !visible,
                              child: AnimatedOpacity(
                                opacity: visible && _appeared ? 1 : 0,
                                duration: fadeDuration,
                                child: _DockBubble(
                                  geometry: _geometry,
                                  session: session,
                                ),
                              ),
                            ),
                          );
                        }
                        final t =
                            Curves.easeInOut.transform(_dockAnim.value);
                        final rect = Rect.lerp(
                          Rect.fromLTWH(dx, dy, width, height),
                          Rect.fromLTWH(screen.width - 10 - bubbleSize,
                              bubbleTop, bubbleSize, bubbleSize),
                          t,
                        )!;
                        return Positioned(
                          left: rect.left,
                          top: rect.top,
                          width: rect.width,
                          height: rect.height,
                          child: IgnorePointer(
                            ignoring: true,
                            child: AnimatedOpacity(
                              opacity: visible && _appeared ? 1 : 0,
                              duration: fadeDuration,
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(14 + 9 * t),
                                child: ColoredBox(
                                  color: Colors.black,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Opacity(
                                          opacity:
                                              (1 - t * 1.5).clamp(0.0, 1.0),
                                          child: child,
                                        ),
                                      ),
                                      Center(
                                        child: Opacity(
                                          opacity: ((t - 0.45) / 0.55)
                                              .clamp(0.0, 1.0),
                                          // Batch 126: the morph
                                          // lands on the cat face,
                                          // not a generic icon.
                                          child: const _PipCatFace(size: 30),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return Positioned(
                        left: dx,
                        top: dy,
                        width: width,
                        height: height,
                        child: IgnorePointer(
                          ignoring: !visible,
                          child: AnimatedOpacity(
                            opacity: visible && _appeared ? 1 : 0,
                            duration: fadeDuration,
                            curve: Curves.easeOut,
                            child: AnimatedScale(
                              // Batch 121: a proper pop-in —
                              // smaller start, gentle overshoot.
                              scale: visible && _appeared ? 1 : 0.82,
                              duration: animations
                                  ? const Duration(milliseconds: 280)
                                  : Duration.zero,
                              curve: Curves.easeOutBack,
                              child: child,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}

/// Batch 126: decodes the user's uploaded dock-face image
/// paths (a JSON list in the settings).
List<String> decodePipCatImages(String raw) {
  if (raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return [
        for (final entry in decoded)
          if (entry is String && entry.isNotEmpty) entry,
      ];
    }
  } catch (_) {
    // A corrupt payload falls back to the built-in face.
  }
  return const [];
}

/// Batch 126: the docked bubble's face frames — the user's
/// uploaded images when the custom style is on and at least
/// one image exists, otherwise the app's own logo (the
/// cat-ear girl, the same image as the app icon).
List<String> pipCatFrames() {
  if (GStorage.getSetting(SettingsKeys.pipCatStyle) == 1) {
    final custom =
        decodePipCatImages(GStorage.getSetting(SettingsKeys.pipCatImages));
    if (custom.isNotEmpty) return custom;
  }
  return const ['assets/images/logo/logo_rounded.png'];
}

/// One dock-face frame (asset or file), used by the morph
/// animation's end state.
class _PipCatFace extends StatelessWidget {
  const _PipCatFace({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final frame = pipCatFrames().first;
    final fallback = Image.asset(
      'assets/images/logo/logo_rounded.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return ClipOval(
      child: frame.startsWith('assets/')
          ? fallback
          : Image.file(
              File(frame),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
    );
  }
}

/// Batch 120/126: the docked edge bubble. Tap restores the
/// window; a vertical drag slides it along the edge. Playback
/// keeps running while docked (audio only — the surface is
/// unmounted). Batch 126: the bubble wears the cat face — the
/// app logo by default, or the user's uploaded images (a
/// flipbook when several) — with a gentle breathing/bobbing
/// motion so it feels alive.
class _DockBubble extends StatefulWidget {
  const _DockBubble({required this.geometry, required this.session});

  final _MiniGeometry geometry;
  final MiniPlayerSession session;

  @override
  State<_DockBubble> createState() => _DockBubbleState();
}

class _DockBubbleState extends State<_DockBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  Timer? _flipTimer;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    final frames = pipCatFrames();
    if (frames.length > 1) {
      _flipTimer = Timer.periodic(const Duration(milliseconds: 380), (_) {
        if (mounted) setState(() => _frame = (_frame + 1) % frames.length);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Breathing runs only when animations are welcome (the
    // PiP animation setting AND the OS switch).
    final animations = GStorage.getSetting(SettingsKeys.pipAnimations) &&
        !MediaQuery.disableAnimationsOf(context);
    if (animations) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
      _breath.value = 0.5;
    }
  }

  @override
  void dispose() {
    _flipTimer?.cancel();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = pipCatFrames();
    final frame = frames[_frame % frames.length];
    return GestureDetector(
      onTap: () => widget.geometry.setDocked(false),
      onPanUpdate: (details) {
        final height = MediaQuery.sizeOf(context).height;
        widget.geometry.updateDockY(
            widget.geometry.dockFractionY + details.delta.dy / height);
      },
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) {
          final t = _breath.value; // 0..1..0 breathing phase
          return Transform.translate(
            offset: Offset(0, -2.2 * t),
            child: Transform.rotate(
              angle: -0.05 + 0.1 * t,
              child: Transform.scale(
                scale: 0.96 + 0.07 * t,
                child: child,
              ),
            ),
          );
        },
        child: Material(
          elevation: 6,
          color: Colors.black.withValues(alpha: 0.35),
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white38),
          ),
          child: ClipOval(
            child: frame.startsWith('assets/')
                ? Image.asset(
                    frame,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                  )
                : Image.file(
                    File(frame),
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        Image.asset(
                      'assets/images/logo/logo_rounded.png',
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerWindow extends StatefulWidget {
  const _MiniPlayerWindow({
    super.key,
    required this.session,
    required this.geometry,
  });

  final MiniPlayerSession session;
  final _MiniGeometry geometry;

  @override
  State<_MiniPlayerWindow> createState() => _MiniPlayerWindowState();
}

class _MiniPlayerWindowState extends State<_MiniPlayerWindow>
    with SingleTickerProviderStateMixin {
  // Controls visibility + auto-hide. Batch 118: the window opens
  // in the low-interference state (controls hidden, hairline
  // progress only); a tap brings the controls up, and a paused
  // video always shows them.
  bool _controlsVisible = false;
  Timer? _hideTimer;
  bool? _lastPlaying;

  /// Last auto-hide setting seen, so a change re-times a pending
  /// hide immediately (batch 119).
  int? _lastAutoHideSeconds;

  /// Effective animation switch: the user's setting AND the OS
  /// animator setting (batch 118). Refreshed on every build.
  bool _effectiveAnimations = true;

  // HUD feedback chip.
  IconData? _hudIcon;
  String? _hudText;
  double? _hudFraction;
  Timer? _hudTimer;

  // Seek-bar drag.
  double? _dragFraction;

  /// Batch 139: a horizontal drag is live on the seek bar
  /// (the tap recognizer's cancel must not clear its preview).
  bool _seekBarDragActive = false;

  // Double-tap side seek accumulation.
  int _seekAccum = 0;
  Timer? _seekAccumTimer;

  // Manual tap discrimination (single vs double tap).
  Timer? _tapTimer;
  Offset? _pendingTapPos;

  // Scale gesture state. Batch 118: one gesture, four outcomes,
  // decided by a direction lock once the drag leaves a small dead
  // zone — mostly horizontal scrubs the playback, anything else
  // moves the window, two fingers pinch, and a mostly vertical
  // drag starting in a side third adjusts brightness/volume (when
  // that option is on). The lock keeps the modes from fighting.
  double _gestureStartScale = 1;
  Offset? _focalTrail;
  String? _gestureMode; // 'move' | 'zoom' | 'side'
  Offset _cumDelta = Offset.zero;
  String? _sideKind; // 'brightness' | 'volume'
  double _sideStartValue = 0;

  AnimationController? _snapController;

  MiniPlayerSession get session => widget.session;

  bool get _animations => GStorage.getSetting(SettingsKeys.pipAnimations);

  void _haptic() {
    if (GStorage.getSetting(SettingsKeys.pipHaptics)) {
      HapticFeedback.selectionClick();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _seekAccumTimer?.cancel();
    _tapTimer?.cancel();
    _snapController?.dispose();
    super.dispose();
  }

  // --- Controls auto-hide -----------------------------------------

  void _pokeControls() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    final seconds = GStorage.getSetting(SettingsKeys.pipAutoHideSeconds);
    final playerController = session.playerController;
    if (seconds <= 0 || playerController == null) return;
    if (!playerController.playback.playing) return;
    _hideTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _onPlayingChanged(bool playing) {
    if (_lastPlaying == playing) return;
    _lastPlaying = playing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!playing) {
        _hideTimer?.cancel();
        if (!_controlsVisible) setState(() => _controlsVisible = true);
      } else {
        _restartHideTimer();
      }
    });
  }

  // --- HUD ----------------------------------------------------------

  void _showHud({IconData? icon, String? text, double? fraction}) {
    setState(() {
      _hudIcon = icon;
      _hudText = text;
      _hudFraction = fraction;
    });
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) {
        setState(() {
          _hudIcon = null;
          _hudText = null;
          _hudFraction = null;
        });
      }
    });
  }

  // --- Taps -----------------------------------------------------------

  void _handleTapUp(TapUpDetails details) {
    // Batch 119: no poke here. Poking showed the controls at
    // once, then the pending single-tap toggle hid them again a
    // beat later — the "wake up and it vanishes in a second" bug.
    // The single-tap decision below owns visibility outright.
    if (_pendingTapPos != null) {
      // Second tap inside the window: a double tap.
      _tapTimer?.cancel();
      final pos = _pendingTapPos!;
      _pendingTapPos = null;
      _handleDoubleTap(pos);
      return;
    }
    _pendingTapPos = details.localPosition;
    _tapTimer = Timer(const Duration(milliseconds: 280), () {
      _pendingTapPos = null;
      if (!mounted) return;
      setState(() => _controlsVisible = !_controlsVisible);
      if (_controlsVisible) {
        _restartHideTimer();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  void _handleDoubleTap(Offset localPos) {
    final playerController = session.playerController!;
    final playback = playerController.playback;
    final width = context.size?.width ?? 1;
    final action = GStorage.getSetting(SettingsKeys.pipDoubleTapAction);
    _haptic();
    if (action == 1) {
      final zone = localPos.dx / width;
      if (zone < 0.38) {
        _sideSeek(-1);
        return;
      }
      if (zone > 0.62) {
        _sideSeek(1);
        return;
      }
    }
    unawaited(playerController.playOrPause());
    _showHud(
      icon: playback.playing ? AnikumoIcons.pause_rounded : AnikumoIcons.play_arrow_rounded,
    );
    _pokeControls();
  }

  void _sideSeek(int direction) {
    final playerController = session.playerController!;
    final step = GStorage.getSetting(SettingsKeys.pipSeekSeconds);
    if (_seekAccum != 0 && (_seekAccum > 0) != (direction > 0)) {
      _seekAccum = 0; // direction flipped: restart the count
    }
    _seekAccum += direction * step;
    unawaited(
        playerController.seekBy(Duration(seconds: direction * step)));
    _showHud(
      icon: direction > 0 ? AnikumoIcons.fast_forward_rounded : AnikumoIcons.fast_rewind_rounded,
      text: '${_seekAccum > 0 ? '+' : ''}$_seekAccum 秒',
    );
    _seekAccumTimer?.cancel();
    _seekAccumTimer = Timer(const Duration(milliseconds: 900), () {
      _seekAccum = 0;
    });
    _pokeControls();
  }

  // --- Scale gestures: move / pinch / side adjust ---------------------

  Future<void> _onScaleStart(ScaleStartDetails details) async {
    _snapController?.stop();
    // Batch 147 (user call): moving or pinch-zooming the
    // window must not summon the control bar — the progress
    // bar appears on a tap, or by dragging the seek bar
    // itself, not because the window moved. If the bar is
    // already up, only re-time its auto-hide so it cannot
    // vanish mid-drag.
    if (_controlsVisible) _restartHideTimer();
    // A pending single-tap decision must not outlive a drag:
    // cancel it, or its timer could toggle the bar mid-gesture
    // and eat the drag's first motion.
    _tapTimer?.cancel();
    _pendingTapPos = null;
    final geom = widget.geometry;
    _gestureStartScale = geom.scale ??
        (GStorage.getSetting(SettingsKeys.pipScale) > 0
            ? GStorage.getSetting(SettingsKeys.pipScale)
            : miniPlayerDefaultScale(
                GStorage.getSetting(SettingsKeys.pipDefaultSize)));
    // Batch 147: the pan trail starts at the touch-down point
    // (rebased once more when the direction lock commits, so
    // the dead zone's travel counts too — see _onScaleUpdate).
    _focalTrail = details.focalPoint;
    _gestureMode = null;
    _cumDelta = Offset.zero;
    _sideKind = null;
    if (GStorage.getSetting(SettingsKeys.pipSideGestures)) {
      // Candidate only: the mode machine promotes it to a real
      // side adjustment if the drag turns mostly vertical.
      final screenWidth = MediaQuery.sizeOf(context).width;
      final fraction = details.focalPoint.dx / screenWidth;
      if (fraction < 0.33) {
        _sideKind = 'brightness';
        _sideStartValue =
            await ScreenBrightnessPlatform.instance.application;
      } else if (fraction > 0.67) {
        _sideKind = 'volume';
        _sideStartValue =
            session.playerController?.playback.mediaPlayer?.state.volume ??
                0;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final geom = widget.geometry;
    if (geom.offset == null) {
      // First touch before any position exists: adopt the default
      // the host displays (bottom-right / remembered), so the
      // gesture has a base to move from.
      final size = MediaQuery.sizeOf(context);
      final width = miniPlayerBaseWidth(size.width) * _gestureStartScale;
      final aspect = miniPlayerAspect(
        videoWidth: session.playerController?.debug.playerWidth ?? 0,
        videoHeight: session.playerController?.debug.playerHeight ?? 0,
      );
      final savedX = GStorage.getSetting(SettingsKeys.pipOffsetX);
      final savedY = GStorage.getSetting(SettingsKeys.pipOffsetY);
      geom.update(
        savedX >= 0 && savedY >= 0
            ? Offset(savedX * size.width, savedY * size.height)
            : Offset(size.width - width - 12,
                size.height - width / aspect - 100),
        _gestureStartScale,
      );
    }
    _cumDelta += details.focalPointDelta;
    // Direction lock: decide the gesture's job once it leaves the
    // dead zone, then keep that job until the finger lifts.
    if (_gestureMode == null) {
      if (details.pointerCount >= 2) {
        _gestureMode = 'zoom';
      } else if (_cumDelta.distance > 14) {
        final mode = miniPlayerDragMode(
          cumDelta: _cumDelta,
          hasSideCandidate: _sideKind != null,
        );
        if (mode == null) return; // In a cone, not yet committed.
        _gestureMode = mode;
      } else {
        return;
      }
      // Batch 147: rebase the pan trail to the touch-down
      // point at commitment, so the first applied movement
      // includes everything the dead zone absorbed — the drag
      // follows the finger from the very start instead of
      // feeling like it needs a second attempt.
      _focalTrail = miniPlayerTrailAtCommit(details.focalPoint, _cumDelta);
    }
    switch (_gestureMode) {
      case 'side':
        _applySideAdjust();
        return;
      default:
        final scale = (_gestureStartScale * details.scale).clamp(0.7, 2.0);
        _focalTrail ??= details.focalPoint;
        final delta = details.focalPoint - _focalTrail!;
        _focalTrail = details.focalPoint;
        geom.update(geom.offset! + delta, scale);
    }
  }

  void _applySideAdjust() {
    // 240 logical pixels of drag span the full 0–100% range.
    final deltaFraction = -_cumDelta.dy / 240;
    if (_sideKind == 'brightness') {
      final value = (_sideStartValue + deltaFraction).clamp(0.05, 1.0);
      unawaited(ScreenBrightnessPlatform.instance
          .setApplicationScreenBrightness(value));
      _showHud(
        icon: AnikumoIcons.brightness_6_rounded,
        text: '${(value * 100).round()}%',
        fraction: value,
      );
    } else if (_sideKind == 'volume') {
      final player = session.playerController?.playback.mediaPlayer;
      if (player == null) return;
      final value = (_sideStartValue + deltaFraction * 100).clamp(0.0, 100.0);
      unawaited(player.setVolume(value));
      _showHud(
        icon: value <= 0
            ? AnikumoIcons.volume_off_rounded
            : AnikumoIcons.volume_up_rounded,
        text: '${value.round()}%',
        fraction: value / 100,
      );
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _focalTrail = null;
    final finishedMode = _gestureMode;
    _gestureMode = null;
    _sideKind = null;
    if (finishedMode == 'side') {
      // Batch 147: a side adjustment ends like any other
      // window drag — the HUD already reported the value, and
      // the control bar stays exactly as it was.
      if (_controlsVisible) _restartHideTimer();
      return;
    }
    if (_controlsVisible) _restartHideTimer();
    _haptic();
    final geom = widget.geometry;
    final offset = geom.offset;
    if (offset == null) return;
    final size = MediaQuery.sizeOf(context);
    final width = miniPlayerBaseWidth(size.width) * (geom.scale ?? 1);
    // Batch 120/121: pushed out past an edge — dock into the
    // circle instead of snapping back. The push-out amount is
    // the attempted offset minus the on-screen clamp the host
    // applies for display.
    final displayedDx =
        offset.dx.clamp(8.0, size.width - width - 8).toDouble();
    if (miniPlayerShouldDock(overshootDx: offset.dx - displayedDx)) {
      final aspect = miniPlayerAspect(
        videoWidth: session.playerController?.debug.playerWidth ?? 0,
        videoHeight: session.playerController?.debug.playerHeight ?? 0,
      );
      geom.setDocked(
        true,
        fractionY: (offset.dy + (width / aspect) / 2) / size.height,
      );
      return;
    }
    final targetDx = miniPlayerSnapDx(
      dx: offset.dx,
      width: width,
      screenWidth: size.width,
    );
    void persist(Offset o, double s) {
      unawaited(GStorage.putSetting(
          SettingsKeys.pipOffsetX, o.dx / size.width));
      unawaited(GStorage.putSetting(
          SettingsKeys.pipOffsetY, o.dy / size.height));
      unawaited(GStorage.putSetting(SettingsKeys.pipScale, s));
    }

    if ((targetDx - offset.dx).abs() < 1 || !_effectiveAnimations) {
      if ((targetDx - offset.dx).abs() >= 1) {
        geom.update(Offset(targetDx, offset.dy), geom.scale ?? 1);
      }
      persist(geom.offset!, geom.scale ?? 1);
      return;
    }
    _snapController?.dispose();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    final animation = Tween<Offset>(
      begin: offset,
      end: Offset(targetDx, offset.dy),
    ).animate(CurvedAnimation(
      parent: _snapController!,
      curve: Curves.easeOutCubic,
    ));
    animation.addListener(() {
      geom.update(animation.value, geom.scale ?? 1);
    });
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        persist(geom.offset!, geom.scale ?? 1);
      }
    });
    unawaited(_snapController!.forward());
  }

  /// The numbered replay/forward icons only exist for 5/10/30;
  /// anything else falls back to the plain symbols.
  IconData _seekIcon(int seconds, {required bool forward}) {
    return switch ((seconds, forward)) {
      (5, false) => AnikumoIcons.replay_5_rounded,
      (10, false) => AnikumoIcons.replay_10_rounded,
      (30, false) => AnikumoIcons.replay_30_rounded,
      (5, true) => AnikumoIcons.forward_5_rounded,
      (10, true) => AnikumoIcons.forward_10_rounded,
      (30, true) => AnikumoIcons.forward_30_rounded,
      (_, false) => AnikumoIcons.replay_rounded,
      (_, true) => AnikumoIcons.fast_forward_rounded,
    };
  }

  // --- Actions ---------------------------------------------------------

  /// The danmaku option for the small window: the same settings
  /// mapping the full player uses, with the font scaled toward
  /// the window's height so comments stay proportional.
  DanmakuOption _miniDanmakuOption(double windowHeight) {
    final fontScale = (windowHeight / 320).clamp(0.5, 1.0);
    return DanmakuOption(
      hideTop: !GStorage.getSetting(SettingsKeys.danmakuTop),
      hideScroll: !GStorage.getSetting(SettingsKeys.danmakuScroll),
      hideBottom: !GStorage.getSetting(SettingsKeys.danmakuBottom),
      area: GStorage.getSetting(SettingsKeys.danmakuArea),
      opacity: GStorage.getSetting(SettingsKeys.danmakuOpacity),
      fontSize: GStorage.getSetting(
            SettingsKeys.danmakuFontSize,
            context: SettingContext(
              compactLayout:
                  MediaQuery.sizeOf(context).shortestSide < 600,
            ),
          ) *
          fontScale,
      duration: GStorage.getSetting(SettingsKeys.danmakuDuration),
      lineHeight: GStorage.getSetting(SettingsKeys.danmakuLineHeight),
      strokeWidth:
          (GStorage.getSetting(SettingsKeys.danmakuBorder) &&
                  !SmoothMode.enabled)
              ? GStorage.getSetting(SettingsKeys.danmakuBorderSize)
              : 0.0,
      fontWeight: GStorage.getSetting(SettingsKeys.danmakuFontWeight),
      massiveMode: GStorage.getSetting(SettingsKeys.danmakuMassive),
      fontFamily: GStorage.getSetting(SettingsKeys.useSystemFont)
          ? null
          : customAppFontFamily,
    );
  }

  void _toggleDanmaku() {
    final danmaku = session.playerController!.danmaku;
    _haptic();
    _pokeControls();
    if (danmaku.danmakuOn) {
      danmaku.canvasController.clear();
      danmaku.setDanmakuEnabled(false);
      unawaited(
          GStorage.putSetting(SettingsKeys.danmakuEnabledByDefault, false));
    } else {
      danmaku.setDanmakuEnabled(true);
      unawaited(
          GStorage.putSetting(SettingsKeys.danmakuEnabledByDefault, true));
    }
  }

  /// Dock into the edge circle at the window's current height.
  void _dock() {
    var fractionY = widget.geometry.dockFractionY;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final pos = box.localToGlobal(Offset.zero);
      final screenH = MediaQuery.sizeOf(context).height;
      fractionY = (pos.dy + box.size.height / 2) / screenH;
    }
    widget.geometry.setDocked(true, fractionY: fractionY);
  }

  void _openPlayer() {
    final args = session.args;
    if (args != null) {
      pushPlayerPageFromOverlay(args);
    }
  }

  Future<void> _stepEpisode(int delta) async {
    final videoPageController = session.videoPageController;
    final playerController = session.playerController;
    if (videoPageController == null || playerController == null) return;
    final selected = videoPageController.selectedEpisode;
    final roads = videoPageController.roadList;
    if (selected.road < 0 || selected.road >= roads.length) return;
    final count = roads[selected.road].data.length;
    final next = selected.episode + delta;
    if (next < 1 || next > count) return;
    _haptic();
    _pokeControls();
    await videoPageController.changeEpisode(
      next,
      currentRoad: selected.road,
      playerController: playerController,
    );
  }

  // --- Build -----------------------------------------------------------

  String _fmt(Duration d) {
    final total = d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final playerController = session.playerController!;
    final playback = playerController.playback;
    final videoPageController = session.videoPageController;
    final theme = miniPlayerTheme(
      GStorage.getSetting(SettingsKeys.pipTheme),
      GStorage.getSetting(SettingsKeys.pipControlsOpacity),
    );
    _effectiveAnimations =
        _animations && !MediaQuery.disableAnimationsOf(context);
    final autoHide = GStorage.getSetting(SettingsKeys.pipAutoHideSeconds);
    if (_lastAutoHideSeconds != autoHide) {
      _lastAutoHideSeconds = autoHide;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controlsVisible) _restartHideTimer();
      });
    }
    return RepaintBoundary(
      child: Material(
        color: Colors.black,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.16),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, constraints) {
          final tier = miniPlayerTier(
            width: constraints.maxWidth,
            controlMode: GStorage.getSetting(SettingsKeys.pipControlMode),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _handleTapUp,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                onLongPress: () => showPipSettingsSheet(context),
                child: Video(
                  controller: playback.videoController!,
                  controls: NoVideoControls,
                  pauseUponEnteringBackgroundMode: false,
                  fit: BoxFit.contain,
                ),
              ),
              // Batch 120: the danmaku layer. The mini window
              // hosts its own DanmakuScreen on the shared
              // controller pair (the full page rebinds its own
              // when it returns, exactly like page transitions
              // already do), so comments keep flowing here.
              Observer(builder: (context) {
                if (!playerController.danmaku.danmakuOn) {
                  return const SizedBox.shrink();
                }
                return Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: DanmakuScreen(
                        createdController: (DanmakuController e) {
                          playerController.danmaku.canvasController = e;
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) {
                            playerController.updateDanmakuSpeed();
                          });
                        },
                        option:
                            _miniDanmakuOption(constraints.maxHeight),
                      ),
                    ),
                  ),
                );
              }),
              if (_hudIcon != null || _hudText != null) _buildHud(theme),
              // Top row: open player (left), close (right).
              // Batch 120: always visible and tappable, NOT
              // gated by the control bar — expanding back into
              // the player page is the primary action and users
              // read its absence as "cannot enlarge".
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor:
                            Colors.black.withValues(alpha: 0.38),
                        side: const BorderSide(color: Colors.white24),
                        fixedSize: const Size(30, 30),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(AnikumoIcons.open_in_full_rounded),
                      onPressed: _openPlayer,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor:
                            Colors.black.withValues(alpha: 0.38),
                        side: const BorderSide(color: Colors.white24),
                        fixedSize: const Size(30, 30),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(AnikumoIcons.close_rounded),
                      onPressed: () {
                        unawaited(session.close());
                      },
                    ),
                  ],
                ),
              ),
              // Hairline progress while the bar is hidden.
              if (!_controlsVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Observer(builder: (context) {
                    final fraction = miniPlayerSeekFraction(
                        playback.currentPosition, playback.duration);
                    return Align(
                      alignment: Alignment.bottomLeft,
                      child: FractionallySizedBox(
                        widthFactor: fraction,
                        child: Container(height: 2, color: theme.accent),
                      ),
                    );
                  }),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: _effectiveAnimations
                      ? const Duration(milliseconds: 160)
                      : Duration.zero,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: _buildControlBar(context, tier, theme,
                        videoPageController?.title ?? '', constraints.maxWidth),
                  ),
                ),
              ),
              Observer(builder: (context) {
                _onPlayingChanged(playback.playing);
                return const SizedBox.shrink();
              }),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildHud(MiniPlayerThemeData theme) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.panelBottom,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.foreground.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hudIcon != null)
              Icon(_hudIcon, color: theme.foreground, size: 20),
            if (_hudText != null) ...[
              if (_hudIcon != null) const SizedBox(width: 6),
              Text(
                _hudText!,
                style: TextStyle(color: theme.foreground, fontSize: 12),
              ),
            ],
            if (_hudFraction != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _hudFraction,
                    minHeight: 3,
                    backgroundColor:
                        theme.foreground.withValues(alpha: 0.25),
                    valueColor: AlwaysStoppedAnimation(theme.accent),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlBar(
    BuildContext context,
    int tier,
    MiniPlayerThemeData theme,
    String title,
    double windowWidth,
  ) {
    final playerController = session.playerController!;
    final playback = playerController.playback;
    final seekSeconds = GStorage.getSetting(SettingsKeys.pipSeekSeconds);
    // Batch 119: in the full tier on a genuinely small window,
    // shed the widest extras first (speed below 240, episode
    // stepping below 200) instead of overflowing the row.
    final showStep = tier == 2 && windowWidth >= 200;
    final showSpeed = tier == 2 && windowWidth >= 240;

    // Batch 141: visual redesign. The old bar was a tall,
    // foggy wash with one long strip of equal-weight icons —
    // the viewer's screenshot read as cluttered and cheap.
    // Now the scrim is short, and the transport row has a
    // clear centre: a filled play disc (the accent) flanked
    // by the two seek buttons, with utilities grouped at the
    // edges (episode stepping / danmaku left, speed / next /
    // dock right).
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.panelTop, theme.panelBottom],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_dragFraction != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Observer(builder: (context) {
                final target =
                    miniPlayerSeekTarget(_dragFraction!, playback.duration);
                return Text(
                  '${_fmt(target)} / ${_fmt(playback.duration)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }),
            ),
          // The complete timeline — current time, the seek
          // bar, total time — at every tier.
          Observer(builder: (context) {
            final position = _dragFraction != null
                ? miniPlayerSeekTarget(_dragFraction!, playback.duration)
                : playback.currentPosition;
            return Row(
              children: [
                SizedBox(
                  width: 40,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _fmt(position),
                      style: TextStyle(
                        color: theme.foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                Expanded(child: _buildSeekBar(theme)),
                SizedBox(
                  width: 40,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _fmt(playback.duration),
                      style: TextStyle(
                        color: theme.foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 2),
          Row(
            children: [
              // Left utilities: episode stepping, danmaku,
              // and (standard tier) the title.
              Expanded(
                child: Row(
                  children: [
                    if (showStep)
                      Observer(builder: (context) {
                        final vpc = session.videoPageController;
                        var canPrev = true;
                        if (vpc != null) {
                          canPrev = vpc.selectedEpisode.episode > 1;
                        }
                        return IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 21,
                          color: theme.foreground,
                          icon: const Icon(AnikumoIcons.skip_previous_rounded),
                          onPressed: canPrev
                              ? () => unawaited(_stepEpisode(-1))
                              : null,
                        );
                      }),
                    if (tier >= 1)
                      Observer(builder: (context) {
                        final on = playerController.danmaku.danmakuOn;
                        return IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 21,
                          color: theme.foreground,
                          icon: Icon(on
                              ? AnikumoIcons.subtitles_rounded
                              : AnikumoIcons.subtitles_off_rounded),
                          onPressed: _toggleDanmaku,
                        );
                      }),
                    if (tier == 1)
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.foreground.withValues(alpha: 0.85),
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Centre transport: seek — play disc — seek.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tier >= 1)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 23,
                      color: theme.foreground,
                      icon: Icon(_seekIcon(seekSeconds, forward: false)),
                      onPressed: () {
                        _haptic();
                        _pokeControls();
                        unawaited(playerController
                            .seekBy(Duration(seconds: -seekSeconds)));
                      },
                    ),
                  Observer(builder: (context) {
                    final playing = playback.playing;
                    return Material(
                      color: theme.accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          _haptic();
                          unawaited(playerController.playOrPause());
                          _pokeControls();
                        },
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(
                            playing
                                ? AnikumoIcons.pause_rounded
                                : AnikumoIcons.play_arrow_rounded,
                            size: 25,
                            color:
                                theme.isLight ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    );
                  }),
                  if (tier >= 1)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 23,
                      color: theme.foreground,
                      icon: Icon(_seekIcon(seekSeconds, forward: true)),
                      onPressed: () {
                        _haptic();
                        _pokeControls();
                        unawaited(playerController
                            .seekBy(Duration(seconds: seekSeconds)));
                      },
                    ),
                ],
              ),
              // Right utilities: speed, next episode, dock.
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (showSpeed)
                      Observer(builder: (context) {
                        final speed = playback.playerSpeed;
                        return TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: theme.foreground,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: () {
                            const speeds = [1.0, 1.25, 1.5, 2.0, 0.5];
                            final index = speeds.indexWhere(
                                (s) => (s - speed).abs() < 0.01);
                            final next = speeds[(index + 1) % speeds.length];
                            _haptic();
                            _pokeControls();
                            unawaited(playerController.setPlaybackSpeed(next));
                            _showHud(text: '$next×');
                          },
                          child: Text(
                            '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }),
                    if (showStep)
                      Observer(builder: (context) {
                        final vpc = session.videoPageController;
                        var canNext = true;
                        if (vpc != null) {
                          final selected = vpc.selectedEpisode;
                          final roads = vpc.roadList;
                          if (selected.road >= 0 &&
                              selected.road < roads.length) {
                            canNext = selected.episode <
                                roads[selected.road].data.length;
                          }
                        }
                        return IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 21,
                          color: theme.foreground,
                          icon: const Icon(AnikumoIcons.skip_next_rounded),
                          onPressed: canNext
                              ? () => unawaited(_stepEpisode(1))
                              : null,
                        );
                      }),
                    // Dock into the edge circle (the
                    // drag-off-the-edge gesture does the same).
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 21,
                      color: theme.foreground,
                      icon: const Icon(AnikumoIcons.minimize_rounded),
                      onPressed: () {
                        _haptic();
                        _dock();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar(MiniPlayerThemeData theme) {
    final playback = widget.session.playerController!.playback;
    return Observer(builder: (context) {
      final duration = playback.duration;
      final fraction = _dragFraction ??
          miniPlayerSeekFraction(playback.currentPosition, duration);
      return LayoutBuilder(builder: (context, constraints) {
        final barWidth = constraints.maxWidth;
        double fractionAt(double dx) => (dx / barWidth).clamp(0.0, 1.0);
        void landSeek() {
          final target = _dragFraction;
          _seekBarDragActive = false;
          setState(() => _dragFraction = null);
          if (target != null) {
            _haptic();
            unawaited(widget.session.playerController!
                .seek(miniPlayerSeekTarget(target, duration)));
          }
          _pokeControls();
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Batch 139: the bar gets a tall grab strip (30dp;
          // the visuals are unchanged), tap-to-seek as a
          // second way in, and the auto-hide timer is
          // suspended for the whole drag — it used to be able
          // to hide the controls mid-drag and kill the
          // gesture, and the old 16dp strip meant most grabs
          // missed the bar and dragged the window instead.
          onTapDown: (details) {
            _pokeControls();
            setState(
                () => _dragFraction = fractionAt(details.localPosition.dx));
          },
          onTapUp: (_) => landSeek(),
          onTapCancel: () {
            if (_seekBarDragActive) return;
            setState(() => _dragFraction = null);
            _pokeControls();
          },
          onHorizontalDragStart: (details) {
            _seekBarDragActive = true;
            _hideTimer?.cancel();
            setState(
                () => _dragFraction = fractionAt(details.localPosition.dx));
          },
          onHorizontalDragUpdate: (details) {
            setState(
                () => _dragFraction = fractionAt(details.localPosition.dx));
          },
          onHorizontalDragEnd: (_) => landSeek(),
          onHorizontalDragCancel: () {
            _seekBarDragActive = false;
            setState(() => _dragFraction = null);
            _pokeControls();
          },
          child: SizedBox(
            height: 30,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.foreground.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // The knob rides the bar at all times (batch
                  // 139; it used to appear only mid-drag), so
                  // the position is visible at a glance.
                  Positioned(
                    left: fraction * barWidth - 6,
                    top: -4,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: theme.accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.foreground,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      });
    });
  }
}
