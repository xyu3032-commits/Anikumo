import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:liuguang_core/liuguang_core.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/modules/bangumi/episode_item.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/notifications/notification_inbox.dart';
import 'package:anikumo/services/novel/novel_api.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 269: 追番 / 追更 update notifications.
///
/// Scope, stated plainly: checks run when the app launches
/// (throttled to one run per 3 hours) — there is no
/// background executor, so a phone that never opens the app
/// gets no pings. When a check finds that a watching anime
/// has aired more episodes than last time, or a favorite
/// novel has more chapters, a local notification is posted.
/// The first sighting of any work only records the baseline;
/// enabling the feature never spams the back-catalogue.
///
/// Batch 281: a third lane — the film zone's favorited
/// series. Favorite snapshots carry no episode counts, so
/// each series' current total comes from its source detail
/// (the fullest play line); movies are skipped.
class UpdateNotificationService {
  UpdateNotificationService._();

  static const _channelId = 'anikumo_updates';
  static const _maxAnimePerRun = 30;
  static const _maxNovelsPerRun = 15;
  static const _maxFilmPerRun = 15;
  static const _throttle = Duration(hours: 3);

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool? _available;

  // ---- pure helpers (unit-tested) ----

  /// Episodes that have aired by [now]. Bangumi lists
  /// announced episodes with air dates; an episode counts
  /// once its air date is today or earlier. When no episode
  /// carries a parseable date at all, fall back to the list
  /// length (some subjects only carry announced counts).
  static int airedCount(List<EpisodeInfo> episodes, DateTime now) {
    var dated = 0;
    var aired = 0;
    final today = DateTime(now.year, now.month, now.day);
    for (final ep in episodes) {
      final parsed = DateTime.tryParse(ep.airDate);
      if (parsed == null) continue;
      dated++;
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      if (!day.isAfter(today)) aired++;
    }
    return dated == 0 ? episodes.length : aired;
  }

  /// The diff core: given the previously known count for a
  /// work (null = never seen) and the current count, decide
  /// whether to notify. Baselines never notify.
  static bool shouldNotify(int? known, int current) =>
      known != null && current > known;

  /// Batch 281: a film series' current episode total from
  /// its detail lines. A detail's seasons are its play
  /// lines, which mirror the same series, so the fullest
  /// line is the total; no lines (or no episodes anywhere)
  /// counts 0 and never notifies.
  static int filmEpisodeTotal(List<Season> seasons) {
    var best = 0;
    for (final season in seasons) {
      if (season.episodes.length > best) best = season.episodes.length;
    }
    return best;
  }

  /// Batch 281: how many episodes a film series gained
  /// since the last check, or null when there is nothing
  /// to announce — a first sighting baselines silently,
  /// and an unchanged or shrunk total stays quiet.
  static int? filmUpdateDelta(int? known, int current) =>
      shouldNotify(known, current) ? current - known! : null;

