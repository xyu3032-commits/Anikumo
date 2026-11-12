import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:anikumo/pages/player/player_controller.dart';
import 'package:anikumo/pages/video/video_controller.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 113: in-app picture-in-picture (mini player).
///
/// The default PiP experience is a small floating window INSIDE the
/// app: leaving the player lands on the anime home with the video
/// still playing in a draggable mini window, instead of shrinking
/// the whole app into the system PiP over the phone's home screen.
/// The system PiP stays available as the "external" mode in the PiP
/// settings (player settings, or long-press the PiP button).
///
/// Ownership model: the '/video' route still creates its controller
/// pair per visit. When the page exits into the mini window, the
/// pair is ADOPTED by this session instead of being disposed (the
/// controllers' dispose() becomes a no-op while adopted); the global
/// overlay renders the mini window from the adopted pair. Reopening
/// the same video hands the same pair back to the page (seamless
/// resume); opening a different video closes the session for real.
/// While the mini window is up, entering the manga/novel zones
/// hides it (and optionally mutes it) until the user comes back —
/// both behaviours are user settings, not hard-coded.

/// Which area of the app the current route belongs to, for the mini
/// window's zone visibility rule.
enum MiniPlayerZone { anime, manga, novel, video, settings }

/// Classifies a route by its Modular path. Unknown/app routes count
/// as the anime side (the mini window stays visible there).
MiniPlayerZone miniPlayerZoneForRoute(String? routeName) {
  final name = routeName ?? '';
  if (name.startsWith('/manga')) return MiniPlayerZone.manga;
  if (name.startsWith('/novel')) return MiniPlayerZone.novel;
  if (name.startsWith('/video')) return MiniPlayerZone.video;
  if (name.startsWith('/settings')) return MiniPlayerZone.settings;
  return MiniPlayerZone.anime;
}

/// Whether the mini window should be on screen.
bool miniPlayerVisible({
  required bool hasSession,
  required MiniPlayerZone zone,
  required bool hideInOtherZones,
  bool playerPageOpen = false,
}) {
  if (!hasSession) return false;
  // The full player page replaces the mini window while it is open;
  // the mini never floats over the player itself. Batch 116: the
  // page reports itself directly (playerPageOpen), because route
  // observation alone missed pushes that land in a nested
  // navigator — the window then stayed over the player, sometimes.
  if (playerPageOpen) return false;
  if (zone == MiniPlayerZone.video) return false;
  // Batch 251: never float over the settings pages. A
  // settings detour while watching used to leave the
  // mini window parked on top of the very pages the
  // user went to adjust — the "it went PiP by itself"
  // complaint. Playback keeps its session; the window
  // simply stays out of the settings area and comes
  // back with the content zones.
  if (zone == MiniPlayerZone.settings) return false;
  if (hideInOtherZones &&
      (zone == MiniPlayerZone.manga || zone == MiniPlayerZone.novel)) {
    return false;
  }
  return true;
}

/// Whether leaving the player page should park playback in the
/// in-app mini window instead of stopping it.
bool miniPlayerShouldExitToMini({
  required bool isDesktopPlatform,
  required bool inAppMode,
  required bool hasPlayableMedia,
}) {
  return !isDesktopPlatform && inAppMode && hasPlayableMedia;
}

/// Batch 116: which args a '/video/' navigation should use when a
/// mini session exists. Online playback resumes by ANIME: if the
/// Batch 220: the mini-resume decision for external
/// (film) sessions, as a pure function. Their args always
/// carry an explicit episode pick, so the anime rule
/// (any pick ends the session) restarted every film on
/// return from the mini window. Resume [current] when the
/// candidate is the session's own args, or the same work
/// at the session's live episode; anything else is a
/// deliberate new pick and ends the session (null).
VideoPlaybackArgs? externalMiniResumeArgs(
  OnlineVideoPlaybackArgs current,
  OnlineVideoPlaybackArgs candidate, {
  required int? liveEpisode,
}) {
  if (identical(current, candidate)) return current;
  if (current.bangumiItem.id != candidate.bangumiItem.id) return null;
  if (candidate.initialEpisode == null ||
      liveEpisode == null ||
      candidate.initialEpisode == liveEpisode) {
    return current;
  }
  return null;
}

