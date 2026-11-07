import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:anikumo/services/storage/storage.dart';

/// A favorited manga in the 漫画专区. Identity is source-scoped:
/// the same id from two sources is two different favorites.
/// Entries written before sources existed carry no source field
/// and read back as 'mangadex'.
class MangaFavorite {
  const MangaFavorite({
    required this.id,
    required this.title,
    required this.coverUrl,
    this.source = 'mangadex',
  });

  final String id;
  final String title;
  final String coverUrl;
  final String source;

  String get key => '$source:$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'coverUrl': coverUrl,
        'source': source,
      };

  static MangaFavorite? fromJson(Map<dynamic, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return MangaFavorite(
      id: id,
      title: json['title']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      source: json['source']?.toString() ?? 'mangadex',
    );
  }
}

/// Where the user stopped reading one manga.
class MangaProgress {
  const MangaProgress({
    required this.mangaId,
    required this.mangaTitle,
    required this.coverUrl,
    required this.chapterId,
    required this.chapterLabel,
    required this.page,
    required this.totalPages,
    required this.updatedAtMs,
    this.mangaSource = 'mangadex',
  });

  final String mangaId;
  final String mangaTitle;
  final String coverUrl;
  final String chapterId;
  final String chapterLabel;

  /// Zero-based page index.
  final int page;
  final int totalPages;
  final int updatedAtMs;
  final String mangaSource;

  String get key => '$mangaSource:$mangaId';

  Map<String, dynamic> toJson() => {
        'mangaId': mangaId,
        'mangaTitle': mangaTitle,
        'coverUrl': coverUrl,
        'chapterId': chapterId,
        'chapterLabel': chapterLabel,
        'page': page,
        'totalPages': totalPages,
        'updatedAtMs': updatedAtMs,
        'mangaSource': mangaSource,
      };

  static MangaProgress? fromJson(Map<dynamic, dynamic> json) {
    final mangaId = json['mangaId']?.toString() ?? '';
    if (mangaId.isEmpty) return null;
    return MangaProgress(
      mangaId: mangaId,
      mangaTitle: json['mangaTitle']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      chapterId: json['chapterId']?.toString() ?? '',
      chapterLabel: json['chapterLabel']?.toString() ?? '',
      page: (json['page'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      mangaSource: json['mangaSource']?.toString() ?? 'mangadex',
    );
  }
}

/// Pure codecs, shared by the store below and the backup story: the
/// manga library lives in two settings JSON strings (no codegen).
class MangaLibraryCodec {
  MangaLibraryCodec._();

  static List<MangaFavorite> decodeFavorites(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map) ?MangaFavorite.fromJson(entry),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encodeFavorites(List<MangaFavorite> favorites) {
    return jsonEncode([for (final f in favorites) f.toJson()]);
  }

  static Map<String, MangaProgress> decodeProgress(String raw) {
    // Batch 82: the empty / invalid cases used to return a
    // const, unmodifiable map. MangaLibraryStore
    // .recordProgress mutates the decoded map in place, so
    // on a fresh install (or right after clearing progress)
    // the first-ever save threw UnsupportedError inside the
    // reader's fire-and-forget call — and the store memo
    // kept handing back that same const map, so manga
    // reading NEVER recorded history again and there was
    // no progress point to resume from. Always return a
    // writable map.
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, MangaProgress>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          final progress = MangaProgress.fromJson(
            (entry.value as Map).cast<dynamic, dynamic>(),
          );
          if (progress != null) result[progress.key] = progress;
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static String encodeProgress(Map<String, MangaProgress> progress) {
    return jsonEncode(
      progress.map((id, value) => MapEntry(id, value.toJson())),
    );
  }

  /// A whole-library export document (favorites + progress), used
  /// by the data settings page's export/import.
  static String buildExport(
    List<MangaFavorite> favorites,
    Map<String, MangaProgress> progress,
  ) {
    return jsonEncode({
      'app': 'anikumo-manga',
      'version': 1,
      'favorites': [for (final f in favorites) f.toJson()],
      'progress': progress.map((id, value) => MapEntry(id, value.toJson())),
    });
  }

  /// Parses an export document back; returns null when the text is
  /// not an Anikumo manga export.
  static ({
    List<MangaFavorite> favorites,
    Map<String, MangaProgress> progress
  })? parseExport(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          (decoded['app'] != 'anikumo-manga' &&
              decoded['app'] != 'hunku-manga')) {
        return null;
      }
      final favoritesRaw = decoded['favorites'];
      final favorites = <MangaFavorite>[
        if (favoritesRaw is List)
          for (final entry in favoritesRaw)
            if (entry is Map) ?MangaFavorite.fromJson(entry),
      ];
      final progressRaw = decoded['progress'];
      final progress = <String, MangaProgress>{};
      if (progressRaw is Map) {
        for (final entry in progressRaw.entries) {
          if (entry.value is Map) {
            final parsed = MangaProgress.fromJson(
              (entry.value as Map).cast<dynamic, dynamic>(),
            );
            if (parsed != null) progress[parsed.key] = parsed;
          }
        }
      }
      return (favorites: favorites, progress: progress);
    } catch (_) {
      return null;
    }
  }
}

/// Settings-backed store for manga favorites and reading progress.
class MangaLibraryStore {
  /// Batch 37: bumped on every library write. The zone's
  /// tabs stay mounted in a cross-fading stack, so a tab
  /// built before a change never rebuilt — the favorites
  /// tab kept showing 0 本 right after the user hearted a
  /// manga on its detail page. Tabs listen and rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bump() => revision.value++;

