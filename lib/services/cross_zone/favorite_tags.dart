import 'dart:convert';

import 'package:anikumo/services/storage/storage.dart';

/// Batch 283 (#21): user tags on favorites, one map for
/// all four zones. Keys are zone-prefixed stable ids so
/// the zones can never collide:
///
/// - anime: `anime:<bangumiId>`
/// - manga: `manga:<MangaItem.storageKey>` (`source:id`)
/// - novel: `novel:<NovelItem.storageKey>` (`source::url`)
/// - film:  `film:<mediaId>`
///
/// Values are tag name sets. The codec normalizes on
/// the way in and out (trimmed, de-duplicated, sorted,
/// empty rows dropped) so the pure helpers below can
/// assume a clean map. Only the cross-zone favorites
/// page reads and writes this store in this batch;
/// each zone's own favorites page is untouched.
abstract final class FavoriteTags {
  static String animeKey(int bangumiId) => 'anime:$bangumiId';
  static String mangaKey(String storageKey) => 'manga:$storageKey';
  static String novelKey(String storageKey) => 'novel:$storageKey';
  static String filmKey(String mediaId) => 'film:$mediaId';

  static List<String> _normalize(Iterable<dynamic> raw) {
    final tags = <String>{
      for (final value in raw)
        if (value != null && value.toString().trim().isNotEmpty)
          value.toString().trim(),
    }.toList()
      ..sort();
    return tags;
  }

  static Map<String, List<String>> decodeAll(String raw) {
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            if (e.key.toString().isNotEmpty &&
                _normalize(e.value as List? ?? const []).isNotEmpty)
              e.key.toString(): _normalize(e.value as List? ?? const []),
        };
      }
    } catch (_) {}
    return {};
  }

  static String encodeAll(Map<String, List<String>> tags) => jsonEncode({
        for (final e in tags.entries)
          if (e.value.isNotEmpty) e.key: _normalize(e.value),
      });

  /// Every tag in use, sorted — the filter chip row.
  static List<String> allTags(Map<String, List<String>> tags) {
    final all = <String>{for (final list in tags.values) ...list}.toList()
      ..sort();
    return all;
  }

  static List<String> tagsFor(
    Map<String, List<String>> tags,
    String itemKey,
  ) =>
      tags[itemKey] ?? const [];

  /// Adds or removes one tag on one item, returning a
  /// new map. Removing an item's last tag drops its row.
  static Map<String, List<String>> withTag(
    Map<String, List<String>> tags,
    String itemKey,
    String tag,
    bool present,
  ) {
    final clean = tag.trim();
    if (clean.isEmpty) return tags;
    final next = {
      for (final e in tags.entries) e.key: [...e.value],
    };
    final current = next[itemKey] ?? <String>[];
    if (present) {
      if (!current.contains(clean)) current.add(clean);
    } else {
      current.remove(clean);
    }
    if (current.isEmpty) {
      next.remove(itemKey);
    } else {
      current.sort();
      next[itemKey] = current;
    }
    return next;
  }

  /// Item keys carrying [tag] — the page filter.
  static Set<String> keysWithTag(
    Map<String, List<String>> tags,
    String tag,
  ) =>
      {
        for (final e in tags.entries)
          if (e.value.contains(tag)) e.key,
      };

  // ---- storage wrappers ----

  static Map<String, List<String>> load() =>
      decodeAll(GStorage.getSetting(SettingsKeys.favoriteTagsJson));

  static Future<void> save(Map<String, List<String>> tags) {
    return GStorage.putSetting(
      SettingsKeys.favoriteTagsJson,
      encodeAll(tags),
    );
  }

  static Future<Map<String, List<String>>> setTag(
    String itemKey,
    String tag,
    bool present,
  ) async {
    final next = withTag(load(), itemKey, tag, present);
    await save(next);
    return next;
  }
}
