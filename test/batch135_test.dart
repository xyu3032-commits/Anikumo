import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/bangumi/bangumi_tag.dart';

BangumiItem _item(int id) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
    summary: '',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: 0,
    images: const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    tags: const <BangumiTag>[],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

void main() {
  group('Top rank row press animation (batch 135)', () {
    Future<void> pumpRow(
      WidgetTester tester, {
      bool disableAnimations = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: disableAnimations),
              child: EditorialRankRow(
                rank: 1,
                item: _item(1),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
    }

    double scaleOf(WidgetTester tester) {
      final finder = find.descendant(
        of: find.byType(EditorialRankRow),
        matching: find.byType(AnimatedScale),
      );
      return tester.widget<AnimatedScale>(finder).scale;
    }

    testWidgets('pressing eases the row to 0.97, releasing restores it',
        (tester) async {
      await pumpRow(tester);
      expect(scaleOf(tester), 1.0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(EditorialRankRow)),
      );
      await tester.pump();
      expect(scaleOf(tester), 0.97);
      await gesture.up();
      await tester.pump();
      expect(scaleOf(tester), 1.0);
    });

    testWidgets('system reduced motion keeps the row unscaled',
        (tester) async {
      await pumpRow(tester, disableAnimations: true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(EditorialRankRow)),
      );
      await tester.pump();
      expect(scaleOf(tester), 1.0);
      await gesture.up();
    });
  });
}
