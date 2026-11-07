import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';

// Batch 37 regression: explore results keyed by section
// title (copy_manga's shape) must flatten to comics — the
// JS copy_manga home section read as permanently empty.
void main() {
  group('mapJsComicList', () {
    test('title-keyed explore map flattens section lists', () {
      final items = mapJsComicList(
        {
          '推荐': [
            {'id': 'a', 'title': '甲', 'cover': 'https://x/a.jpg'},
            {'id': 'b', 'title': '乙', 'cover': 'https://x/b.jpg'},
          ],
          '热门': [
            {'id': 'c', 'title': '丙', 'cover': 'https://x/c.jpg'},
          ],
        },
        sourceId: 'js:copy_manga',
      );
      expect(items.map((e) => e.id), ['a', 'b', 'c']);
      expect(items.first.source, 'js:copy_manga');
    });

    test('comics key still wins when present', () {
      final items = mapJsComicList(
        {
          'comics': [
            {'id': 'a', 'title': '甲', 'cover': 'https://x/a.jpg'},
          ],
          '推荐': [
            {'id': 'b', 'title': '乙', 'cover': 'https://x/b.jpg'},
          ],
        },
        sourceId: 'js:x',
      );
      expect(items.map((e) => e.id), ['a']);
    });

    test('multi-part section list still flattens', () {
      final items = mapJsComicList(
        [
          {
            'title': '第一部分',
            'comics': [
              {'id': 'a', 'title': '甲', 'cover': 'https://x/a.jpg'},
            ],
          },
        ],
        sourceId: 'js:x',
      );
      expect(items.map((e) => e.id), ['a']);
    });
  });
}
