import 'package:flutter/foundation.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Global glass (frosted) surface intensity.
///
/// Level 0 turns glass off (opaque surfaces, no blur), 1 is the light
/// default, 2 is stronger: more blur, more translucency. Surfaces listen
/// to [levelNotifier], so changing the level in settings re-renders
/// every glass surface immediately, without a restart.
class GlassStyle {
  GlassStyle._();

  static const int levelOff = 0;
  static const int levelLight = 1;
  static const int levelStrong = 2;

  static final ValueNotifier<int> levelNotifier =
      ValueNotifier<int>(_storedLevel());

  static int _storedLevel() {
    try {
      final value = GStorage.getSetting(SettingsKeys.glassEffectLevel);
      return value.clamp(levelOff, levelStrong);
    } catch (_) {
      // Storage is not ready yet (early startup): fall back to light.
      return levelLight;
    }
  }

  static int get level => levelNotifier.value;

  static bool get isEnabled => level > levelOff;

  static Future<void> setLevel(int value) async {
    final clamped = value.clamp(levelOff, levelStrong);
    levelNotifier.value = clamped;
    await GStorage.putSetting(SettingsKeys.glassEffectLevel, clamped);
  }

  /// Backdrop blur sigma for content surfaces.
  static double blurSigma({bool strong = false}) => switch (level) {
        levelOff => 0,
        levelStrong => strong ? 28 : 22,
        _ => strong ? 20 : 14,
      };

  /// Fill opacity for content glass surfaces.
  static double fillOpacity({bool strong = false}) => switch (level) {
        levelOff => 1,
        levelStrong => strong ? 0.5 : 0.58,
        _ => strong ? 0.64 : 0.72,
      };

  /// Backdrop blur sigma for the bottom navigation bar.
  static double get navBlurSigma => switch (level) {
        levelStrong => 24,
        _ => 16,
      };

  /// Fill opacity for the bottom navigation bar.
  static double get navFillOpacity => switch (level) {
        levelStrong => 0.6,
        _ => 0.72,
      };
}
