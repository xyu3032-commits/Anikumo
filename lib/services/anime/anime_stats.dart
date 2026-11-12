import 'package:anikumo/modules/history/history_module.dart';

/// Batch 233 （观影报告 pack): watch statistics computed
/// purely from the local anime history — no network, no
/// tracking, just the user's own records read back to
/// them.
class AnimeWatchStats {
  const AnimeWatchStats({
    required this.totalWatchTime,
    required this.titlesWatched,
    required this.episodesWatched,
    required this.lastSevenDays,
    required this.mostWatchedTitle,
    required this.mostWatchedTime,
  });

  /// Sum of per-episode furthest positions.
  final Duration totalWatchTime;
  final int titlesWatched;
  final int episodesWatched;

  /// Watch time per day for the last seven days, oldest
  /// first (index 6 = today). A progress entry counts
  /// toward the day it was last updated.
  final List<Duration> lastSevenDays;

  final String mostWatchedTitle;
  final Duration mostWatchedTime;

  factory AnimeWatchStats.fromHistories(
    List<History> histories, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    var total = Duration.zero;
    var episodes = 0;
    final perTitle = <String, Duration>{};
    final days = List<Duration>.filled(7, Duration.zero);
    final todayStart = DateTime(clock.year, clock.month, clock.day);
    for (final history in histories) {
      var titleTime = Duration.zero;
      for (final progress in history.progresses.values) {
        final watched = progress.progress;
        if (watched <= Duration.zero) continue;
        episodes++;
        total += watched;
        titleTime += watched;
        final updated = DateTime.fromMillisecondsSinceEpoch(
          progress.effectiveUpdatedAtMs(history.lastWatchTime),
        );
        final dayIndex = DateTime(
          updated.year,
          updated.month,
          updated.day,
        ).difference(todayStart).inDays + 6;
        if (dayIndex >= 0 && dayIndex < 7) {
          days[dayIndex] += watched;
        }
      }
      if (titleTime > Duration.zero) {
        final name = history.bangumiItem.nameCn.isNotEmpty
            ? history.bangumiItem.nameCn
            : history.bangumiItem.name;
        perTitle[name] = titleTime;
      }
    }
    var bestTitle = '';
    var bestTime = Duration.zero;
    perTitle.forEach((title, time) {
      if (time > bestTime) {
        bestTitle = title;
        bestTime = time;
      }
    });
    return AnimeWatchStats(
      totalWatchTime: total,
      titlesWatched: perTitle.length,
      episodesWatched: episodes,
      lastSevenDays: days,
      mostWatchedTitle: bestTitle,
      mostWatchedTime: bestTime,
    );
  }
}

/// "12 小时 34 分钟" style formatting for the report.
String formatWatchDuration(Duration d) {
  if (d.inHours >= 1) {
    return '${d.inHours} 小时 ${d.inMinutes % 60} 分钟';
  }
  if (d.inMinutes >= 1) return '${d.inMinutes} 分钟';
  return '${d.inSeconds} 秒';
}
