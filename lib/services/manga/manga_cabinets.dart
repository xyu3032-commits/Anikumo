import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:anikumo/services/manga/local_manga_source.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 122: a user-named cabinet holding locally imported
/// manga (the CBZ/ZIP books of [LocalMangaLibrary]).
///
/// Local imports used to surface only as one anonymous
/// "local" source mixed into the registry — users could not
/// find their own books. Cabinets give them a dedicated home:
/// every imported book lands in the default cabinet, and the
/// user can create more cabinets with their own names and
/// move books between them.
class MangaCabinet {
  const MangaCabinet({
    required this.id,
    required this.name,
    required this.createdAtMs,
  });

  final String id;
  final String name;
  final int createdAtMs;
}

/// The cabinet registry: cabinet definitions plus the
/// book → cabinet assignments, persisted as one JSON setting.
/// The default cabinet is implicit (never stored, cannot be
/// renamed or deleted) and owns every unassigned book.
class MangaCabinets {
  MangaCabinets._();

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
    final raw = GStorage.getSetting(SettingsKeys.mangaCabinetsJson);
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) data = decoded.cast<String, dynamic>();
      } catch (_) {
        // A corrupt payload reads as an empty registry; the
        // books themselves are untouched on disk.
      }
    }
    return _cache = data;
  }

  static Future<void> _write() async {
    await GStorage.putSetting(
      SettingsKeys.mangaCabinetsJson,
      jsonEncode(_cache),
    );
    revision.value++;
  }

  /// All cabinets, the default first, then the user's own in
  /// creation order.
  static List<MangaCabinet> cabinets() {
    final out = <MangaCabinet>[
      const MangaCabinet(id: defaultId, name: defaultName, createdAtMs: 0),
    ];
    final list = _read()['cabinets'];
    if (list is List) {
      for (final entry in list) {
        if (entry is Map && entry['id'] is String && entry['name'] is String) {
          out.add(MangaCabinet(
            id: entry['id'] as String,
            name: entry['name'] as String,
            createdAtMs: (entry['createdAtMs'] as num?)?.toInt() ?? 0,
          ));
        }
      }
    }
    return out;
  }

  /// The cabinet a book lives in — the default when it was
  /// never assigned or its cabinet was deleted.
  static String cabinetIdOf(String bookId) {
    final assign = _read()['assign'];
    if (assign is Map) {
      final id = assign[bookId];
      if (id is String && cabinets().any((c) => c.id == id)) return id;
    }
    return defaultId;
  }

  static List<LocalBook> booksIn(String cabinetId, List<LocalBook> all) {
    return [for (final book in all) if (cabinetIdOf(book.id) == cabinetId) book];
  }

  static Future<MangaCabinet> create(String name) async {
    final trimmed = name.trim();
    final cabinet = MangaCabinet(
      id: 'c${DateTime.now().millisecondsSinceEpoch}',
      name: trimmed.isEmpty ? '未命名柜子' : trimmed,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
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

  /// Deletes a user cabinet. Its books fall back to the
  /// default cabinet (assignments are dropped, books are
  /// never deleted with a cabinet).
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

  static Future<void> assign(String bookId, String cabinetId) async {
    final data = _read();
    final assign = <String, dynamic>{
      if (data['assign'] is Map) ...(data['assign'] as Map).cast<String, dynamic>(),
    };
    if (cabinetId == defaultId ||
        !cabinets().any((c) => c.id == cabinetId)) {
      assign.remove(bookId);
    } else {
      assign[bookId] = cabinetId;
    }
    data['assign'] = assign;
    await _write();
  }
}
