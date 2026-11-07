import 'package:flutter/material.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/bean/widget/error_widget.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/browse/feed_builder.dart';
import 'package:anikumo/services/network/bangumi_acceleration.dart';
import 'package:anikumo/utils/constants.dart';

/// 精选「更多」page (batch 37): one featured section as a
/// full grid. Rebuilds the section from deeper fetches,
/// uncapped — the tab only ever shows the first 12.
/// Batch 81: assembly is single-section
/// (buildFeaturedSection) — reusing the tab's cross-section
/// build starved later sections （冷门佳作 collapsed to the
/// leftovers of 趋势热播 / 高分口碑）.
class FeaturedMorePage extends StatefulWidget {
  const FeaturedMorePage({super.key, required this.sectionId});

  final String sectionId;

  @override
  State<FeaturedMorePage> createState() => _FeaturedMorePageState();
}

class _FeaturedMorePageState extends State<FeaturedMorePage> {
  List<BangumiItem> _items = const [];
  String _title = '更多';
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
    try {
      final mirror =
          BangumiAcceleration.current == BangumiAcceleration.mirror;
      final results = await Future.wait([
        mirror
            ? BangumiApi.getBangumiMirrorPopularSubjects(
                limit: 72, offset: 0)
            : BangumiApi.getBangumiTrendsList(limit: 72, offset: 0),
        mirror
            ? BangumiApi.getBangumiMirrorPopularSubjects(
                limit: 24, offset: 24)
            : BangumiApi.getBangumiList(rank: 2),
      ]);
      final section = buildFeaturedSection<BangumiItem>(
        sectionId: widget.sectionId,
        trending: results[0],
        ranked: results[1],
        idOf: (item) => item.id,
        scoreOf: (item) => item.ratingScore,
        votesOf: (item) => item.votes,
        limit: 72,
      );
      if (!mounted) return;
      setState(() {
        _items = section?.items ?? const [];
        _title = section?.title ?? '更多';
        _loading = false;
        _failed = section == null;
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
    var crossCount = 3;
    if (MediaQuery.sizeOf(context).width >
        LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width >
        LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _loading
          ? const Center(child: LoadingIndicator())
          : _failed || _items.isEmpty
              ? GeneralErrorWidget(
                  errMsg: '这一组暂时没有拉到内容，请重试。',
                  onRetry: _load,
                )
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(8),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          mainAxisSpacing: StyleString.cardSpace - 2,
                          crossAxisSpacing: StyleString.cardSpace,
                          crossAxisCount: crossCount,
                          mainAxisExtent:
                              MediaQuery.of(context).size.width /
                                      crossCount /
                                      0.65 +
                                  MediaQuery.textScalerOf(context)
                                      .scale(32.0),
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              BangumiCardV(bangumiItem: _items[index]),
                          childCount: _items.length,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
