import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/search/plugin_search_module.dart';

SearchItem item(String name, String src) => SearchItem(name: name, src: src);

void main() {
  group('dedupeSearchItems', () {
    test('removes exact duplicates, keeping first occurrence order', () {
      final result = dedupeSearchItems([
        item('A', '/a'),
        item('B', '/b'),
        item('A', '/a'),
      ]);
      expect(result.map((e) => e.name), ['A', 'B']);
    });

    test('treats name case and surrounding whitespace as the same entry',
        () {
      final result = dedupeSearchItems([
        item('Title', '/x'),
        item(' title ', '/x'),
      ]);
      expect(result.length, 1);
    });

    test('keeps the same title when targets differ', () {
      final result = dedupeSearchItems([
        item('A', '/a1'),
        item('A', '/a2'),
      ]);
      expect(result.length, 2);
    });

    test('empty list stays empty', () {
      expect(dedupeSearchItems(const []), isEmpty);
    });
  });
}