  static Map<String, int> decodeKnown(String raw) {
    if (raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry('$key', (value as num?)?.toInt() ?? 0),
        );
      }
    } catch (_) {
      // A corrupt baseline just re-baselines everything.
    }
    return <String, int>{};
  }

  static String encodeKnown(Map<String, int> known) => jsonEncode(known);

  // ---- plugin plumbing ----

  static Future<bool> _ensurePlugin() async {
    if (_available != null) return _available!;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      const linux = LinuxInitializationSettings(
        defaultActionName: 'Open',
      );
      const windows = WindowsInitializationSettings(
        appName: 'Anikumo',
        appUserModelId: 'com.anikumo.app',
        guid: 'a4f1c2e0-3b5d-4e6f-8a9b-0c1d2e3f4a5b',
      );
      await _plugin.initialize(
        const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
          linux: linux,
          windows: windows,
        ),
      );
      _available = true;
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: plugin init failed', error: e);
      _available = false;
    }
    return _available!;
  }

  /// Ask for the Android 13+ notification permission. Called
  /// when the user turns a toggle on; harmless elsewhere.
  static Future<void> requestPermission() async {
    if (!await _ensurePlugin()) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: permission request failed', error: e);
    }
  }

  static Future<void> _show({
    required String key,
    required String title,
    required String body,
  }) async {
    // Batch 282 (#20): every posted notification is
    // also recorded in the in-app inbox; the lane is
    // the key's prefix ('anime' / 'novel' / 'film').
    await NotificationInbox.record(
      title: title,
      body: body,
      category: key.split(':').first,
    );
    try {
      await _plugin.show(
        key.hashCode & 0x7fffffff,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            '更新提醒',
            channelDescription: '追番、追剧与追更的新内容提醒',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: show failed', error: e);
    }
  }

  // ---- checks ----

  /// Launch entry point: honors both toggles and the
  /// throttle. [force] skips the throttle (toggle-on path).
  static Future<void> runChecksIfEnabled({bool force = false}) async {
    final animeOn = GStorage.getSetting(SettingsKeys.notifyAnimeUpdates);
    final novelOn = GStorage.getSetting(SettingsKeys.notifyNovelUpdates);
    final filmOn = GStorage.getSetting(SettingsKeys.notifyFilmUpdates);
    if (!animeOn && !novelOn && !filmOn) return;
    if (!force) {
      final last = GStorage.getSetting(SettingsKeys.notifyLastCheckMs);
      final elapsed = DateTime.now().millisecondsSinceEpoch - last;
      if (last > 0 && elapsed < _throttle.inMilliseconds) return;
    }
    if (!await _ensurePlugin()) return;
    await GStorage.putSetting(
      SettingsKeys.notifyLastCheckMs,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (animeOn) await _checkAnime();
    if (novelOn) await _checkNovels();
    if (filmOn) await _checkFilm();
  }

  static Future<void> _checkAnime() async {
    try {
      final watching = GStorage.collectibles.values
          .where((c) => c.type == 1)
          .take(_maxAnimePerRun)
          .toList();
      if (watching.isEmpty) return;
      final known = decodeKnown(
        GStorage.getSetting(SettingsKeys.notifyKnownAnimeJson),
      );
      var changed = false;
      final now = DateTime.now();
      for (final entry in watching) {
        final item = entry.bangumiItem;
        List<EpisodeInfo> episodes;
        try {
          episodes = await BangumiApi.getBangumiEpisodesByID(item.id);
        } catch (_) {
          continue; // one bad subject never blocks the rest
        }
        if (episodes.isEmpty) continue;
        final aired = airedCount(episodes, now);
        final key = '${item.id}';
        final prev = known[key];
        if (prev == null) {
          known[key] = aired;
          changed = true;
          continue;
        }
        if (shouldNotify(prev, aired)) {
          known[key] = aired;
          changed = true;
          final name = item.nameCn.isNotEmpty ? item.nameCn : item.name;
          await _show(
            key: 'anime:${item.id}',
            title: S.t('追番更新'),
            body: S.f('《{}》更新至第 {} 集', [name, aired]),
          );
        }
      }
      if (changed) {
        await GStorage.putSetting(
          SettingsKeys.notifyKnownAnimeJson,
          encodeKnown(known),
        );
      }
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: anime check failed', error: e);
    }
  }

  static Future<void> _checkNovels() async {
    try {
      final favorites =
          NovelLibraryStore.loadFavorites().take(_maxNovelsPerRun).toList();
      if (favorites.isEmpty) return;
      final known = decodeKnown(
        GStorage.getSetting(SettingsKeys.notifyKnownNovelJson),
      );
      var changed = false;
      for (final book in favorites) {
        List<NovelChapter> chapters;
        try {
          chapters = await NovelApi.chapters(book);
        } catch (_) {
          continue;
        }
        if (chapters.isEmpty) continue;
        final key = book.storageKey;
        final prev = known[key];
        if (prev == null) {
          known[key] = chapters.length;
          changed = true;
          continue;
        }
        if (shouldNotify(prev, chapters.length)) {
          known[key] = chapters.length;
          changed = true;
          await _show(
            key: 'novel:$key',
            title: S.t('小说更新'),
            body: S.f('《{}》更新至第 {} 章', [book.title, chapters.length]),
          );
        }
      }
      if (changed) {
        await GStorage.putSetting(
          SettingsKeys.notifyKnownNovelJson,
          encodeKnown(known),
        );
      }
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: novel check failed', error: e);
    }
  }

  /// Batch 281: the film lane. Favorites store only a
  /// metadata snapshot (no episode counts), so each
  /// favorited series' total is read from its source
  /// detail — one call per series, capped like the novel
  /// lane, and every failure just skips that series.
  static Future<void> _checkFilm() async {
    try {
      final engine = await VideoEngineService.instance.engine();
      final favorites = await engine.favorites.list();
      final series = <MediaItem>[];
      for (final favorite in favorites) {
        if (favorite.mediaSnapshot.isEmpty) continue;
        try {
          final item = TVSeries.mediaFromJson(favorite.mediaSnapshot);
          if (item.mediaType == MediaType.series) series.add(item);
        } catch (_) {
          // A snapshot that no longer parses is skipped.
        }
        if (series.length >= _maxFilmPerRun) break;
      }
      if (series.isEmpty) return;
      final known = decodeKnown(
        GStorage.getSetting(SettingsKeys.notifyKnownFilmJson),
      );
      var changed = false;
      for (final item in series) {
        MediaDetail? detail;
        try {
          detail = await engine.getDetail(item.id);
        } catch (_) {
          continue; // one bad source never blocks the rest
        }
        if (detail == null) continue;
        final total = filmEpisodeTotal(detail.seasons);
        if (total <= 0) continue;
        final prev = known[item.id];
        if (prev == null) {
          known[item.id] = total;
          changed = true;
          continue;
        }
        final delta = filmUpdateDelta(prev, total);
        if (delta != null) {
          known[item.id] = total;
          changed = true;
          await _show(
            key: 'film:${item.id}',
            title: S.t('追剧更新'),
            body: S.f('《{}》更新了 {} 集', [item.title, delta]),
          );
        }
      }
      if (changed) {
        await GStorage.putSetting(
          SettingsKeys.notifyKnownFilmJson,
          encodeKnown(known),
        );
      }
    } catch (e) {
      AnikumoLogger().w('UpdateNotify: film check failed', error: e);
    }
  }
}
