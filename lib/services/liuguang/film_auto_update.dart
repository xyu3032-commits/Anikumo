import 'dart:async';
import 'dart:convert';

import '../storage/storage.dart';
import 'film_features.dart';
import 'film_prefs.dart';
import 'video_engine.dart';

/// Batch 232 （追剧自动更新 feature pack): the favorites
/// update check from Batch 207, automated — entering the
/// film zone runs it at most once per six hours and leaves
/// the findings as a pending banner on the favorites tab
/// instead of a dialog. Uses the same remarks stamps as
/// the manual check, so the two never fight: whichever
/// runs first consumes the change.
abstract final class FilmAutoUpdate {
  static const _throttle = Duration(hours: 6);

  static ({int lastAtMs, List<String> pending}) _state() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.filmUpdateCheckJson);
      if (raw.isEmpty) return (lastAtMs: 0, pending: const []);
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return (
          lastAtMs: (decoded['lastAtMs'] as num?)?.toInt() ?? 0,
          pending: [
            for (final e in (decoded['pending'] as List? ?? const []))
              e.toString(),
          ],
        );
      }
    } catch (_) {}
    return (lastAtMs: 0, pending: const []);
  }

  static Future<void> _save(int lastAtMs, List<String> pending) =>
      GStorage.putSetting(
        SettingsKeys.filmUpdateCheckJson,
        jsonEncode({'lastAtMs': lastAtMs, 'pending': pending}),
      );

  /// Update messages waiting to be shown on the favorites
  /// tab (empty when the pack is off or nothing moved).
  static List<String> pendingUpdates() =>
      FilmFeatures.isInstalled(FilmFeatures.autoUpdateId)
      ? _state().pending
      : const [];

  static Future<void> clearPending() async {
    final state = _state();
    await _save(state.lastAtMs, const []);
  }

  /// Runs the check when the pack is installed and the
  /// throttle has elapsed. Returns the updates found by
  /// this run (they are also stored as pending).
  static Future<List<String>> maybeCheck() async {
    if (!FilmFeatures.isInstalled(FilmFeatures.autoUpdateId)) {
      return const [];
    }
    final state = _state();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - state.lastAtMs < _throttle.inMilliseconds) {
      return state.pending;
    }
    final service = VideoEngineService.instance;
    service.loadRegistry();
    if (!service.hasSources) return const [];
    final engine = await service.engine();
    final favorites = await engine.favorites.list();
    final stamps = FilmPrefs.favoriteStamps();
    final updated = <String>[];
    var stampsChanged = false;
    for (final favorite in favorites) {
      final snapshot = favorite.mediaSnapshot;
      if (snapshot.isEmpty) continue;
      final mediaId = favorite.mediaId;
      try {
        final detail = await engine.getDetail(mediaId);
        final remarks = detail?.item.raw['remarks']?.toString() ?? '';
        if (remarks.isEmpty) continue;
        final previous = stamps[mediaId];
        if (previous == null) {
          // First sight: seed silently, like the manual
          // check's first run.
          stamps[mediaId] = remarks;
          stampsChanged = true;
        } else if (previous != remarks) {
          updated.add('「${detail!.item.title}」$previous → $remarks');
          stamps[mediaId] = remarks;
          stampsChanged = true;
        }
      } catch (_) {
        // One dead favorite must not sink the whole check.
      }
    }
    if (stampsChanged) await FilmPrefs.setFavoriteStamps(stamps);
    final pending = [...state.pending, ...updated];
    await _save(now, pending);
    return updated;
  }
}
