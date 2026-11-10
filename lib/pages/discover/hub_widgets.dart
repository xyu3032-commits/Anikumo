import 'package:flutter/material.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Shared hub widgets for the discover family of tabs
/// （发现 / 工具箱 / 时光）. Extracted in batch 37 when the
/// toolbox and my-time zones left the discover page for
/// their own bottom-nav tabs.

/// Glass entry card used by the hub zones.
class HubEntry extends StatelessWidget {
  const HubEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// Full-width glass row for toolbox shortcuts.
class ToolRow extends StatelessWidget {
  const ToolRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const Icon(AnikumoIcons.chevron_right),
        ],
      ),
    );
  }
}

/// Continue-watching card: cover, title, and where playback stopped.
/// Tapping the card opens details; the play badge resumes directly.
class ContinueWatchCard extends StatelessWidget {
  const ContinueWatchCard({
    super.key,
    required this.history,
    required this.onOpen,
    required this.onResume,
  });

  final History history;
  final VoidCallback onOpen;
  final VoidCallback onResume;

  String get _progressLabel {
    final base = '看到第 ${history.lastWatchEpisode} 集';
    final progress = history.progresses[history.lastWatchEpisode];
    if (progress == null || progress.progress == Duration.zero) return base;
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
    final item = history.bangumiItem;
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: onOpen,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: NetworkImgLayer(
                    src: item.images['large'] ?? '',
                    width: 150,
                    height: 96,
                  ),
                ),
              ),
              Positioned(
                right: 6,
                bottom: 6,
                child: IconButton.filled(
                  tooltip: '继续播放',
                  onPressed: onResume,
                  icon: const Icon(AnikumoIcons.play_arrow_rounded, size: 20),
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            bangumiDisplayTitle(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            _progressLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
