import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:anikumo/services/ui/glass_style.dart';

/// The floating capsule navigation bar — anikumo's signature
/// shell element (batch 14 gave it to the main anime shell;
/// batch 29 extends the same pill to the manga and novel zone
/// shells so all three zones share one navigation language).
///
/// The pill floats inside the scaffold's reserved bottom band
/// (never overlays content), carries the frosted-glass blur
/// when glass is enabled, and falls back to a solid elevated
/// surface at glass level 0.
class FloatingCapsuleNavBar extends StatelessWidget {
  const FloatingCapsuleNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GlassStyle.levelNotifier,
      builder: (context, level, _) {
        final glass = GlassStyle.isEnabled;
        final scheme = Theme.of(context).colorScheme;
        Widget bar = NavigationBar(
          height: 64,
          backgroundColor: glass
              ? scheme.surface.withValues(alpha: GlassStyle.navFillOpacity)
              : scheme.surfaceContainer,
          elevation: 0,
          destinations: destinations,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
        );
        // Batch 47: no BackdropFilter here anymore. The bar
        // floats over scrolling lists, so a live backdrop
        // blur re-rasterized every frame — the main source
        // of scroll/button jank on the zone home pages. The
        // translucent fill (opacity still follows the glass
        // level setting) keeps the frosted look at zero
        // filter cost.
        bar = Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.07),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: bar,
          ),
        );
        return SafeArea(
          top: false,
          child: RepaintBoundary(child: bar),
        );
      },
    );
  }
}
