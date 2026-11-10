// Batch 147: three user-reported behaviour fixes —
// (1) the mini window's drag / pinch must not summon the
// control bar (policy change in the gesture handlers; the
// pure pieces pinned here are the pan-trail maths that make
// the first drag count in full), (2) the same drag used to
// lose the travel absorbed by the direction-lock dead zone,
// (3) the anime home's back-to-top button showed even at the
// very top and now appears only after real scrolling.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/mini_player_overlay.dart';
import 'package:anikumo/pages/popular/popular_page.dart';

void main() {
  group('batch147 back-to-top visibility', () {
    test('hidden at the top and for shallow scrolls', () {
      expect(popularShowBackToTop(0), isFalse);
      expect(popularShowBackToTop(120), isFalse);
      expect(popularShowBackToTop(500), isFalse);
    });

    test('shown once the feed has scrolled a screenful', () {
      expect(popularShowBackToTop(501), isTrue);
      expect(popularShowBackToTop(4200), isTrue);
    });
  });

  group('batch147 mini player pan trail', () {
    test('commit rebases the trail to the touch-down point', () {
      // Finger went down at (90, 104) and has travelled
      // (10, -4) inside the dead zone; at commitment the focal
      // point is (100, 100) and the trail must start back at
      // the touch-down point so nothing is swallowed.
      final trail = miniPlayerTrailAtCommit(
        const Offset(100, 100),
        const Offset(10, -4),
      );
      expect(trail, const Offset(90, 104));
      // The first applied pan delta is then the full travel.
      expect(const Offset(100, 100) - trail, const Offset(10, -4));
    });

    test('zero accumulated travel keeps the trail at the focal point', () {
      expect(
        miniPlayerTrailAtCommit(const Offset(40, 60), Offset.zero),
        const Offset(40, 60),
      );
    });

    test('drag mode still commits plain drags to move', () {
      expect(
        miniPlayerDragMode(
            cumDelta: const Offset(30, 6), hasSideCandidate: false),
        'move',
      );
      expect(
        miniPlayerDragMode(
            cumDelta: const Offset(-24, 18), hasSideCandidate: true),
        'move',
      );
    });

    test('the side cone still waits, then commits to side', () {
      expect(
        miniPlayerDragMode(
            cumDelta: const Offset(2, 20), hasSideCandidate: true),
        isNull,
      );
      expect(
        miniPlayerDragMode(
            cumDelta: const Offset(2, 30), hasSideCandidate: true),
        'side',
      );
    });
  });
}
