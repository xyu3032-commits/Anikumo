// Batch 159: batch source removal — one pass over the
// registry, surgical memo updates, side registries swept
// once — for both the novel and manga registries.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
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

String novelBundle(List<int> ns) => jsonEncode([
      for (final n in ns)
        {
          'bookSourceName': '源$n',
          'bookSourceUrl': 'https://s$n.example.com',
          'searchUrl': 'https://s$n.example.com/search?key={{key}}',
          'ruleSearch': {'bookList': '.item', 'name': '.t'},
        },
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('batch159');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  group('novel batch removal (batch 159)', () {
    test('removes a set in one pass and keeps survivors intact', () async {
      await NovelSources.importFromText(novelBundle([1, 2, 3, 4]));
      expect(NovelSources.imported(), hasLength(4));
      final survivorBefore =
          NovelSources.imported().firstWhere((s) => s.id.contains('s3'));
      await NovelSources.togglePin('https://s2.example.com');

      final removed = await NovelSources.removeImportedBatch({
        'https://s1.example.com',
        'https://s2.example.com',
        'https://s4.example.com',
      });
      expect(removed, 3);
      final after = NovelSources.imported();
      expect(after, hasLength(1));
      // The survivor is the SAME instance: the memoized
      // parse was updated surgically, not rebuilt.
      expect(identical(after.single, survivorBefore), isTrue);
      // The pin of a removed source is gone too.
      expect(NovelSources.pinnedIds(), isNot(contains('https://s2.example.com')));
      // The persisted registry agrees.
      final raw = GStorage.getSetting(SettingsKeys.novelInstalledSourcesJson);
      expect(raw, contains('s3.example.com'));
      expect(raw, isNot(contains('s1.example.com')));
    });

    test('cleanup of dead sources goes through the batch path', () async {
      await NovelSources.importFromText(novelBundle([5, 6]));
      await GStorage.putSetting(
        SettingsKeys.novelDeadSourceIds,
        jsonEncode(['https://s5.example.com']),
      );
      NovelSources.invalidateImportedCache();
      final removed = await NovelSources.cleanupDeadImported();
      expect(removed, 1);
      expect(
        NovelSources.imported().map((s) => s.id),
        containsAll(['https://s3.example.com', 'https://s6.example.com']),
      );
      expect(NovelSources.deadSourceIds(), isEmpty);
    });
  });

  group('manga batch removal (batch 159)', () {
    test('removes JS entries in one write, adapters via the novel store',
        () async {
      await GStorage.putSetting(
        SettingsKeys.mangaJsSourcesJson,
        jsonEncode([
          {'key': 'alpha', 'name': '甲源', 'code': 'class A {}'},
          {'key': 'beta', 'name': '乙源', 'code': 'class B {}'},
          {'key': 'gamma', 'name': '丙源', 'code': 'class C {}'},
        ]),
      );
      MangaSources.invalidateInstalledCaches();
      final removed = await MangaSources.removeInstalledBatch(
        {'js:alpha', 'js:gamma'},
      );
      expect(removed, 2);
      final raw = GStorage.getSetting(SettingsKeys.mangaJsSourcesJson);
      expect(raw, contains('beta'));
      expect(raw, isNot(contains('alpha')));
      expect(
        MangaSources.installed().map((s) => s.id),
        ['js:beta'],
      );
    });
  });
}
