// Batch 65 regressions (user report, five symptoms, three
// mechanisms):
//  1. imported() filtered out sources whose bundle entry
//     said "enabled": false — in Legado bundles that flag
//     is the EXPORTER's local toggle (XIU2 精品 ships 10 of
//     22 disabled). Those sources were counted as imported
//     yet never existed in the app: not listed, not
//     deletable, and re-importing said 都已存在.
//  2. import/remove matched sources by the RAW stored
//     bookSourceUrl while def.id is trimmed — a stored URL
//     with stray whitespace survived deletion and then
//     blocked re-import as a phantom duplicate.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('novel_b65');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('disabled-in-bundle sources are imported AND visible', () async {
    const pack = '''
[
  {"bookSourceName": "启用源", "bookSourceUrl": "https://a.example.com",
   "enabled": true, "searchUrl": "/s?q={{key}}",
   "ruleSearch": {"bookList": ".i", "name": ".n"}},
  {"bookSourceName": "禁用源", "bookSourceUrl": "https://b.example.com",
   "enabled": false, "searchUrl": "/s?q={{key}}",
   "ruleSearch": {"bookList": ".i", "name": ".n"}}
]
''';
    final added = await NovelSources.importFromText(pack);
    expect(added, 2);
    expect(
      NovelSources.all().map((s) => s.id),
      containsAll(
        ['https://a.example.com', 'https://b.example.com'],
      ),
    );
  });

  test('the real XIU2 bundle installs all 22 sources', () async {
    final text = await File('tool/xiu2_bundle.json').readAsString();
    final added = await NovelSources.importFromText(text);
    // 2 already present from the previous test.
    expect(added, 22);
    expect(NovelSources.all().length, 24);
    final again = await NovelSources.importFromText(text);
    expect(again, 0);
  });

  test('delete then re-add works, even with a padded URL', () async {
    const padded = '''
[
  {"bookSourceName": "空白源", "bookSourceUrl": " https://c.example.com ",
   "enabled": true, "searchUrl": "/s?q={{key}}",
   "ruleSearch": {"bookList": ".i", "name": ".n"}}
]
''';
    expect(await NovelSources.importFromText(padded), 1);
    expect(
      NovelSources.all().map((s) => s.id),
      contains('https://c.example.com'),
    );
    // The UI deletes by the (trimmed) def id.
    await NovelSources.removeImported('https://c.example.com');
    expect(
      NovelSources.all().map((s) => s.id),
      isNot(contains('https://c.example.com')),
    );
    // Re-adding after deletion must not claim 都已存在.
    expect(await NovelSources.importFromText(padded), 1);
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
