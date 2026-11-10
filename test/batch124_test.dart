import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/novel_cabinets.dart';
import 'package:anikumo/services/storage/storage.dart';

class _TestPaths extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
}

NovelItem _book(String key, String title) {
  final parts = key.split('::');
  return NovelItem(
    source: parts[0],
    bookUrl: parts[1],
    title: title,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('anikumo_b124_');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('universe dedupes favorites and progress by storage key', () {
    final a = _book('s::a', '甲');
    final b = _book('s::b', '乙');
    final c = _book('s::c', '丙');
    final universe = NovelCabinets.universe(
      favorites: [a, b],
      progressBooks: [b, c],
    );
    expect(universe.map((e) => e.storageKey), ['s::a', 's::b', 's::c']);
  });

  test('cabinet flow: default, create, assign, rename, delete', () async {
    final a = _book('s::a', '甲');
    final b = _book('s::b', '乙');
    final all = NovelCabinets.universe(favorites: [a, b], progressBooks: []);

    // Unassigned books live in the default cabinet.
    expect(NovelCabinets.cabinetIdOf(a.storageKey), NovelCabinets.defaultId);
    expect(NovelCabinets.booksIn(NovelCabinets.defaultId, all), hasLength(2));

    final cabinet = await NovelCabinets.create('  追更中 ');
    expect(cabinet.name, '追更中');
    expect(NovelCabinets.cabinets().map((c) => c.id),
        [NovelCabinets.defaultId, cabinet.id]);

    await NovelCabinets.assign(a.storageKey, cabinet.id);
    expect(NovelCabinets.cabinetIdOf(a.storageKey), cabinet.id);
    expect(NovelCabinets.booksIn(cabinet.id, all).single.title, '甲');
    expect(
        NovelCabinets.booksIn(NovelCabinets.defaultId, all).single.title, '乙');

    await NovelCabinets.rename(cabinet.id, '完结书架');
    expect(
      NovelCabinets.cabinets().firstWhere((c) => c.id == cabinet.id).name,
      '完结书架',
    );

    // Deleting a cabinet returns its books to the default one.
    await NovelCabinets.delete(cabinet.id);
    expect(NovelCabinets.cabinetIdOf(a.storageKey), NovelCabinets.defaultId);
    expect(NovelCabinets.cabinets(), hasLength(1));
  });

  test('the default cabinet cannot be renamed or deleted', () async {
    await NovelCabinets.rename(NovelCabinets.defaultId, 'x');
    await NovelCabinets.delete(NovelCabinets.defaultId);
    expect(NovelCabinets.cabinets().single.name, NovelCabinets.defaultName);
  });
}
