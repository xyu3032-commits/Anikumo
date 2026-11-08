import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';

/// Batch 92: the rail card's text block must occupy the
/// same height with and without a status line (the status
/// line is always rendered now), so covers in a
/// fixed-height rail line up. Also guards the card against
/// overflow regressions at rail geometry.
MangaItem _item({required String status}) {
  return MangaItem(
    id: 'c1',
    title: '一部标题稍微有点长的示例漫画作品',
    description: '',
    coverUrl: '',
    author: '',
    status: status,
    year: null,
    tags: const [],
    source: 'probe',
  );
}

Future<double> _cardHeight(
  WidgetTester tester,
  MangaItem item,
  String key,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 208,
          child: MangaRailCard(
            key: ValueKey(key),
            item: item,
            width: 104,
            onTap: () {},
          ),
        ),
      ),
    ),
  );
  final size = tester.getSize(find.byKey(ValueKey(key)));
  return size.height;
}

void main() {
  testWidgets('rail card renders with and without status, no overflow',
      (tester) async {
    final withStatus = await _cardHeight(
      tester,
      _item(status: 'ongoing'),
      'with-status',
    );
    expect(tester.takeException(), isNull);
    final withoutStatus = await _cardHeight(
      tester,
      _item(status: ''),
      'without-status',
    );
    expect(tester.takeException(), isNull);
    // Both cards fill the rail height identically.
    expect(withStatus, 208);
    expect(withoutStatus, withStatus);
  });

  testWidgets('status text shows for ongoing and reserves space otherwise',
      (tester) async {
    await _cardHeight(tester, _item(status: 'ongoing'), 'a');
    expect(find.text('连载中'), findsOneWidget);
    await _cardHeight(tester, _item(status: ''), 'b');
    expect(find.text('连载中'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
