/// Pure feed-assembly logic for the browse pages （精选/发现）.
///
/// Kept generic and dependency-free so the section rules can be unit
/// tested without Flutter or network: pages pass Bangumi items plus
/// three small accessors, tests pass plain records.
///
/// Section rules for the featured feed (priority order, no item ever
/// appears twice on the page — hero tags and cards share Hero animations
/// keyed by item id, so duplicates would also break transitions):
/// 1. hero: the first trending item.
/// 2. 趋势热播： remaining trending items, in API order.
/// 3. 高分口碑： ranked items with at least 3000 votes (crowd-validated),
///    re-sorted by score (then votes), fresh only.
/// 4. 冷门佳作： score >= 7.5 with fewer than 3000 votes, fresh only,
///    best score first, fewer votes first on ties.
/// The vote-count split makes sections 3 and 4 disjoint by construction,
/// so neither can starve the other.
library;

import 'dart:math';

class FeedSection<T> {
  const FeedSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<T> items;
}

class FeaturedFeed<T> {
  const FeaturedFeed({required this.hero, required this.sections});

  final T? hero;
  final List<FeedSection<T>> sections;

  bool get isEmpty =>
      hero == null && sections.every((s) => s.items.isEmpty);
}

FeaturedFeed<T> buildFeaturedFeed<T>({
  required List<T> trending,
  required List<T> ranked,
  required int Function(T item) idOf,
  required double Function(T item) scoreOf,
  required int Function(T item) votesOf,
  int sectionLimit = 12,
}) {
  final usedIds = <int>{};

  List<T> takeFresh(Iterable<T> source, {int? limit}) {
    final result = <T>[];
    for (final item in source) {
      if (limit != null && result.length >= limit) break;
      if (usedIds.add(idOf(item))) result.add(item);
    }
    return result;
  }

  T? hero;
  for (final item in trending) {
    if (usedIds.add(idOf(item))) {
      hero = item;
      break;
    }
  }

  final sections = <FeedSection<T>>[];

  final trendingItems = takeFresh(trending, limit: sectionLimit);
  if (trendingItems.isNotEmpty) {
    sections.add(FeedSection(
      id: 'trending',
      title: '趋势热播',
      subtitle: '正在被大家追的番',
      items: trendingItems,
    ));
  }

  final byScore = ranked.toList()
    ..sort((a, b) {
      final byScoreDesc = scoreOf(b).compareTo(scoreOf(a));
      if (byScoreDesc != 0) return byScoreDesc;
      final byVotesDesc = votesOf(b).compareTo(votesOf(a));
      if (byVotesDesc != 0) return byVotesDesc;
      return idOf(a).compareTo(idOf(b));
    });
  final topRatedItems = takeFresh(
    byScore.where((item) => scoreOf(item) > 0 && votesOf(item) >= 3000),
    limit: sectionLimit,
  );
  if (topRatedItems.isNotEmpty) {
    sections.add(FeedSection(
      id: 'top_rated',
      title: '高分口碑',
      subtitle: '评分与评价人数都靠前',
      items: topRatedItems,
    ));
  }

  final gemPool = <T>[];
  final gemSeen = <int>{};
  for (final item in [...trending, ...ranked]) {
    if (gemSeen.add(idOf(item))) gemPool.add(item);
  }
  final gems = gemPool
      .where((item) => scoreOf(item) >= 7.5 && votesOf(item) > 0 && votesOf(item) < 3000)
      .toList()
    ..sort((a, b) {
      final byScoreDesc = scoreOf(b).compareTo(scoreOf(a));
      if (byScoreDesc != 0) return byScoreDesc;
      final byVotesAsc = votesOf(a).compareTo(votesOf(b));
      if (byVotesAsc != 0) return byVotesAsc;
      return idOf(a).compareTo(idOf(b));
    });
  final gemItems = takeFresh(gems, limit: sectionLimit);
  if (gemItems.isNotEmpty) {
    sections.add(FeedSection(
      id: 'hidden_gems',
      title: '冷门佳作',
      subtitle: '分数很高，看的人还不多',
      items: gemItems,
    ));
  }

  return FeaturedFeed(hero: hero, sections: sections);
}

