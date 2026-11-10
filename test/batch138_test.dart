import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/fade_slide_in.dart';

void main() {
  group('RankEntrance3D visibility gating (batch 138)', () {
    double opacityOf(WidgetTester tester) {
      final finder = find.descendant(
        of: find.byType(RankEntrance3D),
        matching: find.byType(Opacity),
      );
      return tester.widget<Opacity>(finder).opacity;
    }

    testWidgets('a visible row plays its entrance to full opacity',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RankEntrance3D(
              index: 0,
              child: SizedBox(width: 100, height: 50),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      expect(opacityOf(tester), 1.0);
    });

    testWidgets('an off-screen row waits, then plays when scrolled in',
        (tester) async {
      final controller = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: controller,
              child: const Column(
                children: [
                  SizedBox(height: 2000),
                  RankEntrance3D(
                    index: 0,
                    child: SizedBox(width: 100, height: 50),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Still off-screen (and inside the fallback window):
      // the entrance must not have burned itself unseen.
      await tester.pump(const Duration(milliseconds: 800));
      expect(opacityOf(tester), 0.0);
      controller.jumpTo(1700);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      expect(opacityOf(tester), 1.0);
    });
  });
}
