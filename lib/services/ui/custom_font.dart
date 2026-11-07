import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path_provider/path_provider.dart';

import 'package:anikumo/bean/settings/theme_provider.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/utils/theme.dart';

/// Batch 84: user-imported font support.
///
/// The app already ships a bundled font (MI Sans) with a
/// system-font alternative (主题设置 → 使用系统字体). This
/// service adds the third option the user asked for: pick
/// any ttf / otf file, have it applied app-wide, and be
/// able to go back to the original font in one tap.
///
/// How it works: the picked file is copied into the app
/// documents dir (single slot, re-import replaces), its
/// bytes are registered with the engine's FontLoader
/// under a fresh family name (`AnikumoUserFont<serial>` —
/// the engine caches a family once loaded, so re-imports
/// must not reuse the name), and the family is persisted
/// so the next launch can re-register it (font families
/// do not survive process restarts).
class CustomFontService {
  CustomFontService._();

  static bool get hasCustomFont =>
      GStorage.getSetting(SettingsKeys.customFontFamily).isNotEmpty;

  static String get displayName =>
      GStorage.getSetting(SettingsKeys.customFontName);

  static Future<File> _fontFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/fonts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/user_font');
  }

  static Future<String> _register(List<int> bytes, int serial) async {
    final family = 'AnikumoUserFont$serial';
    final loader = FontLoader(family)
      ..addFont(
        Future.value(Uint8List.fromList(bytes).buffer.asByteData()),
      );
    await loader.load();
    return family;
  }

  /// Rebuilds the provider's static light/dark themes with
  /// its current font family — the same construction the
  /// theme settings page performs when the font changes
  /// (dynamic-color themes read the family per build and
  /// need no rebuild).
  static void rebuildThemes(ThemeProvider provider) {
    final colorSetting = GStorage.getSetting(SettingsKeys.themeColor);
    final Color color = colorSetting == 'default' || colorSetting.isEmpty
        ? Colors.green
        : Color(int.parse(colorSetting, radix: 16));
    final oled = GStorage.getSetting(SettingsKeys.oledEnhance);
    ThemeData build(Brightness brightness) => ThemeData(
          useMaterial3: true,
          fontFamily: provider.currentFontFamily,
          brightness: brightness,
          colorSchemeSeed: color,
          progressIndicatorTheme: progressIndicatorTheme2024,
          sliderTheme: sliderTheme2024,
          pageTransitionsTheme: pageTransitionsTheme2024,
        );
    final dark = build(Brightness.dark);
    provider.setTheme(
      build(Brightness.light),
      oled ? oledDarkTheme(dark) : dark,
    );
  }

  /// Import flow: copy the picked file into the fonts dir,
  /// register it, persist the choice, apply it everywhere.
  static Future<void> importAndApply(
    ThemeProvider provider, {
    required String pickedPath,
    required String name,
  }) async {
    final bytes = await File(pickedPath).readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('字体文件是空的');
    }
    final target = await _fontFile();
    await target.writeAsBytes(bytes, flush: true);
    final serial = GStorage.getSetting(SettingsKeys.customFontSerial) + 1;
    final family = await _register(bytes, serial);
    await GStorage.putSetting(SettingsKeys.customFontSerial, serial);
    await GStorage.putSetting(SettingsKeys.customFontFamily, family);
    await GStorage.putSetting(SettingsKeys.customFontName, name);
    provider.setUserFontFamily(family, notify: false);
    rebuildThemes(provider);
  }

  /// 恢复默认字体: drop the import and fall back to the
  /// bundled / system choice the user had before.
  static Future<void> clear(ThemeProvider provider) async {
    await GStorage.putSetting(SettingsKeys.customFontFamily, '');
    await GStorage.putSetting(SettingsKeys.customFontName, '');
    try {
      final file = await _fontFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // A stuck file is harmless: the settings no longer
      // point at it, so it is never loaded again.
    }
    provider.setUserFontFamily(null, notify: false);
    rebuildThemes(provider);
  }

  /// Startup: re-register the saved font and re-apply it.
  /// Called once from the app widget's stored-settings
  /// pass; fire-and-forget by design — a broken font file
  /// must never break startup, it just falls back to the
  /// default font.
  static Future<void> restore(ThemeProvider provider) async {
    try {
      final family = GStorage.getSetting(SettingsKeys.customFontFamily);
      if (family.isEmpty) {
        return;
      }
      final file = await _fontFile();
      if (!await file.exists()) {
        await GStorage.putSetting(SettingsKeys.customFontFamily, '');
        await GStorage.putSetting(SettingsKeys.customFontName, '');
        return;
      }
      final bytes = await file.readAsBytes();
      final loader = FontLoader(family)
        ..addFont(
          Future.value(Uint8List.fromList(bytes).buffer.asByteData()),
        );
      await loader.load();
      provider.setUserFontFamily(family, notify: false);
      rebuildThemes(provider);
    } catch (_) {
      // Keep the default font; the user can re-import.
    }
  }
}
