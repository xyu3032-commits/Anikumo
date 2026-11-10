import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 124: a user-named cabinet holding novels — the
/// novel-zone counterpart of the manga cabinets (batch 122).
///
/// The cabinet universe is the user's own bookshelf: novels
/// they collected or started reading (favorites + progress).
/// Every such book lives in the implicit default cabinet
/// until the user moves it into one of their own named
/// cabinets.
class NovelCabinet {
  const NovelCabinet({
    required this.id,
    required this.name,
    required this.createdAtMs,
  });

  final String id;
  final String name;
  final int createdAtMs;
}

/// Cabinet definitions plus book → cabinet assignments,
/// persisted as one JSON setting keyed by the novel's
/// storage key. The default cabinet is implicit (never
/// stored, cannot be renamed or deleted).
class NovelCabinets {
  NovelCabinets._();

  static const String defaultId = 'default';
  static const String defaultName = '默认柜子';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, dynamic>? _cache;

  static Map<String, dynamic> _read() {
    final cached = _cache;
    if (cached != null) return cached;
    var data = <String, dynamic>{
      'cabinets': <dynamic>[],
      'assign': <String, dynamic>{},
    };
    final raw = GStorage.getSetting(SettingsKeys.novelCabinetsJson);
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) data = decoded.cast<String, dynamic>();
      } catch (_) {
        // A corrupt payload reads as an empty registry; the
        // books themselves are untouched.
      }
    }
    return _cache = data;
  }

  static Future<void> _write() async {
    await GStorage.putSetting(
      SettingsKeys.novelCabinetsJson,
      jsonEncode(_cache),
    );
    revision.value++;
  }

  static List<NovelCabinet> cabinets() {
    final out = <NovelCabinet>[
      const NovelCabinet(id: defaultId, name: defaultName, createdAtMs: 0),
    ];
    final list = _read()['cabinets'];
    if (list is List) {
      for (final entry in list) {
        if (entry is Map && entry['id'] is String && entry['name'] is String) {
          out.add(NovelCabinet(
            id: entry['id'] as String,
            name: entry['name'] as String,
            createdAtMs: (entry['createdAtMs'] as num?)?.toInt() ?? 0,
          ));
        }
      }
    }
    return out;
  }

  static String cabinetIdOf(String bookKey) {
    final assign = _read()['assign'];
    if (assign is Map) {
      final id = assign[bookKey];
      if (id is String && cabinets().any((c) => c.id == id)) return id;
    }
    return defaultId;
  }

  static List<NovelItem> booksIn(String cabinetId, List<NovelItem> all) {
    return [
      for (final book in all)
        if (cabinetIdOf(book.storageKey) == cabinetId) book,
    ];
  }

  /// The cabinet universe: collected novels first, then
  /// in-progress ones not already collected, deduped by
  /// storage key.
  static List<NovelItem> universe({
    required List<NovelItem> favorites,
    required List<NovelItem> progressBooks,
  }) {
    final seen = <String>{};
    return [
      for (final book in [...favorites, ...progressBooks])
        if (seen.add(book.storageKey)) book,
    ];
  }

  static Future<NovelCabinet> create(String name) async {
    final trimmed = name.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    final cabinet = NovelCabinet(
      id: 'c$now',
      name: trimmed.isEmpty ? '未命名柜子' : trimmed,
      createdAtMs: now,
    );
    final data = _read();
    final list = (data['cabinets'] as List?) ?? <dynamic>[];
    data['cabinets'] = [
      ...list,
      {
        'id': cabinet.id,
        'name': cabinet.name,
        'createdAtMs': cabinet.createdAtMs,
      },
    ];
    await _write();
    return cabinet;
  }

  static Future<void> rename(String id, String name) async {
    if (id == defaultId) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final data = _read();
    final list = data['cabinets'];
    if (list is! List) return;
    data['cabinets'] = [
      for (final entry in list)
        if (entry is Map && entry['id'] == id)
          {...entry.cast<String, dynamic>(), 'name': trimmed}
        else
          entry,
    ];
    await _write();
  }

  static Future<void> delete(String id) async {
    if (id == defaultId) return;
    final data = _read();
    final list = data['cabinets'];
    if (list is List) {
      data['cabinets'] = [
        for (final entry in list)
          if (!(entry is Map && entry['id'] == id)) entry,
      ];
    }
    final assign = data['assign'];
    if (assign is Map) {
      data['assign'] = {
        for (final e in assign.entries)
          if (e.value != id) e.key: e.value,
      };
    }
    await _write();
  }

  static Future<void> assign(String bookKey, String cabinetId) async {
    final data = _read();
    final assign = <String, dynamic>{
      if (data['assign'] is Map)
        ...(data['assign'] as Map).cast<String, dynamic>(),
    };
    if (cabinetId == defaultId ||
        !cabinets().any((c) => c.id == cabinetId)) {
      assign.remove(bookKey);
    } else {
      assign[bookKey] = cabinetId;
    }
    data['assign'] = assign;
    await _write();
  }
}
