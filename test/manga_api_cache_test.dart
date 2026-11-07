import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_source.dart';

// Batch 22: popular/updated/tags go through MangaApi's TTL
// caches — the manga home sections used to call the source
// directly and re-ran it on EVERY entry into the manga zone.
class _CountingSource extends MangaSource {
  int popularCalls = 0;
  int updatedCalls = 0;
  int tagsCalls = 0;

  @override
  String get id => 'counting';

  @override
  String get name => 'Counting';

  @override
  String get description => 'test double';

  MangaItem _item(String id) => MangaItem(
        id: id,
        title: 'T$id',
        description: '',
        coverUrl: '',
        author: '',
        status: '',
        year: 0,
        tags: const [],
        source: 'counting',
      );

  @override
  Future<List<MangaItem>> search(String keyword,
          {int limit = 30, int page = 1}) async =>
      [_item('s')];

  @override
  Future<List<MangaItem>> popular({int limit = 20, int page = 1}) async {
    popularCalls++;
    return [_item('p')];
  }

  @override
  Future<List<MangaItem>> updated({int limit = 20, int page = 1}) async {
    updatedCalls++;
    return [_item('u')];
  }

  @override
  Future<List<MangaTag>> tags() async {
    tagsCalls++;
    return const [MangaTag(id: 't', name: 'Tag', group: 'genre')];
  }

  @override
  Future<List<MangaItem>> byTag(String tagId,
          {int limit = 30, int page = 1}) async =>
      const [];

  @override
  Future<List<MangaChapter>> chapters(MangaItem manga) async => const [];

  @override
  Future<List<MangaPage>> pages(
          MangaItem manga, MangaChapter chapter) async =>
      const [];
}

void main() {
  setUp(MangaApi.clearCaches);

  test('popular/updated/tags are served from cache on repeat', () async {
    final source = _CountingSource();
    await MangaApi.fetchPopularFor(source, limit: 14);
    await MangaApi.fetchPopularFor(source, limit: 14);
    await MangaApi.fetchUpdatedFor(source, limit: 15);
    await MangaApi.fetchUpdatedFor(source, limit: 15);
    await MangaApi.fetchTagsFor(source);
    await MangaApi.fetchTagsFor(source);
    expect(source.popularCalls, 1);
    expect(source.updatedCalls, 1);
    expect(source.tagsCalls, 1);
  });

  test('different limits are different cache entries', () async {
    final source = _CountingSource();
    await MangaApi.fetchPopularFor(source, limit: 14);
    await MangaApi.fetchPopularFor(source, limit: 20);
    expect(source.popularCalls, 2);
  });
}
