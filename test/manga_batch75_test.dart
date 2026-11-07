import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/cross_search_trio.dart';
import 'package:anikumo/services/manga/manga_api.dart';

/// Batch 75: cross-zone search — the auto-switch merge rule
/// and the trio resolution. Pure functions only; the fan-out
/// itself rides the same legs machinery as batch 72.
MangaItem item(String source, String id, String title) => MangaItem(
      id: id,
      title: title,
      description: '',
      coverUrl: '',
      author: '',
      status: '',
      year: null,
      tags: const [],
      source: source,
    );

void main() {
  group('MangaApi.mergeSearchLegs', () {
    test('primary with a relevant hit keeps priority order', () {
      final merged = MangaApi.mergeSearchLegs([
        [item('js:a', '1', '海贼王'), item('js:a', '2', '海贼王 路飞传')],
        [item('js:b', '9', '海贼王')],
      ], '海贼王');
      expect(merged.map((e) => e.source).toList(), ['js:a', 'js:a', 'js:b']);
    });

    test('junk primary auto-switches: fallback leads, primary kept at tail',
        () {
      final junk = [
        for (var i = 0; i < 10; i++) item('js:a', 'j$i', '热门推荐 $i'),
      ];
      final good = [item('js:b', '1', '咒术回战'), item('js:b', '2', '咒术回战 0')];
      final merged = MangaApi.mergeSearchLegs([junk, good], '咒术回战');
      // Fallback results lead…
      expect(merged.first.title, '咒术回战');
      expect(merged[1].title, '咒术回战 0');
      // …and the original source's results are still there,
      // with the reserved tail slice (at most 6).
      final tail = merged.sublist(2);
      expect(tail.length, 6);
      expect(tail.every((e) => e.source == 'js:a'), isTrue);
      expect(merged.length, lessThanOrEqualTo(24));
    });

    test('empty primary lets fallbacks lead without a switch', () {
      final merged = MangaApi.mergeSearchLegs([
        const [],
        [item('js:b', '1', '鬼灭之刃')],
        [item('js:c', '2', '鬼灭之刃 游郭篇')],
      ], '鬼灭之刃');
      expect(merged.map((e) => e.source).toList(), ['js:b', 'js:c']);
    });

    test('nothing relevant anywhere keeps the original order', () {
      final merged = MangaApi.mergeSearchLegs([
        [item('js:a', '1', '随便什么')],
        [item('js:b', '2', '毫不相干')],
      ], '不存在的作品');
      expect(merged.map((e) => e.source).toList(), ['js:a', 'js:b']);
    });

    test('blank keyword never switches', () {
      final merged = MangaApi.mergeSearchLegs([
        [item('js:a', '1', '随便什么')],
        [item('js:b', '2', '毫不相干')],
      ], '  ');
      expect(merged.map((e) => e.source).toList(), ['js:a', 'js:b']);
    });

    test('duplicates by storage key collapse in both modes', () {
      final merged = MangaApi.mergeSearchLegs([
        [item('js:a', '1', '热门推荐')],
        [item('js:b', '1', '海贼王'), item('js:b', '1', '海贼王')],
      ], '海贼王');
      expect(merged.length, 2);
      expect(merged.first.source, 'js:b');
    });

    test('cap applies in priority mode', () {
      final big = [
        for (var i = 0; i < 30; i++) item('js:a', '$i', '海贼王 $i'),
      ];
      final merged = MangaApi.mergeSearchLegs([big], '海贼王', limit: 24);
      expect(merged.length, 24);
    });
  });

  group('cross search trio', () {
    test('decodeCrossSearchIds tolerates junk', () {
      expect(decodeCrossSearchIds(''), isEmpty);
      expect(decodeCrossSearchIds('not json'), isEmpty);
      expect(decodeCrossSearchIds('{"a":1}'), isEmpty);
      expect(decodeCrossSearchIds('["a", 2, ""]'), ['a', '2']);
    });

    test('no pin takes the head of the display order', () {
      final trio = resolveCrossSearchTrio<String>(
        ['a', 'b', 'c', 'd'],
        idOf: (s) => s,
        pinnedIds: const [],
      );
      expect(trio, ['a', 'b', 'c']);
    });

    test('pin picks the chosen sources in display order, capped at 3', () {
      final trio = resolveCrossSearchTrio<String>(
        ['a', 'b', 'c', 'd', 'e'],
        idOf: (s) => s,
        pinnedIds: const ['e', 'c', 'a', 'b'],
      );
      expect(trio, ['a', 'b', 'c']);
    });

    test('pin of only-removed sources falls back to automatic', () {
      final trio = resolveCrossSearchTrio<String>(
        ['a', 'b'],
        idOf: (s) => s,
        pinnedIds: const ['gone'],
      );
      expect(trio, ['a', 'b']);
    });
  });
}