/// session is playing the same bangumi, its own args (and live
/// pair) win over the entry point's. Anything else keeps the
/// strict same-source match.
VideoPlaybackArgs? miniPlayerResumeArgs(
  VideoPlaybackArgs current,
  VideoPlaybackArgs candidate,
) {
  if (current is OnlineVideoPlaybackArgs &&
      candidate is OnlineVideoPlaybackArgs) {
    return current.bangumiItem.id == candidate.bangumiItem.id ? current : null;
  }
  return miniPlayerArgsMatch(current, candidate) ? current : null;
}

/// Whether two playback args describe the same video from the same
/// source (the mini session's resume matching).
bool miniPlayerArgsMatch(VideoPlaybackArgs a, VideoPlaybackArgs b) {
  if (a.bangumiItem.id != b.bangumiItem.id) return false;
  return switch ((a, b)) {
    (OnlineVideoPlaybackArgs x, OnlineVideoPlaybackArgs y) =>
      x.plugin.name == y.plugin.name,
    (OfflineVideoPlaybackArgs x, OfflineVideoPlaybackArgs y) =>
      x.pluginName == y.pluginName,
    _ => false,
  };
}

class MiniPlayerSession extends ChangeNotifier {
  MiniPlayerSession._();

  static final MiniPlayerSession instance = MiniPlayerSession._();

  PlayerController? _playerController;
  VideoPageController? _videoPageController;
  VideoPlaybackArgs? _args;

  PlayerController? get playerController => _playerController;
  VideoPageController? get videoPageController => _videoPageController;
  VideoPlaybackArgs? get args => _args;
  bool get hasSession => _playerController != null;

  MiniPlayerZone _zone = MiniPlayerZone.anime;
  MiniPlayerZone get zone => _zone;

  /// Batch 116: the full player page is currently open (reported by
  /// the page itself, not inferred from routes — see
  /// [miniPlayerVisible]).
  bool _playerPageOpen = false;
  bool get playerPageOpen => _playerPageOpen;

  void setPlayerPageOpen(bool open) {
    if (_playerPageOpen == open) return;
    _playerPageOpen = open;
    _applyZoneAudio();
    notifyListeners();
  }

  double? _volumeBeforeMute;
  bool _mutedBySession = false;

  /// True when [candidate] is the video this session is playing
  /// (same bangumi from the same source), so the player page should
  /// reattach to the adopted pair instead of starting over.
  bool isActiveFor(VideoPlaybackArgs candidate) {
    final current = _args;
    if (current == null) return false;
    return miniPlayerArgsMatch(current, candidate);
  }

  /// Batch 116: the args a '/video/' navigation should actually
  /// use. When the mini session is playing the SAME anime (online),
  /// the session's own args win over whatever the entry point built
  /// — the user tapped the anime that is already playing, so there
  /// is nothing to pick: no source, no line, straight back in with
  /// the live pair. Offline entries keep the strict match (an
  /// explicit download tap must stay offline).
  VideoPlaybackArgs? resumeArgsFor(VideoPlaybackArgs candidate) {
    final current = _args;
    if (current == null) return null;
    // Batch 220: external sessions (film) resume from the
    // mini window — see video_module for why their explicit
    // episode pick must not veto this. Resume for the
    // session's own args object (the mini window's expand),
    // or the same work at the session's live episode; a
    // deliberate pick of a DIFFERENT episode still ends the
    // session and starts fresh, as Batch 127 requires.
    if (current is OnlineVideoPlaybackArgs &&
        current.externalPlayback &&
        candidate is OnlineVideoPlaybackArgs &&
        candidate.externalPlayback) {
      return externalMiniResumeArgs(
        current,
        candidate,
        liveEpisode: _videoPageController?.selectedEpisode.episode,
      );
    }
    return miniPlayerResumeArgs(current, candidate);
  }

