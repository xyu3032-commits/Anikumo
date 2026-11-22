import 'dart:convert';

import 'package:anikumo/services/storage/storage.dart';

/// Batch 282 (#20): the in-app notification inbox.
///
/// System notifications are fire-and-forget: once the
/// shade is cleared, a 追番/追剧 ping is gone. Every
/// notification the update checker actually posts is
/// also recorded here (plus the auto-sync results from
/// #24), newest first, capped at [maxEntries]. The
/// store mirrors the play queue's shape: a pure codec
/// and list operations for tests, thin storage wrappers
/// for the app.
class NotificationInboxEntry {
  final String title;
  final String body;

  /// Epoch millis when the notification was posted.
  final int atMs;

  /// Origin lane: 'anime', 'novel', 'film' or 'sync'.
  final String category;

  final bool read;

  const NotificationInboxEntry({
    required this.title,
    required this.body,
    required this.atMs,
    required this.category,
    this.read = false,
  });

  NotificationInboxEntry copyWith({bool? read}) => NotificationInboxEntry(
        title: title,
        body: body,
        atMs: atMs,
        category: category,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => {
        't': title,
        'b': body,
        'at': atMs,
        'c': category,
        'r': read,
      };

  static NotificationInboxEntry? fromJson(dynamic json) {
    if (json is! Map) return null;
    final title = json['t']?.toString() ?? '';
    if (title.isEmpty) return null;
    return NotificationInboxEntry(
      title: title,
      body: json['b']?.toString() ?? '',
      atMs: (json['at'] as num?)?.toInt() ?? 0,
      category: json['c']?.toString() ?? '',
      read: json['r'] == true,
    );
  }
}

abstract final class NotificationInbox {
  /// Hard cap; recording past it drops the oldest rows.
  static const int maxEntries = 100;

  static List<NotificationInboxEntry> decodeAll(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final item in decoded)
            ?NotificationInboxEntry.fromJson(item),
        ];
      }
    } catch (_) {}
    return const [];
  }

  static String encodeAll(List<NotificationInboxEntry> entries) =>
      jsonEncode([for (final e in entries) e.toJson()]);

  /// Prepends [entry] (the inbox is newest-first) and
  /// trims the tail back to [maxEntries].
  static List<NotificationInboxEntry> insert(
    List<NotificationInboxEntry> entries,
    NotificationInboxEntry entry,
  ) {
    final all = [entry, ...entries];
    return all.length > maxEntries ? all.sublist(0, maxEntries) : all;
  }

  static int unreadOf(List<NotificationInboxEntry> entries) =>
      entries.where((e) => !e.read).length;

  static List<NotificationInboxEntry> markReadAt(
    List<NotificationInboxEntry> entries,
    int index,
  ) {
    if (index < 0 || index >= entries.length) return entries;
    if (entries[index].read) return entries;
    return [
      for (var i = 0; i < entries.length; i++)
        i == index ? entries[i].copyWith(read: true) : entries[i],
    ];
  }

  static List<NotificationInboxEntry> markAllRead(
    List<NotificationInboxEntry> entries,
  ) =>
      [
        for (final e in entries) e.read ? e : e.copyWith(read: true),
      ];

  // ---- storage wrappers ----

  static List<NotificationInboxEntry> entries() =>
      decodeAll(GStorage.getSetting(SettingsKeys.notificationInboxJson));

  static int unreadCount() => unreadOf(entries());

  static Future<void> _saveAll(List<NotificationInboxEntry> entries) {
    return GStorage.putSetting(
      SettingsKeys.notificationInboxJson,
      encodeAll(entries),
    );
  }

  /// Records one posted notification. Best-effort by
  /// design: a broken inbox must never break the
  /// notification that triggered the record.
  static Future<void> record({
    required String title,
    required String body,
    required String category,
  }) async {
    try {
      await _saveAll(
        insert(
          entries(),
          NotificationInboxEntry(
            title: title,
            body: body,
            atMs: DateTime.now().millisecondsSinceEpoch,
            category: category,
          ),
        ),
      );
    } catch (_) {}
  }

  static Future<void> markRead(int index) async {
    await _saveAll(markReadAt(entries(), index));
  }

  static Future<void> markAllReadNow() async {
    await _saveAll(markAllRead(entries()));
  }

  static Future<void> clear() => _saveAll(const []);
}
