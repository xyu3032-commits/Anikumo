import 'dart:convert';

import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 15 manga extras: ratings, pins, update checks, reading
/// statistics and search history. All state lives in settings
/// JSON strings, following the library store's pattern; the
/// decision logic is pure and unit-tested.

// ── Ratings + short notes (M4) ───────────────────────────────

class MangaRating {
  const MangaRating({
    required this.key,
    required this.stars,
    required this.note,
    required this.updatedAtMs,
  });

  /// 'source:id'
  final String key;

  /// 0 (unrated) to 5, in 0.5 steps.
  final double stars;
  final String note;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
        'key': key,
        'stars': stars,
        'note': note,
        'updatedAtMs': updatedAtMs,
      };

  static MangaRating? fromJson(Map<dynamic, dynamic> json) {
    final key = json['key']?.toString() ?? '';
    if (key.isEmpty) return null;
    return MangaRating(
      key: key,
      stars: (json['stars'] as num?)?.toDouble() ?? 0,
      note: json['note']?.toString() ?? '',
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class MangaExtrasStore {
  MangaExtrasStore._();

  static Map<String, MangaRating> loadRatings() {
    final raw = GStorage.getSetting(SettingsKeys.mangaRatingsJson);
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <String, MangaRating>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          final rating = MangaRating.fromJson(
            (entry.value as Map).cast<dynamic, dynamic>(),
          );
          if (rating != null) result[rating.key] = rating;
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  static Future<void> saveRating(MangaRating rating) async {
    final ratings = {...loadRatings()};
    if (rating.stars <= 0 && rating.note.isEmpty) {
      ratings.remove(rating.key);
    } else {
      ratings[rating.key] = rating;
    }
    await GStorage.putSetting(
      SettingsKeys.mangaRatingsJson,
      jsonEncode(ratings.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  // ── Pins (M5) ────────────────────────────────────────────

  static Set<String> loadPinned() {
    final raw = GStorage.getSetting(SettingsKeys.mangaPinnedJson);
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return {for (final e in decoded) e.toString()};
    } catch (_) {
      return const {};
    }
  }

  static Future<void> savePinned(Set<String> keys) async {
    await GStorage.putSetting(
      SettingsKeys.mangaPinnedJson,
      jsonEncode(keys.toList()),
    );
  }

  // ── Known chapter counts for update checks (M2) ──────────

  static Map<String, int> loadKnownChapterCounts() {
    final raw = GStorage.getSetting(SettingsKeys.mangaKnownChaptersJson);
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final e in decoded.entries)
          e.key.toString(): (e.value as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return const {};
    }
  }

  static Future<void> saveKnownChapterCounts(Map<String, int> counts) {
    return GStorage.putSetting(
      SettingsKeys.mangaKnownChaptersJson,
      jsonEncode(counts),
    );
  }

  // ── Search history (M8) ──────────────────────────────────

  static List<String> loadSearchHistory() {
    final raw = GStorage.getSetting(SettingsKeys.mangaSearchHistoryJson);
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [for (final e in decoded) e.toString()];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> addSearchKeyword(String keyword) async {
    final next = addKeywordToHistory(loadSearchHistory(), keyword);
    await GStorage.putSetting(
      SettingsKeys.mangaSearchHistoryJson,
      jsonEncode(next),
    );
  }

  static Future<void> clearSearchHistory() {
    return GStorage.putSetting(SettingsKeys.mangaSearchHistoryJson, '');
  }
}

/// Prepends [keyword] (trimmed, de-duplicated), capped at 20.
List<String> addKeywordToHistory(List<String> history, String keyword) {
  final trimmed = keyword.trim();
  if (trimmed.isEmpty) return history;
  return [
    trimmed,
    for (final entry in history)
      if (entry != trimmed) entry,
  ].take(20).toList();
}

// ── Favorite sorting (M5) ────────────────────────────────────

enum MangaFavoriteSort { recentRead, title, rating, addedOrder }

/// Pinned favorites always float first (keeping the sort order
/// among themselves); the rest follow [mode].
List<MangaFavorite> sortFavorites(
  List<MangaFavorite> favorites, {
  required Set<String> pinned,
  required Map<String, MangaProgress> progress,
  required Map<String, MangaRating> ratings,
  required MangaFavoriteSort mode,
}) {
  final indexed = [
    for (var i = 0; i < favorites.length; i++) (i, favorites[i]),
  ];
  int compare((int, MangaFavorite) a, (int, MangaFavorite) b) {
    final pinA = pinned.contains(a.$2.key) ? 0 : 1;
    final pinB = pinned.contains(b.$2.key) ? 0 : 1;
    if (pinA != pinB) return pinA.compareTo(pinB);
    final primary = switch (mode) {
      MangaFavoriteSort.recentRead => (progress[b.$2.key]?.updatedAtMs ?? 0)
          .compareTo(progress[a.$2.key]?.updatedAtMs ?? 0),
      MangaFavoriteSort.title => a.$2.title.compareTo(b.$2.title),
      MangaFavoriteSort.rating => (ratings[b.$2.key]?.stars ?? 0)
          .compareTo(ratings[a.$2.key]?.stars ?? 0),
      MangaFavoriteSort.addedOrder => 0,
    };
    return primary != 0 ? primary : a.$1.compareTo(b.$1);
  }

  indexed.sort(compare);
  return [for (final entry in indexed) entry.$2];
}

// ── Update check (M2) ────────────────────────────────────────

/// Favorites whose current chapter count exceeds the last known
/// count, mapped to how many new chapters appeared. Favorites
/// never seen before (no known count) are baselines, not updates.
Map<String, int> mangaUpdatesFor(
  Map<String, int> knownCounts,
  Map<String, int> currentCounts,
) {
  final updates = <String, int>{};
  for (final entry in currentCounts.entries) {
    final known = knownCounts[entry.key];
    if (known != null && entry.value > known) {
      updates[entry.key] = entry.value - known;
    }
  }
  return updates;
}

// ── Reading statistics (M6) ──────────────────────────────────

class MangaReadingStats {
  const MangaReadingStats({
    this.chaptersFinished = 0,
    this.pagesRead = 0,
    this.secondsRead = 0,
    this.secondsByDay = const {},
  });

  final int chaptersFinished;
  final int pagesRead;
  final int secondsRead;

  /// 'yyyy-MM-dd' → seconds read that day.
  final Map<String, int> secondsByDay;

  Map<String, dynamic> toJson() => {
        'chaptersFinished': chaptersFinished,
        'pagesRead': pagesRead,
        'secondsRead': secondsRead,
        'secondsByDay': secondsByDay,
      };

  static MangaReadingStats fromJson(Map<dynamic, dynamic> json) {
    final byDay = <String, int>{};
    final rawDays = json['secondsByDay'];
    if (rawDays is Map) {
      for (final entry in rawDays.entries) {
        byDay[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    return MangaReadingStats(
      chaptersFinished: (json['chaptersFinished'] as num?)?.toInt() ?? 0,
      pagesRead: (json['pagesRead'] as num?)?.toInt() ?? 0,
      secondsRead: (json['secondsRead'] as num?)?.toInt() ?? 0,
      secondsByDay: byDay,
    );
  }

  int secondsOn(DateTime day) => secondsByDay[dayKey(day)] ?? 0;

  /// Total seconds over the 7 days ending at [day] (inclusive).
  int secondsInLastWeek(DateTime day) {
    var total = 0;
    for (var i = 0; i < 7; i++) {
      total += secondsOn(day.subtract(Duration(days: i)));
    }
    return total;
  }

  static String dayKey(DateTime day) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }
}

class MangaStatsStore {
  MangaStatsStore._();

  static MangaReadingStats load() {
    final raw = GStorage.getSetting(SettingsKeys.mangaReadingStatsJson);
    if (raw.isEmpty) return const MangaReadingStats();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const MangaReadingStats();
      return MangaReadingStats.fromJson(decoded.cast<dynamic, dynamic>());
    } catch (_) {
      return const MangaReadingStats();
    }
  }

  static Future<void> _save(MangaReadingStats stats) {
    return GStorage.putSetting(
      SettingsKeys.mangaReadingStatsJson,
      jsonEncode(stats.toJson()),
    );
  }

  static Future<void> recordPages(int count) async {
    if (count <= 0) return;
    final stats = load();
    await _save(MangaReadingStats(
      chaptersFinished: stats.chaptersFinished,
      pagesRead: stats.pagesRead + count,
      secondsRead: stats.secondsRead,
      secondsByDay: stats.secondsByDay,
    ));
  }

  static Future<void> recordChapterFinished() async {
    final stats = load();
    await _save(MangaReadingStats(
      chaptersFinished: stats.chaptersFinished + 1,
      pagesRead: stats.pagesRead,
      secondsRead: stats.secondsRead,
      secondsByDay: stats.secondsByDay,
    ));
  }

  static Future<void> recordSeconds(int seconds, DateTime now) async {
    if (seconds <= 0) return;
    final stats = load();
    final byDay = {...stats.secondsByDay};
    final key = MangaReadingStats.dayKey(now);
    byDay[key] = (byDay[key] ?? 0) + seconds;
    await _save(MangaReadingStats(
      chaptersFinished: stats.chaptersFinished,
      pagesRead: stats.pagesRead,
      secondsRead: stats.secondsRead + seconds,
      secondsByDay: byDay,
    ));
  }
}

// ── Next-chapter prefetch cache (M7) ─────────────────────────

/// In-memory cache of fetched chapter page lists, keyed by
/// 'source:mangaId:chapterId'. The reader fills it ahead of
/// time so chapter transitions feel instant.
class ChapterPrefetchCache {
  ChapterPrefetchCache._();

  static final Map<String, List<MangaPage>> _cache = {};
  static const _maxEntries = 4;

  static String keyOf(String source, String mangaId, String chapterId) =>
      '$source:$mangaId:$chapterId';

  static List<MangaPage>? peek(String key) => _cache[key];

  static void put(String key, List<MangaPage> pages) {
    _cache
      ..remove(key)
      ..[key] = pages;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  static void clear() => _cache.clear();
}
