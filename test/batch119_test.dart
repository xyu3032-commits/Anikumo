import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/mini_player_overlay.dart';

/// Batch 119: settings must visibly work — the control mode is a
/// floor (choosing full yields the full set), simple stays a cap.
void main() {
  group('miniPlayerTier floor semantics', () {
    test('full mode yields the full tier at the default width', () {
      expect(miniPlayerTier(width: 232, controlMode: 2), 2);
    });

    test('standard mode at the default width stays standard', () {
      expect(miniPlayerTier(width: 232, controlMode: 1), 1);
    });

    test('simple mode stays simple even on a huge window', () {
      expect(miniPlayerTier(width: 600, controlMode: 0), 0);
    });

    test('an out-of-range mode falls back to standard behaviour', () {
      expect(miniPlayerTier(width: 232, controlMode: 99), 1);
      expect(miniPlayerTier(width: 400, controlMode: 99), 2);
    });
  });
}
