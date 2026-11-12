import 'dart:convert';

import 'package:flutter_modular/flutter_modular.dart';

import '../../modules/collect/collect_module.dart';
import '../../repositories/collect_crud_repository.dart';
import '../../request/apis/bangumi_api.dart';
import '../storage/storage.dart';
import 'anime_features.dart';

/// Batch 233 （追番自动更新 pack): checks the user's
/// "在看" collection against Bangumi's episode lists and
/// remembers which titles gained episodes. State lives
/// in the same setting the film zone uses for its own
/// checker, under an anime-specific key: per-title
/// last-known episode counts plus unacknowledged update
/// messages. The first check only seeds the counts.
abstract final class AnimeAutoUpdate {
  static const throttle = Duration(hours: 6);

  static Map<String, dynamic> _state() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.animeUpdateCheckJson);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  static Future<void> _save(Map<String, dynamic> state) =>
      GStorage.putSetting(SettingsKeys.animeUpdateCheckJson, jsonEncode(state));

  static List<String> pendingUpdates() {
    if (!AnimeFeatures.isInstalled(AnimeFeatures.autoUpdateId)) {
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

  /// One check round over [watching] titles.
  /// [episodeCountOf] resolves a title's current episode
  /// count (Bangumi's episode list length in production).
  static Future<List<String>> checkNow({
    required List<CollectedBangumi> watching,
    required Future<int> Function(int bangumiId) episodeCountOf,
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
    for (final item in watching) {
      final id = item.bangumiItem.id;
      int count;
      try {
        count = await episodeCountOf(id);
      } catch (_) {
        continue;
      }
      if (count <= 0) continue;
      final known = stamps['$id'];
      stamps['$id'] = count;
      if (seeded && known != null && count > known) {
        final name = item.bangumiItem.nameCn.isNotEmpty
            ? item.bangumiItem.nameCn
            : item.bangumiItem.name;
        fresh.add('《$name》更新到第 $count 集');
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

  /// Entry-zone trigger: fire-and-forget, throttled.
  static Future<void> maybeCheck({DateTime? now}) async {
    try {
      if (!AnimeFeatures.isInstalled(AnimeFeatures.autoUpdateId)) return;
      final clock = now ?? DateTime.now();
      final lastAtMs = (_state()['lastAtMs'] as num?)?.toInt() ?? 0;
      if (clock.millisecondsSinceEpoch - lastAtMs <
          throttle.inMilliseconds) {
        return;
      }
      // CollectType 1 = 在看 (see CollectedBangumi.type).
      final watching = inject<ICollectCrudRepository>()
          .getAllCollectibles()
          .where((c) => c.type == 1)
          .toList();
      if (watching.isEmpty) {
        final state = _state();
        state['lastAtMs'] = clock.millisecondsSinceEpoch;
        await _save(state);
        return;
      }
      await checkNow(
        watching: watching,
        episodeCountOf: (id) async {
          final episodes = await BangumiApi.getBangumiEpisodesByID(id);
          final main = episodes.where((e) => e.type == 0).length;
          return main > 0 ? main : episodes.length;
        },
        now: clock,
      );
    } catch (_) {
      // Best-effort: update checks never disturb the zone.
    }
  }
}
