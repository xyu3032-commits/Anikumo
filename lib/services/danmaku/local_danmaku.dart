import 'dart:async';
import 'dart:convert';

import 'package:anikumo/modules/danmaku/danmaku_module.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 182: danmaku the user sent to the video, kept on
/// this device.
///
/// The danmaku providers have no send API at all (the
/// service's only POST is episode matching — verified
/// against the live service and its source), so a sent
/// danmaku used to be a one-shot on-screen echo that
/// vanished forever. Sent items are now stored per
/// episode and merged back into that episode's danmaku
/// on every load: what the user sent stays visible to
/// them, across restarts, and can be wiped from the
/// danmaku settings.
class LocalDanmakuStore {
  /// Per-episode cap; the oldest sends drop off.
  static const int maxPerEpisode = 200;

  /// The storage key for one playing episode. Built from
  /// the same parameters the player fetches danmaku with,
  /// so a send and the next load of the same episode meet.
  static String episodeKey({
    required int bangumiId,
    required String pluginName,
    required int episode,
    required String title,
  }) =>
      '$bangumiId|$pluginName|$episode|${title.trim()}';

  static Map<String, List<Map<String, dynamic>>> _readAll() {
    final raw = GStorage.getSetting(SettingsKeys.danmakuLocalSentJson);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          e.key.toString(): [
            for (final item in (e.value as List? ?? const []))
              if (item is Map) item.cast<String, dynamic>(),
          ],
      };
    } catch (_) {
      return {};
    }
  }

  static void _writeAll(Map<String, List<Map<String, dynamic>>> all) {
    unawaited(GStorage.putSetting(
      SettingsKeys.danmakuLocalSentJson,
      jsonEncode(all),
    ));
  }

  /// The stored entries for [key], oldest first.
  static List<DanmakuEntry> forEpisode(String key) {
    if (key.isEmpty) return const [];
    final items = _readAll()[key];
    if (items == null) return const [];
    return [
      for (final item in items)
        if (item['m'] is String && item['p'] is String)
          DanmakuEntry.fromJson(item),
    ];
  }

  static void add(String key, DanmakuEntry entry) {
    if (key.isEmpty) return;
    final all = _readAll();
    final items = <Map<String, dynamic>>[
      ...(all[key] ?? const <Map<String, dynamic>>[]),
      entry.toJson(),
    ];
    if (items.length > maxPerEpisode) {
      items.removeRange(0, items.length - maxPerEpisode);
    }
    all[key] = items;
    _writeAll(all);
  }

  static int get totalCount =>
      _readAll().values.fold(0, (sum, items) => sum + items.length);

  static void clearAll() {
    unawaited(GStorage.putSetting(SettingsKeys.danmakuLocalSentJson, ''));
  }
}
