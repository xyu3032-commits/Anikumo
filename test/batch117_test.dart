import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/mini_player_overlay.dart';
import 'package:anikumo/services/storage/settings_keys.dart';

/// Batch 117: mini player "ultimate" pass — adaptive tiers, video
/// aspect window, themes, personalisation defaults.
void main() {
  group('miniPlayerTier', () {
    // Batch 119 semantics: the mode is a floor, simple is a cap.
    test('simple always wins, full always wins', () {
      expect(miniPlayerTier(width: 200, controlMode: 0), 0);
      expect(miniPlayerTier(width: 400, controlMode: 0), 0);
      expect(miniPlayerTier(width: 200, controlMode: 2), 2);
      expect(miniPlayerTier(width: 400, controlMode: 2), 2);
    });

    test('standard guarantees at least standard, grows with size', () {
      expect(miniPlayerTier(width: 200, controlMode: 1), 1);
      expect(miniPlayerTier(width: 300, controlMode: 1), 1);
      expect(miniPlayerTier(width: 400, controlMode: 1), 2);
      expect(miniPlayerTier(width: 319, controlMode: 1), 1);
      expect(miniPlayerTier(width: 320, controlMode: 1), 2);
    });
  });

  group('miniPlayerAspect', () {
    test('follows the video, clamped, 16:9 fallback', () {
      expect(miniPlayerAspect(videoWidth: 1920, videoHeight: 1080),
          closeTo(16 / 9, 0.001));
      expect(miniPlayerAspect(videoWidth: 1080, videoHeight: 1920), 0.5625);
      expect(miniPlayerAspect(videoWidth: 0, videoHeight: 0), 16 / 9);
      expect(miniPlayerAspect(videoWidth: 4000, videoHeight: 1000), 2.2);
      expect(miniPlayerAspect(videoWidth: 100, videoHeight: 1000), 0.5);
    });
  });

  group('miniPlayerDefaultScale', () {
    test('small / standard / large', () {
      expect(miniPlayerDefaultScale(0), 0.9);
      expect(miniPlayerDefaultScale(1), 1.0);
      expect(miniPlayerDefaultScale(2), 1.25);
      expect(miniPlayerDefaultScale(99), 1.0);
    });
  });

  group('miniPlayerTheme', () {
    test('moon white is the light theme with dark ink', () {
      final theme = miniPlayerTheme(1, 0.85);
      expect(theme.isLight, isTrue);
      expect(theme.foreground, const Color(0xFF23242B));
    });

    test('dark glass is the default and stays dark', () {
      final theme = miniPlayerTheme(0, 0.85);
      expect(theme.isLight, isFalse);
      expect(theme.foreground, Colors.white);
      expect(miniPlayerTheme(99, 0.85).isLight, isFalse);
    });

    test('opacity scales the panel alpha and clamps', () {
      final full = miniPlayerTheme(2, 1.0);
      final half = miniPlayerTheme(2, 0.5);
      expect(half.panelBottom.a, lessThan(full.panelBottom.a));
      final clamped = miniPlayerTheme(2, 0.1);
      expect(clamped.panelBottom.a,
          miniPlayerTheme(2, 0.4).panelBottom.a);
    });
  });

  group('settings defaults', () {
    test('batch 117 personalisation keys', () {
      expect(SettingsKeys.pipTheme.defaultValue, 0);
      expect(SettingsKeys.pipControlMode.defaultValue, 1);
      expect(SettingsKeys.pipControlsOpacity.defaultValue, 0.85);
      expect(SettingsKeys.pipAutoHideSeconds.defaultValue, 3);
      expect(SettingsKeys.pipSeekSeconds.defaultValue, 10);
      expect(SettingsKeys.pipDoubleTapAction.defaultValue, 0);
      expect(SettingsKeys.pipSideGestures.defaultValue, isFalse);
      expect(SettingsKeys.pipHaptics.defaultValue, isFalse);
      expect(SettingsKeys.pipAnimations.defaultValue, isTrue);
      expect(SettingsKeys.pipDefaultSize.defaultValue, 1);
      expect(SettingsKeys.pipOffsetX.defaultValue, -1);
      expect(SettingsKeys.pipOffsetY.defaultValue, -1);
      expect(SettingsKeys.pipScale.defaultValue, 0);
    });
  });
}
