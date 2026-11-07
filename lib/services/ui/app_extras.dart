import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/services/manga/manga_extras.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 15 "big features" service layer: scheduled dark mode,
/// per-anime playback speed, title filtering, saved searches,
/// PIN lock, smooth mode and history CSV export. Decision logic
/// is pure where it can be and unit-tested.

// ── Scheduled dark (G4) ──────────────────────────────────────

/// Night window for the scheduled dark mode: 21:00 → 06:00.
bool isScheduledDark(DateTime now) => now.hour >= 21 || now.hour < 6;

// ── Per-anime playback speed (G6) ────────────────────────────

class PerAnimePlayStore {
  PerAnimePlayStore._();

  static Map<String, double> _load() {
    final raw = GStorage.getSetting(SettingsKeys.perAnimePlayJson);
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final e in decoded.entries)
          e.key.toString(): (e.value as num?)?.toDouble() ?? 1,
      };
    } catch (_) {
      return const {};
    }
  }

  static double? speedFor(int bangumiId) {
    if (bangumiId <= 0) return null;
    return _load()[bangumiId.toString()];
  }

  static Future<void> saveSpeed(int bangumiId, double speed) async {
    if (bangumiId <= 0) return;
    final map = {..._load(), bangumiId.toString(): speed};
    await GStorage.putSetting(
      SettingsKeys.perAnimePlayJson,
      jsonEncode(map),
    );
  }
}

// ── Title keyword filter (G7) ────────────────────────────────

class TitleFilterStore {
  TitleFilterStore._();

  static List<String> loadKeywords() {
    final raw = GStorage.getSetting(SettingsKeys.titleFilterJson);
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [for (final e in decoded) e.toString()];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveKeywords(List<String> keywords) {
    return GStorage.putSetting(
      SettingsKeys.titleFilterJson,
      jsonEncode(keywords),
    );
  }
}

/// True when [title] contains any non-empty keyword
/// (case-insensitive).
bool titleBlocked(String title, List<String> keywords) {
  final lower = title.toLowerCase();
  for (final keyword in keywords) {
    final needle = keyword.trim().toLowerCase();
    if (needle.isNotEmpty && lower.contains(needle)) return true;
  }
  return false;
}

// ── Saved anime searches (G8) ────────────────────────────────

class SavedSearchStore {
  SavedSearchStore._();

  static List<String> load() {
    final raw = GStorage.getSetting(SettingsKeys.savedAnimeSearchesJson);
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [for (final e in decoded) e.toString()];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add(String keyword) async {
    final next = addKeywordToHistory(load(), keyword);
    await GStorage.putSetting(
      SettingsKeys.savedAnimeSearchesJson,
      jsonEncode(next),
    );
  }

  static Future<void> remove(String keyword) async {
    final next = [for (final k in load()) if (k != keyword) k];
    await GStorage.putSetting(
      SettingsKeys.savedAnimeSearchesJson,
      jsonEncode(next),
    );
  }
}

// ── PIN app lock (G10) ───────────────────────────────────────

class PinLock {
  PinLock._();

  /// Session-scoped: once unlocked, stays unlocked until the
  /// process restarts.
  static bool unlockedThisSession = false;

  static String hashPin(String pin) =>
      sha256.convert(utf8.encode('anikumo-pin:$pin')).toString();

  static bool get isEnabled =>
      GStorage.getSetting(SettingsKeys.pinLockHash).isNotEmpty;

  static bool verify(String pin) {
    final stored = GStorage.getSetting(SettingsKeys.pinLockHash);
    return stored.isNotEmpty && stored == hashPin(pin);
  }

  static Future<void> setPin(String pin) {
    unlockedThisSession = true;
    return GStorage.putSetting(SettingsKeys.pinLockHash, hashPin(pin));
  }

  static Future<void> clear() {
    unlockedThisSession = false;
    return GStorage.putSetting(SettingsKeys.pinLockHash, '');
  }
}

// ── Smooth mode (G12) ────────────────────────────────────────

/// Master "smooth / power-save" switch. When on, entrance
/// animations render statically (see FadeSlideIn) and the
/// settings page orchestrates glass/data-saver settings.
class SmoothMode {
  SmoothMode._();

  static final ValueNotifier<bool> notifier =
      ValueNotifier<bool>(_stored());

  static bool _stored() {
    try {
      return GStorage.getSetting(SettingsKeys.smoothMode);
    } catch (_) {
      return false;
    }
  }

  static bool get enabled => notifier.value;

  static Future<void> setEnabled(bool value) async {
    notifier.value = value;
    await GStorage.putSetting(SettingsKeys.smoothMode, value);
  }
}

// ── History CSV export (G11) ─────────────────────────────────

String _csvCell(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// Anime watch history as CSV rows.
String buildAnimeHistoryCsv(List<History> histories) {
  final buffer = StringBuffer('type,title,episode,time,source\n');
  final sorted = [...histories]
    ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
  for (final history in sorted) {
    buffer.writeln([
      'anime',
      _csvCell(
        history.bangumiItem.nameCn.isNotEmpty
            ? history.bangumiItem.nameCn
            : history.bangumiItem.name,
      ),
      history.lastWatchEpisode.toString(),
      history.lastWatchTime.toIso8601String(),
      _csvCell(history.adapterName),
    ].join(','));
  }
  return buffer.toString();
}

/// Manga reading progress as CSV rows.
String buildMangaHistoryCsv(List<MangaProgress> progress) {
  final buffer = StringBuffer('type,title,chapter,page,time,source\n');
  final sorted = [...progress]
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  for (final entry in sorted) {
    buffer.writeln([
      'manga',
      _csvCell(entry.mangaTitle),
      _csvCell(entry.chapterLabel),
      (entry.page + 1).toString(),
      DateTime.fromMillisecondsSinceEpoch(entry.updatedAtMs)
          .toIso8601String(),
      _csvCell(entry.mangaSource),
    ].join(','));
  }
  return buffer.toString();
}
