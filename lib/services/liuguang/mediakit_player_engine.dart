import 'dart:async';

import 'package:liuguang_core/liuguang_core.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Batch 206: the 流光 PlayerEngine kernel backed by the
/// app's existing media_kit (libmpv) player — the embedding
/// decision made when the engine was designed (no separate
/// decode stack for the film zone; Anikumo's pinned
/// media_kit does the decoding).
///
/// The media_kit [mk.Player] is created lazily in
/// [initialize] so constructing the kernel (registry
/// bookkeeping, tests) never touches native code. The page
/// reaches [player] to build its Video widget.
class MediaKitPlayerEngine implements PlayerEngine {
  @override
  String get kernelId => 'mediakit';

  @override
  PlayerCapabilities get capabilities => const PlayerCapabilities(
        hdr: false,
        hardwareDecode: true,
        subtitles: true,
        multiAudio: true,
        pictureInPicture: false,
        backgroundPlay: false,
        formats: {'mp4', 'hls', 'dash', 'mkv', 'webm'},
      );

  mk.Player? _player;

  /// The underlying media_kit player (after [initialize]).
  mk.Player get player =>
      _player ?? (throw StateError('mediakit kernel not initialized'));

  bool get isInitialized => _player != null;

  PlaybackState _state = const PlaybackState();
  final _stateCtl = StreamController<PlaybackState>.broadcast();
  final _eventCtl = StreamController<PlaybackEvent>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];
  Duration _pendingSeek = Duration.zero;
  bool _seekApplied = true;
  bool _disposed = false;
  double _lastVolume = 1;

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get stateStream => _stateCtl.stream;

  @override
  Stream<PlaybackEvent> get eventStream => _eventCtl.stream;

  void _emit(String type) {
    if (_disposed) return;
    _stateCtl.add(_state);
    _eventCtl.add(PlaybackEvent(type, _state));
  }

  void _set(PlaybackState next, String type) {
    _state = next;
    _emit(type);
  }

  @override
  Future<void> initialize(PlayerConfig config) async {
    if (_player != null) return;
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
        logLevel: mk.MPVLogLevel.error,
      ),
    );
    _player = player;
    _subs.addAll([
      player.stream.playing.listen((playing) {
        _set(
          _state.copyWith(
            status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
          ),
          playing ? 'play' : 'pause',
        );
      }),
      player.stream.buffering.listen((buffering) {
        if (buffering && _state.status != PlaybackStatus.playing) {
          _set(_state.copyWith(status: PlaybackStatus.buffering), 'buffering');
        }
      }),
      player.stream.position.listen((position) {
        _state = _state.copyWith(position: position);
        _emit('progress');
      }),
      player.stream.duration.listen((duration) {
        _state = _state.copyWith(duration: duration);
        _emit('duration');
        if (!_seekApplied && duration > Duration.zero) {
          _seekApplied = true;
          if (_pendingSeek > Duration.zero) {
            player.seek(_pendingSeek);
          }
        }
      }),
      player.stream.rate.listen((rate) {
        _state = _state.copyWith(speed: rate);
        _emit('speed');
      }),
      player.stream.volume.listen((volume) {
        final v = (volume / 100).clamp(0, 1).toDouble();
        if (v > 0) _lastVolume = v;
        _state = _state.copyWith(volume: v);
        _emit('volume');
      }),
      player.stream.completed.listen((completed) {
        if (completed) {
          _set(_state.copyWith(status: PlaybackStatus.ended), 'ended');
        }
      }),
      player.stream.error.listen((error) {
        _set(
          _state.copyWith(
            status: PlaybackStatus.error,
            errorMessage: error,
          ),
          'error',
        );
      }),
    ]);
    _set(const PlaybackState(status: PlaybackStatus.idle), 'initialized');
  }

  @override
  Future<void> open(MediaPlaybackRequest request) async {
    final player = this.player;
    _pendingSeek = request.startPosition;
    _seekApplied = request.startPosition <= Duration.zero;
    _set(
      _state.copyWith(
        status: PlaybackStatus.opening,
        position: Duration.zero,
        errorMessage: null,
      ),
      'opening',
    );
    final media = mk.Media(
      request.source.url,
      httpHeaders: request.source.headers,
    );
    await player.open(media, play: request.autoPlay);
    _emit('opened');
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() async {
    await player.stop();
    _set(
      _state.copyWith(status: PlaybackStatus.idle, position: Duration.zero),
      'stop',
    );
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> setSpeed(double speed) => player.setRate(speed);

  @override
  Future<void> setVolume(double volume) =>
      player.setVolume((volume.clamp(0, 1) * 100).toDouble());

  @override
  Future<void> setMuted(bool muted) =>
      player.setVolume(muted ? 0 : _lastVolume * 100);

  @override
  Future<void> selectSubtitle(String? trackId) async {
    final tracks = player.state.tracks.subtitle;
    if (trackId == null || trackId == 'none') {
      await player.setSubtitleTrack(mk.SubtitleTrack.no());
      _set(_state.copyWith(subtitleId: null), 'subtitle');
      return;
    }
    final index = int.tryParse(trackId);
    if (index != null && index >= 0 && index < tracks.length) {
      await player.setSubtitleTrack(tracks[index]);
      _set(_state.copyWith(subtitleId: trackId), 'subtitle');
    }
  }

  @override
  Future<void> selectAudio(String trackId) async {
    final tracks = player.state.tracks.audio;
    final index = int.tryParse(trackId);
    if (index != null && index >= 0 && index < tracks.length) {
      await player.setAudioTrack(tracks[index]);
      _set(_state.copyWith(audioId: trackId), 'audio');
    }
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    // mpv has no direct subtitle-delay property wired in
    // this media_kit build; kept as a no-op record so hosts
    // can rely on the call not throwing.
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _player?.dispose();
    _player = null;
    await _stateCtl.close();
    await _eventCtl.close();
  }
}
