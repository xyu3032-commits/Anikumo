import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/browse/feed_builder.dart';

typedef TestItem = ({int id, double score, int votes});

TestItem item(int id, double score, int votes) =>
    (id: id, score: score, votes: votes);

FeaturedFeed<TestItem> build(List<TestItem> trending, List<TestItem> ranked) {
  return buildFeaturedFeed<TestItem>(
    trending: trending,
    ranked: ranked,
    idOf: (i) => i.id,
    scoreOf: (i) => i.score,
    votesOf: (i) => i.votes,
  );
}

void main() {
  group('buildFeaturedFeed', () {
    test('hero is the first trending item and appears nowhere else', () {
      final feed = build(
        [item(1, 8.0, 9000), item(2, 7.0, 100), item(3, 6.5, 50)],
        [item(1, 8.0, 9000), item(4, 9.0, 20000)],
      );
      expect(feed.hero?.id, 1);
      final sectionIds =
          feed.sections.expand((s) => s.items).map((i) => i.id).toList();
      expect(sectionIds.contains(1), isFalse);
      expect(feed.sections.first.id, 'trending');
      expect(feed.sections.first.items.map((i) => i.id), [2, 3]);
    });

    test('top rated sorts by score then votes and skips used items', () {
      final feed = build(
        [item(1, 8.0, 9000)],
        [
          item(2, 8.5, 5000),
          item(3, 9.1, 4000),
          item(4, 9.1, 8000),
          item(1, 8.0, 9000),
          // High score but too few votes: belongs to hidden gems, not here.
          item(5, 9.3, 200),
        ],
      );
      final topRated =
          feed.sections.firstWhere((s) => s.id == 'top_rated').items;
      expect(topRated.map((i) => i.id), [4, 3, 2]);
    });

    test('hidden gems need score >= 7.5 and few votes, fresh only', () {
      final feed = build(
        [item(1, 8.0, 9000), item(2, 8.8, 1200)],
        [item(3, 9.0, 2500), item(4, 7.4, 100), item(5, 8.9, 20000)],
      );
      final gems = feed.sections.firstWhere((s) => s.id == 'hidden_gems').items;
      // 2 was consumed by trending, 4 is below 7.5, 5 has too many votes.
      expect(gems.map((i) => i.id), [3]);
    });

    test('empty inputs produce an empty feed', () {
      final feed = build([], []);
      expect(feed.hero, isNull);
      expect(feed.isEmpty, isTrue);
    });

    test('no duplicate ids across the whole feed', () {
      final feed = build(
        [item(1, 8.0, 9000), item(2, 8.8, 1200), item(2, 8.8, 1200)],
        [item(2, 8.8, 1200), item(3, 9.0, 2500), item(1, 8.0, 9000)],
      );
      final allIds = [
        if (feed.hero != null) feed.hero!.id,
        ...feed.sections.expand((s) => s.items).map((i) => i.id),
      ];
      expect(allIds.toSet().length, allIds.length);
    });
  });

  group('TagRotation', () {
    test('batches never repeat until the pool is exhausted', () {
      final tags = [for (var i = 0; i < 15; i++) 'tag$i'];
      final rotation = TagRotation(tags, batchSize: 8, random: Random(42));
      final first = rotation.nextBatch();
      final second = rotation.nextBatch();
      expect(first.length, 8);
      expect(second.length, 7);
      expect({...first, ...second}.length, 15);
      // Third batch starts a fresh cycle and is full again.
      expect(rotation.nextBatch().length, 8);
    });

    test('dedupes and drops empty tags', () {
      final rotation = TagRotation(['a', 'a', '', 'b'], batchSize: 8);
      expect(rotation.totalCount, 2);
      expect(rotation.nextBatch().toSet(), {'a', 'b'});
    });

    test('empty tag list yields empty batches', () {
      final rotation = TagRotation(const []);
      expect(rotation.nextBatch(), isEmpty);
    });
  });
}
