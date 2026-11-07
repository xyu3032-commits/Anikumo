// Batch 11/13 (+59): multi-source manga — the Venera JS
// source result mappers and source-scoped storage. (The
// native source parser groups were removed in batch 59
// together with the built-in sources.)
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/manga/manga_source.dart';

void main() {
  group('status normalization', () {
    test('maps the spellings sources use', () {
      expect(normalizeMangaStatus('连载中'), 'ongoing');
      expect(normalizeMangaStatus('ONGOING'), 'ongoing');
      expect(normalizeMangaStatus('已完结'), 'completed');
      expect(normalizeMangaStatus(''), '');
    });
  });

  group('venera js source mapping', () {
    test('class name extraction finds the ComicSource subclass', () {
      expect(
        VeneraEngine.extractClassName(
          'class CopyManga extends ComicSource { name = "x"; }',
        ),
        'CopyManga',
      );
      expect(VeneraEngine.extractClassName('var a = 1;'), isNull);
    });

    test('comic objects map with subtitle as author and flat tags', () {
      final item = mapJsComic(
        {
          'id': 'haizeiwan',
          'title': '海贼王',
          'subtitle': '尾田荣一郎',
          'cover': 'https://img.example/c.jpg',
          'tags': ['热血', '冒险'],
          'description': '航海王',
        },
        sourceId: 'js:copy_manga',
      );
      expect(item.id, 'haizeiwan');
      expect(item.author, '尾田荣一郎');
      expect(item.tags, ['热血', '冒险']);
      expect(item.source, 'js:copy_manga');
      expect(item.storageKey, 'js:copy_manga:haizeiwan');
    });

    test('grouped detail tags flatten; list results unwrap comics', () {
      final items = mapJsComicList(
        {
          'comics': [
            {
              'id': '1',
              'title': 'A',
              'tags': {
                '题材': ['热血'],
                '作者': ['某人'],
              },
            },
          ],
        },
        sourceId: 'js:x',
      );
      expect(items.single.tags, ['热血', '某人']);
      expect(mapJsComicList(null, sourceId: 'js:x'), isEmpty);
      expect(mapJsComicList({'comics': []}, sourceId: 'js:x'), isEmpty);
    });

    test('chapters flatten group maps in order and parse numbers', () {
      final chapters = mapJsChapters({
        'chapters': {
          '连载': {'101': '第12话 决战', '100': '第11话'},
          '番外': {'201': '番外篇'},
        },
      });
      expect(chapters.map((c) => c.id), ['101', '100', '201']);
      expect(chapters.first.chapter, '12');
      expect(chapters.last.chapter, isNull);
    });

    test('pages accept plain urls and url+headers objects', () {
      final pages = mapJsPages({
        'images': [
          'https://img.example/1.jpg',
          {
            'url': 'https://img.example/2.jpg',
            'headers': {'Referer': 'https://example.com/'},
          },
        ],
      });
      expect(pages.length, 2);
      expect(pages.last.headers['Referer'], 'https://example.com/');
      expect(mapJsPages(const {}), isEmpty);
    });

    test('categories accept strings and name/key objects', () {
      final tags = mapJsCategories([
        '全部',
        {'name': '热血', 'key': 'rexue'},
      ]);
      expect(tags.map((t) => t.id), ['全部', 'rexue']);
      expect(tags.last.name, '热血');
    });
  });

  group('source-scoped storage', () {
    test('same id from two sources stays two favorites', () {
      final favorites = MangaLibraryCodec.decodeFavorites(
        '[{"id":"1","title":"A","coverUrl":"","source":"zaimanhua"},'
        '{"id":"1","title":"B","coverUrl":"","source":"komiic"}]',
      );
      expect(favorites, hasLength(2));
      expect(favorites.map((f) => f.key).toSet(),
          {'zaimanhua:1', 'komiic:1'});
    });

    test('legacy favorites without a source read as mangadex', () {
      final favorites = MangaLibraryCodec.decodeFavorites(
        '[{"id":"9","title":"Old","coverUrl":""}]',
      );
      expect(favorites.single.source, 'mangadex');
      expect(favorites.single.key, 'mangadex:9');
    });

    test('progress keys are source-scoped, legacy defaults apply', () {
      final progress = MangaLibraryCodec.decodeProgress(
        '{"k1":{"mangaId":"5","mangaSource":"zaimanhua","chapterId":"c",'
        '"chapterLabel":"","page":0,"totalPages":1,"updatedAtMs":1},'
        '"k2":{"mangaId":"5","chapterId":"c","chapterLabel":"",'
        '"page":0,"totalPages":1,"updatedAtMs":2}}',
      );
      expect(progress.keys.toSet(), {'zaimanhua:5', 'mangadex:5'});
    });

    test('item storage key and enrichment keep the source', () {
      const item = MangaItem(
        id: '42',
        title: 't',
        description: '',
        coverUrl: '',
        author: '',
        status: '',
        year: null,
        tags: [],
        source: 'komiic',
      );
      expect(item.storageKey, 'komiic:42');
      expect(item.copyWith(description: 'd').source, 'komiic');
    });
  });
}
