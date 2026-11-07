import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/bean/widget/motion_kit.dart';
import 'package:anikumo/modules/manga/manga_item.dart';

/// Shared building blocks for the manga zone's own visual language:
/// taller covers, denser rails, status dots — deliberately distinct
/// from the anime pages' card system.

class MangaCover extends StatelessWidget {
  const MangaCover({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.radius = 8,
    this.headers = const {},
  });

  final String url;
  final double width;
  final double height;
  final double radius;
  final Map<String, String> headers;

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
              child: const Icon(Icons.menu_book_outlined),
            )
          : CachedNetworkImage(
              // Batch 49: no fade-in on covers. During a
              // fling, dozens of covers fading in at once are
              // dozens of concurrent opacity layers — the
              // image just appears now (it is already decoded
              // at display size).
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
      imageUrl: url,
              httpHeaders: headers,
              width: width,
              height: height,
              fit: BoxFit.cover,
              // Decode at (up to) twice the display width: grid
              // covers no longer decode full-size images.
              memCacheWidth: (width * 2).round(),
              placeholder: (context, _) => Container(
                width: width,
                height: height,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              errorWidget: (context, _, _) => Container(
                width: width,
                height: height,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
    );
  }
}

/// Vertical cover card used in the home rails and search results.
class MangaRailCard extends StatelessWidget {
  const MangaRailCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 104,
    this.badge,
  });

  final MangaItem item;
  final VoidCallback onTap;
  final double width;

  /// Optional small label overlaid on the cover's top-left
  /// corner (used to show the source name in aggregated search).
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: PressableScale(
        child: LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = width.isInfinite ? constraints.maxWidth : width;
        return SizedBox(
          width: cardWidth,
          // The cover flexes to whatever height the cell/rail
          // leaves after the title block — a fixed cover height
          // overflowed grid cells by ~7px with two-line titles.
          child: InkWell(
            onTap: () {
              if (TapDebouncer.accept('manga:${item.source}:${item.id}')) {
                onTap();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: item.coverUrl.isEmpty
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.menu_book_outlined),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: item.coverUrl,
                            httpHeaders: item.coverHeaders,
                            width: cardWidth,
                            fit: BoxFit.cover,
                            // Batch 21: decode at the real
                            // device pixel ratio — the fixed
                            // x2 under-decoded (blurry covers)
                            // on DPR-3 phones.
                            memCacheWidth: (cardWidth *
                                    MediaQuery.devicePixelRatioOf(
                                        context))
                                .round(),
                            placeholder: (context, _) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                            errorWidget: (context, _, _) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                      ),
                      if (badge != null)
                        Positioned(
                          left: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                if (item.statusLabel.isNotEmpty)
                  Text(
                    item.statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
        ),
      ),
    );
  }
}

/// Horizontal row used for the 最新更新 list on the home page.
class MangaListRow extends StatelessWidget {
  const MangaListRow({super.key, required this.item, required this.onTap});

  final MangaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        if (TapDebouncer.accept('manga:${item.source}:${item.id}')) {
          onTap();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            MangaCover(url: item.coverUrl, width: 44, height: 62, radius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (item.author.isNotEmpty) item.author,
                      if (item.year != null) '${item.year}',
                      if (item.statusLabel.isNotEmpty) item.statusLabel,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
