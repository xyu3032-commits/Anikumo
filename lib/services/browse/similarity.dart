import 'package:anikumo/modules/bangumi/bangumi_item.dart';

/// 相似推荐 ranking: candidates sharing more tags with [source] rank
/// higher; rating score and votes break ties. Candidates with no
/// shared tag (and the source itself) are dropped.
List<BangumiItem> rankSimilar(
  BangumiItem source,
  Iterable<BangumiItem> candidates, {
  int limit = 12,
}) {
  final sourceTags = source.tags.map((tag) => tag.name).toSet();
  if (sourceTags.isEmpty) return const [];
  final scored = <({BangumiItem item, int shared})>[];
  for (final candidate in candidates) {
    if (candidate.id == source.id) continue;
    final shared =
        candidate.tags.where((tag) => sourceTags.contains(tag.name)).length;
    if (shared > 0) {
      scored.add((item: candidate, shared: shared));
    }
  }
  scored.sort((a, b) {
    if (a.shared != b.shared) return b.shared.compareTo(a.shared);
    final byScore = b.item.ratingScore.compareTo(a.item.ratingScore);
    if (byScore != 0) return byScore;
    return b.item.votes.compareTo(a.item.votes);
  });
  return scored.take(limit).map((entry) => entry.item).toList();
}
