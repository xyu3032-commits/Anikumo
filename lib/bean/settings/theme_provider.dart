import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:anikumo/utils/constants.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  bool useDynamicColor = false;
  late ThemeData light;
  late ThemeData dark;
  String? currentFontFamily = customAppFontFamily;

  /// Returns true if the effective theme is dark mode.
  /// Automatically gets platform brightness when themeMode is ThemeMode.system.
  bool isEffectiveDark() {
    if (themeMode == ThemeMode.dark) return true;
    if (themeMode == ThemeMode.light) return false;
    final platformBrightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return platformBrightness == Brightness.dark;
  }

  void setTheme(ThemeData light, ThemeData dark, {bool notify = true}) {
    this.light = light;
    this.dark = dark;
    if (notify) notifyListeners();
  }

  void setThemeMode(ThemeMode mode, {bool notify = true}) {
    themeMode = mode;
    if (notify) notifyListeners();
  }

  void setDynamic(bool useDynamicColor, {bool notify = true}) {
    this.useDynamicColor = useDynamicColor;
    if (notify) notifyListeners();
  }

  bool _useSystemFont = false;

  /// Batch 84: family of the user-imported font, when one
  /// is active. Takes precedence over the bundled/system
  /// choice until cleared (恢复默认字体).
  String? userFontFamily;

  String? get _baseFontFamily =>
      _useSystemFont ? null : customAppFontFamily;

  void setFontFamily(bool useSystemFont, {bool notify = true}) {
    _useSystemFont = useSystemFont;
    currentFontFamily = userFontFamily ?? _baseFontFamily;
    if (notify) notifyListeners();
  }

  /// Batch 84: activate (or clear, with null) the imported
  /// user font. Callers rebuild the static themes after
  /// this — see CustomFontService.rebuildThemes.
  void setUserFontFamily(String? family, {bool notify = true}) {
    userFontFamily = family;
    currentFontFamily = family ?? _baseFontFamily;
    if (notify) notifyListeners();
  }
}
