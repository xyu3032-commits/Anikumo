import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/repositories/history_repository.dart';
import 'package:anikumo/services/stats/achievements.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// 观看成就： milestones over the local watch history — episodes,
/// hours, distinct titles and active days. Unlocked first, then the
/// closest locked ones with progress bars.
class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final achievements =
        evaluateAchievements(inject<IHistoryRepository>().getAllHistories());
    final unlockedCount = achievements.where((a) => a.unlocked).length;
    return Scaffold(
      appBar: AppBar(title: const Text('观看成就')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          StyleString.pagePadding,
          8,
          StyleString.pagePadding,
          StyleString.sectionSpace,
        ),
        children: [
          GlassSurface(
            strong: true,
            child: Row(
              children: [
                Icon(AnikumoIcons.emoji_events_rounded,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '已解锁 $unlockedCount / ${achievements.length} 个成就',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final achievement in achievements) ...[
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      achievement.unlocked
                          ? AnikumoIcons.verified_rounded
                          : AnikumoIcons.lock_outline_rounded,
                      color: achievement.unlocked
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            achievement.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            achievement.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          if (!achievement.unlocked) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: achievement.progressRatio,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${achievement.current} / ${achievement.threshold}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
