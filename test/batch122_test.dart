import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/local_manga_source.dart';
import 'package:anikumo/services/manga/manga_cabinets.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Batch 122 probe: after importing a manga source mid-session,
/// the registry must expose it IMMEDIATELY (the user reported
/// needing a full app restart before an imported source shows
/// up). This pins the registry-level contract: install → the
/// very next all() / activeOrNull() read sees the source, and
/// the revision tick fires for listening pages.
void main() {
  group('manga source install visibility', () {
    late Directory directory;
    late PathProviderPlatform originalPathProvider;

    const code = '''
class ProbeManga extends ComicSource {
  name = "探针源";
  key = "probe_manga";
  version = "1.0.0";
}
''';

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('anikumo_b122_');
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

    test('an installed source is visible to the next read', () async {
      expect(MangaSources.all(), isEmpty);
      final before = MangaSources.revision.value;

      await MangaSources.installCustomJs(code, fileName: 'probe.js');

      expect(
        MangaSources.revision.value,
        greaterThan(before),
        reason: 'install must tick the registry revision',
      );
      final all = MangaSources.all();
      expect(all, hasLength(1));
      expect(all.single.id, 'js:probe_manga');
      expect(MangaSources.activeOrNull()?.id, 'js:probe_manga');
      expect(MangaSources.byId('js:probe_manga'), isNotNull);
    });

    test('a second install joins the first without a restart', () async {
      const code2 = '''
class SecondManga extends ComicSource {
  name = "第二源";
  key = "second_manga";
  version = "2.0.0";
}
''';
      await MangaSources.installCustomJs(code2, fileName: 'second.js');
      final ids = MangaSources.all().map((s) => s.id).toList();
      expect(ids, containsAll(<String>['js:probe_manga', 'js:second_manga']));
      expect(ids, hasLength(2));
    });

    LocalBook fakeBook(String id) => LocalBook(
          id: id,
          title: '书$id',
          dirPath: '/nowhere/$id',
          pages: 10,
          coverFile: 'cover.jpg',
          importedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );

    test('cabinets: default owns unassigned; create/assign/rename/delete',
        () async {
      final books = [fakeBook('b1'), fakeBook('b2')];
      // The default cabinet is implicit and owns everything
      // unassigned.
      expect(MangaCabinets.cabinets(), hasLength(1));
      expect(MangaCabinets.cabinets().single.id, MangaCabinets.defaultId);
      expect(
        MangaCabinets.booksIn(MangaCabinets.defaultId, books),
        hasLength(2),
      );

      final cabinet = await MangaCabinets.create('  热血专柜  ');
      expect(cabinet.name, '热血专柜');
      expect(MangaCabinets.cabinets(), hasLength(2));

      await MangaCabinets.assign('b1', cabinet.id);
      expect(MangaCabinets.cabinetIdOf('b1'), cabinet.id);
      expect(MangaCabinets.booksIn(cabinet.id, books), hasLength(1));
      expect(
        MangaCabinets.booksIn(MangaCabinets.defaultId, books),
        hasLength(1),
      );

      await MangaCabinets.rename(cabinet.id, '完结专柜');
      expect(
        MangaCabinets.cabinets().last.name,
        '完结专柜',
      );

      // Deleting a cabinet returns its books to the default.
      await MangaCabinets.delete(cabinet.id);
      expect(MangaCabinets.cabinets(), hasLength(1));
      expect(MangaCabinets.cabinetIdOf('b1'), MangaCabinets.defaultId);
      expect(
        MangaCabinets.booksIn(MangaCabinets.defaultId, books),
        hasLength(2),
      );

      // The default cabinet cannot be renamed or deleted.
      await MangaCabinets.rename(MangaCabinets.defaultId, '改名');
      await MangaCabinets.delete(MangaCabinets.defaultId);
      expect(MangaCabinets.cabinets().single.name, MangaCabinets.defaultName);
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
