import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Batch 25: (1) chapter rows no longer claim "0 页" for
// sources that only learn page counts per chapter on open;
// (2) home-section popular lists persist to disk so the
// manga zone paints instantly on cold entry (SWR).
class _FakeSource extends MangaSource {
  int popularCalls = 0;

  @override
  String get id => 'fake25';

  @override
  String get name => 'Fake25';

  @override
  String get description => 'test double';

  MangaItem _item(String id) => MangaItem(
        id: id,
        title: 'Title $id',
        description: 'desc',
        coverUrl: 'https://img/$id.jpg',
        author: 'Author',
        status: 'ongoing',
        year: 2024,
        tags: const ['热血'],
        source: 'fake25',
        headers: const {'Referer': 'https://ref/'},
      );

  @override
  Future<List<MangaItem>> search(String keyword,
          {int limit = 30, int page = 1}) async =>
      [_item('s')];

  @override
  Future<List<MangaItem>> popular({int limit = 20, int page = 1}) async {
    popularCalls++;
    return [_item('p1'), _item('p2')];
  }

  @override
  Future<List<MangaItem>> updated({int limit = 20, int page = 1}) async =>
      [_item('u')];

  @override
  Future<List<MangaTag>> tags() async => const [];

  @override
  Future<List<MangaItem>> byTag(String tagId,
          {int limit = 30, int page = 1}) async =>
      const [];

  @override
  Future<MangaItem> details(MangaItem item) async => item;

  @override
  Future<List<MangaChapter>> chapters(MangaItem item) async => const [];

  @override
  Future<List<MangaPage>> pages(MangaItem item, MangaChapter chapter) async =>
      const [];
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

void main() {
  group('MangaChapter.detailSubtitle', () {
    MangaChapter chapter({required int pages, required String language}) {
      return MangaChapter(
        id: 'c1',
        volume: null,
        chapter: '1',
        title: '',
        language: language,
        pages: pages,
        publishedAt: null,
      );
    }

    test('known pages + language', () {
      expect(chapter(pages: 24, language: 'zh').detailSubtitle, '24 页 · 简中');
    });

    test('JS-source shape (0 pages, no language) is empty, not "0 页"', () {
      expect(chapter(pages: 0, language: '').detailSubtitle, '');
    });

    test('pages only', () {
      expect(chapter(pages: 12, language: '').detailSubtitle, '12 页');
    });
  });

  group('MangaItem snapshot round-trip', () {
    test('every field survives', () {
      final item = _FakeSource()._item('x');
      final restored = MangaItem.fromSnapshot(item.toSnapshot());
      expect(restored.id, item.id);
      expect(restored.title, item.title);
      expect(restored.coverUrl, item.coverUrl);
      expect(restored.year, item.year);
      expect(restored.tags, item.tags);
      expect(restored.source, item.source);
      expect(restored.headers, item.headers);
      expect(restored.storageKey, item.storageKey);
    });
  });

  group('popular disk snapshots (SWR)', () {
    late Directory directory;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('anikumo_b25_');
      PathProviderPlatform.instance = _TestPaths(directory.path);
      Hive.init(directory.path);
      await GStorage.init();
    });

    tearDownAll(() async {
      await Hive.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    setUp(() async {
      await GStorage.putSetting(SettingsKeys.mangaPopularSnapshotsJson, '');
      MangaApi.resetSnapshotStoreForTesting();
      MangaApi.clearCaches();
    });

    test('a successful load writes a fresh snapshot', () async {
      final source = _FakeSource();
      await MangaApi.fetchPopularFor(source, limit: 14);
      final snap = MangaApi.popularSnapshot(source, limit: 14);
      expect(snap, isNotNull);
      expect(snap!.fresh, isTrue);
      expect(snap.items.map((e) => e.id), ['p1', 'p2']);
      expect(snap.items.first.coverUrl, 'https://img/p1.jpg');
    });

    test('a 20-minute-old snapshot is served but stale', () async {
      final source = _FakeSource();
      await MangaApi.fetchPopularFor(source, limit: 14);
      final raw =
          GStorage.getSetting(SettingsKeys.mangaPopularSnapshotsJson);
      final store = jsonDecode(raw) as Map<String, dynamic>;
      final key = store.keys.single;
      (store[key] as Map)['ts'] = DateTime.now().millisecondsSinceEpoch -
          const Duration(minutes: 20).inMilliseconds;
      await GStorage.putSetting(
          SettingsKeys.mangaPopularSnapshotsJson, jsonEncode(store));
      MangaApi.resetSnapshotStoreForTesting();
      final snap = MangaApi.popularSnapshot(source, limit: 14);
      expect(snap, isNotNull);
      expect(snap!.fresh, isFalse);
    });

    test('a week-old snapshot is not served', () async {
      final source = _FakeSource();
      await MangaApi.fetchPopularFor(source, limit: 14);
      final raw =
          GStorage.getSetting(SettingsKeys.mangaPopularSnapshotsJson);
      final store = jsonDecode(raw) as Map<String, dynamic>;
      final key = store.keys.single;
      (store[key] as Map)['ts'] = DateTime.now().millisecondsSinceEpoch -
          const Duration(days: 8).inMilliseconds;
      await GStorage.putSetting(
          SettingsKeys.mangaPopularSnapshotsJson, jsonEncode(store));
      MangaApi.resetSnapshotStoreForTesting();
      expect(MangaApi.popularSnapshot(source, limit: 14), isNull);
    });

    test('no snapshot yet returns null', () {
      expect(MangaApi.popularSnapshot(_FakeSource(), limit: 14), isNull);
    });
  });
}
