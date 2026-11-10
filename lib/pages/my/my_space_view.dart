import 'package:flutter/material.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/modules/my/watch_stats.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

enum MyDestination {
  theme,
  player,
  danmaku,
  rules,
  history,
  downloads,
  sync,
  storage,
  about,
}

/// Batch 44: the My tab becomes a personal archive page in
/// the zone's editorial language — a stats masthead (the
/// same real numbers the old panel showed), wide feature
/// rows for history/downloads, and the two settings groups
/// as numbered index rows. Every destination is the
/// original route; the wide layout keeps the same entries
/// in a two-column arrangement. There is still no account
/// or profile data in the app, so the header is built from
/// watch statistics only — nothing invented.
class MySpaceView extends StatelessWidget {
  const MySpaceView({
    super.key,
    required this.stats,
    required this.onOpen,
    required this.onSettings,
  });

  final WatchStats stats;
  final ValueChanged<MyDestination> onOpen;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final inset = constraints.maxWidth < 600 ? 4.0 : 12.0;
      final width = constraints.maxWidth - inset * 2;
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final wide = width >= 840 && !largeText;
      return SingleChildScrollView(
        key: const PageStorageKey('my-space'),
        padding: EdgeInsets.fromLTRB(inset, 12, inset, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: wide
                ? _WideSpaceLayout(
                    stats: stats,
                    onOpen: onOpen,
                    onSettings: onSettings,
                  )
                : _CompactSpaceLayout(
                    stats: stats,
                    onOpen: onOpen,
                    onSettings: onSettings,
                  ),
          ),
        ),
      );
    });
  }
}

class _ProfileHead extends StatelessWidget {
  const _ProfileHead({required this.stats, required this.onSettings});

  final WatchStats stats;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'PROFILE · 个人档案',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.outline,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.4,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '全部设置',
                onPressed: onSettings,
                icon: const Icon(AnikumoIcons.tune_rounded),
              ),
            ],
          ),
          Text(
            '我的',
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat(context, '${stats.watchedBangumiCount}', '看过的番剧'),
              _divider(context),
              _stat(context, '${stats.watchedEpisodeCount}', '观看集数'),
              _divider(context),
              _stat(context, '${stats.downloadTaskCount}', '下载任务'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
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

  Widget _divider(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color:
          Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
    );
  }
}

/// A wide feature row (history / downloads): icon block,
/// title + live caption, arrow.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 24, color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        caption,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  AnikumoIcons.arrow_forward_ios_rounded,
                  size: 14,
                  color: scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactSpaceLayout extends StatelessWidget {
  const _CompactSpaceLayout({
    required this.stats,
    required this.onOpen,
    required this.onSettings,
  });

  final WatchStats stats;
  final ValueChanged<MyDestination> onOpen;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileHead(stats: stats, onSettings: onSettings),
        const SizedBox(height: 18),
        _FeatureRow(
          icon: AnikumoIcons.history_rounded,
          title: '历史记录',
          caption:
              stats.watchedBangumiCount == 0 ? '暂无观看记录' : '查看观看记录',
          onTap: () => onOpen(MyDestination.history),
        ),
        _FeatureRow(
          icon: AnikumoIcons.download_rounded,
          title: '离线下载',
          caption: stats.downloadTaskCount == 0
              ? '管理离线内容'
              : '${stats.downloadTaskCount} 集下载任务',
          onTap: () => onOpen(MyDestination.downloads),
        ),
        const EditorialSectionHeader(
          index: '01',
          label: 'PREFERENCES',
          title: '内容与偏好',
        ),
        EditorialIndexRow(
          index: '01',
          icon: AnikumoIcons.extension_rounded,
          title: '规则设置',
          onTap: () => onOpen(MyDestination.rules),
        ),
        const EditorialHairline(),
        EditorialIndexRow(
          index: '02',
          icon: AnikumoIcons.palette_rounded,
          title: '外观设置',
          onTap: () => onOpen(MyDestination.theme),
        ),
        const EditorialHairline(),
        EditorialIndexRow(
          index: '03',
          icon: AnikumoIcons.play_circle_rounded,
          title: '播放设置',
          onTap: () => onOpen(MyDestination.player),
        ),
        const EditorialHairline(),
        EditorialIndexRow(
          index: '04',
          icon: AnikumoIcons.subtitles_rounded,
          title: '弹幕设置',
          onTap: () => onOpen(MyDestination.danmaku),
        ),
        const EditorialSectionHeader(
          index: '02',
          label: 'DATA & APP',
          title: '数据与应用',
        ),
        EditorialIndexRow(
          index: '01',
          icon: AnikumoIcons.cloud_sync_rounded,
          title: '同步备份',
          onTap: () => onOpen(MyDestination.sync),
        ),
        const EditorialHairline(),
        EditorialIndexRow(
          index: '02',
          icon: AnikumoIcons.cleaning_services_rounded,
          title: '存储管理',
          onTap: () => onOpen(MyDestination.storage),
        ),
        const EditorialHairline(),
        EditorialIndexRow(
          index: '03',
          icon: AnikumoIcons.info_outline_rounded,
          title: '关于 Anikumo',
          onTap: () => onOpen(MyDestination.about),
        ),
      ],
    );
  }
}

