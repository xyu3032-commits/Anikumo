import 'dart:convert';

import 'package:anikumo/services/storage/storage.dart';

/// Effective intro/outro skip lengths for one bangumi, in seconds.
typedef SkipLengths = ({int opSeconds, int edSeconds});

/// OP/ED skip memory: a global default plus per-bangumi overrides.
///
/// The player applies the OP length by seeking once when an episode
/// starts, and the ED length by seeking to the end early (which lets
/// the existing auto-play-next machinery take over). Overrides are
/// stored as one JSON string in the settings box, no codegen needed.
class SkipSettings {
  SkipSettings._();

  static const int maxSeconds = 600;

  /// Pure resolution: a per-bangumi override wins over the global
  /// default, field by field; everything is clamped to a sane range.
  static SkipLengths resolve({
    required SkipLengths? override,
    required int defaultOp,
    required int defaultEd,
  }) {
    return (
      opSeconds: (override?.opSeconds ?? defaultOp)
          .clamp(0, maxSeconds)
          .toInt(),
      edSeconds: (override?.edSeconds ?? defaultEd)
          .clamp(0, maxSeconds)
          .toInt(),
    );
  }

  static Map<int, SkipLengths> decodeOverrides(String raw) {
    if (raw.isEmpty) return <int, SkipLengths>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <int, SkipLengths>{};
      final result = <int, SkipLengths>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key.toString());
        final value = entry.value;
        if (id == null || value is! Map) continue;
        result[id] = (
          opSeconds: (value['op'] as num?)?.toInt() ?? 0,
          edSeconds: (value['ed'] as num?)?.toInt() ?? 0,
        );
      }
      return result;
    } catch (_) {
      return <int, SkipLengths>{};
    }
  }

  static String encodeOverrides(Map<int, SkipLengths> overrides) {
    return jsonEncode(overrides.map(
      (id, lengths) => MapEntry(
        id.toString(),
        {'op': lengths.opSeconds, 'ed': lengths.edSeconds},
      ),
    ));
  }

  /// The skip lengths that apply to [bangumiId] right now.
  static SkipLengths effectiveFor(int bangumiId) {
    final overrides = decodeOverrides(
      GStorage.getSetting(SettingsKeys.skipMemoryJson),
    );
    return resolve(
      override: overrides[bangumiId],
      defaultOp: GStorage.getSetting(SettingsKeys.defaultOpSkipSeconds),
      defaultEd: GStorage.getSetting(SettingsKeys.defaultEdSkipSeconds),
    );
  }

  /// Persists [lengths] as the override for [bangumiId]. An override
  /// equal to the current global defaults is dropped instead — it
  /// would only shadow future default changes.
  static Future<void> saveOverride(int bangumiId, SkipLengths lengths) async {
    final overrides = decodeOverrides(
      GStorage.getSetting(SettingsKeys.skipMemoryJson),
    );
    final defaults = resolve(
      override: null,
      defaultOp: GStorage.getSetting(SettingsKeys.defaultOpSkipSeconds),
      defaultEd: GStorage.getSetting(SettingsKeys.defaultEdSkipSeconds),
    );
    if (lengths == defaults) {
      overrides.remove(bangumiId);
    } else {
      overrides[bangumiId] = lengths;
    }
    await GStorage.putSetting(
      SettingsKeys.skipMemoryJson,
      encodeOverrides(overrides),
    );
  }
}