  MangaLibraryStore._();

  // Batch 16: parsed results are memoized against the raw JSON —
  // pages call these loaders inside build(), and re-decoding the
  // whole library on every rebuild was pure waste. Writes go
  // through GStorage, which changes the raw string and therefore
  // invalidates the memo naturally.
  static String? _favoritesRaw;
  static List<MangaFavorite>? _favoritesMemo;
  static String? _progressRaw;
  static Map<String, MangaProgress>? _progressMemo;

  static List<MangaFavorite> loadFavorites() {
    final raw = GStorage.getSetting(SettingsKeys.mangaFavoritesJson);
    if (_favoritesMemo != null && _favoritesRaw == raw) {
      return _favoritesMemo!;
    }
    final decoded = MangaLibraryCodec.decodeFavorites(raw);
    _favoritesRaw = raw;
    _favoritesMemo = decoded;
    return decoded;
  }

  static bool isFavorite(String source, String mangaId) {
    return loadFavorites()
        .any((f) => f.source == source && f.id == mangaId);
  }

  /// Returns true when the manga is a favorite after the toggle.
  static Future<bool> toggleFavorite(MangaFavorite favorite) async {
    final favorites = [...loadFavorites()];
    final index = favorites.indexWhere((f) => f.key == favorite.key);
    if (index >= 0) {
      favorites.removeAt(index);
      await GStorage.putSetting(
        SettingsKeys.mangaFavoritesJson,
        MangaLibraryCodec.encodeFavorites(favorites),
      );
      _bump();
      return false;
    }
    favorites.insert(0, favorite);
    await GStorage.putSetting(
      SettingsKeys.mangaFavoritesJson,
      MangaLibraryCodec.encodeFavorites(favorites),
    );
    _bump();
    return true;
  }

  static Map<String, MangaProgress> loadProgressMap() {
    final raw = GStorage.getSetting(SettingsKeys.mangaProgressJson);
    if (_progressMemo != null && _progressRaw == raw) {
      return _progressMemo!;
    }
    final decoded = MangaLibraryCodec.decodeProgress(raw);
    _progressRaw = raw;
    _progressMemo = decoded;
    return decoded;
  }

  /// Most recently read first.
  static List<MangaProgress> loadProgressList() {
    final list = loadProgressMap().values.toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return list;
  }

  static Future<void> recordProgress(MangaProgress progress) async {
    // Batch 82: copy before mutating — the decoded map's
    // mutability is the codec's business, not something this
    // write path should ever have to rely on.
    final map = {...loadProgressMap()};
    map[progress.key] = progress;
    final encoded = MangaLibraryCodec.encodeProgress(map);
    await GStorage.putSetting(SettingsKeys.mangaProgressJson, encoded);
    // Keep the memo in step with what was just written, so
    // immediate re-reads (detail page resume, history list)
    // see the new point without waiting for a raw change.
    _progressRaw = encoded;
    _progressMemo = map;
    _bump();
  }

  /// Batch 83: backup restore merge — backup records win
  /// per key, local-only records are kept.
  static Future<void> mergeBackup({
    required List<MangaFavorite> favorites,
    required Map<String, MangaProgress> progress,
  }) async {
    if (favorites.isNotEmpty) {
      final merged = <String, MangaFavorite>{
        for (final f in loadFavorites()) f.key: f,
      };
      for (final f in favorites) {
        merged[f.key] = f;
      }
      final list = merged.values.toList();
      final encoded = MangaLibraryCodec.encodeFavorites(list);
      await GStorage.putSetting(SettingsKeys.mangaFavoritesJson, encoded);
      _favoritesRaw = encoded;
      _favoritesMemo = list;
    }
    if (progress.isNotEmpty) {
      final merged = {...loadProgressMap(), ...progress};
      final encoded = MangaLibraryCodec.encodeProgress(merged);
      await GStorage.putSetting(SettingsKeys.mangaProgressJson, encoded);
      _progressRaw = encoded;
      _progressMemo = merged;
    }
    if (favorites.isNotEmpty || progress.isNotEmpty) _bump();
  }

  static Future<void> clearProgress() async {
    await GStorage.putSetting(SettingsKeys.mangaProgressJson, '');
    _bump();
  }

  static Future<void> clearFavorites() async {
    await GStorage.putSetting(SettingsKeys.mangaFavoritesJson, '');
    _bump();
  }

  static String exportLibrary() {
    return MangaLibraryCodec.buildExport(loadFavorites(), loadProgressMap());
  }

  /// Merges an export document into the library: new favorites are
  /// prepended, progress entries overwrite per manga. Returns the
  /// imported counts, or null when the document is invalid.
  static Future<({int favorites, int progress})?> importLibrary(
    String raw,
  ) async {
    final parsed = MangaLibraryCodec.parseExport(raw);
    if (parsed == null) return null;
    final favorites = [...loadFavorites()];
    var addedFavorites = 0;
    for (final favorite in parsed.favorites.reversed) {
      if (!favorites.any((f) => f.key == favorite.key)) {
        favorites.insert(0, favorite);
        addedFavorites++;
      }
    }
    await GStorage.putSetting(
      SettingsKeys.mangaFavoritesJson,
      MangaLibraryCodec.encodeFavorites(favorites),
    );
    final progress = loadProgressMap()..addAll(parsed.progress);
    await GStorage.putSetting(
      SettingsKeys.mangaProgressJson,
      MangaLibraryCodec.encodeProgress(progress),
    );
    _bump();
    return (favorites: addedFavorites, progress: parsed.progress.length);
  }
}
