import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';

/// Batch 89: tag-matched recommendations for the manga
/// detail page — catalogue name matching and the
/// shared-tag ranking. Pure functions; the page wiring is
/// best-effort glue around them.
MangaItem _item(
  String id, {
  String source = 'probe',
  List<String> tags = const [],
}) {
  return MangaItem(
    id: id,
    title: '漫画$id',
    description: '',
    coverUrl: 'https://img.example.com/$id.jpg',
    author: '',
    status: '',
    year: null,
    tags: tags,
    source: source,
  );
}

const _catalogue = [
  MangaTag(id: 't-action', name: '动作', group: '题材'),
  MangaTag(id: 't-school', name: '校园', group: '题材'),
  MangaTag(id: 't-sf', name: 'Sci-Fi', group: '题材'),
];

void main() {
  group('matchTagsByName', () {
    test('maps display names to catalogue ids, in item order', () {
      final matched = matchTagsByName(['校园', '动作'], _catalogue);
      expect([for (final t in matched) t.id], ['t-school', 't-action']);
    });

    test('trims, ignores case, skips unknowns and duplicates', () {
      final matched = matchTagsByName(
        [' sci-fi ', 'SCI-FI', '不存在', '动作'],
        _catalogue,
      );
      expect([for (final t in matched) t.id], ['t-sf', 't-action']);
    });

    test('empty inputs yield empty results', () {
      expect(matchTagsByName(const [], _catalogue), isEmpty);
      expect(matchTagsByName(['动作'], const []), isEmpty);
    });
  });

  group('rankTagRecommendations', () {
    final current = _item('self', tags: ['动作', '校园']);

    test('drops self and duplicates, ranks by shared tags', () {
      final ranked = rankTagRecommendations(current, [
        _item('a', tags: ['动作']),
        _item('self', tags: ['动作', '校园']),
        _item('b', tags: ['动作', '校园', '热血']),
        _item('a', tags: ['动作']),
        _item('c'),
      ]);
      // b shares 2, a shares 1, c shares 0 (kept: it came
      // from a tag listing, related by construction).
      expect([for (final i in ranked) i.id], ['b', 'a', 'c']);
    });

    test('ties keep the incoming order', () {
      final ranked = rankTagRecommendations(current, [
        _item('x', tags: ['动作']),
        _item('y', tags: ['校园']),
        _item('z', tags: ['动作']),
      ]);
      expect([for (final i in ranked) i.id], ['x', 'y', 'z']);
    });

    test('same id on another source is a different manga', () {
      final ranked = rankTagRecommendations(current, [
        _item('a', source: 's1', tags: ['动作']),
        _item('a', source: 's2', tags: ['动作']),
      ]);
      expect(ranked, hasLength(2));
    });

    test('limit caps the rail', () {
      final ranked = rankTagRecommendations(
        current,
        [for (var i = 0; i < 20; i++) _item('m$i', tags: ['动作'])],
        limit: 5,
      );
      expect(ranked, hasLength(5));
    });

    test('tag comparison is trimmed and case-insensitive', () {
      final ranked = rankTagRecommendations(
        _item('self', tags: ['Sci-Fi']),
        [
          _item('a', tags: [' sci-fi']),
          _item('b', tags: ['其他']),
        ],
      );
      expect([for (final i in ranked) i.id], ['a', 'b']);
    });
  });
}
