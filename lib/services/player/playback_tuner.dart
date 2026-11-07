import 'dart:async';

import 'package:anikumo/services/logging/logger.dart';
import 'package:media_kit/media_kit.dart';

/// Batch 19: runtime playback tuning, on top of the static
/// profiles (PlaybackCachePolicy owns the demuxer byte caps,
/// PlayerEnhance owns the start-of-playback property profile).
/// This layer watches the RUNNING player and adapts two things:
///
/// 1. Adaptive pre-read: steps `cache-secs` up a ladder when
///    the stream starves (cached-ahead collapses while playing)
///    and back down when the buffer stays comfortably full, so
///    a weak network gets a deeper cushion and a fast one does
///    not waste data. The byte caps stay with the cache policy;
///    `cache-secs` is a separate, complementary knob.
/// 2. Frame-drop guardian: when dropped frames pile up over a
///    window (device cannot keep up), it sheds GPU/CPU load in
///    steps — interpolation off, enhance vf chain off,
///    fast decode + decoder frame-drop — announcing each step.
///
/// All decisions are pure functions so they can be unit-tested
/// without a player.
class PlaybackTuner {
  PlaybackTuner._();

  /// cache-secs ladder, in seconds of media.
  static const List<int> cacheSecsLadder = [30, 60, 120, 240];

  /// Decide the next ladder index.
  ///
  /// [starved] means cached-ahead fell under 2 s while playing
  /// at least once since the last decision. [comfortablePolls]
  /// counts consecutive polls with cached-ahead above 85% of
  /// the current rung; three in a row are required to step down
  /// (hysteresis, so the ladder does not flap).
  static int nextCacheSecsIndex({
    required int currentIndex,
    required double cachedAheadSeconds,
    required bool starved,
    required int comfortablePolls,
    required int maxIndex,
  }) {
    final cappedMax = maxIndex.clamp(0, cacheSecsLadder.length - 1);
    if (starved) {
      return currentIndex < cappedMax ? currentIndex + 1 : currentIndex;
    }
    if (currentIndex > 0 &&
        comfortablePolls >= 3 &&
        cachedAheadSeconds > cacheSecsLadder[currentIndex] * 0.85) {
      return currentIndex - 1;
    }
    return currentIndex;
  }

  /// Bytes the forward demuxer cache needs to actually hold
  /// [secs] seconds at [totalBitrateBps], with 25% headroom
  /// for container overhead and bitrate spikes. An unknown
  /// bitrate (<= 0) keeps the policy baseline — the ladder
  /// must never shrink the buffer on a guess. Clamped to
  /// [baselineBytes, capBytes] so the user's buffer profile
  /// stays the floor and memory stays bounded.
  static int cacheBytesForSecs({
    required int secs,
    required int totalBitrateBps,
    required int baselineBytes,
    required int capBytes,
  }) {
    if (totalBitrateBps <= 0) return baselineBytes;
    final needed = (secs * totalBitrateBps / 8 * 1.25).round();
    if (needed < baselineBytes) return baselineBytes;
    if (needed > capBytes) return capBytes;
    return needed;
  }

  /// Dropped frames (VO + decoder) in one evaluation window
  /// that count as "the device cannot keep up".
  static const int dropWindowThreshold = 40;

  /// Highest guardian step.
  static const int maxDropStep = 4;

  /// Whether the window's drops justify escalating at all.
  static bool dropWindowExceeded(int dropsInWindow) =>
      dropsInWindow >= dropWindowThreshold;

  /// Batch 20: the guardian ladder is now
  ///   1 interpolation off (mpv property)
  ///   2 super-resolution step-down (Anime4K shaders are the
  ///     biggest GPU cost; handled by a session callback, no
  ///     mpv properties)
  ///   3 enhance vf chain off (mpv property)
  ///   4 fast decode + decoder frame-drop (mpv properties)
  /// [resolveDropStep] returns the first step above [from]
  /// that is actually applicable — step 2 needs SR on, step 3
  /// needs the enhance vf chain — or [from] when none is.
  static int resolveDropStep({
    required int from,
    required bool srActive,
    required bool vfActive,
  }) {
    for (var step = from + 1; step <= maxDropStep; step++) {
      final applicable = switch (step) {
        2 => srActive,
        3 => vfActive,
        _ => true,
      };
      if (applicable) return step;
    }
    return from;
  }

