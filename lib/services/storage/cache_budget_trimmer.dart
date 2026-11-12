import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'package:anikumo/services/logging/logger.dart';

/// Batch 145: byte budgets for the on-disk image stores.
///
/// The cache managers cap their stores by OBJECT COUNT
/// (800 pages, 600 covers, 800 shared images) — but a manga
/// page can be anywhere from 200 KB to 8 MB, so a count cap
/// alone lets a long reading session pile up gigabytes
/// before eviction notices. These budgets bound each store
/// by BYTES instead: comfortably above what a normal
/// session needs for resume-reading (the count caps still
/// apply underneath), far below the old worst case.
// Batch 239 ("less cache" pass): every budget tightened
// — pages 512 -> 256 MB, manga covers 192 -> 96 MB,
// shared 256 -> 128 MB — and the film zone's poster store
// joins with its own 96 MB budget (it previously had a
// count cap only). Evicted entries simply re-download on
// next access; no feature reads these stores as data.
const int mangaPageCacheBudgetBytes = 256 * 1024 * 1024;
const int mangaCoverCacheBudgetBytes = 96 * 1024 * 1024;
const int sharedImageCacheBudgetBytes = 128 * 1024 * 1024;
const int filmCoverCacheBudgetBytes = 96 * 1024 * 1024;

/// Trims [dir] down to [budgetBytes] by deleting the
/// oldest-modified files first. Returns the bytes freed.
///
/// Safety rails:
/// - files modified within the last five minutes are never
///   touched (an in-flight download may still be writing);
/// - metadata-looking files (.json/.db) are skipped — the
///   cache managers keep their bookkeeping elsewhere, this
///   is belt-and-braces;
/// - a store entry whose file vanished is handled by the
///   cache manager itself (it re-downloads on next access),
///   so deleting behind its back is safe.
Future<int> trimDirectoryToBudget(
  Directory dir,
  int budgetBytes, {
  DateTime? now,
}) async {
  if (!await dir.exists()) return 0;
  final clock = now ?? DateTime.now();
  final freshCutoff = clock.subtract(const Duration(minutes: 5));
  final files = <({File file, int size, DateTime modified})>[];
  var total = 0;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final lower = entity.path.toLowerCase();
    if (lower.endsWith('.json') || lower.endsWith('.db')) continue;
    try {
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      total += stat.size;
      files.add((file: entity, size: stat.size, modified: stat.modified));
    } catch (_) {
      // A file racing us (deleted by the manager) is fine.
    }
  }
  if (total <= budgetBytes) return 0;
  files.sort((a, b) => a.modified.compareTo(b.modified));
  var freed = 0;
  for (final entry in files) {
    if (total <= budgetBytes) break;
    if (entry.modified.isAfter(freshCutoff)) continue;
    try {
      await entry.file.delete();
      total -= entry.size;
      freed += entry.size;
    } catch (_) {
      // Already gone — nothing to free.
    }
  }
  return freed;
}

Future<Directory> _storeDirectory(String key) async {
  final temp = await getTemporaryDirectory();
  return Directory('${temp.path}/$key');
}

/// Trims one named flutter_cache_manager store to [budget].
Future<void> _trimStore(String key, int budget) async {
  try {
    final freed = await trimDirectoryToBudget(
      await _storeDirectory(key),
      budget,
    );
    if (freed > 0) {
      AnikumoLogger().i(
        'CacheBudget: trimmed $key by ${(freed / 1048576).toStringAsFixed(1)} MB',
      );
    }
  } catch (e) {
    AnikumoLogger().w('CacheBudget: trim failed for $key', error: e);
  }
}

/// Startup pass over every image store. Fire-and-forget:
/// pure IO, all failures swallowed per store.
Future<void> trimImageCachesToBudgets() async {
  await _trimStore('anikumoMangaPages', mangaPageCacheBudgetBytes);
  await _trimStore('anikumoMangaCovers', mangaCoverCacheBudgetBytes);
  await _trimStore(DefaultCacheManager.key, sharedImageCacheBudgetBytes);
  await _trimStore('anikumoFilmCovers', filmCoverCacheBudgetBytes);
}

/// Called when leaving the manga reader — the moment a long
/// session has just grown the page store the most.
Future<void> trimMangaPageCache() =>
    _trimStore('anikumoMangaPages', mangaPageCacheBudgetBytes);
