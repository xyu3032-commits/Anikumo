import 'package:flutter/material.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/pages/discover/bangumi_picker.dart';
import 'package:anikumo/pages/discover/daily_page.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/browse/similarity.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// 相似推荐： pick a show you like; candidates come from the trend
/// list plus your own library, ranked by shared Bangumi tags.
class SimilarPage extends StatefulWidget {
  const SimilarPage({super.key});

  @override
  State<SimilarPage> createState() => _SimilarPageState();
}

class _SimilarPageState extends State<SimilarPage> {
  BangumiItem? _source;
  List<BangumiItem> _results = const [];
  bool _loading = false;

  Future<void> _pickSource() async {
    final picked = await showBangumiPicker(context);
    if (picked == null || !mounted) return;
    setState(() {
      _source = picked;
      _loading = true;
    });
    try {
      final pool = <int, BangumiItem>{};
      final trends = await BangumiApi.getBangumiTrendsList(limit: 50, offset: 0);
      for (final item in trends) {
        pool[item.id] = item;
      }
      final candidates = loadBangumiCandidates();
      for (final item in candidates) {
        pool[item.id] = item;
      }
      if (!mounted) return;
      setState(() {
        _results = rankSimilar(picked, pool.values);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('相似推荐')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          StyleString.pagePadding,
          8,
          StyleString.pagePadding,
          StyleString.sectionSpace,
        ),
        children: [
          OutlinedButton.icon(
            onPressed: _pickSource,
            icon: const Icon(AnikumoIcons.movie_filter_rounded),
            label: Text(
              _source == null
                  ? '选择一部你喜欢的番'
                  : '基于「${bangumiDisplayTitle(_source!)}」找相似',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '按 Bangumi 标签的重合度排序：共享标签越多越靠前。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_source != null && _results.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('没有找到标签相近的番，换一部试试'),
              ),
            )
          else if (_results.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: bangumiGridDelegate(context),
              itemCount: _results.length,
              itemBuilder: (context, index) =>
                  BangumiCardV(bangumiItem: _results[index]),
            ),
        ],
      ),
    );
  }
}
