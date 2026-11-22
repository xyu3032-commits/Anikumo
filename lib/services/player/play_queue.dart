import 'dart:convert';

import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 277 (#1): one entry of the cross-work play queue —
/// an episode the user lined up to play after the current
/// one, possibly from a different work and source.
///
/// The entry carries everything the history-based resolver
/// needs to reopen the episode later: the source plugin
/// ([adapterName]) and the work's page URL on that source
/// ([src], the same value [History.lastSrc] stores), plus
/// the episode/road selection. [episode] is the 1-based
/// list position used by the player's episode selection,
/// not a source-side episode number.
class PlayQueueEntry {
  final int bangumiId;
  final String name;
  final int episode;
  final int road;
  final String adapterName;
  final String src;
  final String cover;
  final int addedAtMs;

  const PlayQueueEntry({
    required this.bangumiId,
    required this.name,
    required this.episode,
    required this.road,
    required this.adapterName,
    required this.src,
    required this.cover,
    required this.addedAtMs,
  });

  /// Whether [other] points at the same episode of the
  /// same work on the same source (queue de-duplication).
  bool sameTarget(PlayQueueEntry other) =>
      bangumiId == other.bangumiId &&
      episode == other.episode &&
      road == other.road &&
      adapterName == other.adapterName &&
      src == other.src;

  Map<String, dynamic> toJson() => {
        'b': bangumiId,
        'n': name,
        'e': episode,
        'r': road,
        'a': adapterName,
        's': src,
        'c': cover,
        'at': addedAtMs,
      };

  static PlayQueueEntry? fromJson(dynamic json) {
    if (json is! Map) return null;
    final bangumiId = (json['b'] as num?)?.toInt();
    final episode = (json['e'] as num?)?.toInt();
    if (bangumiId == null || episode == null || episode <= 0) {
      return null;
    }
    return PlayQueueEntry(
      bangumiId: bangumiId,
      name: json['n']?.toString() ?? '',
      episode: episode,
      road: (json['r'] as num?)?.toInt() ?? 0,
      adapterName: json['a']?.toString() ?? '',
      src: json['s']?.toString() ?? '',
      cover: json['c']?.toString() ?? '',
      addedAtMs: (json['at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The persisted play queue (oldest first). Stored as one
/// JSON list in settings, mirroring the video-bookmarks
/// store's shape: pure decode/encode for tests, thin
/// storage wrappers for the app.
abstract final class PlayQueue {
  /// Hard cap so a forgotten queue cannot grow without
  /// bound; adding past the cap drops the oldest entries.
  static const int maxEntries = 100;

  static List<PlayQueueEntry> decodeAll(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final item in decoded)
            if (PlayQueueEntry.fromJson(item) case final e?) e,
        ];
      }
    } catch (_) {}
    return const [];
  }

  static String encodeAll(List<PlayQueueEntry> entries) =>
      jsonEncode([for (final e in entries) e.toJson()]);

  static List<PlayQueueEntry> entries() =>
      decodeAll(GStorage.getSetting(SettingsKeys.playQueueJson));

  static PlayQueueEntry? get head {
    final all = entries();
    return all.isEmpty ? null : all.first;
  }

  static Future<void> _saveAll(List<PlayQueueEntry> entries) {
    return GStorage.putSetting(
      SettingsKeys.playQueueJson,
      encodeAll(entries),
    );
  }

  /// Appends [entry]; an entry for the same episode of the
  /// same work/source is moved to the end instead of being
  /// duplicated.
  static Future<List<PlayQueueEntry>> add(PlayQueueEntry entry) async {
    final all = [
      for (final e in entries())
        if (!e.sameTarget(entry)) e,
      entry,
    ];
    final trimmed = all.length > maxEntries
        ? all.sublist(all.length - maxEntries)
        : all;
    await _saveAll(trimmed);
    return trimmed;
  }

  static Future<List<PlayQueueEntry>> removeAt(int index) async {
    final all = entries();
    if (index < 0 || index >= all.length) return all;
    all.removeAt(index);
    await _saveAll(all);
    return all;
  }

  /// Removes and returns the head entry, or null when the
  /// queue is empty.
  static Future<PlayQueueEntry?> consumeHead() async {
    final all = entries();
    if (all.isEmpty) return null;
    final head = all.removeAt(0);
    await _saveAll(all);
    return head;
  }

  static Future<void> clear() => _saveAll(const []);

  /// Rebuilds the [History] record the shared
  /// [HistoryPlaybackService] resolver consumes for a
  /// cross-work queue advance. The [BangumiItem] is a stub
  /// carrying the identity the resolver and the player page
  /// need (id, names, cover); the resolver only reads
  /// [History.lastSrc] / [History.adapterName] beyond it.
  static History historyFor(PlayQueueEntry entry) {
    final item = BangumiItem(
      id: entry.bangumiId,
      type: 2,
      name: entry.name,
      nameCn: entry.name,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {
        'large': entry.cover,
        'medium': entry.cover,
        'common': entry.cover,
        'small': entry.cover,
        'grid': entry.cover,
      },
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );
    return History(
      item,
      entry.episode,
      entry.adapterName,
      DateTime.fromMillisecondsSinceEpoch(
        entry.addedAtMs > 0 ? entry.addedAtMs : 0,
      ),
      entry.src,
      '',
    );
  }
}