  /// mpv properties applied when the guardian reaches [step]
  /// (step 2 is shader-side and has none).
  static Map<String, String> dropStepProperties(int step) {
    return switch (step) {
      1 => const {'interpolation': 'no'},
      3 => const {'vf': ''},
      4 => const {'vd-lavc-fast': 'yes', 'framedrop': 'decoder'},
      _ => const {},
    };
  }

  static String dropStepNotice(int step) {
    return switch (step) {
      1 => '检测到持续掉帧，已关闭运动插帧',
      2 => '持续掉帧，已降低超分辨率',
      3 => '持续掉帧，已关闭降噪/锐化滤镜',
      4 => '持续掉帧，已切换快速解码',
      _ => '',
    };
  }
}

/// A live tuning session bound to one [Player]. Self-disposes
/// when the player stops being the current one or its property
/// reads keep failing (player gone).
class PlaybackTunerSession {
  PlaybackTunerSession._(
    this._player,
    this._isCurrent,
    this._onNotice, {
    required bool adaptCache,
    required bool dropGuard,
    required int maxCacheIndex,
    required bool vfChainActive,
    required bool Function() srActive,
    required Future<bool> Function() stepDownSuperResolution,
    required int Function() baselineBytes,
    required int capBytes,
    required bool Function() isSuspended,
  })  : _adaptCache = adaptCache,
        _dropGuard = dropGuard,
        _maxCacheIndex = maxCacheIndex,
        _vfChainActive = vfChainActive,
        _srActive = srActive,
        _stepDownSuperResolution = stepDownSuperResolution,
        _baselineBytes = baselineBytes,
        _capBytes = capBytes,
        _isSuspended = isSuspended;

  static PlaybackTunerSession? _active;

  static void start({
    required Player player,
    required bool Function() isCurrent,
    required void Function(String message) onNotice,
    required bool adaptCache,
    required bool dropGuard,
    required int maxCacheIndex,
    required bool vfChainActive,
    required bool Function() srActive,
    required Future<bool> Function() stepDownSuperResolution,
    required int Function() baselineBytes,
    required int capBytes,
    required bool Function() isSuspended,
  }) {
    _active?.dispose();
    _active = PlaybackTunerSession._(
      player,
      isCurrent,
      onNotice,
      adaptCache: adaptCache,
      dropGuard: dropGuard,
      maxCacheIndex: maxCacheIndex,
      vfChainActive: vfChainActive,
      srActive: srActive,
      stepDownSuperResolution: stepDownSuperResolution,
      baselineBytes: baselineBytes,
      capBytes: capBytes,
      isSuspended: isSuspended,
    ).._start();
  }

  final Player _player;
  final bool Function() _isCurrent;
  final void Function(String message) _onNotice;
  final bool _adaptCache;
  final bool _dropGuard;
  final int _maxCacheIndex;
  final bool _vfChainActive;
  final bool Function() _srActive;
  final Future<bool> Function() _stepDownSuperResolution;
  final int Function() _baselineBytes;
  final int _capBytes;
  final bool Function() _isSuspended;

  Timer? _timer;
  bool _ticking = false;
  bool _disposed = false;
  int _failures = 0;

  int _cacheIndex = 1; // start at the 60 s rung
  bool _starved = false;
  int _comfortablePolls = 0;

  int _dropStep = 0;
  int _lastDropTotal = 0;
  int _windowDrops = 0;
  int _windowTicks = 0;

