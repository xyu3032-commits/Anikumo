import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/collect/collect_type.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';

/// 即将开播： shows in the 想看 (plan-to-watch) collection whose air
/// date is still ahead, sorted by how soon they start, each with a
/// countdown. Purely local — no network needed.
class ComingPage extends StatelessWidget {
  const ComingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final upcoming = <({BangumiItem item, DateTime airDate, int days})>[];
    for (final entry in GStorage.collectibles.values) {
      if (entry.type != CollectType.planToWatch.value) continue;
      final airDate = DateTime.tryParse(entry.bangumiItem.airDate);
      if (airDate == null) continue;
      final airDay = DateTime(airDate.year, airDate.month, airDate.day);
      final days = airDay.difference(todayDate).inDays;
      if (days < 0) continue;
      upcoming.add((item: entry.bangumiItem, airDate: airDay, days: days));
    }
    upcoming.sort((a, b) => a.days.compareTo(b.days));

    return Scaffold(
      appBar: AppBar(title: const Text('即将开播')),
      body: upcoming.isEmpty
          ? const Center(child: Text('「想看」里没有尚未开播的番'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                StyleString.pagePadding,
                12,
                StyleString.pagePadding,
                StyleString.sectionSpace,
              ),
              itemCount: upcoming.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = upcoming[index];
                final item = entry.item;
                return Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: () =>
                        context.pushNamed('/info/', arguments: item),
                    child: Row(
                      children: [
                        NetworkImgLayer(
                          src: item.images['large'] ?? '',
                          width: 52,
                          height: 70,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bangumiDisplayTitle(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${entry.airDate.year} 年 ${entry.airDate.month} 月 ${entry.airDate.day} 日开播',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Chip(
                            label: Text(
                              entry.days == 0
                                  ? '今天开播'
                                  : '还有 ${entry.days} 天',
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
