import 'dart:convert';

import 'package:anikumo/services/storage/storage.dart';

/// Remembers which road （线路） of a plugin last played successfully,
/// and computes the order in which roads should be attempted.
///
/// Attempt order: the remembered road first (it worked last time),
/// then the road the caller asked for, then the rest in order. When
/// playback fails with auto-switch enabled, the caller walks this
/// list instead of giving up on the first dead road.
class RoadPreference {
  RoadPreference._();

  /// Pure attempt ordering; out-of-range indices are dropped and the
  /// result never contains duplicates.
  static List<int> order({
    required int totalRoads,
    int? preferred,
    int? current,
  }) {
    final result = <int>[];
    void add(int? index) {
      if (index != null &&
          index >= 0 &&
          index < totalRoads &&
          !result.contains(index)) {
        result.add(index);
      }
    }

    add(preferred);
    add(current);
    for (var i = 0; i < totalRoads; i++) {
      add(i);
    }
    return result;
  }

  static Map<String, int> decode(String raw) {
    if (raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final result = <String, int>{};
      for (final entry in decoded.entries) {
        final road = (entry.value as num?)?.toInt();
        if (road != null && road >= 0) {
          result[entry.key.toString()] = road;
        }
      }
      return result;
    } catch (_) {
      return <String, int>{};
    }
  }

  static String encode(Map<String, int> preferences) {
    return jsonEncode(preferences);
  }

  static int? preferredRoad(String pluginName) {
    return decode(GStorage.getSetting(SettingsKeys.roadPreferenceJson))[
        pluginName];
  }

  static Future<void> save(String pluginName, int road) async {
    final preferences = decode(
      GStorage.getSetting(SettingsKeys.roadPreferenceJson),
    );
    if (preferences[pluginName] == road) return;
    preferences[pluginName] = road;
    await GStorage.putSetting(
      SettingsKeys.roadPreferenceJson,
      encode(preferences),
    );
  }
}