  void _start() {
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_tick());
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (identical(_active, this)) _active = null;
  }

  Future<String?> _get(String name) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return null;
    final value = await platform.getProperty(name);
    return value;
  }

  Future<void> _set(String name, String value) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty(name, value);
  }

  Future<void> _tick() async {
    if (_disposed || _ticking) return;
    if (!_isCurrent()) {
      dispose();
      return;
    }
    _ticking = true;
    try {
      final playing = _player.state.playing;
      // Batch 20: read the three metrics in one batch instead
      // of three sequential round-trips per poll.
      final reads = await Future.wait([
        _get('demuxer-cache-duration'),
        _get('frame-drop-count'),
        _get('decoder-frame-drop-count'),
        _get('cache-secs'),
        _get('video-bitrate'),
        _get('audio-bitrate'),
      ]);
      final cacheAhead = double.tryParse(reads[0] ?? '') ?? 0;
      if (playing && cacheAhead < 2.0) _starved = true;

      if (_adaptCache && !_isSuspended()) {
        // Batch 23: self-heal cache-secs drift. The Android
        // lifecycle hook rewrites cache-secs (0 while
        // backgrounded, 36000 on resume); without this, one
        // background cycle silently discarded the ladder for
        // the rest of the episode. While suspended we must
        // NOT write — the suspension is what keeps a
        // backgrounded demuxer from burning retries.
        final actualSecs = double.tryParse(reads[3] ?? '');
        final rung = PlaybackTuner.cacheSecsLadder[_cacheIndex];
        if (actualSecs != null && (actualSecs - rung).abs() > 1) {
          await _set('cache-secs', rung.toString());
        }
        final target = PlaybackTuner.cacheSecsLadder[_cacheIndex];
        if (cacheAhead > target * 0.85) {
          _comfortablePolls++;
        } else {
          _comfortablePolls = 0;
        }
        final next = PlaybackTuner.nextCacheSecsIndex(
          currentIndex: _cacheIndex,
          cachedAheadSeconds: cacheAhead,
          starved: _starved,
          comfortablePolls: _comfortablePolls,
          maxIndex: _maxCacheIndex,
        );
        if (next != _cacheIndex) {
          _cacheIndex = next;
          _starved = false;
          _comfortablePolls = 0;
          final secs = PlaybackTuner.cacheSecsLadder[next];
          await _set('cache-secs', secs.toString());
          // Batch 23: scale the byte cap with the ladder —
          // at high bitrates the old fixed cap bound long
          // before cache-secs did, so the top rungs were
          // dead letters for 4K streams.
          final bitrate = (int.tryParse(reads[4] ?? '') ?? 0) +
              (int.tryParse(reads[5] ?? '') ?? 0);
          final bytes = PlaybackTuner.cacheBytesForSecs(
            secs: secs,
            totalBitrateBps: bitrate,
            baselineBytes: _baselineBytes(),
            capBytes: _capBytes,
          );
          await _set('demuxer-max-bytes', bytes.toString());
          AnikumoLogger().i(
            'PlaybackTuner: cache-secs -> ${secs}s, '
            'demuxer-max-bytes -> $bytes',
          );
        } else if (_starved && _cacheIndex >= _maxCacheIndex) {
          _starved = false; // already at the cap; do not latch
        }
      }

      if (_dropGuard) {
        final vo = int.tryParse(reads[1] ?? '') ?? 0;
        final dec = int.tryParse(reads[2] ?? '') ?? 0;
        final total = vo + dec;
        _windowDrops += (total - _lastDropTotal).clamp(0, 1 << 30);
        _lastDropTotal = total;
        _windowTicks++;
        if (_windowTicks >= 2) {
          final drops = _windowDrops;
          _windowDrops = 0;
          _windowTicks = 0;
          if (PlaybackTuner.dropWindowExceeded(drops)) {
            final next = PlaybackTuner.resolveDropStep(
              from: _dropStep,
              srActive: _srActive(),
              vfActive: _vfChainActive,
            );
            if (next != _dropStep) {
              _dropStep = next;
              if (next == 2) {
                await _stepDownSuperResolution();
              } else {
                final props = PlaybackTuner.dropStepProperties(next);
                for (final entry in props.entries) {
                  try {
                    await _set(entry.key, entry.value);
                  } catch (_) {
                    // A rejected property must not kill the session.
                  }
                }
              }
              final notice = PlaybackTuner.dropStepNotice(next);
              if (notice.isNotEmpty) _onNotice(notice);
              AnikumoLogger().i(
                'PlaybackTuner: drop guardian step $next '
                '($drops drops in window)',
              );
            }
          }
        }
      }
      _failures = 0;
    } catch (e) {
      _failures++;
      if (_failures >= 3) {
        AnikumoLogger().w('PlaybackTuner: session ended (player gone)');
        dispose();
      }
    } finally {
      _ticking = false;
    }
  }
}
