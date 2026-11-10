import 'dart:io';

import 'package:anikumo/services/manga/manga_source_updates.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

String _code(String cls, String key, String version) => '''
class $cls extends ComicSource {
  name = "源$key";
  key = "$key";
  version = "$version";
}
''';

/// Batch 190: source update checking — version compare,
/// repository + origin channels, origin preservation,
/// and the apply path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('batch190');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  group('isNewerMangaVersion', () {
    test('dotted numeric compare', () {
      expect(isNewerMangaVersion('1.4.3', '1.4.2'), isTrue);
      expect(isNewerMangaVersion('1.4.3', '1.4.3'), isFalse);
      expect(isNewerMangaVersion('1.4.2', '1.4.3'), isFalse);
      expect(isNewerMangaVersion('1.10.0', '1.9.9'), isTrue);
      expect(isNewerMangaVersion('2.0', '1.9.9'), isTrue);
      expect(isNewerMangaVersion('1.0.1', '1.0'), isTrue);
      expect(isNewerMangaVersion('1.0', '1.0.1'), isFalse);
    });

    test('empty versions never count', () {
      expect(isNewerMangaVersion('', '1.0'), isFalse);
      expect(isNewerMangaVersion('2.0', ''), isFalse);
      expect(isNewerMangaVersion('', ''), isFalse);
    });
  });

  group('repositories + origins registry', () {
    test('repositories dedupe and persist', () async {
      await MangaSources.addSourceRepository('https://r.example/i.json');
      await MangaSources.addSourceRepository('https://r.example/i.json');
      await MangaSources.addSourceRepository(' https://r.example/i.json ');
      expect(
        MangaSources.sourceRepositories(),
        ['https://r.example/i.json'],
      );
    });

    test('install without origin keeps the recorded one', () async {
      await MangaSources.installCustomJs(
        _code('FakeOne', 'fake_one', '1.0.0'),
        origin: 'https://cdn.example/fake_one.js',
      );
      expect(
        MangaSources.originOfKey('fake_one'),
        'https://cdn.example/fake_one.js',
      );
      await MangaSources.installCustomJs(
        _code('FakeOne', 'fake_one', '1.0.1'),
      );
      expect(
        MangaSources.originOfKey('fake_one'),
        'https://cdn.example/fake_one.js',
      );
    });
  });

  group('check + apply', () {
    const repoUrl = 'https://repo.example.com/index.json';
    const indexJson = '''
[
  {"name": "源fake_repo", "fileName": "fake_repo.js", "key": "fake_repo", "version": "1.2.0"},
  {"name": "未装的源", "fileName": "other.js", "key": "not_installed", "version": "9.9.9"}
]
''';

    Future<String?> fetcher(String url) async {
      if (url == repoUrl) return indexJson;
      if (url == 'https://cdn.example/fake_origin.js') {
        return _code('FakeOrigin', 'fake_origin', '2.0.0');
      }
      if (url == 'https://repo.example.com/fake_repo.js') {
        return _code('FakeRepo', 'fake_repo', '1.2.0');
      }
      if (url == 'https://cdn.example/fake_one.js') {
        return _code('FakeOne', 'fake_one', '1.0.1');
      }
      return null;
    }

    test('finds updates via repository and via origin', () async {
      await MangaSources.addSourceRepository(repoUrl);
      await MangaSources.installCustomJs(
        _code('FakeRepo', 'fake_repo', '1.0.0'),
      );
      await MangaSources.installCustomJs(
        _code('FakeOrigin', 'fake_origin', '1.5.0'),
        origin: 'https://cdn.example/fake_origin.js',
      );
      await MangaSources.installCustomJs(
        _code('FakeFresh', 'fake_fresh', '3.0.0'),
        origin: 'https://nowhere.example/fake_fresh.js',
      );

      final updates = await MangaSourceUpdates.check(fetch: fetcher);
      final byKey = {for (final u in updates) u.jsKey: u};
      expect(byKey.keys, containsAll(['fake_repo', 'fake_origin']));
      expect(byKey['fake_repo']!.latestVersion, '1.2.0');
      expect(
        byKey['fake_repo']!.fileUrl,
        'https://repo.example.com/fake_repo.js',
      );
      expect(byKey['fake_origin']!.latestVersion, '2.0.0');
      // fake_one is already at the version its origin
      // serves, fake_fresh's origin is unreachable:
      expect(byKey.keys, isNot(contains('fake_one')));
      expect(byKey.keys, isNot(contains('fake_fresh')));
      expect(byKey.keys, isNot(contains('not_installed')));
    });

    test('apply installs the new code and keeps origins', () async {
      final updates = await MangaSourceUpdates.check(fetch: fetcher);
      final result = await MangaSourceUpdates.apply(
        updates,
        fetch: fetcher,
      );
      expect(result.failed, 0);
      expect(result.updated, updates.length);
      final installed = {
        for (final s in MangaSources.installed()) s.jsKey: s.version,
      };
      expect(installed['fake_repo'], '1.2.0');
      expect(installed['fake_origin'], '2.0.0');
      // A fresh check now finds nothing for them.
      final again = await MangaSourceUpdates.check(fetch: fetcher);
      expect(
        again.map((u) => u.jsKey),
        isNot(containsAll(['fake_repo', 'fake_origin'])),
      );
    });
  });
}
