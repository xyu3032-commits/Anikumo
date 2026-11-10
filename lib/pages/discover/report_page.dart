import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/repositories/history_repository.dart';
import 'package:anikumo/services/stats/report_stats.dart';
import 'package:anikumo/services/stats/watch_stats.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

const _weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const _goalOptions = [3, 5, 7, 10, 15, 20, 30];

/// 观看报告： the current month's viewing — episodes, minutes,
/// active days, favourite tags, busiest weekday — plus the weekly
/// goal progress and a 12-week activity heatmap.
class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  void _shiftMonth(int delta) {
    setState(() {
      var month = _month + delta;
      var year = _year;
      while (month < 1) {
        month += 12;
        year -= 1;
      }
      while (month > 12) {
        month -= 12;
        year += 1;
      }
      _month = month;
      _year = year;
    });
  }

  Future<void> _editGoal(int currentGoal, int weekEpisodes) async {
    final picked = await AnikumoDialog.show<int>(
      builder: (dialogContext) => SimpleDialog(
        title: const Text('每周观看目标'),
        children: [
          for (final option in _goalOptions)
            SimpleDialogOption(
              onPressed: () =>
                  AnikumoDialog.dismiss(context: dialogContext, popWith: option),
              child: Text('每周 $option 集'),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await GStorage.putSetting(SettingsKeys.weeklyGoalEpisodes, picked);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final histories = inject<IHistoryRepository>().getAllHistories();
    final report =
        computeMonthlyReport(histories, year: _year, month: _month);
    final stats = computeWatchStats(histories);
    final weekEpisodes =
        stats.last7DaysEpisodes.fold<int>(0, (sum, count) => sum + count);
    final goal = GStorage.getSetting(SettingsKeys.weeklyGoalEpisodes);
    final heatmap = dailyEpisodeCounts(histories, today: DateTime.now());
    final maxHeat = heatmap.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(title: const Text('观看报告')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          StyleString.pagePadding,
          8,
          StyleString.pagePadding,
          StyleString.sectionSpace,
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(AnikumoIcons.chevron_left_rounded),
              ),
              Text(
                '$_year 年 $_month 月',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              IconButton(
                onPressed: () => _shiftMonth(1),
                icon: const Icon(AnikumoIcons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: _StatTile(
                    label: '本月集数',
                    value: '${report.episodes}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: _StatTile(
                    label: '本月时长',
                    value: report.minutes >= 60
                        ? '${(report.minutes / 60).toStringAsFixed(1)} 小时'
                        : '${report.minutes} 分钟',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: _StatTile(
                    label: '活跃天数',
                    value: '${report.activeDays}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GlassSurface(
            onTap: () => _editGoal(goal, weekEpisodes),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AnikumoIcons.flag_rounded,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '本周目标：$weekEpisodes / $goal 集',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      weekEpisodes >= goal ? '已达成' : '点此修改',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: goal <= 0
                      ? 0
                      : (weekEpisodes / goal).clamp(0, 1).toDouble(),
                ),
              ],
            ),
          ),
          if (report.topTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本月最常看的类型',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final tag in report.topTags)
                        Chip(
                          label: Text('${tag.name} · ${tag.count}'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  if (report.busiestWeekday > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '最爱在${_weekdayNames[report.busiestWeekday]}看番',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            '近 12 周观看热力',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 12,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
            ),
            itemCount: heatmap.length,
            itemBuilder: (context, index) {
              final count = heatmap.values.elementAt(index);
              final intensity =
                  maxHeat == 0 ? 0.0 : (count / maxHeat).clamp(0.0, 1.0);
              return Container(
                decoration: BoxDecoration(
                  color: count == 0
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.primary
                          .withValues(alpha: 0.25 + 0.75 * intensity),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            '颜色越深，那天看得越多',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }
}
