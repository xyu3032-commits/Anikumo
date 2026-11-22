import 'dart:async';

import 'package:anikumo/services/storage/storage.dart';

/// Batch 282 (#26): a token bucket that paces byte
/// streams to a configured rate.
///
/// The bucket refills at [bytesPerSecond] up to a
/// one-second burst capacity. [reserve] is the pure
/// core: given a chunk size and the current time it
/// mutates the bucket and returns how long the caller
/// must wait before emitting that chunk so the average
/// rate holds. It is synchronous, so several concurrent
/// streams can share one bucket safely — reservations
/// interleave at await points, never mid-computation.
class TokenBucket {
  TokenBucket({
    required this.bytesPerSecond,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _tokens = bytesPerSecond.toDouble();
    _lastRefill = _clock();
  }

  final int bytesPerSecond;
  final DateTime Function() _clock;

  late double _tokens;
  late DateTime _lastRefill;

  double get _capacity => bytesPerSecond.toDouble();

  /// Reserves room for [bytes] and returns the wait
  /// before those bytes may pass. A wait of zero means
  /// the burst capacity covers the chunk right away.
  ///
  /// [_lastRefill] doubles as the debt anchor: after a
  /// reservation that overdrew the bucket it points at
  /// the moment the overdrawn chunk may be released, so
  /// a reservation made while an earlier wait is still
  /// pending queues behind it instead of under-waiting.
  Duration reserve(int bytes) {
    if (bytesPerSecond <= 0 || bytes <= 0) return Duration.zero;
    final now = _clock();
    if (now.isAfter(_lastRefill)) {
      final elapsedMs = now.difference(_lastRefill).inMilliseconds;
      _tokens += elapsedMs * bytesPerSecond / 1000.0;
      if (_tokens > _capacity) _tokens = _capacity;
      _lastRefill = now;
    }
    _tokens -= bytes;
    if (_tokens >= 0) {
      final wait = _lastRefill.difference(now);
      return wait.isNegative ? Duration.zero : wait;
    }
    final deficitMs = (-_tokens * 1000.0 / bytesPerSecond).ceil();
    _tokens = 0;
    final base = _lastRefill.isAfter(now) ? _lastRefill : now;
    final releaseAt = base.add(Duration(milliseconds: deficitMs));
    _lastRefill = releaseAt;
    return releaseAt.difference(now);
  }
}

/// Paces [source] through [bucket]: each chunk is
/// emitted only after its reservation wait elapses.
Stream<List<int>> rateLimited(
  Stream<List<int>> source,
  TokenBucket bucket, {
  Future<void> Function(Duration)? sleep,
}) async* {
  final doSleep = sleep ?? Future<void>.delayed;
  await for (final chunk in source) {
    final wait = bucket.reserve(chunk.length);
    if (wait > Duration.zero) await doSleep(wait);
    yield chunk;
  }
}

/// The app-wide download rate limiter facade. One
/// shared bucket across every download stream, so the
/// configured cap is a true global cap (anime episodes,
/// segments and manga pages together). The rate is
/// read from settings each time a stream starts; a
/// changed rate replaces the bucket.
abstract final class DownloadRateLimiter {
  static TokenBucket? _bucket;
  static int _bucketKbps = -1;

  /// Current configured cap in bytes/second, or 0 when
  /// limiting is off.
  static int get bytesPerSecond =>
      GStorage.getSetting(SettingsKeys.downloadRateLimitKbps) * 1024;

  static bool get enabled => bytesPerSecond > 0;

  static TokenBucket _sharedBucket() {
    final kbps =
        GStorage.getSetting(SettingsKeys.downloadRateLimitKbps);
    if (_bucket == null || _bucketKbps != kbps) {
      _bucketKbps = kbps;
      _bucket = TokenBucket(bytesPerSecond: kbps * 1024);
    }
    return _bucket!;
  }

  /// Returns [source] paced to the configured cap, or
  /// [source] untouched when limiting is off.
  static Stream<List<int>> throttle(Stream<List<int>> source) {
    if (!enabled) return source;
    return rateLimited(source, _sharedBucket());
  }
}
