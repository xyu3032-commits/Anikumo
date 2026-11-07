import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Batch 35 regression: importing a source pack on a fresh
// install (nothing stored yet) died with "Unsupported
// operation: Cannot add to an unmodifiable list" because
// parseSourceArray returned a const [] for empty storage
// and importFromText added to it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const oneSource = '''
[
  {
    "bookSourceName": "测试源",
    "bookSourceUrl": "https://example.com/source",
    "bookSourceType": 0,
    "enabled": true,
    "searchUrl": "/search?q={{key}}",
    "ruleSearch": {"bookList": ".item", "name": ".name"}
  }
]
''';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('novel_import');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('first import on empty storage adds the source', () async {
    final added = await NovelSources.importFromText(oneSource);
    expect(added, 1);
    expect(
      NovelSources.imported().map((s) => s.id),
      contains('https://example.com/source'),
    );
  });

  test('re-importing the same pack adds nothing', () async {
    final added = await NovelSources.importFromText(oneSource);
    expect(added, 0);
  });

  test('removeImported works after import', () async {
    await NovelSources.removeImported('https://example.com/source');
    expect(NovelSources.imported(), isEmpty);
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
