import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/mini_player_overlay.dart';

void main() {
  group('mini player drag mode (batch 136)', () {
    test('a horizontal drag moves the window — it never seeks', () {
      expect(
        miniPlayerDragMode(
          cumDelta: const Offset(120, 4),
          hasSideCandidate: false,
        ),
        'move',
      );
      expect(
        miniPlayerDragMode(
          cumDelta: const Offset(-90, 10),
          hasSideCandidate: true,
        ),
        'move',
      );
    });

    test('diagonal and vertical drags without a side candidate move', () {
      expect(
        miniPlayerDragMode(
          cumDelta: const Offset(30, 30),
          hasSideCandidate: false,
        ),
        'move',
      );
      expect(
        miniPlayerDragMode(
          cumDelta: const Offset(2, 80),
          hasSideCandidate: false,
        ),
        'move',
      );
    });

    test('a committed steep vertical drag at a side adjusts', () {
      expect(
        miniPlayerDragMode(
          cumDelta: const Offset(8, 60),
          hasSideCandidate: true,
        ),
        'side',
      );
    });

    test('inside the side cone before commitment the drag waits', () {
      expect(
        miniPlayerDragMode(
          cumDelta: const Offset(3, 20),
          hasSideCandidate: true,
        ),
        isNull,
      );
    });
  });
}