/// Batch 81: assembles ONE featured section from the full
/// pool, for the section's 「更多」 page.
///
/// [buildFeaturedFeed] de-dupes ACROSS sections — right for
/// the tab, where no card may repeat on one screen. The more
/// page originally reused it with the cap raised, so the
/// sections assembled earlier （趋势热播 first, then 高分口碑）
/// consumed the shared pool and starved the later ones:
/// 冷门佳作， built last, collapsed to a couple of leftovers
/// while the tab's own preview showed many. Here each
/// section sees the whole pool; de-dup only happens within
/// the section itself. Section rules mirror
/// [buildFeaturedFeed] exactly.
FeedSection<T>? buildFeaturedSection<T>({
  required String sectionId,
  required List<T> trending,
  required List<T> ranked,
  required int Function(T item) idOf,
  required double Function(T item) scoreOf,
  required int Function(T item) votesOf,
  int limit = 72,
}) {
  List<T> dedup(Iterable<T> source) {
    final seen = <int>{};
    return [
      for (final item in source)
        if (seen.add(idOf(item))) item,
    ];
  }

  switch (sectionId) {
    case 'trending':
      final items = dedup(trending).take(limit).toList();
      if (items.isEmpty) return null;
      return FeedSection(
        id: 'trending',
        title: '趋势热播',
        subtitle: '正在被大家追的番',
        items: items,
      );
    case 'top_rated':
      final items = dedup(ranked
              .where((item) => scoreOf(item) > 0 && votesOf(item) >= 3000))
          .toList()
        ..sort((a, b) {
          final byScoreDesc = scoreOf(b).compareTo(scoreOf(a));
          if (byScoreDesc != 0) return byScoreDesc;
          final byVotesDesc = votesOf(b).compareTo(votesOf(a));
          if (byVotesDesc != 0) return byVotesDesc;
          return idOf(a).compareTo(idOf(b));
        });
      final capped = items.take(limit).toList();
      if (capped.isEmpty) return null;
      return FeedSection(
        id: 'top_rated',
        title: '高分口碑',
        subtitle: '评分与评价人数都靠前',
        items: capped,
      );
    case 'hidden_gems':
      final pool = dedup([...trending, ...ranked]);
      final gems = pool
          .where((item) =>
              scoreOf(item) >= 7.5 && votesOf(item) > 0 && votesOf(item) < 3000)
          .toList()
        ..sort((a, b) {
          final byScoreDesc = scoreOf(b).compareTo(scoreOf(a));
          if (byScoreDesc != 0) return byScoreDesc;
          final byVotesAsc = votesOf(a).compareTo(votesOf(b));
          if (byVotesAsc != 0) return byVotesAsc;
          return idOf(a).compareTo(idOf(b));
        });
      final capped = gems.take(limit).toList();
      if (capped.isEmpty) return null;
      return FeedSection(
        id: 'hidden_gems',
        title: '冷门佳作',
        subtitle: '分数很高，看的人还不多',
        items: capped,
      );
  }
  return null;
}

/// Rotates the discover page's tag chips: every batch is drawn from a
/// shuffled pool without repetition until the pool is exhausted, then
/// the pool is reshuffled. 「换一批」 therefore always shows new tags
/// until every tag has been offered once.
class TagRotation {
  TagRotation(
    List<String> tags, {
    this.batchSize = 8,
    Random? random,
  })  : _random = random ?? Random(),
        _tags = _dedupe(tags) {
    _reshuffle();
  }

  final int batchSize;
  final Random _random;
  final List<String> _tags;
  List<String> _pool = [];
  int _cursor = 0;

  int get totalCount => _tags.length;

  static List<String> _dedupe(List<String> tags) {
    final seen = <String>{};
    return [
      for (final tag in tags)
        if (tag.isNotEmpty && seen.add(tag)) tag,
    ];
  }

  void _reshuffle() {
    _pool = _tags.toList()..shuffle(_random);
    _cursor = 0;
  }

  List<String> nextBatch() {
    if (_tags.isEmpty) return const [];
    if (_cursor >= _pool.length) _reshuffle();
    final batch = _pool.skip(_cursor).take(batchSize).toList();
    _cursor += batch.length;
    return List.unmodifiable(batch);
  }
}
