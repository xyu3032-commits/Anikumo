import 'package:flutter/material.dart';

/// anikumo's signature design language (batch 29 visual overhaul).
///
/// The identity anchors carried over from earlier redesigns:
/// iris violet as the primary hue, frosted glass surfaces and
/// the floating capsule navigation. What changes is everything
/// around them — the scheme is hand-tinted (violet ink surfaces
/// instead of stock Material greys), shapes get rounder, type
/// gets bolder, and a single aurora gradient (iris → teal) is
/// the recurring accent on entry tiles and section markers.
abstract final class Signature {
  /// The default theme color: an evolved iris violet (batch 14
  /// used 0xFF5F55E0; batch 29 brightens it toward indigo).
  static const Color primary = Color(0xFF6C5CE7);

  /// The aurora partner color (used at the gradient's far end
  /// and as the scheme's tertiary).
  static const Color auroraTeal = Color(0xFF00A8B5);

  /// The signature aurora gradient: iris violet into teal.
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, auroraTeal],
  );

  /// Hand-tinted light scheme: white cards over a lavender-grey
  /// app background, violet-tinted ink text. Stock Material
  /// surfaces are neutral grey; the tint is what makes the app
  /// read as a different product at a glance.
  static ColorScheme tintLight(ColorScheme base) {
    return base.copyWith(
      tertiary: auroraTeal,
      surface: const Color(0xFFFBFAFE),
      surfaceDim: const Color(0xFFE3DEF2),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF5F3FC),
      surfaceContainer: const Color(0xFFEDEAF8),
      surfaceContainerHigh: const Color(0xFFE4DEF3),
      surfaceContainerHighest: const Color(0xFFD9D1EC),
      onSurface: const Color(0xFF1D1930),
      onSurfaceVariant: const Color(0xFF4B4560),
      outline: const Color(0xFF7B7394),
      outlineVariant: const Color(0xFFCFC8E0),
    );
  }

  /// Hand-tinted dark scheme: deep violet-ink surfaces instead
  /// of neutral near-black.
  static ColorScheme tintDark(ColorScheme base) {
    return base.copyWith(
      tertiary: auroraTeal,
      surface: const Color(0xFF16131E),
      surfaceDim: const Color(0xFF100D16),
      surfaceContainerLowest: const Color(0xFF0D0B12),
      surfaceContainerLow: const Color(0xFF1C1828),
      surfaceContainer: const Color(0xFF221D31),
      surfaceContainerHigh: const Color(0xFF2B2440),
      surfaceContainerHighest: const Color(0xFF352C4F),
      onSurface: const Color(0xFFEDEAF6),
      onSurfaceVariant: const Color(0xFFB4ACCC),
      outline: const Color(0xFF6E648C),
      outlineVariant: const Color(0xFF3A3352),
    );
  }

  /// Scaffold background paired with the tinted schemes.
  static Color scaffoldOf(Brightness brightness) =>
      brightness == Brightness.light
          ? const Color(0xFFF5F3FC)
          : const Color(0xFF12101A);
}

/// The recurring section marker: a short rounded bar in the
/// aurora gradient, placed before section titles across the
/// anime, manga and novel surfaces so the three zones share
/// one recognizable rhythm.
class SectionAccentBar extends StatelessWidget {
  const SectionAccentBar({super.key, this.height = 20});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: height,
      decoration: const BoxDecoration(
        gradient: Signature.gradient,
        borderRadius: BorderRadius.all(Radius.circular(2)),
      ),
    );
  }
}
