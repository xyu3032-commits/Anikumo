import 'dart:convert';

import 'package:flutter/foundation.dart';


import 'package:anikumo/services/storage/storage.dart';

/// Batch 207/208: the film zone's remaining local state —
/// the favorites update-check stamps. Playback preferences
/// moved to the app's global player settings when the zone
/// adopted the shared player page (Batch 208); the old
/// zone-local keys are simply no longer read.
abstract final class FilmPrefs {
  /// mediaId → last-seen remarks （更新至X集） for the
  /// favorites update check.
  static Map<String, String> favoriteStamps() {
    final raw = GStorage.getSetting(SettingsKeys.videoFavoriteStampsJson);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry('$k', '$v'));
      }
    } catch (_) {
      // Corrupt stamp map degrades to "no stamps yet".
    }
    return {};
  }

  static Future<void> setFavoriteStamps(Map<String, String> stamps) =>
      GStorage.putSetting(
        SettingsKeys.videoFavoriteStampsJson,
        jsonEncode(stamps),
      );
}

/// Batch 237: per-channel home source pins — the user
/// picks which interface feeds the 电视剧 shelf, which
/// feeds 电影， and so on. Stored as {kindName: entryId};
/// an absent kind means 自动 (the multi-source race).
abstract final class FilmHomeSources {
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Map<String, String> _pins() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.filmHomeSourceJson);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            if (e.value.toString().isNotEmpty)
              e.key.toString(): e.value.toString(),
        };
      }
    } catch (_) {}
    return {};
  }

  static String? preferredId(String kindName) => _pins()[kindName];

  static Future<void> setPreferred(String kindName, String? sourceId) async {
    final pins = _pins();
    if (sourceId == null || sourceId.isEmpty) {
      pins.remove(kindName);
    } else {
      pins[kindName] = sourceId;
    }
    await GStorage.putSetting(
      SettingsKeys.filmHomeSourceJson,
      jsonEncode(pins),
    );
    revision.value++;
  }
}

/// Batch 250: 看剧取源 — which interface's copy of a
/// work the detail page settles on for watching. Two
/// modes, one stored pin: no pin = 最快优先 (the shared
/// speed table decides, Batch 249 keeps it fresh); a
/// pin = 自定义 (that interface's copy wins; when it
/// has no copy — or is gone — the current copy stays,
/// which is the automatic default). Deliberately NOT
/// the 主页接口 pins (FilmHomeSources): those curate
/// which catalogue fills each home shelf, this decides
/// playback sourcing. Same source list, same speed
/// table, separate question.
abstract final class FilmPlaybackSource {
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static String? get pinnedId {
    try {
      final raw = GStorage.getSetting(SettingsKeys.filmPlaybackSourceId);
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPinned(String? id) async {
    await GStorage.putSetting(
      SettingsKeys.filmPlaybackSourceId,
      id ?? '',
    );
    revision.value++;
  }

  /// Moves the pinned source (when set) to the front of
  /// an already speed-ordered list, so its copies win
  /// aggregated merges under 自定义.
  static List<T> pinnedFirst<T>(List<T> items, String Function(T) idOf) {
    final pin = pinnedId;
    if (pin == null) return items;
    final i = items.indexWhere((e) => idOf(e) == pin);
    if (i <= 0) return items;
    final copy = List<T>.of(items);
    copy.insert(0, copy.removeAt(i));
    return copy;
  }
}

/// Batch 237 (speed half): per-source speed-test results,
/// one table shared by every surface that cares how fast
/// an interface answers — the sources tab's 测速 buttons,
/// the settings 测速 row, the home page's automatic
/// fastest-first order and the discover page's all-source
/// merge priority (Batch 238).
///
/// Stored as {entryId: {ms, at}}; ms = -1 marks a failed
/// probe. A record counts as FRESH for 24 hours; older
/// records are treated as "never measured" by the ordering
/// (the rows still display them — ageing text tells the
/// user when the number was taken).
abstract final class FilmSourceSpeeds {
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static const Duration freshFor = Duration(hours: 24);

  static Map<String, ({int ms, DateTime at})> _all() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.filmSourceSpeedJson);
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            if (e.value is Map &&
                (e.value as Map)['ms'] is num &&
                (e.value as Map)['at'] is num)
              e.key.toString(): (
                ms: ((e.value as Map)['ms'] as num).toInt(),
                at: DateTime.fromMillisecondsSinceEpoch(
                  ((e.value as Map)['at'] as num).toInt(),
                ),
              ),
        };
      }
    } catch (_) {}
    return {};
  }

  /// The stored record for [id], fresh or not (null when
  /// never measured). ms < 0 means the probe failed.
  static ({int ms, DateTime at})? recordOf(String id) => _all()[id];

  static bool isFresh(({int ms, DateTime at}) record, DateTime now) =>
      now.difference(record.at) < freshFor;

  /// The fastest freshly-measured source id, or null when
  /// nothing fresh is on the table.
  static String? fastestId(DateTime now) {
    String? best;
    var bestMs = 1 << 62;
    for (final e in _all().entries) {
      if (e.value.ms < 0 || !isFresh(e.value, now)) continue;
      if (e.value.ms < bestMs) {
        bestMs = e.value.ms;
        best = e.key;
      }
    }
    return best;
  }

  static Future<void> record(String id, int? ms) async {
    final all = _all();
    all[id] = (ms: ms ?? -1, at: DateTime.now());
    await GStorage.putSetting(
      SettingsKeys.filmSourceSpeedJson,
      jsonEncode({
        for (final e in all.entries)
          e.key: {'ms': e.value.ms, 'at': e.value.at.millisecondsSinceEpoch},
      }),
    );
    revision.value++;
  }

  /// Orders [items] for "fastest first" consumption:
  /// freshly-measured successes by ascending ms, then
  /// unmeasured / stale entries in their original order,
  /// then fresh failures. Stable for equal keys.
  static List<T> orderBySpeed<T>(
    List<T> items,
    String Function(T) idOf,
    DateTime now,
  ) {
    final all = _all();
    int rank(T item) {
      final r = all[idOf(item)];
      if (r == null || !isFresh(r, now)) return 1;
      return r.ms < 0 ? 2 : 0;
    }

    final decorated = [
      for (var i = 0; i < items.length; i++) (i, items[i]),
    ];
    decorated.sort((a, b) {
      final ra = rank(a.$2), rb = rank(b.$2);
      if (ra != rb) return ra.compareTo(rb);
      if (ra == 0) {
        final ma = all[idOf(a.$2)]!.ms, mb = all[idOf(b.$2)]!.ms;
        if (ma != mb) return ma.compareTo(mb);
      }
      return a.$1.compareTo(b.$1);
    });
    return [for (final d in decorated) d.$2];
  }

  /// Whether at least one entry carries a fresh successful
  /// measurement — the home page only switches from racing
  /// to strict fastest-first order once this holds.
  static bool hasFreshSuccess(Iterable<String> ids, DateTime now) {
    final all = _all();
    for (final id in ids) {
      final r = all[id];
      if (r != null && r.ms >= 0 && isFresh(r, now)) return true;
    }
    return false;
  }
}
