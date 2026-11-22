import 'dart:convert';

import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/services/liuguang/film_features.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 281: one work's pinned play line — the source
/// the pin was made on, and the line's key on that source
/// (see [FilmLineFavorites.lineKeyOf]). A pin is a
/// preference, not a promise: it applies only while the
/// work is opened from the same source and a line with
/// the same key still exists; otherwise it is ignored
/// silently and never renders a stale marker.
class FilmLinePin {
  const FilmLinePin({required this.sourceId, required this.lineKey});

  final String sourceId;
  final String lineKey;

  Map<String, dynamic> toJson() => {'s': sourceId, 'l': lineKey};

  static FilmLinePin? fromJson(dynamic json) {
    if (json is! Map) return null;
    final sourceId = json['s']?.toString() ?? '';
    final lineKey = json['l']?.toString() ?? '';
    if (sourceId.isEmpty || lineKey.isEmpty) return null;
    return FilmLinePin(sourceId: sourceId, lineKey: lineKey);
  }
}

/// Batch 281: 收藏线路 — per-work pinned lines for the
/// film zone, stored as one JSON object in settings
/// (work media id → pin), mirroring the line-speed
/// store's shape: pure decode/encode and ordering for
/// tests, thin guarded storage wrappers for the app.
abstract final class FilmLineFavorites {
  /// A line's stable key inside one work's detail. Play
  /// lines are identified by title everywhere in the
  /// zone (the speed order keys on titles too); a line
  /// the source leaves untitled falls back to its
  /// 1-based position marker.
  static String lineKeyOf({required String title, required int seasonNumber}) =>
      title.isNotEmpty ? title : '#$seasonNumber';

  static String lineKeyOfSeason(Season season) =>
      lineKeyOf(title: season.title, seasonNumber: season.seasonNumber);

  static Map<String, FilmLinePin> decodePins(String raw) {
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            if (FilmLinePin.fromJson(e.value) case final pin?)
              e.key.toString(): pin,
        };
      }
    } catch (_) {
      // A corrupt pin map just means no pins.
    }
    return {};
  }

  static String encodePins(Map<String, FilmLinePin> pins) => jsonEncode({
        for (final e in pins.entries) e.key: e.value.toJson(),
      });

  static Map<String, FilmLinePin> _all() {
    try {
      return decodePins(GStorage.getSetting(SettingsKeys.filmLinePinsJson));
    } catch (_) {
      return {};
    }
  }

  /// The pin recorded for [workKey] (a work's media id),
  /// or null. Guarded like every film-zone storage read.
  static FilmLinePin? pinFor(String workKey) => _all()[workKey];

  static Future<void> savePin(String workKey, FilmLinePin pin) async {
    final all = _all();
    all[workKey] = pin;
    try {
      await GStorage.putSetting(
        SettingsKeys.filmLinePinsJson,
        encodePins(all),
      );
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  static Future<void> clearPin(String workKey) async {
    final all = _all();
    if (all.remove(workKey) == null) return;
    try {
      await GStorage.putSetting(
        SettingsKeys.filmLinePinsJson,
        encodePins(all),
      );
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  /// Where the pinned line sits in [seasons] — its index,
  /// or -1 when there is no usable pin: no pin, a pin made
  /// on another source, or the pinned line is gone from
  /// the detail. Rendering and auto-selection both read
  /// existence from here, so a dead pin never shows.
  static int pinnedIndexOf(
    List<Season> seasons,
    FilmLinePin? pin,
    String sourceId,
  ) {
    if (pin == null || pin.sourceId != sourceId) return -1;
    for (var i = 0; i < seasons.length; i++) {
      if (lineKeyOfSeason(seasons[i]) == pin.lineKey) return i;
    }
    return -1;
  }

  /// [detail] with the pinned line moved first (the rest
  /// keep their order), or [detail] itself when the pin
  /// does not apply. Mirrors [reorderDetailLines]: the
  /// detail page applies this after the speed order, so
  /// an explicit per-work pin wins over the per-source
  /// speed preference.
  static MediaDetail applyPinToDetail(
    MediaDetail detail,
    FilmLinePin? pin,
    String sourceId,
  ) {
    if (pin == null || pin.sourceId != sourceId) return detail;
    if (pinnedIndexOf(detail.seasons, pin, sourceId) <= 0) return detail;
    final seasons = orderByLinePreference(
      detail.seasons,
      [pin.lineKey],
      lineKeyOfSeason,
    );
    if (identical(seasons, detail.seasons)) return detail;
    return MediaDetail(item: detail.item, seasons: seasons);
  }
}
