import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/bean/widget/anikumo_menu.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/pages/popular/popular_controller.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/bean/appbar/drag_to_move_bar.dart' as dtb;

class PopularPage extends StatefulWidget {
  const PopularPage({
    super.key,
    required this.controller,
  });

  final PopularController controller;

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage> {
  late final ScrollController scrollController;
  PopularController get popularController => widget.controller;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    super.dispose();
  }

  void scrollListener() {
    popularController.scrollOffset = scrollController.offset;
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 200 &&
        !popularController.isLoadingMore) {
      AnikumoLogger()
          .i('PopularPageController: Fetching next recommendation batch');
      if (popularController.currentTag != '') {
        popularController.queryBangumiByTag();
      } else {
        popularController.queryBangumiByTrend();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        controller: scrollController,
        slivers: [
          buildEditorialTitleBar(),
          SliverToBoxAdapter(
            child: Observer(
              builder: (_) => AnimatedOpacity(
                opacity: popularController.isLoadingMore ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: popularController.isLoadingMore
                    ? const LinearProgressIndicator(minHeight: 4)
                    : const SizedBox(height: 4),
              ),
            ),
          ),
          SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  StyleString.cardSpace, 0, StyleString.cardSpace, 0),
              sliver: Observer(builder: (_) {
                if (popularController.isTimeOut) {
                  return SliverToBoxAdapter(
                    child: SizedBox(
                      height: 400,
                      child: BangumiMirrorErrorWidget(
                        onRetry: () {
                          if (popularController.trendList.isEmpty) {
                            popularController.queryBangumiByTrend();
                          } else {
                            popularController.queryBangumiByTag();
                          }
                        },
                        onSettingsReturned: () {
                          if (mounted) {
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  );
                }
                final raw = (popularController.currentTag == '')
                    ? popularController.trendList
                    : popularController.bangumiList;
                return SliverMainAxisGroup(
                  slivers: [
                    _spotlightSliver(raw),
                    contentGrid(raw),
                  ],
                );
              })),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => scrollController.animateTo(0,
            duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
        child: const Icon(Icons.arrow_upward),
      ),
    );
  }

  // Batch 15 (G7): hide titles matching the user's filter
  // keywords. Batch 44: shared by the grid and the new
  // spotlight/rank presentations of the same list.
  List<BangumiItem> _filtered(List<BangumiItem> rawList) {
    final filterKeywords = TitleFilterStore.loadKeywords();
    if (filterKeywords.isEmpty) return rawList;
    return [
      for (final item in rawList)
        if (!titleBlocked(
          item.nameCn.isNotEmpty ? item.nameCn : item.name,
          filterKeywords,
        ))
          item,
    ];
  }

  /// Batch 44: the editorial top of the home feed — a
  /// full-bleed spotlight of the current list's first entry
  /// plus a Top-5 rank strip. Same controller data, no extra
  /// requests; the full grid follows below unchanged.
  Widget _spotlightSliver(List<BangumiItem> rawList) {
    final list = _filtered(rawList);
    if (list.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final isTrend = popularController.currentTag == '';
    final top = list.take(5).toList();
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Batch 70: the main visual is the whole Top 5,
          // freely swipeable with wrap-around in both
          // directions (was: Top 1 only, static).
          EditorialHeroCarousel(
            items: top,
            kickerFor: (rank) => isTrend
                ? '今日主视觉 · TOP ${rank + 1}'
                : '标签精选 · TOP ${rank + 1}',
            onTap: (item) => context.pushNamed(
              '/info/',
              arguments: item,
            ),
          ),
          EditorialSectionHeader(
            index: '01',
            label: 'RANKING',
            title: isTrend ? '本日榜单' : '标签人气榜',
            subtitle: isTrend ? '大家正在追的五部' : '这个标签里最热的五部',
          ),
          for (var i = 0; i < top.length; i++)
            EditorialRankRow(
              rank: i + 1,
              item: top[i],
              showDivider: i != top.length - 1,
              // Batch 115: rank rows fly their cover into the
              // detail page like every other cover entry; the
              // grid below disables its own hero for these five
              // so each tag stays unique on this page.
              enableHero: true,
              onTap: () => context.pushNamed(
                '/info/',
                arguments: top[i],
              ),
            ),
          EditorialSectionHeader(
            index: '02',
            label: isTrend ? 'TRENDING' : 'TAG FEED',
            title: isTrend ? '热门番组' : popularController.currentTag,
            subtitle: '继续向下，慢慢挑',
          ),
        ],
      ),
    );
  }

  Widget contentGrid(List<BangumiItem> rawList) {
    final bangumiList = _filtered(rawList);
    // Batch 115: the spotlight rank rows above carry the hero
    // for the top five; the same items reappear in this grid and
    // must not duplicate the hero tag.
    final heroTakenIds = <int>{
      for (final item in bangumiList.take(5)) item.id,
    };
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // 行间距
          mainAxisSpacing: StyleString.cardSpace - 2,
          // 列间距
          crossAxisSpacing: StyleString.cardSpace,
          // 列数
          crossAxisCount: crossCount,
          mainAxisExtent:
              MediaQuery.of(context).size.width / crossCount / 0.65 +
                  MediaQuery.textScalerOf(context).scale(32.0),
        ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
            return bangumiList.isNotEmpty
                ? BangumiCardV(
                    bangumiItem: bangumiList[index],
                    enableHero:
                        !heroTakenIds.contains(bangumiList[index].id),
                  )
                : null;
          },
          childCount: bangumiList.isNotEmpty ? bangumiList.length : 10,
        ),
      ),
    );
  }

  /// Batch 44: the old collapsing SliverAppBar is gone (the
  /// shell masthead carries search/history/exit now). What
  /// remains in-page is the tag switch — the same menu with
  /// the same items and behavior, set as a large editorial
  /// title.
  Widget buildEditorialTitleBar() {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: dtb.DragToMoveArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'POPULAR · 今日推荐',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 4),
              Observer(
                builder: (_) {
                  final bool isTrend = popularController.currentTag == '';
                  return AnikumoMenuButton(
                    animated: true,
                    style: const MenuStyle(
                      maximumSize: WidgetStatePropertyAll(Size(240, 350)),
                    ),
                    menuChildren: [
                      for (final tag in ['', ...defaultAnimeTags])
                        AnikumoMenuItem(
                          label: tag.isEmpty ? '热门番组' : tag,
                          selected: tag == popularController.currentTag,
                          onPressed: () => _selectTag(tag),
                        ),
                    ],
                    builder: (context, toggle) => InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: toggle,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isTrend
                                ? '热门番组'
                                : popularController.currentTag,
                            style: theme.textTheme.headlineMedium!
                                .copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 26,
                            color: theme.iconTheme.color,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectTag(String selected) async {
    if (!mounted || selected == popularController.currentTag) return;
    scrollController.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    popularController.setCurrentTag(selected);
    if (selected.isEmpty) {
      popularController.clearBangumiList();
      if (popularController.trendList.isEmpty) {
        await popularController.queryBangumiByTrend();
      }
    } else {
      await popularController.queryBangumiByTag(type: 'init');
    }
  }
}
