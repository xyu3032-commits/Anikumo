import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/bean/widget/error_widget.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/browse/rank_order.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/services/network/bangumi_acceleration.dart';
import 'package:anikumo/utils/constants.dart';

/// 排行榜 (hub 区一）: currently trending subjects re-ordered by their
/// Bangumi rank, so the list reads as a leaderboard instead of a feed.
class RankPage extends StatefulWidget {
  const RankPage({super.key});

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage> {
  List<BangumiItem> _items = [];
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
    // Batch 30: the API layer is contracted to swallow
    // errors, but the page no longer depends on that — any
    // throw lands in the retryable failure state instead of
    // leaving the spinner up forever (the batch-27 lesson).
    var result = const <BangumiItem>[];
    var threw = false;
    try {
      final mirror = BangumiAcceleration.current == BangumiAcceleration.mirror;
      result = mirror
          ? await BangumiApi.getBangumiMirrorPopularSubjects(
              limit: 50,
              offset: 0,
            )
          : await BangumiApi.getBangumiTrendsList(limit: 50, offset: 0);
    } catch (_) {
      threw = true;
    }
    if (!mounted) return;
    setState(() {
      _items = sortByBangumiRank(result);
      _loading = false;
      _failed = threw || result.isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: Text('排行榜')),
      body: _loading
          ? const Center(child: LoadingIndicator())
          : _failed
              ? GeneralErrorWidget(
                  errMsg: '排行榜暂时拉不到，请稍后重试。',
                  onRetry: _load,
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: StyleString.pagePadding,
                    vertical: StyleString.safeSpace,
                  ),
                  itemCount: _items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) =>
                      _RankRow(item: _items[index], position: index + 1),
                ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.item, required this.position});

  final BangumiItem item;
  final int position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rankColor = switch (position) {
      1 => Colors.amber.shade600,
      2 => Colors.blueGrey.shade300,
      3 => Colors.brown.shade300,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: StyleString.lgRadius),
      onTap: () {
        if (TapDebouncer.accept('info:${item.id}')) {
          context.pushNamed('/info/', arguments: item);
        }
      },
      leading: SizedBox(
        width: 36,
        child: Text(
          '$position',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: rankColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: NetworkImgLayer(
              src: item.images['large'] ?? '',
              width: 46,
              height: 62,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bangumiDisplayTitle(item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (item.ratingScore > 0)
                      '评分 ${item.ratingScore.toStringAsFixed(1)}',
                    if (item.rank > 0) 'Bangumi 排名 #${item.rank}',
                    if (item.airDate.length >= 4) item.airDate.substring(0, 4),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
