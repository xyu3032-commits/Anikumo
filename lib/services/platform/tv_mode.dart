import 'dart:io';

import 'package:flutter/services.dart';

import 'package:anikumo/services/logging/logger.dart';

/// Batch 284 (#31): Android TV detection.
///
/// The native side answers one question — is the current
/// UI mode television (UiModeManager)? Only an explicit
/// "yes" counts: a missing plugin, a non-Android platform
/// or any error resolves to false, so phones and desktops
/// never drift into TV behavior by accident.
bool resolveIsTelevision({required bool? uiModeTelevision}) =>
    uiModeTelevision ?? false;

abstract final class TvModeService {
  static const MethodChannel _channel = MethodChannel('com.anikumo.app/tv');

  static bool? _cached;

  /// Cached after the first answer; safe to call often.
  static Future<bool> isTelevision() async {
    final cached = _cached;
    if (cached != null) return cached;
    bool? native;
    if (Platform.isAndroid) {
      try {
        native = await _channel.invokeMethod<bool>('isTelevision');
      } catch (e) {
        AnikumoLogger().w('TvMode: native check failed', error: e);
        native = null;
      }
    }
    return _cached = resolveIsTelevision(uiModeTelevision: native);
  }
}
