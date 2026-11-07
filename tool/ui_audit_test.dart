import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/pages/novel/novel_main_page.dart';
import 'package:anikumo/pages/novel/novel_sources_tab.dart';
import 'package:anikumo/services/storage/storage.dart';

// Batch 43 UI audit: pump the novel zone's main surfaces at
// a small-phone logical size and surface any layout
// exception (RenderFlex overflow etc.) the framework
// captured. Network is mocked to fail fast, so sections sit
// in their error/empty states — the shapes that ship.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_ui_audit');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    Hive.init(dir.path);
    await GStorage.init();
  });

  Future<void> audit(
    WidgetTester tester,
    Widget page,
    String name,
  ) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    final ex = tester.takeException();
    // ignore: avoid_print
    print('AUDIT $name exception: $ex');
    expect(ex, isNull, reason: '$name threw during render');
  }

  testWidgets('novel main page renders clean', (tester) async {
    await audit(tester, const NovelMainPage(), 'NovelMainPage');
  });

  testWidgets('novel sources tab renders clean', (tester) async {
    await audit(tester, const Scaffold(body: NovelSourcesTab()), 'NovelSourcesTab');
  });
}
