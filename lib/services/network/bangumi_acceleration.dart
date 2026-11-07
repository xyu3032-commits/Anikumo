import 'package:anikumo/services/network/acceleration_mode.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/bangumi_mirror_credentials.dart';

enum BangumiAcceleration implements AccelerationMode {
  direct,
  ech,
  mirror;

  static BangumiAcceleration get current {
    final mode = values.asNameMap()[GStorage.getSetting(
          SettingsKeys.bangumiAcceleration,
        )] ??
        (GStorage.getSetting(SettingsKeys.enableBangumiProxy)
            ? mirror
            : direct);
    // Batch 26: the mirror only accepts requests signed with
    // the release credentials (ANIKUMO_APPID / ANIKUMO_KEY dart
    // defines, injected by upstream CI). Builds without them
    // sign with empty secrets and the mirror 401s every
    // signed call — and since the proxy switch defaults ON,
    // anime search found NOTHING out of the box (the direct
    // API works fine). Without usable credentials the mirror
    // is unusable: fall back to direct.
    if (mode == mirror && !hasMirrorCredentials) return direct;
    return mode;
  }

  /// Whether this build carries usable mirror credentials.
  static bool get hasMirrorCredentials =>
      (bangumiMirrorCredentials['id'] ?? '').isNotEmpty &&
      (bangumiMirrorCredentials['value'] ?? '').isNotEmpty;

  @override
  String get label => switch (this) {
    direct => '直连',
    ech => 'ECH',
    mirror => '镜像',
  };

  @override
  String get description => switch (this) {
    direct => '访问官方接口',
    ech => '启用加密握手',
    mirror => '镜像接口（默认）',
  };
}
