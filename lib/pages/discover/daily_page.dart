import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/repositories/history_repository.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/browse/daily_picks.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// 每日推荐： from trends and this week's calendar, a deterministic
/// sample changes once a day. Titles already in the watch history
/// are excluded — recommendations should be new to the user.
class DailyPage extends StatefulWidget {
  const DailyPage({super.key});

  @override
  State<DailyPage> createState() => _DailyPageState();
}

class _DailyPageState extends State<DailyPage> {
  List<BangumiItem> _picks = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pool = <int, BangumiItem>{};
      final trends = await BangumiApi.getBangumiTrendsList(limit: 50, offset: 0);
      for (final item in trends) {
        pool[item.id] = item;
      }
      final calendar = await BangumiApi.getCalendar();
      for (final dayItems in calendar) {
        for (final item in dayItems) {
          pool[item.id] = item;
        }
      }
      final watchedIds = inject<IHistoryRepository>()
          .getAllHistories()
          .map((history) => history.bangumiItem.id)
          .toSet();
      if (!mounted) return;
      setState(() {
        _picks = dailyPicks(
          pool.values.toList(),
          date: DateTime.now(),
          count: 9,
          excludeIds: watchedIds,
        );
        _loading = false;
        _failed = pool.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('每日推荐')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? const Center(child: Text('加载失败，请检查网络后重试'))
              : ListView(
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
                          Icon(AnikumoIcons.auto_awesome_rounded,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${now.month} 月 ${now.day} 日 · 今天这几部值得一看，每天零点更新',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: bangumiGridDelegate(context),
                      itemCount: _picks.length,
                      itemBuilder: (context, index) =>
                          BangumiCardV(bangumiItem: _picks[index]),
                    ),
                  ],
                ),
    );
  }
}

/// Shared responsive grid geometry for discover sub-pages, matching
/// the discover hub's tag grid.
SliverGridDelegateWithFixedCrossAxisCount bangumiGridDelegate(
    BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final count = width < 600
      ? 3
      : width < 900
          ? 5
          : 6;
  final cellWidth =
      (width - StyleString.pagePadding * 2 - (count - 1) * 8) / count;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: count,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    mainAxisExtent: cellWidth / 0.65 + 32,
  );
}
