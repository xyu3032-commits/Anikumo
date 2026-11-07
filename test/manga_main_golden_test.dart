import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/pages/manga/manga_main_page.dart';
import 'package:anikumo/services/storage/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_golden');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    Hive.init(dir.path);
    await GStorage.init();
  });

  testWidgets('real MangaMainPage renders one tab at a time',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: MangaMainPage()),
    );
    // Let the (failing, in test env) source requests settle into
    // their fallback states without pumpAndSettle (spinners).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(
      find.byType(MangaMainPage),
      matchesGoldenFile('goldens/manga_main_home.png'),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(
      find.byType(MangaMainPage),
      matchesGoldenFile('goldens/manga_main_settings.png'),
    );
  });

  testWidgets('tab switch is instant, no cross-fade (batch 49)',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: MangaMainPage()),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The tab wrappers are the Opacity widgets whose child is
    // the RepaintBoundary around each kept-alive tab.
    List<double> tabOpacities() {
      return tester
          .elementList(find.byWidgetPredicate(
              (w) => w is Opacity && w.child is RepaintBoundary))
          .map((element) => (element.widget as Opacity).opacity)
          .toList();
    }

    // Batch 22: tabs mount lazily — only the home tab exists
    // until another tab is first visited.
    expect(tabOpacities(), [1.0]);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    // Batch 49: the 220ms cross-fade is gone (full-screen blend
    // read as a hitch on the user's device). On the FIRST frame
    // after the switch the outgoing tab must already be fully
    // hidden and the incoming one fully visible — no partial
    // opacities in between.
    expect(tabOpacities(), [0.0, 1.0]);
  });
}