  /// Takes ownership of the pair leaving the player page. The
  /// controllers are flagged adopted BEFORE this runs (see
  /// [markAdopted]) so the route scope's disposal cannot stop
  /// playback mid-handover.
  void adopt({
    required PlayerController playerController,
    required VideoPageController videoPageController,
    required VideoPlaybackArgs args,
  }) {
    markAdopted(
      playerController: playerController,
      videoPageController: videoPageController,
    );
    _playerController = playerController;
    _videoPageController = videoPageController;
    _args = args;
    _applyZoneAudio();
    notifyListeners();
  }

  /// Flags a pair as adopted so its dispose() turns into a no-op.
  /// Called synchronously when the exit-to-mini decision is made,
  /// ahead of any route teardown.
  static void markAdopted({
    required PlayerController playerController,
    required VideoPageController videoPageController,
  }) {
    playerController.adoptedByMiniPlayer = true;
    videoPageController.adoptedByMiniPlayer = true;
  }

  /// The current exit decision for a pair leaving the player page,
  /// from the user's settings and the pair's playback state.
  static bool shouldExitToMini({
    required bool isDesktopPlatform,
    required PlayerController playerController,
  }) {
    return miniPlayerShouldExitToMini(
      isDesktopPlatform: isDesktopPlatform,
      inAppMode: GStorage.getSetting(SettingsKeys.pipInAppMode),
      hasPlayableMedia: playerController.playback.videoController != null,
    );
  }

  bool get visible => miniPlayerVisible(
    hasSession: hasSession,
    zone: _zone,
    hideInOtherZones: GStorage.getSetting(SettingsKeys.pipHideInOtherZones),
    playerPageOpen: _playerPageOpen,
  );

  /// Route changes come from [MiniPlayerRouteObserver]. Zone entry
  /// hides/shows the window and applies the mute preference.
  void updateZone(MiniPlayerZone next) {
    if (_zone == next) return;
    _zone = next;
    _applyZoneAudio();
    notifyListeners();
  }

  /// Settings changed (mode/hide/mute) — re-evaluate audio + UI.
  void refreshFromSettings() {
    _applyZoneAudio();
    notifyListeners();
  }

  void _applyZoneAudio() {
    final player = _playerController?.playback.mediaPlayer;
    if (player == null) return;
    final shouldMute =
        hasSession &&
        !visible &&
        _zone != MiniPlayerZone.video &&
        // Batch 116: never mute while the full player page is open
        // (the user is watching it there) — zone tracking can lag
        // behind the page in nested navigators.
        !_playerPageOpen &&
        GStorage.getSetting(SettingsKeys.pipMuteWhenHidden);
    if (shouldMute && !_mutedBySession) {
      _volumeBeforeMute = player.state.volume;
      _mutedBySession = true;
      unawaited(player.setVolume(0));
    } else if (!shouldMute && _mutedBySession) {
      _mutedBySession = false;
      final restore = _volumeBeforeMute;
      _volumeBeforeMute = null;
      if (restore != null) {
        unawaited(player.setVolume(restore));
      }
    }
  }

  /// Ends the session for real: restores audio, then runs the
  /// controllers' deferred teardown.
  Future<void> close() async {
    final player = _playerController;
    final video = _videoPageController;
    if (player == null && video == null) return;
    _playerController = null;
    _videoPageController = null;
    _args = null;
    if (_mutedBySession) {
      _mutedBySession = false;
      final restore = _volumeBeforeMute;
      _volumeBeforeMute = null;
      final mediaPlayer = player?.playback.mediaPlayer;
      if (mediaPlayer != null && restore != null) {
        unawaited(mediaPlayer.setVolume(restore));
      }
    }
    notifyListeners();
    player?.disposeAfterMini();
    video?.disposeAfterMini();
  }
}

/// Feeds the session's zone tracking from the app's navigator.
class MiniPlayerRouteObserver extends RouteObserver<PageRoute<void>> {
  void _report(Route<dynamic>? route) {
    MiniPlayerSession.instance.updateZone(
      miniPlayerZoneForRoute(route?.settings.name),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _report(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _report(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _report(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _report(previousRoute);
  }
}

final miniPlayerRouteObserver = MiniPlayerRouteObserver();
