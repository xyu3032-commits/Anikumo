import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:anikumo/repositories/history_repository.dart';
import 'package:anikumo/services/anime/anime_stats.dart';

/// Batch 233 （观影报告 pack): the watch report page —
/// exists only while the pack is installed (the entry in
/// 扩展设置 is gated, and this page double-checks via the
/// caller's navigation). All numbers come from the local
/// history store.
class AnimeStatsPage extends StatelessWidget {
  const AnimeStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final histories = inject<IHistoryRepository>().getAllHistories();
    final stats = AnimeWatchStats.fromHistories(histories);
    final theme = Theme.of(context);
    final maxDay = stats.lastSevenDays.fold<Duration>(
      Duration.zero,
      (a, b) => b > a ? b : a,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('观影报告')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            '累计观看 ${formatWatchDuration(stats.totalWatchTime)}',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            '共 ${stats.titlesWatched} 部番 · ${stats.episodesWatched} 集'
            '（按本机历史里每集的最远进度统计）',
            style: theme.textTheme.bodySmall,
          ),
          if (stats.mostWatchedTitle.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('看得最多', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '《${stats.mostWatchedTitle}》 · '
              '${formatWatchDuration(stats.mostWatchedTime)}',
            ),
          ],
          const SizedBox(height: 24),
          Text('最近 7 天', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: maxDay.inMilliseconds == 0
                                ? 2
                                : 8 +
                                    72 *
                                        (stats.lastSevenDays[i]
                                                .inMilliseconds /
                                            maxDay.inMilliseconds),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: i == 6 ? 1 : 0.45),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            i == 6 ? '今天' : '${6 - i}天前',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '柱子按每集最后更新的那天归集，是大致节奏，不是精确账单。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
