import 'dart:async';

import 'package:flutter/material.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/services/manga/manga_source_updates.dart';

/// Batch 190: the "a source has a new version" prompt.
///
/// Runs when the manga zone is entered (and on demand
/// from the sources page's 检查更新 button): checks the
/// recorded repositories and source origins, and when
/// updates exist asks once — 更新 applies them through
/// the validated installer, 稍后 leaves everything as-is
/// (the prompt returns on the next entry, per the
/// requested behavior). A fresh check is debounced for
/// a minute against rapid zone hopping; the cached
/// verdict still drives the prompt on every entry.
class MangaSourceUpdatePrompt {
  MangaSourceUpdatePrompt._();

  static bool _showing = false;
  static bool _checking = false;
  static DateTime? _lastCheckAt;
  static List<MangaSourceUpdate> _cached = const [];

  static Future<void> run(
    BuildContext context, {
    bool force = false,
  }) async {
    if (_showing || _checking) return;
    final stale = _lastCheckAt == null ||
        DateTime.now().difference(_lastCheckAt!) >
            const Duration(minutes: 1);
    if (force || stale) {
      _checking = true;
      try {
        _cached = await MangaSourceUpdates.check();
        _lastCheckAt = DateTime.now();
      } catch (_) {
        // A failed check stays silent.
      } finally {
        _checking = false;
      }
    }
    if (!context.mounted) return;
    if (_cached.isEmpty) {
      if (force) {
        AnikumoDialog.showToast(message: '所有漫画源都是最新版');
      }
      return;
    }
    _showing = true;
    try {
      final updates = _cached;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('漫画源有新版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final update in updates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${update.name}：'
                    '${update.installedVersion} → '
                    '${update.latestVersion}',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('更新'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      AnikumoDialog.showToast(message: '正在更新 ${updates.length} 个源…');
      final result = await MangaSourceUpdates.apply(updates);
      // Whatever was attempted is re-evaluated by the
      // next fresh check, not by this cached verdict.
      _cached = const [];
      _lastCheckAt = null;
      if (!context.mounted) return;
      AnikumoDialog.showToast(
        message: result.failed == 0
            ? '已更新 ${result.updated} 个源'
            : '已更新 ${result.updated} 个，${result.failed} 个更新失败',
      );
    } finally {
      _showing = false;
    }
  }
}
