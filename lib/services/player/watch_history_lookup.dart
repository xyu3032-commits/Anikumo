import 'package:anikumo/modules/history/history_module.dart';

/// Batch 134: pure lookups over the stored watch history,
/// backing the episode picker's memory — which line to open
/// by default, which episodes were watched on it, and how
/// far through each one the user got.

bool _isOnline(History history) =>
    HistoryEntryKind.normalize(history.entryKind) ==
    HistoryEntryKind.online;

/// The most recently watched ONLINE history record for
/// [bangumiId] across all sources, or null when the anime
/// was never watched. "Most recent" is the record's own
/// lastWatchTime — with records from several sources, the
/// newest one is the line the user actually used last.
History? latestOnlineHistory(Iterable<History> all, int bangumiId) {
  History? best;
  for (final history in all) {
    if (history.bangumiItem.id != bangumiId || !_isOnline(history)) {
      continue;
    }
    if (best == null || history.lastWatchTime.isAfter(best.lastWatchTime)) {
      best = history;
    }
  }
  return best;
}

/// The latest ONLINE record for one source ([pluginName]),
/// or null when that source never played this anime.
History? historyForPlugin(
  Iterable<History> all,
  int bangumiId,
  String pluginName,
) {
  History? best;
  for (final history in all) {
    if (history.bangumiItem.id != bangumiId ||
        !_isOnline(history) ||
        history.adapterName != pluginName) {
      continue;
    }
    if (best == null || history.lastWatchTime.isAfter(best.lastWatchTime)) {
      best = history;
    }
  }
  return best;
}

/// The road the user watched most recently on [history]'s
/// source (by per-episode progress timestamps), clamped to
/// [roadCount]. 0 when there is nothing to go on.
int preferredRoadIndex(History? history, int roadCount) {
  if (history == null || roadCount <= 0) return 0;
  Progress? latest;
  for (final progress in history.progresses.values) {
    if (latest == null ||
        progress.effectiveUpdatedAtMs(history.lastWatchTime) >
            latest.effectiveUpdatedAtMs(history.lastWatchTime)) {
      latest = progress;
    }
  }
  final road = latest?.road ?? 0;
  return road.clamp(0, roadCount - 1);
}

/// Watched durations by episode number for one [road] of
/// [history]'s source. Only episodes with real progress
/// (> 0) count as watched.
Map<int, Duration> watchedDurations(History? history, int road) {
  if (history == null) return const {};
  return {
    for (final entry in history.progresses.entries)
      if (entry.value.road == road && entry.value.progress > Duration.zero)
        entry.key: entry.value.progress,
  };
}

/// How far through an episode the grey fill reaches:
/// watched / total, clamped to [0, 1]. 0 when either side
/// is unknown — a missing total must not fake a fill.
double watchFraction(Duration watched, int totalMinutes) {
  if (watched <= Duration.zero || totalMinutes <= 0) return 0;
  final fraction = watched.inSeconds / (totalMinutes * 60);
  return fraction.clamp(0.0, 1.0);
}

/// m:ss under an hour, h:mm:ss above — the compact clock
/// shown beside episode numbers.
String formatWatchClock(Duration duration) {
  final total = duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// The duration label riding at the right of 第N集:
/// "12:34 / 24:00" when both sides are known, "已看 12:34"
/// with only progress, "24:00" with only a total, '' with
/// neither.
String episodeDurationLabel({
  required Duration? watched,
  required int totalMinutes,
}) {
  final total = totalMinutes > 0
      ? formatWatchClock(Duration(minutes: totalMinutes))
      : '';
  if (watched != null && watched > Duration.zero) {
    final seen = formatWatchClock(watched);
    return total.isEmpty ? '已看 $seen' : '$seen / $total';
  }
  return total;
}
