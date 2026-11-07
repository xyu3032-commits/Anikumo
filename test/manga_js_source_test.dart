import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';

void main() {
  _batch16MapperTests();
}


void _batch16MapperTests() {
  group('batch16 mapper hardening (harness-verified shapes)', () {
    test('explore sections flatten to comics', () {
      final items = mapJsComicList([
        {
          'title': 'Popular',
          'comics': [
            {'id': 'a', 'title': 'A', 'cover': 'ca'},
            {'id': 'b', 'title': 'B', 'cover': 'cb'},
          ],
          'viewMore': null,
        },
        {
          'title': 'Recent',
          'comics': [
            {'id': 'c', 'title': 'C', 'cover': 'cc'},
          ],
        },
      ], sourceId: 'js:x');
      expect(items.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('map with sections key flattens too', () {
      final items = mapJsComicList({
        'sections': [
          {
            'title': 'S',
            'comics': [
              {'id': 'z', 'title': 'Z', 'cover': 'cz'},
            ],
          },
        ],
      }, sourceId: 'js:x');
      expect(items.single.id, 'z');
    });

    test('flat chapter map {epId: title} parses', () {
      final chapters = mapJsChapters({
        'chapters': {'10': '第10话', '9': '第9话'},
      });
      expect(chapters.map((c) => c.id), ['10', '9']);
      expect(chapters.first.title, '第10话');
    });

    test('comic envelope unwraps for details and chapters', () {
      final unwrapped = unwrapJsDetails({
        'comic': {
          'title': 'T',
          'chapters': {
            '正文': {'1': '第1话'},
          },
        },
      });
      expect(unwrapped['title'], 'T');
      final chapters = mapJsChapters(unwrapped);
      expect(chapters.single.id, '1');
    });

    test('cover and title fallback keys', () {
      final item = mapJsComic(
        {'id': '1', 'name': 'N', 'coverUrl': 'u'},
        sourceId: 'js:x',
      );
      expect(item.title, 'N');
      expect(item.coverUrl, 'u');
    });

    test('pages accept urls key', () {
      final pages = mapJsPages({
        'urls': ['https://x/1.jpg'],
      });
      expect(pages.single.url, 'https://x/1.jpg');
    });
  });
}
