import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/collect/collect_module.dart';
import 'package:anikumo/modules/collect/collect_type.dart';
import 'package:anikumo/pages/discover/daily_page.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/share/share_builders.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';

const _weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 更新中心： the intersection of "shows I am watching" and this
/// week's broadcast calendar — what updates today, what is still
/// coming this week — plus an .ics export of the whole schedule.
class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  bool _loading = true;
  bool _failed = false;

  /// weekday (1-7) -> watching shows airing that day.
  Map<int, List<BangumiItem>> _byWeekday = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<CollectedBangumi> get _watching {
    return GStorage.collectibles.values
        .where((entry) => entry.type == CollectType.watching.value)
        .toList();
  }

  Future<void> _load() async {
    try {
      final watchingIds = _watching.map((entry) => entry.bangumiItem.id).toSet();
      final calendar = await BangumiApi.getCalendar();
      final byWeekday = <int, List<BangumiItem>>{};
      for (var i = 0; i < calendar.length && i < 7; i++) {
        final items = calendar[i]
            .where((item) => watchingIds.contains(item.id))
            .toList();
        if (items.isNotEmpty) {
          byWeekday[i + 1] = items;
        }
      }
      if (!mounted) return;
      setState(() {
        _byWeekday = byWeekday;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _exportIcs() async {
    final shows = _watching
        .map((entry) => (
              item: entry.bangumiItem,
              weekday: entry.bangumiItem.airWeekday,
            ))
        .where((show) => show.weekday >= 1 && show.weekday <= 7)
        .toList();
    if (shows.isEmpty) {
      AnikumoDialog.showToast(message: '在看的番剧没有可用的放送星期信息');
      return;
    }
    final ics = buildBangumiCalendarIcs(shows, fromDate: DateTime.now());
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出放送日历',
      fileName: 'anikumo-bangumi-calendar.ics',
      bytes: utf8.encode(ics),
    );
    if (path != null) {
      AnikumoDialog.showToast(message: '已导出 ${shows.length} 部番的放送日历');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayWeekday = DateTime.now().weekday;
    final todayItems = _byWeekday[todayWeekday] ?? const <BangumiItem>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('更新中心'),
        actions: [
          IconButton(
            onPressed: _exportIcs,
            icon: const Icon(Icons.event_available_rounded),
            tooltip: '导出放送日历 (.ics)',
          ),
        ],
      ),
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
                          Icon(Icons.update_rounded,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              todayItems.isEmpty
                                  ? '今天没有在看的番更新，看看本周还有什么'
                                  : '今天有 ${todayItems.length} 部在看的番更新',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (todayItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 168,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: todayItems.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) => SizedBox(
                            width: 112,
                            child: BangumiCardV(
                                bangumiItem: todayItems[index]),
                          ),
                        ),
                      ),
                    ],
                    for (var weekday = 1; weekday <= 7; weekday++)
                      if ((_byWeekday[weekday] ?? const []).isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(
                              _weekdayLabels[weekday - 1],
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (weekday == todayWeekday) ...[
                              const SizedBox(width: 8),
                              const Chip(
                                label: Text('今天'),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: bangumiGridDelegate(context),
                          itemCount: _byWeekday[weekday]!.length,
                          itemBuilder: (context, index) => BangumiCardV(
                              bangumiItem: _byWeekday[weekday]![index]),
                        ),
                      ],
                    if (_byWeekday.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 32),
                        child: Center(child: Text('本周没有在看的番更新')),
                      ),
                  ],
                ),
    );
  }
}
