import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';

/// Batch 90: paged-grid merge policy (the explore grid's
/// false-end fix) and the shuffle helper. The old rule —
/// "a page shorter than requested ends the list" — ended
/// browsing after one page for every source whose own
/// page size differed from ours, and the page number was
/// derived from the item count, which sent 20-per-page
/// sources back to page 1.
MangaItem _item(String id, {String source = 'probe'}) {
  return MangaItem(
    id: id,
    title: '漫画$id',
    description: '',
    coverUrl: 'https://img.example.com/$id.jpg',
    author: '',
    status: '',
    year: null,
    tags: const [],
    source: source,
  );
}

void main() {
  group('nextMangaPageBatch', () {
    test('a short but new page is NOT the end', () {
      final batch = nextMangaPageBatch(
        ['probe:a', 'probe:b'],
        [_item('c'), _item('d'), _item('e')],
      );
      expect([for (final i in batch.additions) i.id], ['c', 'd', 'e']);
      expect(batch.hasMore, isTrue);
    });

    test('an empty page ends the list', () {
      final batch = nextMangaPageBatch(['probe:a'], const []);
      expect(batch.additions, isEmpty);
      expect(batch.hasMore, isFalse);
    });

    test('an all-duplicate page ends the list (source repeats itself)', () {
      final batch = nextMangaPageBatch(
        ['probe:a', 'probe:b'],
        [_item('a'), _item('b')],
      );
      expect(batch.additions, isEmpty);
      expect(batch.hasMore, isFalse);
    });

    test('partial overlap keeps only the new items and continues', () {
      final batch = nextMangaPageBatch(
        ['probe:a', 'probe:b'],
        [_item('b'), _item('c'), _item('c')],
      );
      expect([for (final i in batch.additions) i.id], ['c']);
      expect(batch.hasMore, isTrue);
    });

    test('same id on another source is not a duplicate', () {
      final batch = nextMangaPageBatch(
        ['s1:a'],
        [_item('a', source: 's2')],
      );
      expect(batch.additions, hasLength(1));
      expect(batch.hasMore, isTrue);
    });
  });

  group('shuffledMangaItems', () {
    test('keeps every item exactly once and does not mutate the input', () {
      final input = [for (var i = 0; i < 30; i++) _item('m$i')];
      final before = [for (final i in input) i.id];
      final shuffled = shuffledMangaItems(input);
      expect([for (final i in input) i.id], before);
      expect(shuffled, hasLength(30));
      expect(
        {for (final i in shuffled) i.id},
        {for (final i in input) i.id},
      );
    });

    test('empty and single lists pass through', () {
      expect(shuffledMangaItems(const []), isEmpty);
      expect(shuffledMangaItems([_item('x')]).single.id, 'x');
    });
  });
}
