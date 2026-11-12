import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:liuguang_storage/liuguang_storage.dart';

/// Batch 203: the 流光 LiuGuang engine's [StorageAdapter]
/// on top of the app's already-initialized Hive (main.dart
/// runs Hive.initFlutter once for the whole app — the
/// engine must NOT init a second home, which is why the app
/// uses this adapter instead of liuguang_storage_hive's,
/// whose adapter owns its own Hive.init call).
///
/// One box per logical table, named `liuguang_<table>`;
/// values are JSON strings, so no code generation is
/// needed and the engine's tables stay fully separate from
/// the anime zone's history/collect boxes.
class AnikumoLiuguangStorage implements StorageAdapter {
  final Map<String, Box<String>> _boxes = {};

  Future<Box<String>> _box(String table) async {
    final existing = _boxes[table];
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<String>('liuguang_$table');
    _boxes[table] = box;
    return box;
  }

  @override
  Future<void> put(String table, String key, Map<String, dynamic> value) async {
    final box = await _box(table);
    await box.put(key, jsonEncode(value));
  }

  @override
  Future<Map<String, dynamic>?> get(String table, String key) async {
    final box = await _box(table);
    final raw = box.get(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  @override
  Future<List<Map<String, dynamic>>> all(String table) async {
    final box = await _box(table);
    return box.values
        .map((raw) {
          final decoded = jsonDecode(raw);
          return decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{};
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  @override
  Future<void> delete(String table, String key) async {
    final box = await _box(table);
    await box.delete(key);
  }

  @override
  Future<void> clearTable(String table) async {
    final box = await _box(table);
    await box.clear();
  }

  @override
  Future<Map<String, dynamic>> exportAll() async {
    // The engine's repositories only ever touch the tables
    // they own; export walks the boxes this adapter opened.
    final tables = <String, dynamic>{};
    for (final entry in _boxes.entries) {
      final rows = <String, dynamic>{};
      for (final key in entry.value.keys) {
        final raw = entry.value.get(key.toString());
        if (raw != null) rows[key.toString()] = jsonDecode(raw);
      }
      tables[entry.key] = rows;
    }
    return {'version': 1, 'tables': tables};
  }

  @override
  Future<void> importAll(Map<String, dynamic> data) async {
    if (data['version'] != 1) {
      throw FormatException('unsupported export version ${data['version']}');
    }
    final tables = data['tables'];
    if (tables is Map) {
      for (final t in tables.entries) {
        final rows = t.value;
        if (rows is Map) {
          final box = await _box(t.key.toString());
          await box.clear();
          for (final r in rows.entries) {
            if (r.value is Map) {
              await box.put(
                r.key.toString(),
                jsonEncode(Map<String, dynamic>.from(r.value as Map)),
              );
            }
          }
        }
      }
    }
  }
}