class _WideSpaceLayout extends StatelessWidget {
  const _WideSpaceLayout({
    required this.stats,
    required this.onOpen,
    required this.onSettings,
  });

  final WatchStats stats;
  final ValueChanged<MyDestination> onOpen;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileHead(stats: stats, onSettings: onSettings),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _FeatureRow(
                icon: AnikumoIcons.history_rounded,
                title: '历史记录',
                caption: stats.watchedBangumiCount == 0
                    ? '暂无观看记录'
                    : '查看观看记录',
                onTap: () => onOpen(MyDestination.history),
              ),
            ),
            Expanded(
              child: _FeatureRow(
                icon: AnikumoIcons.download_rounded,
                title: '离线下载',
                caption: stats.downloadTaskCount == 0
                    ? '管理离线内容'
                    : '${stats.downloadTaskCount} 集下载任务',
                onTap: () => onOpen(MyDestination.downloads),
              ),
            ),
          ],
        ),
        const EditorialSectionHeader(
          index: '01',
          label: 'PREFERENCES',
          title: '内容与偏好',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  EditorialIndexRow(
                    index: '01',
                    icon: AnikumoIcons.extension_rounded,
                    title: '规则设置',
                    onTap: () => onOpen(MyDestination.rules),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '02',
                    icon: AnikumoIcons.palette_rounded,
                    title: '外观设置',
                    onTap: () => onOpen(MyDestination.theme),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  EditorialIndexRow(
                    index: '03',
                    icon: AnikumoIcons.play_circle_rounded,
                    title: '播放设置',
                    onTap: () => onOpen(MyDestination.player),
                  ),
                  const EditorialHairline(),
                  EditorialIndexRow(
                    index: '04',
                    icon: AnikumoIcons.subtitles_rounded,
                    title: '弹幕设置',
                    onTap: () => onOpen(MyDestination.danmaku),
                  ),
                ],
              ),
            ),
          ],
        ),
        const EditorialSectionHeader(
          index: '02',
          label: 'DATA & APP',
          title: '数据与应用',
        ),
        EditorialIndexRow(
          index: '01',
          icon: AnikumoIcons.cloud_sync_rounded,
          title: '同步备份',
          onTap: () => onOpen(MyDestination.sync),
        ),
        const EditorialHairline(),
        EditorialIndexRow(
          index: '02',
          icon: AnikumoIcons.cleaning_services_rounded,
          title: '存储管理',
          onTap: () => onOpen(MyDestination.storage),
        ),
        const EditorialHairline(),
        EditorialIndexRow(
          index: '03',
          icon: AnikumoIcons.info_outline_rounded,
          title: '关于 Anikumo',
          onTap: () => onOpen(MyDestination.about),
        ),
      ],
    );
  }
}

/// Kept for compatibility with the old app-bar action; the
/// redesigned page head uses a plain IconButton instead.
class MySettingsButton extends StatelessWidget {
  const MySettingsButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '全部设置',
      onPressed: onTap,
      icon: const Icon(AnikumoIcons.tune_rounded),
    );
  }
}
