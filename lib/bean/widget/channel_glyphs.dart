import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Batch 62 (appendix): the anime shell channel glyphs,
/// drawn for Anikumo — a cat-ear family in one stroke
/// language (the stock Material icons were replaced at
/// the user's request for a unique set). Each channel
/// has an outline and a filled variant, mirroring the
/// old outlined/filled Material pairing. The literal
/// token COLOR in the SVG strings is replaced with the
/// render color by [ChannelGlyph] before parsing (the
/// same trick as the danmaku icons in the player).
class ChannelGlyphs {
  const ChannelGlyphs._();

  /// 推荐 · cat-house (outline).
  static const homeOutline =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M4 12.4 L6.4 5.6 L9.9 8.8 L14.1 8.8 L17.6 5.6 L20 12.4 M6.4 10.8 L6.4 19.4 L17.6 19.4 L17.6 10.8 M10.3 19.4 L10.3 15.2 Q12 13.9 13.7 15.2 L13.7 19.4" fill="none" stroke="COLOR" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>';

  /// 推荐 · cat-house (filled).
  static const homeFilled =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M4 12.4 L6.4 5.6 L9.9 8.8 L14.1 8.8 L17.6 5.6 L20 12.4 L15.6 12.4 L12 10 L8.4 12.4 Z" fill="COLOR" /><path d="M6.4 10.4 L17.6 10.4 L17.6 19.4 L6.4 19.4 Z M10.3 19.4 L10.3 15.2 Q12 13.9 13.7 15.2 L13.7 19.4" fill="COLOR" fill-rule="evenodd"/></svg>';

  /// 精选 · star with cat-ear accents (outline).
  static const featuredOutline =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12.00 5.20 L13.94 10.43 L19.51 10.66 L15.14 14.12 L16.64 19.49 L12.00 16.40 L7.36 19.49 L8.86 14.12 L4.49 10.66 L10.06 10.43 Z" fill="none" stroke="COLOR" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/><path d="M5.60 6.60 L6.10 4.00 L8.20 6.20 Z M18.40 6.60 L17.90 4.00 L15.80 6.20 Z" fill="COLOR" /></svg>';

  /// 精选 · star with cat-ear accents (filled).
  static const featuredFilled =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12.00 5.20 L13.94 10.43 L19.51 10.66 L15.14 14.12 L16.64 19.49 L12.00 16.40 L7.36 19.49 L8.86 14.12 L4.49 10.66 L10.06 10.43 Z M5.60 6.60 L6.10 4.00 L8.20 6.20 Z M18.40 6.60 L17.90 4.00 L15.80 6.20 Z" fill="COLOR" /></svg>';

  /// 发现 · compass with cat ears (outline).
  static const discoverOutline =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 5.6 A7.4 7.4 0 1 1 11.99 5.6 M12 10 L15 13.4 L12 16.8 L9 13.4 Z" fill="none" stroke="COLOR" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/><circle cx="12" cy="13.4" r="1.05" fill="COLOR"/><path d="M6.90 7.60 L7.40 5.00 L9.50 7.20 Z M17.10 7.60 L16.60 5.00 L14.50 7.20 Z" fill="COLOR" /></svg>';

  /// 发现 · compass with cat ears (filled).
  static const discoverFilled =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 5.6 A7.4 7.4 0 1 1 11.99 5.6" fill="none" stroke="COLOR" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 10 L15 13.4 L12 16.8 L9 13.4 Z M6.90 7.60 L7.40 5.00 L9.50 7.20 Z M17.10 7.60 L16.60 5.00 L14.50 7.20 Z" fill="COLOR" /><circle cx="12" cy="13.4" r="1.05" fill="COLOR"/></svg>';

  /// 时光 · hourglass with cat ears (outline).
  static const momentsOutline =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M6.8 4.8 L17.2 4.8 M6.8 19.6 L17.2 19.6 M7.6 4.8 C7.6 9.2 12 10.4 12 12.2 C12 14 16.4 15.2 16.4 19.6 M16.4 4.8 C16.4 9.2 12 10.4 12 12.2" fill="none" stroke="COLOR" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/><path d="M5.90 4.80 L6.40 2.60 L8.10 4.40 Z M18.10 4.80 L17.60 2.60 L15.90 4.40 Z" fill="COLOR" /></svg>';

  /// 时光 · hourglass with cat ears (filled).
  static const momentsFilled =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M6.8 4.8 L17.2 4.8 M6.8 19.6 L17.2 19.6 M7.6 4.8 C7.6 9.2 12 10.4 12 12.2 C12 14 16.4 15.2 16.4 19.6 M16.4 4.8 C16.4 9.2 12 10.4 12 12.2" fill="none" stroke="COLOR" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/><path d="M5.90 4.80 L6.40 2.60 L8.10 4.40 Z M18.10 4.80 L17.60 2.60 L15.90 4.40 Z M9.9 19.6 L12 16.9 L14.1 19.6 Z" fill="COLOR" /></svg>';

