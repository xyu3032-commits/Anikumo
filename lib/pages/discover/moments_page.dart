import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/repositories/history_repository.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/services/player/history_playback_service.dart';
import 'package:anikumo/services/stats/achievements.dart';
import 'package:anikumo/services/stats/report_stats.dart';
import 'package:anikumo/services/stats/watch_stats.dart';
import 'package:anikumo/utils/constants.dart';

/// 时光 tab (batch 37): everything personal that used to sit
/// at the bottom of the discover page as 「我的时光」 — moved
/// up into its own bottom-nav destination at the user's
/// request. Batch 44 recasts it as a personal watch ARCHIVE:
/// a real-data stats band up top, continue watching as wide
/// cinematic cards, and the five library entries as a
/// numbered index with live counts. All data comes from the
/// same local history and stores the sub-pages use; every
/// destination is the original route.
class MomentsPage extends StatefulWidget {
  const MomentsPage({super.key});

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  List<History> _allHistories = [];
  List<History> _recentHistories = [];

  @override
  void initState() {
    super.initState();
    try {
      final all = [...inject<IHistoryRepository>().getAllHistories()];
      all.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      _allHistories = all;
      _recentHistories = all.take(10).toList();
    } catch (_) {
      _allHistories = const [];
      _recentHistories = const [];
    }
  }

  Future<void> _resume(History history) async {
    final result = await inject<HistoryPlaybackService>().open(history);
    if (!mounted) return;
    switch (result) {
      case HistoryPlaybackReady(:final args):
        context.pushNamed('/video/', arguments: args);
      case HistoryPlaybackUnavailable(:final reason):
        AnikumoDialog.showToast(context: context, message: reason);
    }
  }

  String _progressLabel(History history) {
    final base = '看到第 ${history.lastWatchEpisode} 集';
    final progress = history.progresses[history.lastWatchEpisode];
    if (progress == null || progress.progress == Duration.zero) {
      return base;
    }
    final duration = progress.progress;
    final minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return duration.inHours > 0
        ? '$base · ${duration.inHours}:$minutes:$seconds'
        : '$base · $minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats =
        _allHistories.isEmpty ? null : computeWatchStats(_allHistories);
    final achievements = _allHistories.isEmpty
        ? const <Achievement>[]
        : evaluateAchievements(_allHistories);
    final unlocked = achievements.where((a) => a.unlocked).length;
    final now = DateTime.now();
    final monthly = _allHistories.isEmpty
        ? null
        : computeMonthlyReport(_allHistories, year: now.year, month: now.month);
    final listCount = UserListsStore.load().length;
    final noteCount = BangumiNotesStore.load().length;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ARCHIVE · 观看档案',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '我的时光',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '接着上次看到的地方继续',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (stats != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _statColumn(
                      context,
                      '${stats.distinctAnime}',
                      '看过的番剧',
                    ),
                    _statDivider(context),
                    _statColumn(
                      context,
                      '${stats.totalEpisodes}',
                      '观看集数',
                    ),
                    _statDivider(context),
                    _statColumn(
                      context,
                      stats.totalMinutes >= 60
                          ? '${stats.totalMinutes ~/ 60} 小时'
                          : '${stats.totalMinutes} 分钟',
                      '观看时长',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
            const EditorialSectionHeader(
              index: '01',
              label: 'CONTINUE',
              title: '继续观看',
            ),
            if (_recentHistories.isNotEmpty)
              SizedBox(
                height: 158,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: StyleString.pagePadding,
                  ),
                  itemCount: _recentHistories.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) =>
                      _continueCard(_recentHistories[index]),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: StyleString.pagePadding,
                  vertical: 8,
                ),
                child: GeneralEmptyState(
                  icon: Icons.hourglass_empty_rounded,
                  title: '还没有观看记录',
                  compact: true,
                ),
              ),
            const EditorialSectionHeader(
              index: '02',
              label: 'LIBRARY',
              title: '我的收藏夹',
              subtitle: '榜单、统计、笔记、报告与成就',
            ),
            EditorialIndexRow(
              index: '01',
              icon: Icons.list_alt_outlined,
              title: '我的榜单',
              subtitle: '自建片单',
              trailingText: listCount > 0 ? '$listCount 个' : null,
              onTap: () => context.pushNamed('/tab/discover/my-lists/'),
            ),
            const EditorialHairline(),
            EditorialIndexRow(
              index: '02',
              icon: Icons.bar_chart_rounded,
              title: '观看统计',
              subtitle: '集数与时长',
              onTap: () => context.pushNamed('/tab/discover/watch-stats/'),
            ),
            const EditorialHairline(),
            EditorialIndexRow(
              index: '03',
              icon: Icons.sticky_note_2_outlined,
              title: '番剧笔记',
              subtitle: '私人备注',
              trailingText: noteCount > 0 ? '$noteCount 条' : null,
              onTap: () => context.pushNamed('/tab/discover/notes/'),
            ),
            const EditorialHairline(),
            EditorialIndexRow(
              index: '04',
              icon: Icons.insights_outlined,
              title: '观看报告',
              subtitle: '月度总结与热力图',
              trailingText: monthly != null && monthly.episodes > 0
                  ? '本月 ${monthly.episodes} 集'
                  : null,
              onTap: () => context.pushNamed('/tab/discover/report/'),
            ),
            const EditorialHairline(),
            EditorialIndexRow(
              index: '05',
              icon: Icons.emoji_events_outlined,
              title: '观看成就',
              subtitle: achievements.isEmpty
                  ? '里程碑徽章'
                  : '里程碑徽章 · 已解锁 $unlocked/${achievements.length}',
              onTap: () =>
                  context.pushNamed('/tab/discover/achievements/'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statColumn(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color:
          Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
    );
  }

  /// Wide cinematic continue card: the cover fills the card,
  /// the title and last position sit on a scrim, and the
  /// play button resumes playback directly (same behavior
  /// as the old card's play badge).
  Widget _continueCard(History history) {
    final theme = Theme.of(context);
    final item = history.bangumiItem;
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 272,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkImgLayer(
              src: item.images['large'] ?? '',
              width: 272,
              height: 158,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black45, Colors.black87],
                  stops: [0.3, 0.65, 1],
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => context.pushNamed(
                  '/info/',
                  arguments: item,
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 64,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _progressLabel(history),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: FilledButton(
                onPressed: () => _resume(history),
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(10),
                  minimumSize: const Size(40, 40),
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
