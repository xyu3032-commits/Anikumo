import 'package:anikumo/modules/bangumi/bangumi_item.dart';

/// Ordering for the 排行榜 page: Bangumi rank ascending first. A rank
/// of 0 means "not ranked" and sinks below every ranked title; votes
/// break ties so popular unranked titles still surface sensibly.
int compareByBangumiRank(BangumiItem a, BangumiItem b) {
  const unranked = 1 << 30;
  final rankA = a.rank > 0 ? a.rank : unranked;
  final rankB = b.rank > 0 ? b.rank : unranked;
  if (rankA != rankB) return rankA.compareTo(rankB);
  return b.votes.compareTo(a.votes);
}

/// Returns a new list with [items] in leaderboard order.
List<BangumiItem> sortByBangumiRank(Iterable<BangumiItem> items) {
  return [...items]..sort(compareByBangumiRank);
}
