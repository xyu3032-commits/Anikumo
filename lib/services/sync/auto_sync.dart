import 'dart:async';

import 'package:anikumo/services/download/download_gate.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/notifications/notification_inbox.dart';
import 'package:anikumo/services/profile/github_sync.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/sync/webdav.dart';
import 'package:anikumo/services/sync/zone_sync.dart';

/// Batch 282 (#24): timed automatic sync.
///
/// Stated plainly, like the update checks (#269):
/// this app has no background executor, so "timed"
/// means a check when the app opens plus a periodic
/// re-check while the app keeps running. Nothing syncs
/// while the app is closed.
///
/// A run syncs the WebDAV zone bundles (manga / novel
/// / film) through the same per-zone entry the settings
/// page uses, so the decision is the shared
/// [decideZoneSync]: upload/download happen on their
/// own, a conflict is only recorded in the notification
/// inbox (#20) — never auto-resolved. When GitHub sync
/// is signed in it is triggered too, with remote-led
/// pulls declined (an automatic run never overwrites
/// local data with a newer remote copy; the user does
/// that by hand). Everything degrades silently.
abstract final class AutoSyncService {
  static bool _running = false;
  static Timer? _timer;

  /// The pure due decision: enabled, and either never
  /// run or the configured interval has elapsed.
  static bool isDue({
    required bool enabled,
    required int nowMs,
    required int lastMs,
    required int intervalHours,
  }) {
    if (!enabled) return false;
    if (lastMs <= 0) return true;
    final intervalMs = intervalHours * Duration.millisecondsPerHour;
    return nowMs - lastMs >= intervalMs;
  }

  /// Starts the while-running re-check. Idempotent;
  /// the timer only ever calls [runIfDue], which is
  /// cheap when nothing is due.
  static void startPeriodicChecks() {
    _timer ??= Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(runIfDue()),
    );
  }

  /// Runs one automatic sync when due; returns true
  /// when a run was attempted (win or lose per zone).
  static Future<bool> runIfDue() async {
    if (_running) return false;
    final due = isDue(
      enabled: GStorage.getSetting(SettingsKeys.autoSyncEnabled),
      nowMs: DateTime.now().millisecondsSinceEpoch,
      lastMs: GStorage.getSetting(SettingsKeys.autoSyncLastMs),
      intervalHours: GStorage.getSetting(SettingsKeys.autoSyncIntervalHours),
    );
    if (!due) return false;
    // #25: the Wi-Fi-only gate also covers auto sync.
    // A gated run does not stamp the ledger — it stays
    // due and retries at the next check.
    if (DownloadGate.blockedNow()) return false;
    _running = true;
    try {
      await _run();
      await GStorage.putSetting(
        SettingsKeys.autoSyncLastMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      return true;
    } catch (e) {
      AnikumoLogger().w('AutoSync: run failed', error: e);
      return false;
    } finally {
      _running = false;
    }
  }

  static Future<void> _run() async {
    var changed = 0;
    final conflicts = <String>[];

    // ---- WebDAV zone bundles ----
    final webDavReady = GStorage.getSetting(SettingsKeys.webDavEnable) &&
        GStorage.getSetting(SettingsKeys.webDavURL).trim().isNotEmpty;
    if (webDavReady) {
      try {
        final webDav = WebDav();
        if (!webDav.initialized) await webDav.init();
        for (final zone in ZoneSyncService.zones) {
          try {
            final outcome = await webDav.syncZoneData(zone);
            switch (outcome) {
              case 'uploaded':
              case 'downloaded':
                changed++;
              case 'conflict':
                conflicts.add(ZoneSyncService.zoneLabel(zone));
            }
          } catch (e) {
            AnikumoLogger().w(
              'AutoSync: zone $zone failed',
              error: e,
            );
          }
        }
      } catch (e) {
        AnikumoLogger().w('AutoSync: WebDAV leg failed', error: e);
      }
    }

    // ---- GitHub (signed-in only) ----
    String? githubOutcome;
    if (GithubSync.connected && GithubSync.syncRepo.isNotEmpty) {
      try {
        githubOutcome = await GithubSync.syncNow(
          // An automatic run never applies a newer
          // remote copy over local data on its own.
          confirmPull: (_) async => false,
        );
      } catch (e) {
        AnikumoLogger().w('AutoSync: GitHub leg failed', error: e);
      }
    }

    // ---- report into the inbox (#20) ----
    if (conflicts.isNotEmpty) {
      await NotificationInbox.record(
        title: S.t('自动同步发现冲突'),
        body: S.f('{}出现同步冲突，请到 WebDAV 同步页的冲突页处理', [
          conflicts.join('、'),
        ]),
        category: 'sync',
      );
    }
    if (changed > 0) {
      await NotificationInbox.record(
        title: S.t('自动同步完成'),
        body: S.f('{} 个分区已同步', [changed]),
        category: 'sync',
      );
    }
    if (githubOutcome != null) {
      await NotificationInbox.record(
        title: S.t('自动同步完成'),
        body: S.f('GitHub：{}', [githubOutcome]),
        category: 'sync',
      );
    }
  }
}
