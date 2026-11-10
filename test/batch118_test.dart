import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/mini_player_overlay.dart';

/// Batch 118: experience-first fixes — default window lands in
/// the standard tier. (The horizontal-drag scrub that landed
/// with this batch was retired in batch 136; its tests moved
/// to batch136_test.dart.)
void main() {
  group('miniPlayerTier defaults', () {
    test('the default window width gets the standard controls', () {
      // ~230 logical px on a typical phone at the default size.
      expect(miniPlayerTier(width: 232, controlMode: 1), 1);
    });
  });


}
