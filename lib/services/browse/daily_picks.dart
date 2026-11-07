import 'dart:math';

import 'package:anikumo/modules/bangumi/bangumi_item.dart';

/// 每日推荐 selection: a deterministic pseudo-random sample of [pool]
/// for [date]. The seed is the calendar date, so the picks are stable
/// across app restarts on the same day and change overnight — no
/// storage and no server involved.
List<BangumiItem> dailyPicks(
  List<BangumiItem> pool, {
  required DateTime date,
  int count = 6,
  Set<int> excludeIds = const {},
}) {
  final candidates =
      pool.where((item) => !excludeIds.contains(item.id)).toList();
  if (candidates.length <= count) return candidates;
  final seed = date.year * 10000 + date.month * 100 + date.day;
  final random = Random(seed);
  final shuffled = [...candidates];
  // Partial Fisher–Yates: only the first [count] positions matter.
  for (var i = 0; i < count; i++) {
    final j = i + random.nextInt(shuffled.length - i);
    final tmp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }
  return shuffled.sublist(0, count);
}
