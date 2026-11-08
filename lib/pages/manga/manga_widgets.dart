import 'dart:io';
import 'dart:typed_data';

import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:anikumo/bean/widget/motion_kit.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_image_pipeline.dart';

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
    this.transformOf,
    this.transform,
  });

  final String url;
  final double width;
  final double height;
  final double radius;
  final Map<String, String> headers;

  /// Batch 102: the original cover url when the source's
  /// thumbnail hook registered an `onResponse` transform for
  /// this cover (see MangaItem.coverTransformOf), plus the
  /// transform itself. Both null on the ordinary path.
  final String? transformOf;
  final MangaByteTransform? transform;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget placeholder = Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
    );
    final Widget error = Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.broken_image_outlined),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? Container(
              width: width,
              height: height,
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.menu_book_outlined),
            )
          : url.startsWith('file://')
              // Batch 102: local (imported) books carry their
              // cover as an extracted page file.
              ? Image.file(
                  File(Uri.parse(url).toFilePath()),
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  cacheWidth: (width * 2).round(),
                  errorBuilder: (context, _, _) => error,
                )
              : transformOf != null && transform != null
                  ? MangaTransformedImage(
                      url: url,
                      headers: headers,
                      cacheManager: mangaCoverCacheManager,
                      transform: transform!,
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                      memCacheWidth: (width * 2).round(),
                      placeholder: placeholder,
                      errorWidget: error,
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
                      // Batch 102: covers use their own gated
                      // cache store now.
                      cacheManager: mangaCoverCacheManager,
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                      // Decode at (up to) twice the display width: grid
                      // covers no longer decode full-size images.
                      memCacheWidth: (width * 2).round(),
                      placeholder: (context, _) => placeholder,
                      errorWidget: (context, _, _) => error,
                    ),
    );
  }
}

/// Batch 102: displays an image whose bytes must pass through
/// a source `onResponse` transform before they can decode
/// (encrypted-image sources). The transformed bytes are
/// cached under the url by [cacheManager], so this costs one
/// download + one engine call per image, ever (until the
/// cache evicts it).
class MangaTransformedImage extends StatefulWidget {
  const MangaTransformedImage({
    super.key,
    required this.url,
    required this.headers,
    required this.cacheManager,
    this.transform,
    this.spec,
    required this.fit,
    required this.placeholder,
    required this.errorWidget,
    this.width,
    this.height,
    this.memCacheWidth,
  });

  final String url;
  final Map<String, String> headers;
  final CacheManager cacheManager;

  /// The byte transform (batch 102 covers/pages). Ignored
  /// when [spec] is given.
  final MangaByteTransform? transform;

  /// Batch 103: a full load spec (transform and/or
  /// modifyImage processing, plus the onLoadFailed fallback
  /// chain) for reader pages.
  final MangaImageLoadSpec? spec;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final Widget placeholder;
  final Widget errorWidget;

  @override
  State<MangaTransformedImage> createState() =>
      _MangaTransformedImageState();
}

class _MangaTransformedImageState extends State<MangaTransformedImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  @override
  void didUpdateWidget(MangaTransformedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = _load();
    }
  }

  Future<Uint8List> _load() {
    final spec = widget.spec;
    if (spec != null) {
      return loadProcessedImageBytes(
        cacheManager: widget.cacheManager,
        spec: spec,
      );
    }
    return loadTransformedImageBytes(
      cacheManager: widget.cacheManager,
      url: widget.url,
      headers: widget.headers,
      transform: widget.transform!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) return widget.errorWidget;
        final data = snapshot.data;
        if (data == null) return widget.placeholder;
        return Image.memory(
          data,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: widget.memCacheWidth,
          gaplessPlayback: true,
          errorBuilder: (context, _, _) => widget.errorWidget,
        );
      },
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
                        : item.coverUrl.startsWith('file://')
                            // Batch 102: local (imported) books.
                            ? Image.file(
                                File(Uri.parse(item.coverUrl).toFilePath()),
                                width: cardWidth,
                                fit: BoxFit.cover,
                                cacheWidth: (cardWidth *
                                        MediaQuery.devicePixelRatioOf(
                                            context))
                                    .round(),
                                errorBuilder: (context, _, _) => Container(
                                  color: theme.colorScheme
                                      .surfaceContainerHighest,
                                  child: const Center(
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              )
                            : coverTransformCallback(item) != null
                                // Batch 102: covers whose bytes an
                                // onResponse transform must fix.
                                ? MangaTransformedImage(
                                    url: item.coverUrl,
                                    headers: item.coverHeaders,
                                    cacheManager: mangaCoverCacheManager,
                                    transform: coverTransformCallback(item)!,
                                    width: cardWidth,
                                    fit: BoxFit.cover,
                                    memCacheWidth: (cardWidth *
                                            MediaQuery.devicePixelRatioOf(
                                                context))
                                        .round(),
                                    placeholder: Container(
                                      color: theme.colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                    errorWidget: Container(
                                      color: theme.colorScheme
                                          .surfaceContainerHighest,
                                      child: const Center(
                                        child:
                                            Icon(Icons.broken_image_outlined),
                                      ),
                                    ),
                                  )
                                : CachedNetworkImage(
                            imageUrl: item.coverUrl,
                            httpHeaders: item.coverHeaders,
                            // Batch 102: dedicated gated cover store.
                            cacheManager: mangaCoverCacheManager,
                            width: cardWidth,
                            fit: BoxFit.cover,
                            // Batch 92: no fade-in, matching
                            // MangaCover (batch 49) and the
                            // reader (batch 88) — this card
                            // still used the 500ms default,
                            // so grid covers kept cross-fading
                            // in while everything around them
                            // appeared instantly.
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
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
                // Batch 92: the status line is always
                // rendered (empty when there is no status),
                // reserving its height — in a fixed-height
                // rail every cover now gets the same height
                // instead of status-less cards stretching
                // taller than their neighbours.
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
            MangaCover(
              url: item.coverUrl,
              width: 44,
              height: 62,
              radius: 8,
              headers: item.coverHeaders,
              transformOf: item.coverTransformOf,
              transform: coverTransformCallback(item),
            ),
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
