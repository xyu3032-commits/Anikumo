import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/player/playback_cache_policy.dart';

// Batch 23: the back buffer is a quarter of the forward one,
// clamped — it only serves backward seeks.
void main() {
  test('back buffer sizing', () {
    const mb = 1024 * 1024;
    // Default 1500MB forward -> capped at 48MB back.
    expect(PlaybackCachePolicy.backBufferSizeFor(1500 * mb), 48 * mb);
    // 96MB saver forward -> 24MB back.
    expect(PlaybackCachePolicy.backBufferSizeFor(96 * mb), 24 * mb);
    // Tiny forward sizes still get the 8MB floor.
    expect(PlaybackCachePolicy.backBufferSizeFor(2 * mb), 8 * mb);
  });
}
