import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/pages/manga/manga_search_page.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Batch 78: two portrait layout defects from device
/// screenshots.
/// 1. The manga search page put the mode switch and the
///    当前源/全部源 toggle on one row — together they need
///    ~480dp, so on a ~360-410dp portrait phone the toggle
///    was clipped at the right edge. They now stack on
///    narrow widths.
/// 2. The watch report's glass cards passed no padding, so
///    every value and label sat flush against the card
///    edges. The cards now carry the same inner padding
///    as the other glass surfaces. (That page is injected
///    through Modular and cannot pump standalone; its
///    change is declarative padding only.)
void main() {
  group('batch 78 portrait layouts', () {
    late Directory directory;
    late PathProviderPlatform originalPathProvider;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('anikumo_b78_');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(directory.path);
      Hive.init(directory.path);
      await GStorage.init();
    });

    tearDownAll(() async {
      PathProviderPlatform.instance = originalPathProvider;
      await Hive.close();
      await directory.delete(recursive: true);
    });

    void usePortrait(WidgetTester tester) {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(720, 1600);
      addTearDown(tester.view.reset);
    }

    testWidgets('manga search toggle stays on-screen in portrait',
        (tester) async {
      usePortrait(tester);
      await tester.pumpWidget(
        const MaterialApp(home: MangaSearchPage()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final toggle = find.text('全部源');
      expect(toggle, findsOneWidget);
      final rect = tester.getRect(toggle);
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.left, greaterThanOrEqualTo(0));
      // Stacked: the toggle sits BELOW the mode switch.
      final modeRect = tester.getRect(find.text('小说'));
      expect(rect.top, greaterThan(modeRect.bottom - 1));
    });

  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
