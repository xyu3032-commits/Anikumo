import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/services/ui/card_style.dart';

void main() {
  testWidgets('bangumi card preview extent fits every style',
      (tester) async {
    for (var style = 0; style < 5; style++) {
      CardStyle.styleNotifier.value = style;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                Center(
                  child: SizedBox(
                    width: 160,
                    height: 160 / 0.65 + 32,
                    child: BangumiCardV(
                      bangumiItem: BangumiItem(
                        id: 1,
                        name: '测试番剧',
                        nameCn: '测试番剧',
                        summary: '',
                        type: 2,
                        rank: 0,
                        airDate: '',
                        airWeekday: 1,
                        images: const {},
                        tags: const [],
                        alias: const [],
                        ratingScore: 8.0,
                        votes: 100,
                        votesCount: const [],
                        info: '',
                      ),
                      canTap: false,
                    ),
                  ),
                ),
                const Text('below-marker'),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('below-marker'), findsOneWidget,
          reason: 'style $style pushed content away or threw');
    }
  });
}
