import 'dart:convert';

import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Display title for a bangumi: the Chinese name when there is one.
String bangumiDisplayTitle(BangumiItem item) {
  return item.nameCn.isNotEmpty ? item.nameCn : item.name;
}

/// One user-created list （我的榜单）: a name plus bangumi IDs, kept in
/// the order they were added.
class UserList {
  UserList({
    required this.id,
    required this.name,
    List<int>? bangumiIds,
  }) : bangumiIds = bangumiIds ?? <int>[];

  final String id;
  String name;
  final List<int> bangumiIds;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'bangumiIds': bangumiIds,
      };

  factory UserList.fromJson(Map<String, dynamic> json) {
    return UserList(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      bangumiIds: ((json['bangumiIds'] as List?) ?? const [])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList(),
    );
  }
}

/// Pure (de)serialization for [UserList]s, kept storage-free so the
/// format can be unit-tested and reused by local backup.
class UserListsCodec {
  UserListsCodec._();

  static List<UserList> decode(String raw) {
    if (raw.isEmpty) return <UserList>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <UserList>[];
      return decoded
          .whereType<Map>()
          .map((entry) => UserList.fromJson(Map<String, dynamic>.from(entry)))
          .where((list) => list.id.isNotEmpty)
          .toList();
    } catch (_) {
      return <UserList>[];
    }
  }

  static String encode(List<UserList> lists) {
    return jsonEncode(lists.map((list) => list.toJson()).toList());
  }
}

/// Persistence for [UserList]s: one JSON string in the settings box,
/// so no new Hive type or code generation is needed.
class UserListsStore {
  UserListsStore._();

  static List<UserList> load() {
    return UserListsCodec.decode(
      GStorage.getSetting(SettingsKeys.userListsJson),
    );
  }

  static Future<void> save(List<UserList> lists) {
    return GStorage.putSetting(
      SettingsKeys.userListsJson,
      UserListsCodec.encode(lists),
    );
  }
}

/// Pure (de)serialization for per-bangumi notes （番剧笔记）:
/// a JSON object mapping bangumi ID (as string) to note text.
class BangumiNotesCodec {
  BangumiNotesCodec._();

  static Map<int, String> decode(String raw) {
    if (raw.isEmpty) return <int, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <int, String>{};
      final result = <int, String>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key.toString());
        final text = entry.value;
        if (id != null && text is String && text.isNotEmpty) {
          result[id] = text;
        }
      }
      return result;
    } catch (_) {
      return <int, String>{};
    }
  }

  static String encode(Map<int, String> notes) {
    return jsonEncode(
      notes.map((id, text) => MapEntry(id.toString(), text)),
    );
  }
}

/// Persistence for bangumi notes, same settings-JSON approach as lists.
class BangumiNotesStore {
  BangumiNotesStore._();

  static Map<int, String> load() {
    return BangumiNotesCodec.decode(
      GStorage.getSetting(SettingsKeys.bangumiNotesJson),
    );
  }

  static Future<void> save(Map<int, String> notes) {
    return GStorage.putSetting(
      SettingsKeys.bangumiNotesJson,
      BangumiNotesCodec.encode(notes),
    );
  }
}
