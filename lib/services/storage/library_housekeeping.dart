import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/notifications/notification_inbox.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 283 (#27/#28): the two startup housekeeping
/// passes — the total cache cap and history retention.
///
/// Both passes are planned by pure functions (below)
/// and executed best-effort at launch: a failure in
/// either leaves the data exactly as it was and never
/// blocks startup. Neither pass ever touches
/// downloads, favorites or backups — the cache pass
/// only walks the cache-manager stores (the same four
/// the per-store byte budgets in
/// cache_budget_trimmer.dart already guard), and the
/// retention pass only deletes history rows the user
/// asked to expire.

/// One file considered by the cache-cap planner.
typedef CacheFileEntry = ({String path, int size, DateTime modified});

/// Files younger than this are never deleted: a cache
/// write may still be in flight (same rail as the
/// per-store trimmer).
const _freshGuard = Duration(minutes: 5);

/// #27: which files to delete so the stores' total
/// size drops to [capBytes]. Oldest first; metadata
/// files (.json/.db — the cache managers' bookkeeping)
/// and fresh files are untouchable. An empty result
/// means "already within budget" (or cap disabled).
List<String> planCacheTrim(
  List<CacheFileEntry> files,
  int capBytes,
  DateTime now,
) {
  if (capBytes <= 0) return const [];
  var total = 0;
  for (final file in files) {
    total += file.size;
  }
  if (total <= capBytes) return const [];
  final freshCutoff = now.subtract(_freshGuard);
  final candidates = [
    for (final file in files)
      if (!file.modified.isAfter(freshCutoff) &&
          !file.path.toLowerCase().endsWith('.json') &&
          !file.path.toLowerCase().endsWith('.db'))
        file,
  ]..sort((a, b) => a.modified.compareTo(b.modified));
  final plan = <String>[];
  for (final file in candidates) {
    if (total <= capBytes) break;
    plan.add(file.path);
    total -= file.size;
  }
  return plan;
}

/// #28: the keys whose last-watch time is older than
/// the retention window. [retentionDays] <= 0 keeps
/// everything (the default).
List<String> expiredHistoryKeys(
  List<({String key, DateTime lastWatchTime})> rows,
  int retentionDays,
  DateTime now,
) {
  if (retentionDays <= 0) return const [];
  final cutoff = now.subtract(Duration(days: retentionDays));
  return [
    for (final row in rows)
      if (row.lastWatchTime.isBefore(cutoff)) row.key,
  ];
}

/// The cache-manager stores the cap governs — the
/// same set the storage analysis page reports as the
/// image cache.
List<String> get cacheStoreKeys => [
      'anikumoMangaPages',
      'anikumoMangaCovers',
      DefaultCacheManager.key,
      'anikumoFilmCovers',
    ];

abstract final class LibraryHousekeeping {
  /// Launch entry point (init_page, deferred): runs
  /// both passes in sequence, each fully guarded.
  static Future<void> runStartupChecks() async {
    await _trimCachesToCap();
    await _expireHistories();
  }

  static Future<List<CacheFileEntry>> _cacheFiles() async {
    final temp = await getTemporaryDirectory();
    final entries = <CacheFileEntry>[];
    for (final key in cacheStoreKeys) {
      final dir = Directory('${temp.path}/$key');
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.type != FileSystemEntityType.file) continue;
          entries.add(
            (path: entity.path, size: stat.size, modified: stat.modified),
          );
        } catch (_) {
          // Racing a cache eviction is fine.
        }
      }
    }
    return entries;
  }

  static Future<void> _trimCachesToCap() async {
    try {
      final capMb = GStorage.getSetting(SettingsKeys.cacheCapMb);
      if (capMb <= 0) return;
      final files = await _cacheFiles();
      final plan = planCacheTrim(files, capMb * 1024 * 1024, DateTime.now());
      if (plan.isEmpty) return;
      final sizes = {for (final f in files) f.path: f.size};
      var freed = 0;
      for (final path in plan) {
        try {
          await File(path).delete();
          freed += sizes[path] ?? 0;
        } catch (_) {
          // Already gone — nothing to free.
        }
      }
      if (freed <= 0) return;
      AnikumoLogger().i(
        'Housekeeping: cache cap freed ${(freed / 1048576).toStringAsFixed(1)} MB',
      );
      await NotificationInbox.record(
        title: S.t('缓存已自动清理'),
        body: S.f('缓存超过上限，已自动清理 {}', [formatBytes(freed)]),
        category: 'cache',
      );
    } catch (e) {
      AnikumoLogger().w('Housekeeping: cache trim failed', error: e);
    }
  }

  static Future<void> _expireHistories() async {
    try {
      final days = GStorage.getSetting(SettingsKeys.historyRetentionDays);
      if (days <= 0) return;
      final now = DateTime.now();

      // Anime: the histories box, keyed by History.key.
      final animeRows = [
        for (final history in GStorage.histories.values)
          (key: history.key, lastWatchTime: history.lastWatchTime),
      ];
      final expiredAnime = expiredHistoryKeys(animeRows, days, now).toSet();
      var removed = 0;
      for (final history in [...GStorage.histories.values]) {
        if (!expiredAnime.contains(history.key)) continue;
        await GStorage.histories.delete(history.key);
        removed++;
      }

      // Film: engine history rows carry lastPlayedAt.
      try {
        final engine = await VideoEngineService.instance.engine();
        final rows = await engine.history.list(limit: 100000);
        final filmRows = [
          for (final row in rows)
            (
              key: '${row.mediaId}::${row.episodeId ?? ''}',
              lastWatchTime: row.lastPlayedAt,
            ),
        ];
        final expiredFilm = expiredHistoryKeys(filmRows, days, now).toSet();
        for (final row in rows) {
          if (!expiredFilm.contains('${row.mediaId}::${row.episodeId ?? ''}')) {
            continue;
          }
          await engine.history.remove(row.mediaId, episodeId: row.episodeId);
          removed++;
        }
      } catch (_) {
        // The film engine being unavailable never
        // blocks the anime pass above.
      }

      if (removed > 0) {
        AnikumoLogger().i('Housekeeping: expired $removed history rows');
      }
    } catch (e) {
      AnikumoLogger().w('Housekeeping: history expiry failed', error: e);
    }
  }
}

/// Shared byte formatting (storage page + inbox
/// records): 1024-based, one decimal, no trailing .0.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text =
      value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text} ${units[unit]}';
}
