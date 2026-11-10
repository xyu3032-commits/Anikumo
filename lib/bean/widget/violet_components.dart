import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:anikumo/bean/theme/violet_glass.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/services/ui/glass_style.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Shared Violet Glass components for the manga / novel zones
/// (batch 38). Every zone page composes THESE instead of
/// hand-rolling its own cards, headers and bars, so the two
/// zones share one component language.

/// Section header: lavender accent bar, bold title, optional
/// subtitle and a trailing text action ( usually 「更多」).
class VioletSectionHeader extends StatelessWidget {
  const VioletSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            gradient: VioletGlass.gradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!),
                const Icon(AnikumoIcons.chevron_right_rounded, size: 16),
              ],
            ),
          ),
      ],
    );
  }
}

/// Static-glass card: translucent violet fill, hairline
/// white-violet border, soft shadow. No per-card backdrop
/// blur (performance budget — blur lives on floating chrome).
class VioletGlassCard extends StatelessWidget {
  const VioletGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.radius = VioletGlass.radiusCard,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        color: VioletGlass.cardFill(context),
        borderRadius: br,
        border: Border.all(color: VioletGlass.border(context)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.25)
                : const Color(0xFF7A5CFF).withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: br,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Real-blur floating glass bar (nav capsule companions,
/// reader toolbars, bottom sheets' grab areas). Blur follows
/// [GlassStyle]; glass off (or smooth mode) → solid surface,
/// zero blur cost.
class VioletGlassBar extends StatelessWidget {
  const VioletGlassBar({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GlassStyle.levelNotifier,
      builder: (context, level, _) {
        final scheme = Theme.of(context).colorScheme;
        final glass = GlassStyle.isEnabled && !SmoothMode.enabled;
        final br = BorderRadius.circular(radius);
        Widget content = Container(
          padding: padding,
          decoration: BoxDecoration(
            color: glass
                ? VioletGlass.cardFill(context)
                : scheme.surfaceContainer,
            borderRadius: br,
            border: Border.all(color: VioletGlass.border(context)),
            boxShadow: VioletGlass.floatingShadow(context),
          ),
          child: child,
        );
        // Batch 47: BackdropFilter removed — see
        // floating_capsule_nav.dart. Translucent fill only.
        return RepaintBoundary(child: content);
      },
    );
  }
}

/// Glass search pill used at the top of zone home pages:
/// search icon, hint text, optional trailing action.
class VioletSearchPill extends StatelessWidget {
  const VioletSearchPill({
    super.key,
    required this.hint,
    required this.onTap,
    this.trailing,
  });

  final String hint;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return VioletGlassCard(
      radius: VioletGlass.radiusPill,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(AnikumoIcons.search_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Thin gradient progress line (continue reading, shelf
/// progress): track in faint lavender, fill in the gradient.
class VioletProgressLine extends StatelessWidget {
  const VioletProgressLine({
    super.key,
    required this.value,
    this.height = 4,
  });

  /// 0..1 (clamped).
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: VioletGlass.primary(context).withValues(alpha: 0.16),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v,
              child: const DecoratedBox(
                decoration: BoxDecoration(gradient: VioletGlass.gradient),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsing skeleton block for loading states. The pulse runs
/// only when animations are welcome (not in smooth mode);
/// otherwise a static block is shown.
class VioletSkeleton extends StatefulWidget {
  const VioletSkeleton({
    super.key,
    this.width,
    this.height,
    this.radius = 12,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  State<VioletSkeleton> createState() => _VioletSkeletonState();
}

class _VioletSkeletonState extends State<VioletSkeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!SmoothMode.enabled) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHigh;
    Widget block = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
    final controller = _controller;
    if (controller == null) return block;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1).animate(controller),
      child: block,
    );
  }
}
