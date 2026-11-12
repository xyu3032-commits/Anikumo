import 'dart:convert';

import '../storage/storage.dart';
import 'local_books.dart';
import 'novel_api.dart';
import 'novel_features.dart';
import 'novel_library.dart';
import '../../models/novel_item.dart';

/// Batch 235 （追书自动更新 pack): checks favorited books
/// against their sources' current chapter counts and
/// remembers which ones grew. State: per-book last-known
/// chapter counts keyed by storageKey, plus unack'd
/// update messages. The first check only seeds counts;
/// local books never change and are skipped.
abstract final class NovelAutoUpdate {
  static const throttle = Duration(hours: 6);

  static Map<String, dynamic> _state() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.novelUpdateCheckJson);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  static Future<void> _save(Map<String, dynamic> state) =>
      GStorage.putSetting(SettingsKeys.novelUpdateCheckJson, jsonEncode(state));

  static List<String> pendingUpdates() {
    if (!NovelFeatures.isInstalled(NovelFeatures.autoUpdateId)) {
      return const [];
    }
    final pending = _state()['pending'];
    if (pending is List) {
      return [for (final e in pending) e.toString()];
    }
    return const [];
  }

  static Future<void> clearPending() async {
    final state = _state();
    state['pending'] = const [];
    await _save(state);
  }

  /// One check round over [favorites].
  /// [chapterCountOf] resolves a book's current chapter
  /// count in production via the zone's API.
  static Future<List<String>> checkNow({
    required List<NovelItem> favorites,
    required Future<int> Function(NovelItem item) chapterCountOf,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final state = _state();
    final seeded = state.containsKey('stamps');
    final stamps = <String, int>{
      if (state['stamps'] is Map)
        for (final e in (state['stamps'] as Map).entries)
          e.key.toString(): (e.value as num?)?.toInt() ?? 0,
    };
    final fresh = <String>[];
    for (final item in favorites) {
      if (item.source == LocalNovelSource.sourceId) continue;
      int count;
      try {
        count = await chapterCountOf(item);
      } catch (_) {
        continue;
      }
      if (count <= 0) continue;
      final key = item.storageKey;
      final known = stamps[key];
      stamps[key] = count;
      if (seeded && known != null && count > known) {
        fresh.add('《${item.title}》更新到第 $count 章');
      }
    }
    state['stamps'] = stamps;
    state['lastAtMs'] = clock.millisecondsSinceEpoch;
    if (fresh.isNotEmpty) {
      final pending = state['pending'];
      state['pending'] = [
        if (pending is List) ...pending.map((e) => e.toString()),
        ...fresh,
      ];
    }
    await _save(state);
    return fresh;
  }

  /// Zone-entry trigger: fire-and-forget, throttled.
  static Future<void> maybeCheck({DateTime? now}) async {
    try {
      if (!NovelFeatures.isInstalled(NovelFeatures.autoUpdateId)) return;
      final clock = now ?? DateTime.now();
      final lastAtMs = (_state()['lastAtMs'] as num?)?.toInt() ?? 0;
      if (clock.millisecondsSinceEpoch - lastAtMs <
          throttle.inMilliseconds) {
        return;
      }
      final favorites = NovelLibraryStore.loadFavorites();
      if (favorites.isEmpty) {
        final state = _state();
        state['lastAtMs'] = clock.millisecondsSinceEpoch;
        await _save(state);
        return;
      }
      await checkNow(
        favorites: favorites,
        chapterCountOf: (item) async =>
            (await NovelApi.chapters(item)).length,
        now: clock,
      );
    } catch (_) {
      // Best-effort: update checks never disturb the zone.
    }
  }
}
