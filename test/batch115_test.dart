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

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('batch115 rank row hero transition', () {
    testWidgets('no hero by default (other pages unchanged)', (tester) async {
      await tester.pumpWidget(_host(
        EditorialRankRow(rank: 1, item: _item(42), onTap: () {}),
      ));
      expect(find.byType(Hero), findsNothing);
    });

    testWidgets('enableHero wraps the cover in a hero tagged by item id',
        (tester) async {
      await tester.pumpWidget(_host(
        EditorialRankRow(
          rank: 2,
          item: _item(42),
          onTap: () {},
          enableHero: true,
        ),
      ));
      final hero = tester.widget<Hero>(find.byType(Hero));
      expect(hero.tag, 42);
    });

    testWidgets('tap still fires the callback exactly once', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        EditorialRankRow(
          rank: 3,
          item: _item(7),
          onTap: () => taps++,
          enableHero: true,
        ),
      ));
      await tester.tap(find.byType(EditorialRankRow));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
