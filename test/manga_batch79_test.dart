import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Batch 79: the manga source registry used to re-decode
/// the full installed-sources JSON (every source's complete
/// JS code) on every installed() / all() call — and those
/// run per build and per lookup all over the manga zone.
/// The decode and the built lists are now memoized on the
/// raw stored string.
void main() {
  group('MangaSources memoization', () {
    late Directory directory;
    late PathProviderPlatform originalPathProvider;

    String registryJson(List<String> keys) => jsonEncode([
          for (final key in keys)
            {
              'key': key,
              'name': '源 $key',
              'version': '1.0.0',
              'fileName': '$key.js',
              'code': '/* $key */'.padRight(2048, 'x'),
            },
        ]);

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('anikumo_b79_');
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

    test('decode and lists are memoized while the raw is unchanged',
        () async {
      await GStorage.putSetting(
        SettingsKeys.mangaJsSourcesJson,
        registryJson(['a', 'b']),
      );
      final entries1 = MangaSources.installedJsEntries();
      final entries2 = MangaSources.installedJsEntries();
      expect(entries1, hasLength(2));
      expect(identical(entries1, entries2), isTrue);

      final installed1 = MangaSources.installed();
      final installed2 = MangaSources.installed();
      expect(installed1.map((s) => s.id), ['js:a', 'js:b']);
      expect(identical(installed1, installed2), isTrue);

      final all1 = MangaSources.all();
      final all2 = MangaSources.all();
      expect(identical(all1, all2), isTrue);
    });

    test('a registry rewrite invalidates naturally', () async {
      await GStorage.putSetting(
        SettingsKeys.mangaJsSourcesJson,
        registryJson(['c']),
      );
      expect(MangaSources.installedJsEntries(), hasLength(1));
      expect(MangaSources.installed().map((s) => s.id), ['js:c']);
      expect(MangaSources.byId('js:c'), isNotNull);
      expect(MangaSources.byId('js:a'), isNull);
    });

    test('empty registry stays empty and cheap', () async {
      await GStorage.putSetting(SettingsKeys.mangaJsSourcesJson, '');
      expect(MangaSources.installedJsEntries(), isEmpty);
      expect(MangaSources.installed(), isEmpty);
      expect(MangaSources.activeOrNull(), isNull);
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
