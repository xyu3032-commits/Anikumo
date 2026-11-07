import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/bean/widget/browse_section_header.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/error_widget.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/collect/collect_type.dart';
import 'package:anikumo/repositories/collect_repository.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/utils/constants.dart';

/// 今日上新 (hub 区一）: today's slice of the weekly broadcast calendar,
/// with the shows the user is actually following pulled out on top.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  List<BangumiItem> _items = [];
  Set<int> _watchingIds = const {};
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    // Batch 30: same hardening as the rank page, plus a
    // fully-empty week (a partial fetch failure returns seven
    // empty days) now reads as failure-with-retry instead of
    // the misleading "no anime today" empty state.
    var calendar = const <List<BangumiItem>>[];
    var threw = false;
    try {
      calendar = await BangumiApi.getCalendar();
    } catch (_) {
      threw = true;
    }
    if (!mounted) return;
    final todayIndex = DateTime.now().weekday - 1;
    final items =
        todayIndex < calendar.length ? calendar[todayIndex] : <BangumiItem>[];
    setState(() {
      _items = items;
      _watchingIds = inject<ICollectRepository>()
          .getBangumiIdsByType(CollectType.watching);
      _loading = false;
      _failed = threw ||
          calendar.isEmpty ||
          calendar.every((day) => day.isEmpty);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final watching = _items.where((item) => _watchingIds.contains(item.id)).toList();
    return Scaffold(
      appBar: const SysAppBar(title: Text('今日上新')),
      body: _loading
          ? const Center(child: LoadingIndicator())
          : _failed
              ? GeneralErrorWidget(
                  errMsg: '今日上新暂时拉不到，请稍后重试。',
                  onRetry: _load,
                )
              : _items.isEmpty
                  ? const GeneralEmptyState(
                      icon: Icons.event_busy_outlined,
                      title: '今天没有新番播出',
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              StyleString.pagePadding,
                              StyleString.safeSpace,
                              StyleString.pagePadding,
                              0,
                            ),
                            child: GlassSurface(
                              strong: true,
                              padding: const EdgeInsets.all(
                                StyleString.pagePadding,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.today_rounded, size: 28),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${now.month}月${now.day}日 · 星期${'一二三四五六日'[now.weekday - 1]}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      Text(
                                        '今日共 ${_items.length} 部更新 · 你在追 ${watching.length} 部',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (watching.isNotEmpty) ...[
                          const SliverToBoxAdapter(
                            child: SizedBox(height: StyleString.sectionSpace),
                          ),
                          const SliverToBoxAdapter(
                            child: BrowseSectionHeader(
                              title: '正在追的',
                              subtitle: '你追的番今天有更新',
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 216,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: StyleString.pagePadding,
                                ),
                                itemCount: watching.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(width: StyleString.cardSpace),
                                itemBuilder: (context, index) => SizedBox(
                                  width: 112,
                                  child: BangumiCardV(
                                    bangumiItem: watching[index],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SliverToBoxAdapter(
                          child: SizedBox(height: StyleString.sectionSpace),
                        ),
                        const SliverToBoxAdapter(
                          child: BrowseSectionHeader(
                            title: '今日全部',
                            subtitle: '今天播出的所有番剧',
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: StyleString.cardSpace,
                          ),
                          sliver: _grid(_items),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: StyleString.sectionSpace),
                        ),
                      ],
                    ),
    );
  }

  Widget _grid(List<BangumiItem> items) {
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        mainAxisSpacing: StyleString.cardSpace - 2,
        crossAxisSpacing: StyleString.cardSpace,
        crossAxisCount: crossCount,
        mainAxisExtent: MediaQuery.of(context).size.width / crossCount / 0.65 +
            MediaQuery.textScalerOf(context).scale(32.0),
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => BangumiCardV(bangumiItem: items[index]),
        childCount: items.length,
      ),
    );
  }
}
