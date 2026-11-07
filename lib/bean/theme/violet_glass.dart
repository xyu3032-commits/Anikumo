import 'package:flutter/material.dart';

/// Violet Glass design system (batch 38) — scoped to the manga
/// and novel zones ONLY. The anime zone and the global
/// Signature scheme stay exactly as they are; every manga /
/// novel route wraps its page in [VioletZone], which installs
/// this theme for that subtree.
///
/// Language: deep violet-black (dark) / moon white (light),
/// lavender primary, moonlight secondary, translucent violet
/// glass cards with hairline white-violet borders, soft
/// shadows, generous radii. Real backdrop blur is reserved
/// for floating chrome (nav capsule, reader toolbars, sheets)
/// per the zone's performance budget — in-list cards use the
/// static translucent fill, which reads as the same glass at a
/// fraction of the raster cost.
abstract final class VioletGlass {
  // ── Brand ────────────────────────────────────────────────
  /// 高级薰衣草紫 — the primary accent (dark scheme).
  static const Color lavender = Color(0xFFB7A6FF);

  /// Deeper lavender for the light scheme (contrast on white).
  static const Color lavenderDeep = Color(0xFF7A5CFF);

  /// 月光紫 — the secondary accent.
  static const Color moonlight = Color(0xFFD8CCFF);

  /// Soft success / error (both schemes keep the soft tone).
  static const Color success = Color(0xFF8FE3B0);
  static const Color successLight = Color(0xFF2E9E63);
  static const Color error = Color(0xFFFF9D9D);
  static const Color errorLight = Color(0xFFD64545);

  /// The zone's signature gradient: lavender into moonlight.
  /// Used sparingly (selected capsule, banner CTA, markers).
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9D86FF), Color(0xFFB7A6FF)],
  );

  // ── Radii ────────────────────────────────────────────────
  static const double radiusCard = 20;
  static const double radiusSheet = 28;
  static const double radiusPill = 999;

  // ── Brightness-aware tokens ──────────────────────────────
  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Page background: deep violet-black / moon white.
  static Color background(BuildContext context) => _dark(context)
      ? const Color(0xFF0C0913)
      : const Color(0xFFF5F2FB);

  /// Translucent card fill (the static glass look).
  static Color cardFill(BuildContext context) => _dark(context)
      ? const Color(0xFF1E1733).withValues(alpha: 0.72)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.78);

  /// Hairline border: low-opacity white-violet.
  static Color border(BuildContext context) => _dark(context)
      ? const Color(0xFFD8CCFF).withValues(alpha: 0.14)
      : const Color(0xFF7A5CFF).withValues(alpha: 0.14);

  static Color primary(BuildContext context) =>
      _dark(context) ? lavender : lavenderDeep;

  static Color secondary(BuildContext context) =>
      _dark(context) ? moonlight : const Color(0xFF9B85FF);

  static Color successOf(BuildContext context) =>
      _dark(context) ? success : successLight;

  static Color errorOf(BuildContext context) =>
      _dark(context) ? error : errorLight;

  /// Soft shadow under floating glass chrome.
  static List<BoxShadow> floatingShadow(BuildContext context) => [
        BoxShadow(
          color: _dark(context)
              ? Colors.black.withValues(alpha: 0.45)
              : const Color(0xFF7A5CFF).withValues(alpha: 0.14),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// The scoped [ThemeData] for a manga / novel subtree:
  /// the ambient theme with its color scheme re-tinted to the
  /// Violet Glass palette and its chrome (nav indicator,
  /// chips, cards, dividers) aligned to the zone language.
  static ThemeData themeOf(BuildContext context) {
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final scheme = base.colorScheme.copyWith(
      primary: dark ? lavender : lavenderDeep,
      onPrimary: dark ? const Color(0xFF2A1B5E) : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF3A2A6B) : const Color(0xFFE4DBFF),
      onPrimaryContainer:
          dark ? const Color(0xFFE4DBFF) : const Color(0xFF3A2A6B),
      secondary: dark ? moonlight : const Color(0xFF9B85FF),
      onSecondary: dark ? const Color(0xFF2A1B5E) : Colors.white,
      secondaryContainer:
          dark ? const Color(0xFF2C2150) : const Color(0xFFEDE7FF),
      onSecondaryContainer:
          dark ? const Color(0xFFD8CCFF) : const Color(0xFF463377),
      tertiary: dark ? const Color(0xFF8F7BFF) : const Color(0xFF6A4AE0),
      surface: dark ? const Color(0xFF171126) : const Color(0xFFFBF9FF),
      onSurface: dark ? const Color(0xFFF4F1FF) : const Color(0xFF221A3D),
      surfaceDim: dark ? const Color(0xFF0C0913) : const Color(0xFFE9E2F6),
      surfaceBright:
          dark ? const Color(0xFF322657) : const Color(0xFFFFFFFF),
      surfaceContainerLowest:
          dark ? const Color(0xFF120D1E) : const Color(0xFFFFFFFF),
      surfaceContainerLow:
          dark ? const Color(0xFF1A1429) : const Color(0xFFF5F1FC),
      surfaceContainer:
          dark ? const Color(0xFF1E1733) : const Color(0xFFEFEBF9),
      surfaceContainerHigh:
          dark ? const Color(0xFF271E42) : const Color(0xFFE7DFF6),
      surfaceContainerHighest:
          dark ? const Color(0xFF322657) : const Color(0xFFDCD0F2),
      onSurfaceVariant:
          dark ? const Color(0xFFB9B0D9) : const Color(0xFF5D5478),
      outline: dark ? const Color(0xFF57497D) : const Color(0xFFA79BCB),
      outlineVariant:
          dark ? const Color(0xFF3A2E5C) : const Color(0xFFD9D0EE),
      error: dark ? error : errorLight,
      onError: dark ? const Color(0xFF4A0E0E) : Colors.white,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background(context),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: cardFill(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: border(context)),
        ),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        // The selected destination's capsule: lavender glass.
        indicatorColor: (dark ? lavender : lavenderDeep)
            .withValues(alpha: dark ? 0.28 : 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: border(context)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: border(context),
        thickness: 0.7,
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.18),
      ),
    );
  }
}

/// Installs the Violet Glass scoped theme over [child].
/// Applied by every manga / novel route builder so pushed
/// pages (detail, reader, search…) share the zone language
/// while the rest of the app keeps the global theme.
class VioletZone extends StatelessWidget {
  const VioletZone({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: VioletGlass.themeOf(context),
      child: child,
    );
  }
}
