import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/error_widget.dart';
import 'package:anikumo/bean/widget/fade_slide_in.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/browse/feed_builder.dart';
import 'package:anikumo/services/network/bangumi_acceleration.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

/// 发现 (discover) tab: anime discovery only.
///
/// 内容发现 — 排行榜 / 今日上新 entries plus the tag exploration
/// (rotating tag chips, same queries as the popular page's
/// tag mode). Batch 37 moved the toolbox and 我的时光 zones
/// out to their own bottom-nav tabs （工具箱 / 时光）. The manga
/// and novel zone entry features that used to headline this
/// page were removed in batch 132 — zone switching lives on
/// the zone-name wheel (batch 131) now.
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final TagRotation _tagRotation = TagRotation(defaultAnimeTags, batchSize: 8);
  final ScrollController _scrollController = ScrollController();

  late List<String> _chipTags;
  String? _selectedTag;
  List<BangumiItem> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _chipTags = _tagRotation.nextBatch();
    _scrollController.addListener(_onScroll);
    if (_chipTags.isNotEmpty) {
      _selectTag(_chipTags.first);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        !_loadingMore &&
        _selectedTag != null) {
      _loadTag(_selectedTag!, append: true);
    }
  }

  Future<void> _selectTag(String tag) async {
    if (tag == _selectedTag && _items.isNotEmpty) return;
    setState(() => _selectedTag = tag);
    await _loadTag(tag);
  }

  Future<void> _loadTag(String tag, {bool append = false}) async {
    if (append) {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final mirror = BangumiAcceleration.current == BangumiAcceleration.mirror;
    // Same query shape as PopularController.queryBangumiByTag.
    final result = mirror
        ? await BangumiApi.getBangumiMirrorPopularSubjects(
            tag: tag,
            offset: append ? _items.length : 0,
          )
        : await BangumiApi.getBangumiList(
            rank: Random().nextInt(8000) + 1,
            tag: tag,
          );
    if (!mounted || tag != _selectedTag) return;
    setState(() {
      if (append) {
        final existingIds = _items.map((item) => item.id).toSet();
        _items = [
          ..._items,
          ...result.where((item) => existingIds.add(item.id)),
        ];
        _loadingMore = false;
      } else {
        _items = result;
        _loading = false;
        _failed = result.isEmpty;
      }
    });
  }

  void _rotateTags() {
    setState(() => _chipTags = _tagRotation.nextBatch());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.t('DISCOVER · 探索中心'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.4,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    S.t('发现'),
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),

          // ── 内容发现 ──────────────────────────────────
          // Batch 132: the manga / novel zone features that
          // used to sit here are gone — zone switching moved
          // to the zone-name wheel (batch 131), so Discover is
          // purely about anime content again.
          // Batch 44: the two-column entry cards become a
          // numbered editorial index — same seven destinations.
          SliverToBoxAdapter(
            child: FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: EditorialSectionHeader(
                index: '01',
                label: 'EXPLORE',
                title: S.t('内容发现'),
                subtitle: S.t('排行榜、今日上新，还有按标签慢慢逛'),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: Column(
                children: [
                  EditorialIndexRow(
                    index: '01',
                    icon: AnikumoIcons.emoji_events_outlined,
                    title: S.t('排行榜'),
                    subtitle: S.t('按 Bangumi 排名看热门'),
                    onTap: () =>
                        context.pushNamed('/tab/discover/rank/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '02',
                    icon: AnikumoIcons.today_outlined,
                    title: S.t('今日上新'),
                    subtitle: S.t('今天播出的新番与你的在追'),
                    onTap: () =>
                        context.pushNamed('/tab/discover/today/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '03',
                    icon: AnikumoIcons.auto_awesome_outlined,
                    title: S.t('每日推荐'),
                    subtitle: S.t('每天换一批，专挑没看过的'),
                    onTap: () =>
                        context.pushNamed('/tab/discover/daily/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '04',
                    icon: AnikumoIcons.update_outlined,
                    title: S.t('更新中心'),
                    subtitle: S.t('在看的番这周哪天更新'),
                    onTap: () =>
                        context.pushNamed('/tab/discover/updates/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '05',
                    icon: AnikumoIcons.movie_filter_outlined,
                    title: S.t('相似推荐'),
                    subtitle: S.t('喜欢这部？再找几部像的'),
                    onTap: () =>
                        context.pushNamed('/tab/discover/similar/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '06',
                    icon: AnikumoIcons.upcoming_outlined,
                    title: S.t('即将开播'),
                    subtitle: S.t('想看里还没开播的，带倒计时'),
                    onTap: () =>
                        context.pushNamed('/tab/discover/coming/'),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '07',
                    icon: AnikumoIcons.casino_outlined,
                    title: S.t('随便看一部'),
                    subtitle: S.t('选择困难时，随机抽一部今晚看'),
                    onTap: () =>
                        context.pushNamed('/tab/discover/random/'),
                  ),
                  const EditorialHairline(),
                  // Batch 275 (#43): cross-zone favorites.
                  EditorialIndexRow(
                    index: '08',
                    icon: AnikumoIcons.favorite_rounded,
                    title: S.t('全部收藏'),
                    subtitle: S.t('四个专区的收藏放在一页看'),
                    onTap: () => context
                        .pushNamed('/tab/discover/cross-favorites/'),
                  ),
                  const EditorialHairline(),
                  // Batch 276 (#58): cross-zone hot chart.
                  EditorialIndexRow(
                    index: '09',
                    icon: AnikumoIcons.emoji_events_rounded,
                    title: S.t('四区热门榜'),
                    subtitle: S.t('每个专区现在最热的十部'),
                    onTap: () => context
                        .pushNamed('/tab/discover/cross-ranks/'),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
              child: SizedBox(height: StyleString.sectionSpace)),
          SliverToBoxAdapter(
            child: EditorialSectionHeader(
              index: '02',
              label: 'BY TAGS',
              title: S.t('按标签发现'),
              subtitle: S.t('点一个标签，看看这个分类里有什么'),
              actionLabel: S.t('换一批'),
              onAction: _rotateTags,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: StyleString.pagePadding,
              ),
              child: Wrap(
                spacing: StyleString.cardSpace,
                runSpacing: StyleString.cardSpace,
                children: [
                  for (final tag in _chipTags)
                    ChoiceChip(
                      label: Text(tag),
                      selected: tag == _selectedTag,
                      onSelected: (_) => _selectTag(tag),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
              child: SizedBox(height: StyleString.sectionSpace)),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: LoadingIndicator()),
            )
          else if (_failed)
            SliverFillRemaining(
              hasScrollBody: false,
              child: GeneralErrorWidget(
                errMsg: S.t('这个标签暂时没有拉到内容，请重试或换个标签。'),
                onRetry: () =>
                    _selectedTag == null ? null : _loadTag(_selectedTag!),
              ),
            )
          else if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: GeneralEmptyState(
                icon: AnikumoIcons.explore_outlined,
                title: S.t('选一个标签开始发现'),
                compact: true,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: StyleString.cardSpace,
              ),
              sliver: _resultsGrid(),
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(StyleString.pagePadding),
                child: Center(child: LoadingIndicator(size: 28)),
              ),
            ),
          const SliverToBoxAdapter(
              child: SizedBox(height: StyleString.sectionSpace)),

        ],
      ),
    );
  }

  /// Same grid geometry as the popular page (3/5/6 columns by width),
  /// so cards feel identical across tabs.
  Widget _resultsGrid() {
    // Batch 15 (G7): the title filter also applies to tag
    // browse results.
    final filterKeywords = TitleFilterStore.loadKeywords();
    final visibleItems = filterKeywords.isEmpty
        ? _items
        : [
            for (final item in _items)
              if (!titleBlocked(
                item.nameCn.isNotEmpty ? item.nameCn : item.name,
                filterKeywords,
              ))
                item,
          ];
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    // Batch 284 (#30): wide screens (tablet/desktop shell
    // caps content at 1280) get two more columns instead
    // of oversized cards.
    if (MediaQuery.sizeOf(context).width >= 1280) {
      crossCount = 8;
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
        (context, index) => BangumiCardV(bangumiItem: visibleItems[index]),
        childCount: visibleItems.length,
      ),
    );
  }
}
