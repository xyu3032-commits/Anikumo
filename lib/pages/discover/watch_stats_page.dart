import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/repositories/history_repository.dart';
import 'package:anikumo/services/stats/watch_stats.dart';
import 'package:anikumo/utils/constants.dart';

/// 观看统计 (hub 区二）: totals and a last-7-days chart computed from
/// local playback history (see [computeWatchStats]).
class WatchStatsPage extends StatelessWidget {
  const WatchStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final histories = inject<IHistoryRepository>().getAllHistories();
    final stats = computeWatchStats(histories);
    return Scaffold(
      appBar: const SysAppBar(title: Text('观看统计')),
      body: stats.totalEpisodes == 0
          ? const GeneralEmptyState(
              icon: Icons.bar_chart_rounded,
              title: '还没有观看记录',
            )
          : ListView(
              padding: const EdgeInsets.all(StyleString.pagePadding),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        icon: Icons.play_circle_outline,
                        value: '${stats.totalEpisodes}',
                        label: '看过的集数',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.schedule_outlined,
                        value: _formatMinutes(stats.totalMinutes),
                        label: '观看时长',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.movie_outlined,
                        value: '${stats.distinctAnime}',
                        label: '看过的番剧',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: StyleString.sectionSpace),
                Text(
                  '最近 7 天',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: StyleString.sectionHeaderSpace),
                GlassSurface(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                  child: SizedBox(
                    height: 200,
                    child: _WeekChart(values: stats.last7DaysEpisodes),
                  ),
                ),
                if (stats.mostWatchedWeekday > 0) ...[
                  const SizedBox(height: StyleString.sectionSpace),
                  GlassSurface(
                    padding: const EdgeInsets.all(StyleString.pagePadding),
                    child: Row(
                      children: [
                        const Icon(Icons.favorite_outline),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '你最爱在星期${'一二三四五六日'[stats.mostWatchedWeekday - 1]}看番',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  static String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.values});

  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = values.fold(0, math.max);
    final maxY = math.max(5, (maxValue * 1.25).ceil()).toDouble();
    final today = DateTime.now();
    String dayLabel(int index) {
      final date = today.subtract(Duration(days: 6 - index));
      return '日一二三四五六'[date.weekday % 7];
    }

    return BarChart(
      BarChartData(
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index > 6) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    dayLabel(index),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(7, (index) {
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: values[index].toDouble(),
                width: 18,
                color: scheme.primary,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: scheme.surfaceContainerHighest,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
