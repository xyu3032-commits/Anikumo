import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/bean/theme/signature.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';

import 'package:flutter_modular/flutter_modular.dart';

import '../../models/novel_item.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Open a novel's detail page (zone route).
void openNovelDetail(BuildContext context, NovelItem item) {
  if (!TapDebouncer.accept('novel:${item.storageKey}')) return;
  context.pushNamed('/novel/detail', arguments: item);
}

/// Cover image for a novel (same treatment as manga covers:
/// cached, sized decode, graceful placeholders).
class NovelCover extends StatelessWidget {
  const NovelCover({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final String url;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? Container(
              width: width,
              height: height,
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(AnikumoIcons.auto_stories_outlined),
            )
          : CachedNetworkImage(
              imageUrl: url,
              width: width,
              height: height,
              fit: BoxFit.cover,
              memCacheWidth:
                  (width * MediaQuery.devicePixelRatioOf(context)).round(),
              // Batch 49: see MangaCover — no fade layers in
              // scrolling lists.
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (context, _) => Container(
                width: width,
                height: height,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              errorWidget: (context, _, _) => Container(
                width: width,
                height: height,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(AnikumoIcons.broken_image_outlined),
              ),
            ),
    );
  }
}

/// A book card for horizontal rails: cover, title, author.
class NovelRailCard extends StatelessWidget {
  const NovelRailCard({super.key, required this.item, this.width = 104});

  final NovelItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = width.isFinite ? width : constraints.maxWidth;
        // Batch 30: the cover used to be a rigid width*1.36 —
        // in tighter grid cells (narrow screens, larger text
        // scale) cover + two title lines + author overflowed
        // the cell. The cover now gives back height when the
        // parent offers less than the full card needs.
        final scaler = MediaQuery.textScalerOf(context);
        final textReserve = 6 +
            scaler.scale(14) * 1.25 * 2 +
            (item.author.isNotEmpty ? scaler.scale(12) * 1.4 : 0);
        final coverHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - textReserve)
                .clamp(60.0, w * 1.36)
            : w * 1.36;
        return SizedBox(
          width: w,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => openNovelDetail(context, item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NovelCover(
                  url: item.coverUrl,
                  width: w,
                  height: coverHeight,
                ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
                if (item.author.isNotEmpty)
                  Text(
                    item.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A book row for lists (search results, favorites, history).
class NovelBookTile extends StatelessWidget {
  const NovelBookTile({
    super.key,
    required this.item,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final NovelItem item;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: NovelCover(url: item.coverUrl, width: 44, height: 60, radius: 8),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle ??
            [
              if (item.author.isNotEmpty) item.author,
              if (item.lastChapter.isNotEmpty) item.lastChapter,
            ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      trailing: trailing ??
          (item.sourceName.isNotEmpty
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 92),
                  child: Chip(
                    label: Text(
                      item.sourceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                )
              : null),
      onTap: onTap ?? () => openNovelDetail(context, item),
    );
  }
}

/// A section header inside the novel zone.
class NovelSectionHeader extends StatelessWidget {
  const NovelSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              gradient: VioletGlass.gradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Full-area error state with the real reason and a retry —
/// the pattern the batch-27 pages established.
class NovelErrorState extends StatelessWidget {
  const NovelErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('加载失败，点这里重试')),
          ],
        ),
      ),
    );
  }
}
