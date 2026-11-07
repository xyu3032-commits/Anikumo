import 'package:anikumo/modules/history/history_module.dart';

/// Aggregated viewing statistics derived from local playback history.
class WatchStats {
  const WatchStats({
    required this.totalEpisodes,
    required this.totalMinutes,
    required this.distinctAnime,
    required this.last7DaysEpisodes,
    required this.mostWatchedWeekday,
  });

  /// Distinct episodes with any recorded progress, across all anime.
  final int totalEpisodes;

  /// Sum of recorded per-episode progress, in whole minutes. This is
  /// time actually spent in the player, not episode runtime.
  final int totalMinutes;

  /// How many different anime appear in history.
  final int distinctAnime;

  /// Episodes touched per day for the last 7 days, oldest first;
  /// always exactly 7 entries.
  final List<int> last7DaysEpisodes;

  /// Weekday (1 = Monday … 7 = Sunday) with the most episode activity,
  /// or 0 when there is no data.
  final int mostWatchedWeekday;

  static const WatchStats empty = WatchStats(
    totalEpisodes: 0,
    totalMinutes: 0,
    distinctAnime: 0,
    last7DaysEpisodes: <int>[0, 0, 0, 0, 0, 0, 0],
    mostWatchedWeekday: 0,
  );
}

/// Pure aggregation over [histories]; [now] is injectable for tests.
WatchStats computeWatchStats(List<History> histories, {DateTime? now}) {
  if (histories.isEmpty) return WatchStats.empty;
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  var totalEpisodes = 0;
  var totalMinutes = 0;
  final perDay = List<int>.filled(7, 0);
  final perWeekday = List<int>.filled(8, 0);
  for (final history in histories) {
    totalEpisodes += history.progresses.length;
    for (final progress in history.progresses.values) {
      totalMinutes += progress.progress.inMinutes;
      final updatedMs = progress.effectiveUpdatedAtMs(history.lastWatchTime);
      final updated = DateTime.fromMillisecondsSinceEpoch(updatedMs);
      final day = DateTime(updated.year, updated.month, updated.day);
      final daysAgo = today.difference(day).inDays;
      if (daysAgo >= 0 && daysAgo < 7) {
        perDay[6 - daysAgo] += 1;
      }
      perWeekday[updated.weekday] += 1;
    }
  }
  var bestWeekday = 0;
  var bestCount = 0;
  for (var weekday = 1; weekday <= 7; weekday++) {
    if (perWeekday[weekday] > bestCount) {
      bestCount = perWeekday[weekday];
      bestWeekday = weekday;
    }
  }
  return WatchStats(
    totalEpisodes: totalEpisodes,
    totalMinutes: totalMinutes,
    distinctAnime: histories.length,
    last7DaysEpisodes: perDay,
    mostWatchedWeekday: bestWeekday,
  );
}