  /// 时间表 · calendar, ears as binder posts (outline).
  static const scheduleOutline =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M5.4 7 L18.6 7 L18.6 19.8 Q18.6 20.6 17.8 20.6 L6.2 20.6 Q5.4 20.6 5.4 19.8 Z M5.4 10.6 L18.6 10.6" fill="none" stroke="COLOR" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/><circle cx="8.9" cy="14" r="1.15" fill="COLOR"/><circle cx="12.1" cy="14" r="1.15" fill="COLOR"/><circle cx="15.3" cy="14" r="1.15" fill="COLOR"/><circle cx="8.9" cy="17.2" r="1.15" fill="COLOR"/><circle cx="12.1" cy="17.2" r="1.15" fill="COLOR"/><path d="M6.60 7.00 L7.10 4.10 L8.90 6.60 Z M17.40 7.00 L16.90 4.10 L15.10 6.60 Z" fill="COLOR" /></svg>';

  /// 时间表 · calendar, ears as binder posts (filled).
  static const scheduleFilled =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M5.4 7 L18.6 7 L18.6 19.8 Q18.6 20.6 17.8 20.6 L6.2 20.6 Q5.4 20.6 5.4 19.8 Z" fill="none" stroke="COLOR" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/><path d="M5.4 7 L18.6 7 L18.6 10.6 L5.4 10.6 Z M6.60 7.00 L7.10 4.10 L8.90 6.60 Z M17.40 7.00 L16.90 4.10 L15.10 6.60 Z" fill="COLOR" /><circle cx="8.9" cy="14" r="1.15" fill="COLOR"/><circle cx="12.1" cy="14" r="1.15" fill="COLOR"/><circle cx="15.3" cy="14" r="1.15" fill="COLOR"/><circle cx="8.9" cy="17.2" r="1.15" fill="COLOR"/><circle cx="12.1" cy="17.2" r="1.15" fill="COLOR"/></svg>';

  /// 追番 · heart with ear horns (outline).
  static const followingOutline =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 20.2 C7.2 16.6 4.2 13.4 4.2 10.1 C4.2 7.3 6.1 5.2 8.5 5.2 C10 5.2 11.3 6.1 12 7.4 C12.7 6.1 14 5.2 15.5 5.2 C17.9 5.2 19.8 7.3 19.8 10.1 C19.8 13.4 16.8 16.6 12 20.2 Z" fill="none" stroke="COLOR" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/><path d="M6.00 6.90 L6.50 4.40 L8.40 6.50 Z M18.00 6.90 L17.50 4.40 L15.60 6.50 Z" fill="COLOR" /></svg>';

  /// 追番 · heart with ear horns (filled).
  static const followingFilled =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 20.2 C7.2 16.6 4.2 13.4 4.2 10.1 C4.2 7.3 6.1 5.2 8.5 5.2 C10 5.2 11.3 6.1 12 7.4 C12.7 6.1 14 5.2 15.5 5.2 C17.9 5.2 19.8 7.3 19.8 10.1 C19.8 13.4 16.8 16.6 12 20.2 Z M6.00 6.90 L6.50 4.40 L8.40 6.50 Z M18.00 6.90 L17.50 4.40 L15.60 6.50 Z" fill="COLOR" /></svg>';

  /// 我的 · cat face (outline).
  static const mineOutline =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 5.4 C16.9 5.4 19.7 8.8 19.7 12.9 C19.7 17.1 16.2 20 12 20 C7.8 20 4.3 17.1 4.3 12.9 C4.3 8.8 7.1 5.4 12 5.4 Z" fill="none" stroke="COLOR" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/><path d="M6.30 7.90 L6.80 4.90 L9.20 7.50 Z M17.70 7.90 L17.20 4.90 L14.80 7.50 Z" fill="COLOR" /><circle cx="9.2" cy="12.7" r="1.05" fill="COLOR"/><circle cx="14.8" cy="12.7" r="1.05" fill="COLOR"/></svg>';

  /// 我的 · cat face (filled).
  static const mineFilled =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 5.4 C16.9 5.4 19.7 8.8 19.7 12.9 C19.7 17.1 16.2 20 12 20 C7.8 20 4.3 17.1 4.3 12.9 C4.3 8.8 7.1 5.4 12 5.4 Z M6.30 7.90 L6.80 4.90 L9.20 7.50 Z M17.70 7.90 L17.20 4.90 L14.80 7.50 Z M9.2 11.65 A1.05 1.05 0 1 1 9.19 11.65 M14.8 11.65 A1.05 1.05 0 1 1 14.79 11.65" fill="COLOR" fill-rule="evenodd"/></svg>';

}

/// Renders one [ChannelGlyphs] string tinted [color].
class ChannelGlyph extends StatelessWidget {
  const ChannelGlyph({super.key, required this.svg, required this.color, required this.size});

  final String svg;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hex = color.toARGB32().toRadixString(16).substring(2);
    return SvgPicture.string(
      svg.replaceAll('COLOR', '#$hex'),
      width: size,
      height: size,
    );
  }
}
