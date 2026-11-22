import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:anikumo/services/download/download_directory_service.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/storage/library_housekeeping.dart';
import 'package:anikumo/utils/file_system.dart';

/// Batch 283 (#29): the measurement half of the
/// storage analysis page. Every row is a plain
/// recursive directory walk (files only, races
/// tolerated); the page owns presentation and the
/// clear/jump actions, this file owns the numbers so
/// they stay testable and reusable.
enum StorageRowKind {
  /// Cache-manager stores — safe to clear, they
  /// simply re-download on next access.
  cache,

  /// Finished downloads — user content; the page
  /// shows the size and a jump entry, never a delete.
  download,

  /// Local backups — same treatment as downloads.
  backup,

  /// The log directory — shown, with a jump to the
  /// log page.
  log,

  /// Space that cannot be attributed to one owner
  /// (the player spills its stream buffer into the
  /// system temp dir alongside other short-lived
  /// scratch). Shown for honesty; no clear action —
  /// there is no manager to clear it through, and
  /// the OS reclaims temp space itself.
  scratch,
}

class StorageRowData {
  final String id;
  final StorageRowKind kind;
  final int bytes;

  const StorageRowData({
    required this.id,
    required this.kind,
    required this.bytes,
  });
}

int totalBytesOf(List<StorageRowData> rows) =>
    rows.fold(0, (sum, row) => sum + row.bytes);

/// Recursive size of [dir]; a missing directory is 0
/// and files vanishing mid-walk are skipped.
Future<int> directorySize(Directory dir) async {
  if (!await dir.exists()) return 0;
  var bytes = 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    try {
      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.file) bytes += stat.size;
    } catch (_) {
      // Racing a writer/eviction is fine.
    }
  }
  return bytes;
}

abstract final class StorageAnalysis {
  /// Measures every row. Each row is guarded on its
  /// own: one broken source degrades to 0, never to a
  /// failed page.
  static Future<List<StorageRowData>> measure() async {
    final rows = <StorageRowData>[];

    Future<void> add(
      String id,
      StorageRowKind kind,
      Future<int> Function() measure,
    ) async {
      var bytes = 0;
      try {
        bytes = await measure();
      } catch (_) {}
      rows.add(StorageRowData(id: id, kind: kind, bytes: bytes));
    }

    await add(
      'animeDownloads',
      StorageRowKind.download,
      () async => directorySize(
        Directory(await _animeDownloadRoot()),
      ),
    );
    await add(
      'mangaDownloads',
      StorageRowKind.download,
      () async => directorySize(await MangaDownloadStore.root()),
    );
    await add(
      'filmDownloads',
      StorageRowKind.download,
      () async =>
          directorySize(await VideoEngineService.instance.downloadsDirectory()),
    );

    // The image cache: the four cache-manager stores,
    // plus whatever else the temp dir holds (reported
    // separately as scratch).
    final temp = await getTemporaryDirectory();
    var imageBytes = 0;
    for (final key in cacheStoreKeys) {
      imageBytes += await directorySize(Directory(p.join(temp.path, key)));
    }
    rows.add(
      StorageRowData(
        id: 'imageCache',
        kind: StorageRowKind.cache,
        bytes: imageBytes,
      ),
    );
    final tempTotal = await directorySize(temp);
    rows.add(
      StorageRowData(
        id: 'playbackScratch',
        kind: StorageRowKind.scratch,
        bytes: tempTotal > imageBytes ? tempTotal - imageBytes : 0,
      ),
    );

    final support = await getApplicationSupportDirectory();
    await add(
      'subtitleCache',
      StorageRowKind.cache,
      () => directorySize(Directory(p.join(support.path, 'subtitle_translations'))),
    );
    await add(
      'logs',
      StorageRowKind.log,
      () => directorySize(Directory(p.join(support.path, 'logs'))),
    );

    final docs = await getApplicationDocumentsDirectory();
    await add(
      'backups',
      StorageRowKind.backup,
      () => directorySize(Directory(p.join(docs.path, 'anikumo_backups'))),
    );

    return rows;
  }

  static Future<String> _animeDownloadRoot() async {
    try {
      return await DownloadDirectoryService().getDownloadDirectory();
    } catch (_) {
      return getDefaultDownloadDirectory();
    }
  }
}
