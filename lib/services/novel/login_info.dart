// Batch 169: login form definitions and the per-source
// login-info store.
//
// Sources may declare a login form (their loginUi field):
// a JSON array of rows — text/password inputs, selects
// with a chars list, and buttons carrying a JS action.
// The values a user saves are stored per source as a JSON
// string; rule scripts read them back through the JS
// bridge (as a raw string or as a map), exactly the two
// shapes the format defines. Nothing here names the
// format in user-visible text.

import 'dart:convert';

import '../storage/storage.dart';

/// One row of a source's declared login form.
class LoginRow {
  const LoginRow({
    required this.name,
    required this.type,
    this.chars = const [],
    this.defaultValue = '',
    this.action = '',
    this.viewName = '',
  });

  final String name;

  /// 'text' | 'password' | 'select' | 'button' | …
  final String type;
  final List<String> chars;
  final String defaultValue;
  final String action;
  final String viewName;

  bool get isButton => type == 'button';
  bool get isSelect => type == 'select';
  bool get isPassword => type == 'password';

  /// The label shown for the row.
  String get label => viewName.isNotEmpty ? viewName : name;

  /// The value in force before the user touches anything:
  /// the declared default when usable, else (for selects)
  /// the first choice, else empty.
  String get initialValue {
    if (isSelect && chars.isNotEmpty) {
      return chars.contains(defaultValue) ? defaultValue : chars.first;
    }
    return defaultValue;
  }
}

/// Parsing for the loginUi declaration, tolerant of the
/// shapes real sources ship (a JSON string or an inline
/// list; chars as a JSON string, a comma list, or a list).
abstract final class LoginUi {
  static List<LoginRow> parse(dynamic raw) {
    dynamic decoded = raw;
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return const [];
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! List) return const [];
    final rows = <LoginRow>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final name = entry['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      rows.add(
        LoginRow(
          name: name,
          type: entry['type']?.toString().trim().toLowerCase() ?? 'text',
          chars: _parseChars(entry['chars']),
          defaultValue: entry['default']?.toString() ?? '',
          action: entry['action']?.toString() ?? '',
          viewName: entry['viewName']?.toString() ?? '',
        ),
      );
    }
    return rows;
  }

  static List<String> _parseChars(dynamic raw) {
    if (raw is List) {
      return [for (final c in raw) c.toString()];
    }
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return const [];
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          return [for (final c in decoded) c.toString()];
        }
      } catch (_) {
        // Not JSON: fall through to the comma form.
      }
      return [
        for (final part in text.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];
    }
    return const [];
  }
}

/// The stored login info, keyed by source id. The stored
/// value is a JSON STRING (name -> value), which is what
/// scripts receive verbatim from the string accessor.
abstract final class NovelLoginInfo {
  static Map<String, dynamic> _store() {
    final raw = GStorage.getSetting(SettingsKeys.novelLoginInfoJson);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // A corrupt store reads as empty; the next save
      // rewrites it wholesale.
    }
    return {};
  }

  /// The stored login-info JSON string for [sourceId],
  /// or null when the user never saved the form — the
  /// distinction scripts branch on.
  static String? rawFor(String sourceId) {
    final value = _store()[sourceId];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// The values currently in force: declared defaults
  /// (buttons excluded) overlaid with the saved values.
  static Map<String, String> valuesFor(
    String sourceId,
    List<LoginRow> rows,
  ) {
    final values = <String, String>{
      for (final row in rows)
        if (!row.isButton) row.name: row.initialValue,
    };
    final raw = rawFor(sourceId);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            values[e.key.toString()] = e.value?.toString() ?? '';
          }
        }
      } catch (_) {
        // Unparseable stored info: defaults stand.
      }
    }
    return values;
  }

  static Future<void> save(
    String sourceId,
    Map<String, String> values,
  ) async {
    final store = _store();
    store[sourceId] = jsonEncode(values);
    await GStorage.putSetting(
      SettingsKeys.novelLoginInfoJson,
      jsonEncode(store),
    );
  }

  static Future<void> clear(String sourceId) async {
    final store = _store();
    if (store.remove(sourceId) == null) return;
    await GStorage.putSetting(
      SettingsKeys.novelLoginInfoJson,
      jsonEncode(store),
    );
  }
}
