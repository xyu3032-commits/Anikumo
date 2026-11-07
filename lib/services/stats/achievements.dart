import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/services/stats/watch_stats.dart';

/// One milestone on the 观看成就 page.
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.current,
    required this.threshold,
  });

  final String id;
  final String title;
  final String description;

  /// Current progress value (episodes / hours / titles / days).
  final int current;

  /// Value at which the achievement unlocks.
  final int threshold;

  bool get unlocked => current >= threshold;

  double get progressRatio =>
      threshold <= 0 ? 1 : (current / threshold).clamp(0, 1).toDouble();
}

class _Milestone {
  const _Milestone(this.threshold, this.title, this.description);

  final int threshold;
  final String title;
  final String description;
}

/// Evaluates every milestone against the user's history. Unlocked
/// achievements come first (highest tier first within each series is
/// NOT guaranteed — series order is preserved), then locked ones by
/// closeness to unlocking.
List<Achievement> evaluateAchievements(List<History> histories) {
  final stats = computeWatchStats(histories);
  final activeDays = _activeDays(histories);
  final hours = stats.totalMinutes ~/ 60;

  Achievement build(String series, _Milestone m, int current) {
    return Achievement(
      id: '$series-${m.threshold}',
      title: m.title,
      description: m.description,
      current: current,
      threshold: m.threshold,
    );
  }

  final all = <Achievement>[
    for (final m in const [
      _Milestone(10, '初露锋芒', '累计看过 10 集'),
      _Milestone(50, '渐入佳境', '累计看过 50 集'),
      _Milestone(100, '百集斩', '累计看过 100 集'),
      _Milestone(300, '追番达人', '累计看过 300 集'),
      _Milestone(500, '五百集传说', '累计看过 500 集'),
      _Milestone(1000, '千集王', '累计看过 1000 集'),
    ])
      build('episodes', m, stats.totalEpisodes),
    for (final m in const [
      _Milestone(10, '十小时俱乐部', '累计观看 10 小时'),
      _Milestone(50, '沉浸者', '累计观看 50 小时'),
      _Milestone(100, '百小时修行', '累计观看 100 小时'),
      _Milestone(300, '时间领主', '累计观看 300 小时'),
    ])
      build('hours', m, hours),
    for (final m in const [
      _Milestone(5, '初探异世界', '看过 5 部番剧'),
      _Milestone(20, '阅番无数', '看过 20 部番剧'),
      _Milestone(50, '活字片单', '看过 50 部番剧'),
      _Milestone(100, '百番斩', '看过 100 部番剧'),
    ])
      build('titles', m, stats.distinctAnime),
    for (final m in const [
      _Milestone(7, '一周不断更', '有观看记录的天数达到 7 天'),
      _Milestone(30, '月度常客', '有观看记录的天数达到 30 天'),
      _Milestone(100, '百日追番', '有观看记录的天数达到 100 天'),
    ])
      build('days', m, activeDays),
  ];

  final unlocked = all.where((a) => a.unlocked).toList();
  final locked = all.where((a) => !a.unlocked).toList()
    ..sort((a, b) => b.progressRatio.compareTo(a.progressRatio));
  return [...unlocked, ...locked];
}

int _activeDays(List<History> histories) {
  final days = <int>{};
  for (final history in histories) {
    for (final progress in history.progresses.values) {
      final updatedMs = progress.effectiveUpdatedAtMs(history.lastWatchTime);
      final updated = DateTime.fromMillisecondsSinceEpoch(updatedMs);
      days.add(updated.year * 10000 + updated.month * 100 + updated.day);
    }
  }
  return days.length;
}
