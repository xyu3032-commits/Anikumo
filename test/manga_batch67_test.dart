// Batch 67: Legado type-2 （漫画） sources adapted into
// the manga zone. Pins the model translation (NovelItem /
// NovelChapter / NovelImageBlock → MangaItem /
// MangaChapter / MangaPage), the registry surfacing
// (novel registry stays the single store; only type 2
// adapts), and removal routing back to that registry.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/manga/legado_manga_source.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/novel/novel_source.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakeNovelSource implements NovelSource {
  @override
  String get id => 'https://m.example.com';

  @override
  String get name => '示例漫画源';

  @override
  bool get builtin => false;

  @override
  String get loginUrl => '';

  @override
  int get type => 2;

  @override
  Map<String, String> get headers => const {'User-Agent': 'UA'};

  @override
  List<NovelExploreCategory> get exploreCategories => const [
        NovelExploreCategory(title: '热门', url: 'https://m.example.com/hot'),
        NovelExploreCategory(
          title: '最近更新',
          url: 'https://m.example.com/new',
        ),
      ];

  @override
  Future<List<NovelItem>> search(String key, {int page = 1}) async => [
        NovelItem(
          bookUrl: 'https://m.example.com/book/1',
          title: '某漫画',
          author: '作者甲',
          coverUrl: 'https://m.example.com/c.jpg',
          intro: '简介',
          kind: '少年 / 连载',
          source: id,
          sourceName: name,
        ),
      ];

  String? lastExploreTitle;

  @override
  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  }) async {
    lastExploreTitle = category.title;
    return search('');
  }

  @override
  Future<NovelItem> bookInfo(NovelItem item) async => item;

  @override
  Future<List<NovelChapter>> chapters(NovelItem item) async => const [
        NovelChapter(title: '第12话 决战', url: 'https://m.example.com/c/12'),
        NovelChapter(title: '序章', url: 'https://m.example.com/c/0'),
      ];

  @override
  Future<List<NovelBlock>> content(
    NovelItem item,
    NovelChapter chapter,
  ) async =>
      const [
        NovelImageBlock('https://m.example.com/p1.jpg'),
        NovelTextBlock('不是图片'),
        NovelImageBlock(
          'https://m.example.com/p2.jpg',
          headers: {'Referer': 'https://m.example.com'},
        ),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('manga_b67');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  group('adapter translation', () {
    final fake = _FakeNovelSource();
    final source = LegadoMangaSource(fake);

    test('identity is namespaced', () {
      expect(source.id, 'legado:https://m.example.com');
      expect(
        LegadoMangaSource.novelIdOf(source.id),
        'https://m.example.com',
      );
      expect(LegadoMangaSource.novelIdOf('js:abc'), isNull);
    });

    test('search maps items (kind → tags + status)', () async {
      final items = await source.search('某');
      expect(items, hasLength(1));
      final item = items.single;
      expect(item.title, '某漫画');
      expect(item.source, source.id);
      expect(item.status, 'ongoing');
      expect(item.tags, containsAll(['少年', '连载']));
    });

    test('updated() prefers the 更新 category', () async {
      await source.updated();
      expect(fake.lastExploreTitle, '最近更新');
      await source.popular();
      expect(fake.lastExploreTitle, '热门');
    });

    test('chapters map with number extraction', () async {
      final manga = (await source.search('某')).single;
      final chapters = await source.chapters(manga);
      expect(chapters[0].chapter, '12');
      expect(chapters[0].id, 'https://m.example.com/c/12');
      expect(chapters[1].chapter, isNull);
      expect(chapters[1].title, '序章');
    });

    test('pages keep only image blocks, with header fallback', () async {
      final manga = (await source.search('某')).single;
      final chapter = (await source.chapters(manga)).first;
      final pages = await source.pages(manga, chapter);
      expect(pages.map((p) => p.url), [
        'https://m.example.com/p1.jpg',
        'https://m.example.com/p2.jpg',
      ]);
      expect(pages[0].headers['User-Agent'], 'UA');
      expect(pages[1].headers['Referer'], 'https://m.example.com');
    });
  });

  test('registry surfaces only type-2 sources, removal routes back',
      () async {
    const pack = '''
[
  {"bookSourceName": "漫画源", "bookSourceUrl": "https://c.example.com",
   "bookSourceType": 2, "searchUrl": "/s?q={{key}}",
   "ruleSearch": {"bookList": ".i", "name": ".n"}},
  {"bookSourceName": "小说源", "bookSourceUrl": "https://n.example.com",
   "bookSourceType": 0, "searchUrl": "/s?q={{key}}",
   "ruleSearch": {"bookList": ".i", "name": ".n"}}
]
''';
    final packResult = await MangaSources.importLegadoPackIfAny(pack);
    expect(packResult, isNotNull);
    expect(packResult!.added, 2);
    expect(packResult.mangaCount, 1);

    final all = MangaSources.all();
    expect(
      all.map((s) => s.id),
      contains('legado:https://c.example.com'),
    );
    expect(
      all.map((s) => s.id),
      isNot(contains('legado:https://n.example.com')),
    );
    expect(MangaSources.byId('legado:https://c.example.com'), isNotNull);
    expect(MangaSources.activeOrNull(), isNotNull);

    await MangaSources.removeInstalled('legado:https://c.example.com');
    expect(NovelSources.byId('https://c.example.com'), isNull);
    expect(
      MangaSources.all().map((s) => s.id),
      isNot(contains('legado:https://c.example.com')),
    );
    // The novel source is untouched by the manga-side removal.
    expect(NovelSources.byId('https://n.example.com'), isNotNull);
  });

  test('a JS payload is not mistaken for a Legado pack', () async {
    final result = await MangaSources.importLegadoPackIfAny(
      'class Foo extends ComicSource { }',
    );
    expect(result, isNull);
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
