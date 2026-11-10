import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anikumo/bean/widget/zone_switcher.dart';

void main() {
  group('zone wheel mapping (batch 131)', () {
    test('indices cycle through the three zones forever', () {
      expect(zoneForWheelIndex(0), AppZone.anime);
      expect(zoneForWheelIndex(1), AppZone.manga);
      expect(zoneForWheelIndex(2), AppZone.novel);
      expect(zoneForWheelIndex(3), AppZone.anime);
      expect(zoneForWheelIndex(3001), AppZone.manga);
      expect(zoneForWheelIndex(3002), AppZone.novel);
      expect(zoneForWheelIndex(3003), AppZone.anime);
    });

    test('the initial page centres the current zone, aligned', () {
      for (final zone in AppZone.values) {
        final page = zoneWheelInitialPage(zone);
        expect(page % AppZone.values.length, zone.index);
        expect(zoneForWheelIndex(page), zone);
      }
    });

    test('only the anime zone lives at the root shell', () {
      expect(AppZone.anime.route, isNull);
      expect(AppZone.manga.route, '/manga/');
      expect(AppZone.novel.route, '/novel/');
    });
  });

  testWidgets('zone mark chip opens the wheel; outside tap closes it',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ZoneWheelChip(current: AppZone.anime, english: true),
        ),
      ),
    );
    await tester.tap(find.byType(ZoneWheelChip));
    await tester.pumpAndSettle();
    expect(find.text('切换专区'), findsOneWidget);
    expect(find.text('动漫'), findsWidgets);
    expect(find.text('漫画'), findsWidgets);
    expect(find.text('小说'), findsWidgets);
    expect(find.text('你在这里'), findsOneWidget);
    // Tap the dimmed corner — the wheel goes away, nothing
    // else changes.
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('切换专区'), findsNothing);
  });
}
