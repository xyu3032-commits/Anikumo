// Reader settings model for the manga zone, mirroring Venera's
// reading options: gallery (paged) modes in both directions plus
// a continuous (webtoon) mode.

abstract final class MangaReaderModes {
  /// Paged, pages advance left → right (manhua / western style).
  static const galleryLtr = 'galleryLTR';

  /// Paged, pages advance right → left (manga style).
  static const galleryRtl = 'galleryRTL';

  /// Continuous vertical scroll.
  static const continuous = 'continuous';

  static const labels = <String, String>{
    galleryLtr: '分页 · 从左到右',
    galleryRtl: '分页 · 从右到左（日漫）',
    continuous: '连续滚动 · 条漫',
  };
}

/// Normalizes a stored reader mode, migrating the first version's
/// 'paged' / 'scroll' values to the Venera-style mode names.
String normalizeMangaReaderMode(String raw) {
  return switch (raw) {
    MangaReaderModes.galleryLtr ||
    MangaReaderModes.galleryRtl ||
    MangaReaderModes.continuous =>
      raw,
    'scroll' => MangaReaderModes.continuous,
    _ => MangaReaderModes.galleryLtr,
  };
}

/// Content ratings requested from MangaDex for listings.
List<String> mangaContentRatings(bool allowSuggestive) {
  return allowSuggestive ? const ['safe', 'suggestive'] : const ['safe'];
}
