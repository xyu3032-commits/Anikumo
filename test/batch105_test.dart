// Batch 105: the user's correction of the tag-search
// rule — a tag search runs on the tagged manga's OWN
// source alone (batch 104 had kept the all-source fan-out
// with priority ordering inside it; superseded).
//  1. fetchMangaByTagName with a one-source scope consults
//     only that source (the search page's tag mode passes
//     exactly the origin source).
//  2. A near-name catalogue entry （热血 vs 热血漫） still
//     resolves, via the partial-match second chance.
//  3. An exact catalogue match beats the partial one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/storage/storage.dart';
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

class _TagSource extends MangaSource {
  _TagSource(this.id, this._catalogue, this._byTagResults);

  @override
  final String id;
  final List<MangaTag> _catalogue;
  final List<MangaItem> _byTagResults;
  int tagsCalls = 0;
  int byTagCalls = 0;
  String? lastByTagId;

  @override
  String get name => id;

  @override
  String get description => 'test double';

  MangaItem _item(String itemId) => MangaItem(
        id: itemId,
        title: 'T$itemId',
        description: '',
        coverUrl: '',
        author: '',
        status: '',
        year: 0,
        tags: const [],
        source: id,
      );

  @override
  Future<List<MangaItem>> search(String keyword,
          {int limit = 30, int page = 1}) async =>
      [_item('search-hit')];

  @override
  Future<List<MangaItem>> popular({int limit = 20, int page = 1}) async =>
      const [];

  @override
  Future<List<MangaItem>> updated({int limit = 20, int page = 1}) async =>
      const [];

  @override
  Future<List<MangaTag>> tags() async {
    tagsCalls++;
    return _catalogue;
  }

  @override
  Future<List<MangaItem>> byTag(String tagId,
      {int limit = 30, int page = 1}) async {
    byTagCalls++;
    lastByTagId = tagId;
    return _byTagResults;
  }

  @override
  Future<List<MangaChapter>> chapters(MangaItem manga) async => const [];

  @override
  Future<List<MangaPage>> pages(MangaItem manga, MangaChapter chapter) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('batch105_tag');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('one-source scope: only the origin source is consulted', () async {
    final origin = _TagSource(
      'b105-origin',
      const [MangaTag(id: 't-hot', name: '热血', group: 'genre')],
      [
        MangaItem(
          id: 'o1',
          title: 'To1',
          description: '',
          coverUrl: '',
          author: '',
          status: '',
          year: 0,
          tags: const [],
          source: 'b105-origin',
        ),
      ],
    );
    final results = await fetchMangaByTagName(
      '热血',
      sources: [origin],
    );
    expect(results.map((e) => e.id), ['o1']);
    expect(origin.byTagCalls, 1);
    expect(origin.lastByTagId, 't-hot');
  });

  test('partial-name fallback resolves a near-name catalogue entry',
      () async {
    final source = _TagSource(
      'b105-partial',
      const [MangaTag(id: 't-hotman', name: '热血漫', group: 'genre')],
      [
        MangaItem(
          id: 'p1',
          title: 'Tp1',
          description: '',
          coverUrl: '',
          author: '',
          status: '',
          year: 0,
          tags: const [],
          source: 'b105-partial',
        ),
      ],
    );
    final results = await fetchMangaByTagName('热血', sources: [source]);
    expect(results.map((e) => e.id), ['p1']);
    expect(source.lastByTagId, 't-hotman');
  });

  test('exact match beats the partial one', () async {
    final source = _TagSource(
      'b105-exact',
      const [
        MangaTag(id: 't-hotman', name: '热血漫', group: 'genre'),
        MangaTag(id: 't-hot', name: '热血', group: 'genre'),
      ],
      const [],
    );
    await fetchMangaByTagName('热血', sources: [source]);
    expect(source.lastByTagId, 't-hot');
  });

  group('matchTagByPartialName', () {
    const catalogue = [
      MangaTag(id: 'a', name: '热血漫', group: 'g'),
      MangaTag(id: 'b', name: '热血格斗漫', group: 'g'),
      MangaTag(id: 'c', name: '恋爱', group: 'g'),
    ];

    test('closest-length candidate wins', () {
      expect(matchTagByPartialName('热血', catalogue).single.id, 'a');
    });

    test('the query containing the catalogue name also matches', () {
      expect(matchTagByPartialName('热血漫推荐', catalogue).single.id, 'a');
    });

    test('unrelated and one-character names do not match', () {
      expect(matchTagByPartialName('科幻', catalogue), isEmpty);
      expect(matchTagByPartialName('热', catalogue), isEmpty);
    });
  });
}
