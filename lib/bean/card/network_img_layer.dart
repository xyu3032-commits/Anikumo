import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/utils/image_extension.dart';

/// Batch 72: the ordered URL candidates for a network image.
/// Bangumi's cover CDN serves several sizes of the same
/// cover; when the requested size fails transiently (timeouts
/// and 5xx from that host are common under a grid's parallel
/// load), another size of the SAME cover usually succeeds.
List<String> imageRetryCandidates(String src, String? fallbackSrc) {
  final candidates = <String>[];
  if (src.isNotEmpty) candidates.add(src);
  if (fallbackSrc != null && fallbackSrc.isNotEmpty && fallbackSrc != src) {
    candidates.add(fallbackSrc);
  }
  return candidates;
}

class NetworkImgLayer extends StatefulWidget {
  const NetworkImgLayer({
    super.key,
    this.src,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.type,
    this.fadeOutDuration,
    this.fadeInDuration,
    this.origAspectRatio,
    this.filterQuality = FilterQuality.high,
    this.color,
    this.colorBlendMode,
    this.borderRadius,
    this.fallbackSrc,
  });

  final String? src;
  final double width;
  final double height;
  final BoxFit fit;
  final String? type;
  final Duration? fadeOutDuration;
  final Duration? fadeInDuration;
  final double? origAspectRatio;
  final FilterQuality filterQuality;
  final Color? color;
  final BlendMode? colorBlendMode;
  final BorderRadius? borderRadius;

  /// Batch 72: an alternate URL for the same image (another
  /// size of the same cover), tried when [src] keeps failing.
  final String? fallbackSrc;

  static Widget heroFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final fromHero = fromHeroContext.widget as Hero;
    final toHero = toHeroContext.widget as Hero;
    final heroContext = flightDirection == HeroFlightDirection.push
        ? fromHeroContext
        : toHeroContext;
    final hero = flightDirection == HeroFlightDirection.push
        ? fromHero
        : toHero;

    return InheritedTheme.captureAll(
      heroContext,
      Material(type: MaterialType.transparency, child: hero.child),
    );
  }

  @override
  State<NetworkImgLayer> createState() => _NetworkImgLayerState();
}

class _NetworkImgLayerState extends State<NetworkImgLayer> {
  // Batch 72: cover loads used to be single-attempt — one
  // transient failure (device report: 发现页封面「有几率失败」)
  // pinned the paw placeholder until the card happened to be
  // rebuilt. Each candidate URL now gets one delayed retry,
  // then the next candidate (the fallback size) gets its own
  // retry, before the placeholder is allowed to stick.
  int _candidate = 0;
  int _retries = 0;
  bool _gaveUp = false;
  Timer? _retryTimer;

  List<String> get _candidates =>
      imageRetryCandidates(widget.src ?? '', widget.fallbackSrc);

  @override
  void didUpdateWidget(NetworkImgLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src ||
        oldWidget.fallbackSrc != widget.fallbackSrc) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _candidate = 0;
      _retries = 0;
      _gaveUp = false;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _handleError(Object error) {
    AnikumoLogger().w('NetworkImage: network image load error', error: error);
    if (!mounted || _gaveUp || _retryTimer != null) return;
    final canRetry = _retries < 1;
    final canAdvance = _candidate + 1 < _candidates.length;
    if (!canRetry && !canAdvance) {
      _gaveUp = true;
      return;
    }
    _retryTimer = Timer(
      canRetry
          ? const Duration(milliseconds: 700)
          : const Duration(milliseconds: 400),
      () {
        _retryTimer = null;
        if (!mounted) return;
        setState(() {
          if (canRetry) {
            _retries++;
          } else {
            _candidate++;
            _retries = 0;
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    if (candidates.isEmpty) {
      return _placeholder(context);
    }
    final imageUrl =
        candidates[_candidate < candidates.length
            ? _candidate
            : candidates.length - 1];

    final (memCacheWidth, memCacheHeight) = _cacheSize(context);
    return ClipRRect(
      clipBehavior: Clip.antiAlias,
      borderRadius: _borderRadius,
      child: CachedNetworkImage(
        // A fresh key per attempt: a failed download is not
        // cached, but the widget only re-requests when its
        // provider is recreated.
        key: ValueKey('nil:$imageUrl:$_candidate:$_retries'),
        imageUrl: imageUrl,
        width: widget.width,
        height: widget.height,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        fit: widget.fit,
        fadeOutDuration:
            widget.fadeOutDuration ?? const Duration(milliseconds: 120),
        fadeInDuration:
            widget.fadeInDuration ?? const Duration(milliseconds: 120),
        filterQuality: widget.filterQuality,
        color: widget.color,
        colorBlendMode: widget.colorBlendMode,
        errorListener: _handleError,
        errorWidget: (context, url, error) => _placeholder(context),
        placeholder: (context, url) => _placeholder(context),
      ),
    );
  }

  (int?, int?) _cacheSize(BuildContext context) {
    final cacheWidth = widget.width.cacheSize(context);
    final cacheHeight = widget.height.cacheSize(context);
    final aspectRatio = widget.width / widget.height;
    final sourceAspectRatio = widget.origAspectRatio;

    switch (widget.fit) {
      case BoxFit.none:
      case BoxFit.scaleDown:
        // These modes depend on the original image dimensions.
        return (null, null);
      case BoxFit.fill:
        return (cacheWidth, cacheHeight);
      case BoxFit.fitWidth:
        return (cacheWidth, null);
      case BoxFit.fitHeight:
        return (null, cacheHeight);
      case BoxFit.contain:
        // A single decode axis preserves unknown source proportions.
        return sourceAspectRatio != null && sourceAspectRatio > aspectRatio
            ? (cacheWidth, null)
            : (null, cacheHeight);
      case BoxFit.cover:
        // Decode enough pixels along the axis that fills the box.
        if (sourceAspectRatio != null) {
          if (sourceAspectRatio < aspectRatio) return (cacheWidth, null);
          if (sourceAspectRatio > aspectRatio) return (null, cacheHeight);
        } else {
          if (aspectRatio > 1) return (null, cacheHeight);
          if (aspectRatio < 1) return (cacheWidth, null);
        }
        return (cacheWidth, cacheHeight);
    }
  }

  BorderRadius get _borderRadius =>
      widget.borderRadius ??
      BorderRadius.circular(switch (widget.type) {
        'avatar' => 50,
        'emote' => 0,
        _ => StyleString.imgRadius.x,
      });

  Widget _placeholder(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.onInverseSurface.withValues(alpha: 0.4),
        borderRadius: _borderRadius,
      ),
      child: widget.type == 'bg'
          ? const SizedBox()
          : Center(
              child: Image.asset(
                widget.type == 'avatar'
                    ? 'assets/images/noface.jpeg'
                    : 'assets/images/loading.png',
                width: widget.width,
                height: widget.height,
                cacheWidth: widget.width.cacheSize(context),
                cacheHeight: widget.height.cacheSize(context),
              ),
            ),
    );
  }
}
