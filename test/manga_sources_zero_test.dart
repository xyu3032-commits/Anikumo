// Batch 62 regression: with zero manga sources installed,
// the source management page (the "add a source" page) must
// render its import entry — it used to call the throwing
// MangaSources.active() inside build(), which in release
// mode showed as a pure grey screen. Same guard class for
// the cross-search mode label and NovelApi.searchActive.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:anikumo/pages/manga/manga_sources_page.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/novel/novel_api.dart';
import 'package:anikumo/services/storage/storage.dart';

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

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('anikumo_b62_');
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  testWidgets('sources page renders with zero sources', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MangaSourcesPage()),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('导入自定义源'), findsOneWidget);
    expect(find.text('漫画源管理'), findsOneWidget);
  });

  test('zero-source facades stay null-safe', () async {
    expect(MangaApi.activeOrNull, isNull);
    expect(await NovelApi.searchActive('anything'), isEmpty);
  });
}
