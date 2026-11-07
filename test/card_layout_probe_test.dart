import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/ui/card_style.dart';

BangumiItem _item() {
  return BangumiItem(
    id: 1,
    type: 2,
    name: '葬送のフリーレン',
    nameCn: '葬送的芙莉莲：一段很长很长的中文标题用来测试溢出',
    summary: '',
    airDate: '2023-09-29',
    airWeekday: 5,
    rank: 12,
    images: const {'large': ''},
    tags: const [],
    alias: const [],
    ratingScore: 8.7,
    votes: 12345,
    votesCount: const [],
    info: '',
  );
}

void main() {
  // Grid cells as configured by the browse grids: mainAxisExtent is
  // cellWidth / 0.65 + 32 for anime cards.
  for (final style in [0, 1, 2, 3, 4]) {
    testWidgets('BangumiCardV style $style fits its grid cell',
        (tester) async {
      CardStyle.styleNotifier.value = style;
      const cellWidth = 118.0;
      const cellHeight = cellWidth / 0.65 + 32;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: cellWidth,
                height: cellHeight,
                child: BangumiCardV(bangumiItem: _item(), canTap: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('MangaRailCard fits its grid cell', (tester) async {
    const cellWidth = 118.0;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: cellWidth,
              height: cellWidth / 0.52,
              child: MangaRailCard(
                item: MangaItem(
                  id: 'm1',
                  title: '一段很长很长的漫画标题用来测试溢出的问题',
                  description: '',
                  coverUrl: '',
                  author: '',
                  status: 'ongoing',
                  year: 2024,
                  tags: [],
                ),
                width: double.infinity,
                onTap: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
