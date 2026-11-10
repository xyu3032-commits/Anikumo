import 'package:anikumo/bean/widget/mini_player_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

/// Batch 120/121: the dock decision uses the push-out amount —
/// how far a finished drag tried to carry the window past its
/// on-screen clamp. Parking against an edge produces almost no
/// push-out; pushing the window out produces a lot, regardless
/// of where the window was grabbed.
void main() {
  group('miniPlayerShouldDock (push-out semantics)', () {
    test('parking against an edge does not dock', () {
      expect(miniPlayerShouldDock(overshootDx: 0), isFalse);
      expect(miniPlayerShouldDock(overshootDx: 18), isFalse);
      expect(miniPlayerShouldDock(overshootDx: -24), isFalse);
    });

    test('pushing out past the threshold docks, either side', () {
      expect(miniPlayerShouldDock(overshootDx: 57), isTrue);
      expect(miniPlayerShouldDock(overshootDx: 140), isTrue);
      expect(miniPlayerShouldDock(overshootDx: -57), isTrue);
      expect(miniPlayerShouldDock(overshootDx: -200), isTrue);
    });

    test('the boundary is the 56dp threshold', () {
      expect(miniPlayerShouldDock(overshootDx: 56), isFalse);
      expect(miniPlayerShouldDock(overshootDx: 56.1), isTrue);
      expect(miniPlayerShouldDock(overshootDx: -56), isFalse);
      expect(miniPlayerShouldDock(overshootDx: -56.1), isTrue);
    });

    test('a custom threshold is honoured', () {
      expect(
        miniPlayerShouldDock(overshootDx: 30, threshold: 20),
        isTrue,
      );
      expect(
        miniPlayerShouldDock(overshootDx: 10, threshold: 20),
        isFalse,
      );
    });
  });
}
