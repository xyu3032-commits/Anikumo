import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:anikumo/services/ui/glass_style.dart';
import 'package:anikumo/utils/constants.dart';

/// A frosted-glass surface: backdrop blur under a translucent fill with
/// a hairline border. Intensity follows [GlassStyle]; at level 0 it
/// degrades to a plain opaque surface, so disabling glass costs nothing.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.strong = false,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final BorderRadius? borderRadius;

  /// Stronger blur and translucency, for hero surfaces.
  final bool strong;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GlassStyle.levelNotifier,
      builder: (context, level, _) {
        final scheme = Theme.of(context).colorScheme;
        final radius = borderRadius ?? StyleString.lgRadius;
        final sigma = GlassStyle.blurSigma(strong: strong);
        Widget surface = Material(
          color: scheme.surface
              .withValues(alpha: GlassStyle.fillOpacity(strong: strong)),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: scheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: padding ?? EdgeInsets.zero,
              child: child,
            ),
          ),
        );
        if (sigma > 0) {
          // Batch 47: the live BackdropFilter is gone (it
          // re-rasterized on every scroll frame wherever a
          // glass surface sat in a list). The boundary stays;
          // the translucent fill carries the look now.
          surface = RepaintBoundary(child: surface);
        }
        return ClipRRect(borderRadius: radius, child: surface);
      },
    );
  }
}
