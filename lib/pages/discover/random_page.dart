import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/bean/widget/fade_slide_in.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// 随便看一部： for decision paralysis. Draws one random title from
/// trends + this week's calendar; reroll as often as you like.
class RandomPage extends StatefulWidget {
  const RandomPage({super.key});

  @override
  State<RandomPage> createState() => _RandomPageState();
}

class _RandomPageState extends State<RandomPage> {
  final _random = Random();
  List<BangumiItem> _pool = const [];
  BangumiItem? _current;
  bool _loading = true;
  bool _failed = false;
  int _drawCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pool = <int, BangumiItem>{};
      // Batch 79: trends and the calendar used to load
      // strictly sequentially — two network round trips
      // before the first card could appear. They are
      // independent; start both, then await.
      final trendsFuture =
          BangumiApi.getBangumiTrendsList(limit: 50, offset: 0);
      final calendarFuture = BangumiApi.getCalendar();
      final trends = await trendsFuture;
      for (final item in trends) {
        pool[item.id] = item;
      }
      final calendar = await calendarFuture;
      for (final dayItems in calendar) {
        for (final item in dayItems) {
          pool[item.id] = item;
        }
      }
      if (!mounted) return;
      setState(() {
        _pool = pool.values.toList();
        _loading = false;
        _failed = _pool.isEmpty;
      });
      _draw();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _draw() {
    if (_pool.isEmpty) return;
    setState(() {
      _current = _pool[_random.nextInt(_pool.length)];
      _drawCount += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _current;
    return Scaffold(
      appBar: AppBar(title: const Text('随便看一部')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? const Center(child: Text('加载失败，请检查网络后重试'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    StyleString.pagePadding,
                    12,
                    StyleString.pagePadding,
                    StyleString.sectionSpace,
                  ),
                  children: [
                    if (current != null)
                      FadeSlideIn(
                        key: ValueKey('${current.id}-$_drawCount'),
                        child: GlassSurface(
                          strong: true,
                          padding: const EdgeInsets.all(16),
                          onTap: () => context.pushNamed(
                            '/info/',
                            arguments: current,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: StyleString.lgRadius,
                                child: NetworkImgLayer(
                                  src: current.images['large'] ?? '',
                                  width: double.infinity,
                                  height: 220,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                bangumiDisplayTitle(current),
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (current.ratingScore > 0)
                                    Chip(
                                      label: Text(
                                        '评分 ${current.ratingScore.toStringAsFixed(1)}',
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  if (current.airDate.isNotEmpty)
                                    Chip(
                                      label: Text(current.airDate),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                              if (current.summary.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  current.summary,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _draw,
                      icon: const Icon(AnikumoIcons.casino_rounded),
                      label: const Text('换一部'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '从 ${_pool.length} 部热门与本周新番里随机抽取',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
    );
  }
}
