import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/browse/feed_builder.dart';

typedef TestItem = ({int id, double score, int votes});

TestItem item(int id, double score, int votes) =>
    (id: id, score: score, votes: votes);

FeedSection<TestItem>? section(
  String id,
  List<TestItem> trending,
  List<TestItem> ranked,
) {
  return buildFeaturedSection<TestItem>(
    sectionId: id,
    trending: trending,
    ranked: ranked,
    idOf: (i) => i.id,
    scoreOf: (i) => i.score,
    votesOf: (i) => i.votes,
  );
}

/// Batch 81: the featured 「更多」 page used to rebuild the
/// whole tab feed with the cap raised to 72 — 趋势热播，
/// assembled first, consumed every trending item into the
/// shared used-set, so 冷门佳作 (built last) collapsed to a
/// couple of leftovers even though the tab preview showed
/// many. buildFeaturedSection gives each section the full
/// pool.
void main() {
  group('buildFeaturedSection', () {
    // A pool where most trending titles are ALSO hidden gems
    // (high score, low votes) — the starvation scenario.
    final trending = [
      item(1, 9.0, 9000),
      for (var i = 2; i <= 30; i++) item(i, 8.0 + i / 100, 500 + i),
    ];
    final ranked = [
      item(101, 9.5, 20000),
      item(102, 8.8, 400),
      item(103, 7.2, 100),
    ];

    test('hidden gems are not starved by the trending section', () {
      final gems = section('hidden_gems', trending, ranked);
      expect(gems, isNotNull);
      // 29 trending gems + ranked #102; #1/#101 have too many
      // votes, #103 scores too low.
      expect(gems!.items.length, 30);
      expect(gems.items.map((i) => i.id), contains(102));
      expect(gems.items.map((i) => i.id), isNot(contains(1)));
      // Best score first: #102 (8.8) beats the trending gems
      // (8.02-8.30), whose best is #30.
      expect(gems.items.first.id, 102);
      expect(gems.items[1].id, 30);
    });

    test('the tab build of the same pool really does starve them',
        () {
      // Documents the bug this batch fixes: with the tab's
      // cross-section de-dup, trending eats the gem pool.
      final feed = buildFeaturedFeed<TestItem>(
        trending: trending,
        ranked: ranked,
        idOf: (i) => i.id,
        scoreOf: (i) => i.score,
        votesOf: (i) => i.votes,
        sectionLimit: 72,
      );
      final gems =
          feed.sections.where((s) => s.id == 'hidden_gems').firstOrNull;
      expect(gems?.items.length ?? 0, lessThan(5));
    });

    test('top rated keeps its own rule, independent of trending', () {
      final top = section('top_rated', trending, ranked);
      expect(top, isNotNull);
      expect(top!.items.map((i) => i.id), [101]);
    });

    test('trending keeps API order and de-dupes within itself', () {
      final dup = [item(5, 8.0, 10), item(5, 8.0, 10), item(6, 7.0, 10)];
      final result = section('trending', dup, const []);
      expect(result!.items.map((i) => i.id), [5, 6]);
    });

    test('unknown or empty sections return null', () {
      expect(section('nope', trending, ranked), isNull);
      expect(section('hidden_gems', const [], const []), isNull);
      expect(section('trending', const [], ranked), isNull);
    });
  });
}
