import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:anikumo/bean/widget/motion_kit.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/bean/widget/fade_slide_in.dart';
import 'package:anikumo/bean/widget/error_widget.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/browse/feed_builder.dart';
import 'package:anikumo/services/network/bangumi_acceleration.dart';
import 'package:anikumo/utils/constants.dart';

/// 精选 (featured) tab: a curated browse surface assembled from data the
/// app already fetches — Bangumi trends for the hero and 趋势热播，
/// the rank search for 高分口碑 / 冷门佳作. Section assembly rules live
/// in [buildFeaturedFeed] and are unit tested; this page only renders.
class FeaturedPage extends StatefulWidget {
  const FeaturedPage({super.key});

  @override
  State<FeaturedPage> createState() => _FeaturedPageState();
}

class _FeaturedPageState extends State<FeaturedPage> {
  FeaturedFeed<BangumiItem>? _feed;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final mirror = BangumiAcceleration.current == BangumiAcceleration.mirror;
    final results = await Future.wait([
      mirror
          ? BangumiApi.getBangumiMirrorPopularSubjects(limit: 24, offset: 0)
          : BangumiApi.getBangumiTrendsList(limit: 24, offset: 0),
      mirror
          ? BangumiApi.getBangumiMirrorPopularSubjects(limit: 24, offset: 24)
          : BangumiApi.getBangumiList(rank: 2),
    ]);
    if (!mounted) return;
    final feed = buildFeaturedFeed<BangumiItem>(
      trending: results[0],
      ranked: results[1],
      idOf: (item) => item.id,
      scoreOf: (item) => item.ratingScore,
      votesOf: (item) => item.votes,
    );
    setState(() {
      _feed = feed;
      _loading = false;
      _failed = feed.isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(600),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FEATURED · 编辑精选',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                            color:
                                Theme.of(context).colorScheme.outline,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.4,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '精选',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: LoadingIndicator()),
              )
            else if (_failed || _feed == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: GeneralErrorWidget(
                  errMsg: '精选内容加载失败，请检查网络后重试。',
                  onRetry: _load,
                ),
              )
            else ...[
              if (_feed!.hero != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ScaleIn(
                      child: EditorialHero(
                        item: _feed!.hero!,
                        kicker: '编辑主推 · HEADLINE',
                        onTap: () => context.pushNamed(
                          '/info/',
                          arguments: _feed!.hero!,
                        ),
                      ),
                    ),
                  ),
                ),
              for (final (i, section) in _feed!.sections.indexed) ...[
                SliverToBoxAdapter(
                  child: EditorialSectionHeader(
                    index: (i + 1).toString().padLeft(2, '0'),
                    label: switch (section.id) {
                      'trending' => 'TRENDING',
                      'top_rated' => 'TOP RATED',
                      'hidden_gems' => 'HIDDEN GEMS',
                      _ => 'FEATURED',
                    },
                    title: section.title,
                    subtitle: section.subtitle,
                    actionLabel: '更多',
                    onAction: () => context.pushNamed(
                      '/tab/featured/more',
                      arguments: section.id,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _sectionBody(section)),
              ],
              const SliverToBoxAdapter(
                child: SizedBox(height: StyleString.sectionSpace),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Batch 44: each section gets its own shape — trending is
  /// a big-card rail, top rated is a numbered rank list, and
  /// hidden gems is a staggered magazine rail. The section
  /// DATA and the 「更多」 destinations are unchanged.
  Widget _sectionBody(FeedSection<BangumiItem> section) {
    switch (section.id) {
      case 'top_rated':
        // Batch 125: the 精选 ranking runs Top 1–10 (was 5),
        // with the same 3D cascade entrance as the Top-5 lists.
        final top = section.items.take(10).toList();
        return Column(
          children: [
            for (var i = 0; i < top.length; i++)
              // Batch 123: the Top-5 rows cascade in with a
              // 3D perspective flip.
              RankEntrance3D(
                index: i,
                child: EditorialRankRow(
                  rank: i + 1,
                  item: top[i],
                  showDivider: i != top.length - 1,
                  onTap: () => context.pushNamed(
                    '/info/',
                    arguments: top[i],
                  ),
                ),
              ),
          ],
        );
      case 'hidden_gems':
        return SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: StyleString.pagePadding,
            ),
            itemCount: section.items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: StyleString.cardSpace),
            itemBuilder: (context, index) {
              // Staggered widths give the rail a magazine
              // rhythm instead of a uniform card strip.
              final wide = index % 3 == 0;
              return SizedBox(
                width: wide ? 148 : 108,
                child: BangumiCardV(bangumiItem: section.items[index]),
              );
            },
          ),
        );
      default:
        // 'trending' and any future section: big-card rail.
        return SizedBox(
          height: 258,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: StyleString.pagePadding,
            ),
            itemCount: section.items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: StyleString.cardSpace),
            itemBuilder: (context, index) {
              return SizedBox(
                width: 130,
                child: BangumiCardV(bangumiItem: section.items[index]),
              );
            },
          ),
        );
    }
  }
}
