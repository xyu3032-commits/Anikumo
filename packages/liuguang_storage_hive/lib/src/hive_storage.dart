
import 'dart:convert'; import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:liuguang_storage/liuguang_storage.dart';

/// StorageAdapter backed by Hive (hive_ce, same major as the host app's
/// persistence stack). One box per logical table ("collection"), values are
/// JSON strings so no TypeAdapters / code generation are needed.
class HiveStorageAdapter implements StorageAdapter {
  final Directory directory;
  final Map<String, Box<String>> _boxes = {};
  bool _initialized = false;
  HiveStorageAdapter(String path) : directory = Directory(path);

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await directory.create(recursive: true);
    Hive.init(directory.path);
    _initialized = true;
  }

  Future<Box<String>> _box(String table) async {
    await _ensureInit();
    final existing = _boxes[table];
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<String>('liuguang_$table');
    _boxes[table] = box;
    final meta = await Hive.openBox<String>('liuguang_meta');
    final names = (meta.get('tables') ?? '').split(',').where((e) => e.isNotEmpty).toSet()..add(table);
    await meta.put('tables', names.join(','));
    return box;
  }

  Future<List<String>> _knownTables() async {
    await _ensureInit();
    final meta = await Hive.openBox<String>('liuguang_meta');
    return (meta.get('tables') ?? '').split(',').where((e) => e.isNotEmpty).toList();
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
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<List<Map<String, dynamic>>> all(String table) async {
    final box = await _box(table);
    return box.values.map((raw) => Map<String, dynamic>.from(jsonDecode(raw) as Map)).toList();
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
    final tables = <String, dynamic>{};
    for (final t in await _knownTables()) {
      final box = await _box(t);
      tables[t] = {for (final k in box.keys) k.toString(): jsonDecode(box.get(k.toString())!)};
    }
    return {'version': 1, 'tables': tables};
  }

  @override
  Future<void> importAll(Map<String, dynamic> data) async {
    if (data['version'] != 1) throw FormatException('unsupported export version ${data['version']}');
    final tables = data['tables'];
    if (tables is Map) {
      for (final entry in tables.entries) {
        final box = await _box(entry.key.toString());
        await box.clear();
        if (entry.value is Map) {
          for (final row in (entry.value as Map).entries) {
            await box.put(row.key.toString(), jsonEncode(Map<String, dynamic>.from(row.value as Map)));
          }
        }
      }
    }
  }

  /// Flush and close all boxes. A new adapter on the same directory reopens
  /// the same on-disk data (verified by tests).
  Future<void> close() async {
    _boxes.clear();
    if (_initialized) {
      await Hive.close();
      _initialized = false;
    }
  }
}
