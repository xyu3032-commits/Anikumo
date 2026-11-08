import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/novel_item.dart';
import '../storage/storage.dart';

/// Favorites + reading progress for the 小说专区, stored as
/// JSON in settings, source-scoped like the manga library.
class NovelLibraryStore {
  NovelLibraryStore._();

  /// Batch 106: change tick for progress mutations — the
  /// manga store has had one since its own staleness fix;
  /// the novel store lacked it, so history displays that
  /// read novel progress never learned about deletions
  /// made on other pages. Mirrors MangaLibraryStore.revision.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bump() => revision.value++;

  // ----------------------------------------------------------
  // Favorites
  // ----------------------------------------------------------

  static List<NovelItem> loadFavorites() {
    final raw = GStorage.getSetting(SettingsKeys.novelFavoritesJson);
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final e in decoded)
            if (e is Map) ?NovelItem.fromJson(e),
        ];
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveFavorites(List<NovelItem> items) {
    return GStorage.putSetting(
      SettingsKeys.novelFavoritesJson,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }

  static bool isFavorite(NovelItem item) {
    return loadFavorites().any((f) => f.storageKey == item.storageKey);
  }

  static Future<bool> toggleFavorite(NovelItem item) async {
    final favorites = loadFavorites();
    final index =
        favorites.indexWhere((f) => f.storageKey == item.storageKey);
    if (index >= 0) {
      favorites.removeAt(index);
      await saveFavorites(favorites);
      return false;
    }
    favorites.insert(0, item);
    await saveFavorites(favorites);
    return true;
  }

  // ----------------------------------------------------------
  // Progress
  // ----------------------------------------------------------

  static Map<String, NovelProgress> loadProgressMap() {
    final raw = GStorage.getSetting(SettingsKeys.novelProgressJson);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            if (e.value is Map)
              e.key.toString(): NovelProgress.fromJson(
                (e.value as Map).cast<String, dynamic>(),
              ),
        };
      }
    } catch (_) {}
    return {};
  }

  /// Most recently read first.
  static List<NovelProgress> loadProgressList() {
    final list = loadProgressMap().values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  static Future<void> recordProgress(NovelProgress progress) async {
    final map = loadProgressMap();
    map[progress.item.storageKey] = progress;
    await GStorage.putSetting(
      SettingsKeys.novelProgressJson,
      jsonEncode({
        for (final e in map.entries) e.key: e.value.toJson(),
      }),
    );
    _bump();
  }

  /// Batch 98: remove ONE reading-history record (the
  /// history lists' per-row delete).
  static Future<void> removeProgress(String key) async {
    final map = loadProgressMap();
    if (map.remove(key) == null) return;
    await GStorage.putSetting(
      SettingsKeys.novelProgressJson,
      jsonEncode({
        for (final e in map.entries) e.key: e.value.toJson(),
      }),
    );
    _bump();
  }

  /// Batch 98: clear the whole reading history — the
  /// manga store has had this for its settings page; the
  /// novel store was missing the counterpart.
  static Future<void> clearProgress() async {
    await GStorage.putSetting(SettingsKeys.novelProgressJson, '');
    _bump();
  }

  /// Batch 83: backup restore merge — backup records win
  /// per key, local-only records are kept.
  static Future<void> mergeBackup({
    required List<NovelItem> favorites,
    required List<NovelProgress> progress,
  }) async {
    if (favorites.isNotEmpty) {
      final merged = <String, NovelItem>{
        for (final f in loadFavorites()) f.storageKey: f,
      };
      for (final f in favorites) {
        merged[f.storageKey] = f;
      }
      await saveFavorites(merged.values.toList());
    }
    if (progress.isNotEmpty) {
      final map = loadProgressMap();
      for (final p in progress) {
        map[p.item.storageKey] = p;
      }
      await GStorage.putSetting(
        SettingsKeys.novelProgressJson,
        jsonEncode({
          for (final e in map.entries) e.key: e.value.toJson(),
        }),
      );
      _bump();
    }
  }
}

/// Where the user stopped in one book.
class NovelProgress {
  const NovelProgress({
    required this.item,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.updatedAt,
  });

  final NovelItem item;
  final int chapterIndex;
  final String chapterTitle;
  final int updatedAt; // epoch millis

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        'chapterIndex': chapterIndex,
        'chapterTitle': chapterTitle,
        'updatedAt': updatedAt,
      };

  static NovelProgress fromJson(Map<String, dynamic> json) {
    return NovelProgress(
      item: NovelItem.fromJson(
            (json['item'] as Map?)?.cast<dynamic, dynamic>() ?? const {},
          ) ??
          const NovelItem(bookUrl: '', title: ''),
      chapterIndex:
          int.tryParse(json['chapterIndex']?.toString() ?? '') ?? 0,
      chapterTitle: json['chapterTitle']?.toString() ?? '',
      updatedAt: int.tryParse(json['updatedAt']?.toString() ?? '') ?? 0,
    );
  }
}
