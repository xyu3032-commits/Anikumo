import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Batch 99: tag search by name. The detail page's tag
// fallback used to keyword-search the tag name (source
// search matches titles → empty page). fetchMangaByTagName
// must resolve the name against each source's catalogue
// and merge byTag results ONLY from sources carrying the
// tag, isolating failures per source.
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
  _TagSource(
    this.id,
    this._catalogue,
    this._byTagResults, {
    bool failTags = false,
  }) : _failTags = failTags;

  @override
  final String id;
  final List<MangaTag> _catalogue;
  final List<MangaItem> _byTagResults;
  final bool _failTags;
  int byTagCalls = 0;

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
    if (_failTags) throw StateError('catalogue down');
    return _catalogue;
  }

  @override
  Future<List<MangaItem>> byTag(String tagId,
      {int limit = 30, int page = 1}) async {
    byTagCalls++;
    return _byTagResults;
  }

  @override
  Future<List<MangaChapter>> chapters(MangaItem manga) async => const [];

  @override
  Future<List<MangaPage>> pages(
          MangaItem manga, MangaChapter chapter) async =>
      const [];
}

MangaItem _it(String source, String id) => MangaItem(
      id: id,
      title: 'T$id',
      description: '',
      coverUrl: '',
      author: '',
      status: '',
      year: 0,
      tags: const [],
      source: source,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('batch99_tag');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('merges byTag from sources carrying the tag only', () async {
    final carrier = _TagSource(
      'carrier',
      const [MangaTag(id: 't-hot', name: '热血', group: 'genre')],
      [_it('carrier', 'c1'), _it('carrier', 'c2')],
    );
    final other = _TagSource(
      'other',
      const [MangaTag(id: 't-love', name: '恋爱', group: 'genre')],
      [_it('other', 'o1')],
    );
    final results = await fetchMangaByTagName(
      '热血',
      sources: [carrier, other],
    );
    expect(results.map((e) => e.id), ['c1', 'c2']);
    expect(carrier.byTagCalls, 1);
    expect(other.byTagCalls, 0);
  });

  test('a failing catalogue is isolated, others still answer', () async {
    final broken = _TagSource('broken', const [], const [], failTags: true);
    final carrier = _TagSource(
      'carrier2',
      const [MangaTag(id: 't-hot', name: '热血', group: 'genre')],
      [_it('carrier2', 'c9')],
    );
    final results = await fetchMangaByTagName(
      ' 热血 ',
      sources: [broken, carrier],
    );
    expect(results.map((e) => e.id), ['c9']);
  });

  test('no source carrying the tag yields an empty list', () async {
    final other = _TagSource(
      'other2',
      const [MangaTag(id: 't-love', name: '恋爱', group: 'genre')],
      [_it('other2', 'o1')],
    );
    final results = await fetchMangaByTagName('科幻', sources: [other]);
    expect(results, isEmpty);
    expect(other.byTagCalls, 0);
  });
}
