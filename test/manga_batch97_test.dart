import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';

// Batch 97: the 猜你喜欢 taste profile + ranker. The old
// rail keyed off one seed and its first tag; these tests
// pin the new contract — generic format/status tags never
// drive, weights accumulate across seeds, candidates that
// share nothing measurable are dropped (not tailed), and
// tag-less pools fall back to source order.
MangaItem _item(String id, List<String> tags) => MangaItem(
      id: id,
      title: 'T$id',
      description: '',
      coverUrl: '',
      author: '',
      status: '',
      year: 0,
      tags: tags,
      source: 's',
    );

void main() {
  group('buildMangaTasteProfile', () {
    test('generic tags are excluded, weights accumulate', () {
      final profile = buildMangaTasteProfile([
        (tags: ['热血', '全彩', '连载'], weight: 2),
        (tags: ['热血', '校园'], weight: 1),
      ]);
      expect(profile.weights, {'热血': 3.0, '校园': 1.0});
      expect(profile.display['热血'], '热血');
    });

    test('names normalize case/space and dedupe within a seed', () {
      final profile = buildMangaTasteProfile([
        (tags: [' Action ', 'action', 'ACTION'], weight: 1),
      ]);
      expect(profile.weights, {'action': 1.0});
    });

    test('english generic labels are excluded too', () {
      final profile = buildMangaTasteProfile([
        (tags: ['Completed', 'Webtoon', 'Drama'], weight: 1),
      ]);
      expect(profile.weights, {'drama': 1.0});
    });
  });

  group('rankForYouCandidates', () {
    final profile = {'热血': 3.0, '校园': 1.0};

    test('zero-overlap candidates are dropped, best first', () {
      final ranked = rankForYouCandidates(
        profile: profile,
        candidates: [
          _item('a', ['校园']),
          _item('b', ['恋爱']),
          _item('c', ['热血', '校园']),
          _item('d', ['热血']),
        ],
        excludeKeys: const {},
      );
      expect(ranked.map((e) => e.id), ['c', 'd', 'a']);
    });

    test('exclusions and duplicates are removed', () {
      final ranked = rankForYouCandidates(
        profile: profile,
        candidates: [
          _item('a', ['热血']),
          _item('a', ['热血']),
          _item('b', ['热血']),
        ],
        excludeKeys: {'s:b'},
      );
      expect(ranked.map((e) => e.id), ['a']);
    });

    test('tag-less candidates cannot be judged when others have tags',
        () {
      final ranked = rankForYouCandidates(
        profile: profile,
        candidates: [
          _item('a', []),
          _item('b', ['热血']),
        ],
        excludeKeys: const {},
      );
      expect(ranked.map((e) => e.id), ['b']);
    });

    test('a fully tag-less pool keeps the source order', () {
      final ranked = rankForYouCandidates(
        profile: profile,
        candidates: [_item('a', []), _item('b', []), _item('c', [])],
        excludeKeys: const {},
        limit: 2,
      );
      expect(ranked.map((e) => e.id), ['a', 'b']);
    });
  });
}
