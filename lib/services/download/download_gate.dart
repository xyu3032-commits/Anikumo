import 'package:anikumo/services/network/metered_network_service.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 282 (#25): the Wi-Fi-only download gate.
///
/// Pure decision, shared by the anime download
/// manager, the manga download queue and the auto
/// sync (#24): when the user turned on 仅 Wi-Fi 下载
/// and the current network is metered (mobile data),
/// no NEW download or sync work may start. Work
/// already running is never interrupted — the gate is
/// only consulted at start points — and queued work
/// simply waits until the network turns unmetered.
abstract final class DownloadGate {
  static bool startAllowed({
    required bool wifiOnly,
    required bool metered,
  }) =>
      !wifiOnly || !metered;

  /// Live decision from the current setting + the
  /// metered-network tracker's latest state.
  static bool blockedNow() => !startAllowed(
        wifiOnly: GStorage.getSetting(SettingsKeys.wifiOnlyDownloads),
        metered: MeteredNetworkService.isMetered,
      );
}
