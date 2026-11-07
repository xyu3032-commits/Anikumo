import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/player/playback_tuner.dart';

// Batch 19: the runtime tuner's decisions are pure functions —
// ladder movement with hysteresis, drop-step escalation.
void main() {
  group('adaptive cache-secs ladder', () {
    test('starvation steps up, bounded by maxIndex', () {
      expect(
        PlaybackTuner.nextCacheSecsIndex(
          currentIndex: 1,
          cachedAheadSeconds: 0.5,
          starved: true,
          comfortablePolls: 0,
          maxIndex: 3,
        ),
        2,
      );
      expect(
        PlaybackTuner.nextCacheSecsIndex(
          currentIndex: 1,
          cachedAheadSeconds: 0.5,
          starved: true,
          comfortablePolls: 0,
          maxIndex: 1,
        ),
        1,
      );
    });

    test('steps down only after 3 comfortable polls above 85%', () {
      expect(
        PlaybackTuner.nextCacheSecsIndex(
          currentIndex: 2,
          cachedAheadSeconds: 110,
          starved: false,
          comfortablePolls: 2,
          maxIndex: 3,
        ),
        2,
      );
      expect(
        PlaybackTuner.nextCacheSecsIndex(
          currentIndex: 2,
          cachedAheadSeconds: 110,
          starved: false,
          comfortablePolls: 3,
          maxIndex: 3,
        ),
        1,
      );
    });

    test('starvation wins over comfort', () {
      expect(
        PlaybackTuner.nextCacheSecsIndex(
          currentIndex: 1,
          cachedAheadSeconds: 999,
          starved: true,
          comfortablePolls: 9,
          maxIndex: 3,
        ),
        2,
      );
    });
  });

  group('cache byte scaling', () {
    const mb = 1024 * 1024;

    test('unknown bitrate keeps the baseline', () {
      expect(
        PlaybackTuner.cacheBytesForSecs(
          secs: 240,
          totalBitrateBps: 0,
          baselineBytes: 150 * mb,
          capBytes: 512 * mb,
        ),
        150 * mb,
      );
    });

    test('high bitrate scales up to the cap', () {
      // 25 Mbps 4K: 240 s needs ~937 MB -> capped at 512 MB.
      expect(
        PlaybackTuner.cacheBytesForSecs(
          secs: 240,
          totalBitrateBps: 25000000,
          baselineBytes: 150 * mb,
          capBytes: 512 * mb,
        ),
        512 * mb,
      );
    });

    test('low bitrate never shrinks below the baseline', () {
      // 800 kbps: 60 s needs ~7 MB -> baseline wins.
      expect(
        PlaybackTuner.cacheBytesForSecs(
          secs: 60,
          totalBitrateBps: 800000,
          baselineBytes: 150 * mb,
          capBytes: 512 * mb,
        ),
        150 * mb,
      );
    });
  });

  group('frame-drop guardian', () {
    test('window threshold gates escalation', () {
      expect(PlaybackTuner.dropWindowExceeded(39), isFalse);
      expect(PlaybackTuner.dropWindowExceeded(40), isTrue);
    });

    test('resolver picks the first applicable step', () {
      // Everything available: walk the ladder in order.
      expect(
        PlaybackTuner.resolveDropStep(
            from: 0, srActive: true, vfActive: true),
        1,
      );
      expect(
        PlaybackTuner.resolveDropStep(
            from: 1, srActive: true, vfActive: true),
        2,
      );
      expect(
        PlaybackTuner.resolveDropStep(
            from: 2, srActive: true, vfActive: true),
        3,
      );
      expect(
        PlaybackTuner.resolveDropStep(
            from: 3, srActive: true, vfActive: true),
        4,
      );
      // SR off: step 2 is skipped.
      expect(
        PlaybackTuner.resolveDropStep(
            from: 1, srActive: false, vfActive: true),
        3,
      );
      // Neither SR nor vf: from 1 straight to fast decode.
      expect(
        PlaybackTuner.resolveDropStep(
            from: 1, srActive: false, vfActive: false),
        4,
      );
      // Top of the ladder stays.
      expect(
        PlaybackTuner.resolveDropStep(
            from: 4, srActive: true, vfActive: true),
        4,
      );
    });

    test('step properties shed load in order', () {
      expect(PlaybackTuner.dropStepProperties(1),
          {'interpolation': 'no'});
      // Step 2 is the shader step-down: no mpv properties.
      expect(PlaybackTuner.dropStepProperties(2), <String, String>{});
      expect(PlaybackTuner.dropStepProperties(3), {'vf': ''});
      expect(
        PlaybackTuner.dropStepProperties(4),
        {'vd-lavc-fast': 'yes', 'framedrop': 'decoder'},
      );
    });
  });
}
