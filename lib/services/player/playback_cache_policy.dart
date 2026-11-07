import 'dart:async';

import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/network/metered_network_service.dart';
import 'package:anikumo/services/player/low_memory_mode.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/async_serial_queue.dart';
import 'package:media_kit/media_kit.dart';

class PlaybackCachePolicy {
  PlaybackCachePolicy({
    required bool Function() isLocalPlayback,
    required Player? Function() currentPlayer,
  })  : _isLocalPlayback = isLocalPlayback,
        _currentPlayer = currentPlayer;

  static const int _lowMemoryBufferSize = 2 * 1024 * 1024;

  /// Batch 23: the back buffer only serves backward seeks;
  /// sizing it equal to the forward buffer (the old
  /// behaviour) doubled the demuxer memory for a window
  /// viewers rarely scrub across. A quarter of the forward
  /// size, clamped to [8MB, 48MB], still covers minutes of
  /// backward seek at typical bitrates.
  static int backBufferSizeFor(int forwardBytes) {
    final quarter = forwardBytes ~/ 4;
    if (quarter < 8 * 1024 * 1024) return 8 * 1024 * 1024;
    if (quarter > 48 * 1024 * 1024) return 48 * 1024 * 1024;
    return quarter;
  }
  static const int _defaultBufferSize = 1500 * 1024 * 1024;

  /// 省流 buffer-profile cap: big enough for a smooth minute or so of
  /// typical streams, far below the default demuxer cache.
  static const int _saverBufferSize = 96 * 1024 * 1024;

  final bool Function() _isLocalPlayback;
  final Player? Function() _currentPlayer;
  final AsyncSerialQueue _writes = AsyncSerialQueue();

  StreamSubscription<void>? _settingsSubscription;

  bool get networkAutomatic =>
      LowMemoryMode.current == LowMemoryMode.auto &&
      !_isLocalPlayback() &&
      MeteredNetworkService.isMetered;

  int get bufferSize {
    // The user's buffer profile wins over the automatic logic:
    // 'saver' caps the demuxer cache, 'smooth' always uses the large
    // buffer (an explicit low-memory mode still shrinks it), 'auto'
    // keeps the original metered/low-memory behaviour. Local files
    // are never capped.
    final profile = _bufferProfile;
    if (!_isLocalPlayback()) {
      if (profile == 'saver') {
        return _saverBufferSize;
      }
      if (profile == 'smooth') {
        return LowMemoryMode.current == LowMemoryMode.always
            ? _lowMemoryBufferSize
            : _defaultBufferSize;
      }
    }
    return LowMemoryMode.current.isEnabled(
          isMetered: MeteredNetworkService.isMetered,
          isLocalPlayback: _isLocalPlayback(),
        )
        ? _lowMemoryBufferSize
        : _defaultBufferSize;
  }

  String get _bufferProfile {
    try {
      return GStorage.getSetting(SettingsKeys.bufferProfile);
    } catch (_) {
      return 'auto';
    }
  }

  StreamSubscription<void>? _profileSubscription;

  void startWatching() {
    if (_settingsSubscription != null) {
      return;
    }
    _settingsSubscription = LowMemoryMode.watch().listen((_) => _onChanged());
    _profileSubscription = GStorage.watchSettings(
      [SettingsKeys.bufferProfile],
    ).listen((_) => _onChanged());
    MeteredNetworkService.listenable.addListener(_onChanged);
  }

  void stopWatching() {
    MeteredNetworkService.listenable.removeListener(_onChanged);
    unawaited(_settingsSubscription?.cancel());
    _settingsSubscription = null;
    unawaited(_profileSubscription?.cancel());
    _profileSubscription = null;
  }

  Future<void> apply() async {
    final player = _currentPlayer();
    if (player == null) {
      return;
    }
    try {
      final pp = player.platform as NativePlayer;
      // A stale player's initialization must not block its replacement's writes.
      await pp.waitForPlayerInitialization;
      await _writes.run(() async {
        if (!identical(_currentPlayer(), player)) {
          return;
        }
        final size = bufferSize;
        await pp.setProperty('demuxer-max-bytes', size.toString());
        await pp.setProperty(
          'demuxer-max-back-bytes',
          backBufferSizeFor(size).toString(),
        );
      });
    } catch (e) {
      AnikumoLogger().w(
        'PlaybackCachePolicy: failed to apply demuxer cache size',
        error: e,
      );
    }
  }

  void _onChanged() {
    unawaited(apply());
  }
}
