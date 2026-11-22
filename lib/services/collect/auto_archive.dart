import 'package:anikumo/modules/bangumi/episode_item.dart';
import 'package:anikumo/modules/collect/collect_module.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/notifications/notification_inbox.dart';
import 'package:anikumo/services/notifications/update_notification_service.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 283 (#23): finished-show auto archive.
///
/// A watching （在看） entry whose series has fully
/// aired AND whose every episode has been watched is
/// moved to 看过 without the user having to prune the
/// shelf by hand. The rule is deliberately strict —
/// any gap in the data (no episode list, episodes
/// still unaired, no local watch progress) leaves the
/// entry exactly where it is.
///
/// The run rides the launch chain like the update
/// notification check (the app has no background
/// executor) and throttles itself to one run per
/// three hours; each archived work leaves a record in
/// the notification inbox instead of a system ping.
abstract final class AutoArchiveService {
  static const _throttle = Duration(hours: 3);
  static const _maxPerRun = 30;

  /// The decision. Only 在看 (type 1), only with a
  /// known total, only when watched covers the total.
  static bool shouldAutoArchive({
    required int collectType,
    required int totalEpisodes,
    required int watchedEpisodes,
  }) =>
      collectType == 1 &&
      totalEpisodes > 0 &&
      watchedEpisodes >= totalEpisodes;

  /// The total an episode list proves: the full list
  /// length, but only once every announced episode has
  /// aired — a still-airing show proves no total, so
  /// this returns 0 (which the decision reads as
  /// "unknown, do not touch").
  static int provenTotal(List<EpisodeInfo> episodes, DateTime now) {
    if (episodes.isEmpty) return 0;
    final aired = UpdateNotificationService.airedCount(episodes, now);
    return aired >= episodes.length ? episodes.length : 0;
  }

  /// The highest episode number the local history
  /// records for [bangumiId] (0 when never watched
  /// through the app).
  static int watchedEpisodesOf(int bangumiId) {
    var best = 0;
    for (final history in GStorage.histories.values) {
      if (history.bangumiItem.id == bangumiId &&
          history.lastWatchEpisode > best) {
        best = history.lastWatchEpisode;
      }
    }
    return best;
  }

  static Future<void> runIfDue() async {
    try {
      if (!GStorage.getSetting(SettingsKeys.autoArchiveFinished)) return;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final last = GStorage.getSetting(SettingsKeys.autoArchiveLastMs);
      if (last > 0 && nowMs - last < _throttle.inMilliseconds) return;
      await GStorage.putSetting(SettingsKeys.autoArchiveLastMs, nowMs);

      final watching = GStorage.collectibles.values
          .where((c) => c.type == 1)
          .take(_maxPerRun)
          .toList();
      if (watching.isEmpty) return;
      final now = DateTime.now();
      for (final entry in watching) {
        await _archiveIfFinished(entry, now);
      }
    } catch (e) {
      AnikumoLogger().w('AutoArchive: run failed', error: e);
    }
  }

  static Future<void> _archiveIfFinished(
    CollectedBangumi entry,
    DateTime now,
  ) async {
    final item = entry.bangumiItem;
    final watched = watchedEpisodesOf(item.id);
    if (watched <= 0) return;
    List<EpisodeInfo> episodes;
    try {
      episodes = await BangumiApi.getBangumiEpisodesByID(item.id);
    } catch (_) {
      return; // one bad subject never blocks the rest
    }
    final total = provenTotal(episodes, now);
    if (!shouldAutoArchive(
      collectType: entry.type,
      totalEpisodes: total,
      watchedEpisodes: watched,
    )) {
      return;
    }
    entry.type = 4;
    await GStorage.collectibles.put(item.id, entry);
    await GStorage.appendCollectChange(
      bangumiId: item.id,
      action: 2,
      type: 4,
    );
    final name = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    await NotificationInbox.record(
      title: S.f('《{}》已自动归档', [name]),
      body: S.f('全 {} 集已看完，已从「在看」移入「看过」', [total]),
      category: 'archive',
    );
    AnikumoLogger().i('AutoArchive: archived bangumi ${item.id} ($name)');
  }
}
