import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_image_pipeline.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:path_provider/path_provider.dart';

/// One downloaded chapter, stored as page image files under the
/// app documents directory (batch 15, M1). The index is a JSON
/// file next to the page folders, so wiping the folder wipes
/// everything consistently.
class MangaDownloadEntry {
  const MangaDownloadEntry({
    required this.source,
    required this.mangaId,
    required this.mangaTitle,
    required this.coverUrl,
    required this.chapterId,
    required this.chapterLabel,
    required this.pageCount,
    required this.downloadedAtMs,
  });

  final String source;
  final String mangaId;
  final String mangaTitle;
  final String coverUrl;
  final String chapterId;
  final String chapterLabel;
  final int pageCount;
  final int downloadedAtMs;

  String get key => '$source:$mangaId:$chapterId';

  Map<String, dynamic> toJson() => {
    'source': source,
    'mangaId': mangaId,
    'mangaTitle': mangaTitle,
    'coverUrl': coverUrl,
    'chapterId': chapterId,
    'chapterLabel': chapterLabel,
    'pageCount': pageCount,
    'downloadedAtMs': downloadedAtMs,
  };

  static MangaDownloadEntry? fromJson(Map<dynamic, dynamic> json) {
    final chapterId = json['chapterId']?.toString() ?? '';
    final mangaId = json['mangaId']?.toString() ?? '';
    if (chapterId.isEmpty || mangaId.isEmpty) return null;
    return MangaDownloadEntry(
      source: json['source']?.toString() ?? 'mangadex',
      mangaId: mangaId,
      mangaTitle: json['mangaTitle']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      chapterId: chapterId,
      chapterLabel: json['chapterLabel']?.toString() ?? '',
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      downloadedAtMs: (json['downloadedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class MangaDownloadStore {
  MangaDownloadStore._();

  static Directory? _rootCache;

  static Future<Directory> root() async {
    if (_rootCache != null) return _rootCache!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/manga_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _rootCache = dir;
  }

  static String _safe(String segment) =>
      segment.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  static Future<Directory> chapterDir(MangaDownloadEntry entry) async {
    final base = await root();
    return Directory(
      '${base.path}/${_safe(entry.source)}/${_safe(entry.mangaId)}/${_safe(entry.chapterId)}',
    );
  }

  static Future<File> _indexFile() async {
    final base = await root();
    return File('${base.path}/index.json');
  }

  /// Batch 252: in-memory copy of the index. Every
  /// chapter open used to re-read and re-decode the
  /// whole index file from disk (plus a path_provider
  /// round trip) just to answer "is this chapter
  /// downloaded" — pure latency on the reader's enter
  /// path. Writes funnel through [_saveIndex], which
  /// keeps the memo in step; readers get copies, never
  /// the memo itself (batch 104's in-place-mutation
  /// lesson).
  static List<MangaDownloadEntry>? _indexMemo;

  static Future<List<MangaDownloadEntry>> loadIndex() async {
    final memo = _indexMemo;
    if (memo != null) return [...memo];
    // Batch 104: never return a const list. On a fresh
    // install (no index file yet) the empty cases used to
    // hand back `const []`, and downloadChapter's in-place
    // removeWhere on it threw UnsupportedError AFTER the
    // pages were fetched — so the first-ever download on
    // any install failed, the index was never created, and
    // every later download failed the same way. (The batch
    // 82 lesson, learned for reading progress, applied here
    // at the source: always return a writable list.)
    try {
      final file = await _indexFile();
      if (!await file.exists()) {
        _indexMemo = <MangaDownloadEntry>[];
        return <MangaDownloadEntry>[];
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        _indexMemo = <MangaDownloadEntry>[];
        return <MangaDownloadEntry>[];
      }
      final entries = [
        for (final entry in decoded)
          if (entry is Map) ?MangaDownloadEntry.fromJson(entry),
      ];
      _indexMemo = entries;
      return [...entries];
    } catch (_) {
      return <MangaDownloadEntry>[];
    }
  }

  /// Batch 83: backup restore — merges records whose
  /// chapter files still exist on this device. The chapter
  /// images themselves never travel inside a JSON backup,
  /// so records pointing at missing files are skipped
  /// instead of becoming zombie entries. Returns
  /// (restored, skipped).
  static Future<(int, int)> mergeIndexEntries(
    List<MangaDownloadEntry> incoming,
  ) async {
    if (incoming.isEmpty) return (0, 0);
    final existing = await loadIndex();
    final byKey = {for (final e in existing) e.key: e};
    var restored = 0;
    var skipped = 0;
    for (final entry in incoming) {
      final dir = await chapterDir(entry);
      if (await dir.exists()) {
        byKey[entry.key] = entry;
        restored++;
      } else {
        skipped++;
      }
    }
    if (restored > 0) {
      await _saveIndex(byKey.values.toList());
    }
    return (restored, skipped);
  }

  static Future<void> _saveIndex(List<MangaDownloadEntry> entries) async {
    _indexMemo = [...entries];
    final file = await _indexFile();
    await file.writeAsString(jsonEncode([for (final e in entries) e.toJson()]));
  }

  static Future<bool> isDownloaded(
    String source,
    String mangaId,
    String chapterId,
  ) async {
    final entries = await loadIndex();
    return entries.any((e) => e.key == '$source:$mangaId:$chapterId');
  }

  /// Local page list for a downloaded chapter, in order, as
  /// 'file://' URLs the reader renders from disk.
  static Future<List<MangaPage>?> localPages(
    String source,
    String mangaId,
    String chapterId,
  ) async {
    final entries = await loadIndex();
    final entry = entries
        .where((e) => e.key == '$source:$mangaId:$chapterId')
        .firstOrNull;
    if (entry == null) return null;
    final dir = await chapterDir(entry);
    if (!await dir.exists()) return null;
    final files = await dir
        .list()
        .where((f) => f is File && f.path.endsWith('.img'))
        .cast<File>()
        .toList();
    // Batch 185: order by the page number in the file
    // name, not lexicographically — zero padding made the
    // two agree only up to page 9999.
    int pageNo(File f) {
      final base = f.path.split('/').last;
      return int.tryParse(base.split('.').first) ?? 1 << 30;
    }

    files.sort((a, b) {
      final byNo = pageNo(a).compareTo(pageNo(b));
      return byNo != 0 ? byNo : a.path.compareTo(b.path);
    });
    if (files.isEmpty) return null;
    return [for (final f in files) MangaPage('file://${f.path}')];
  }

  /// Downloads every page of [chapter]; [onProgress] receives
  /// (done, total). Returns the stored entry, or null on failure
  /// (partial files are cleaned up).
  static Future<MangaDownloadEntry?> downloadChapter({
    required MangaItem manga,
    required MangaChapter chapter,
    void Function(int done, int total)? onProgress,
  }) async {
    final pages = await MangaApi.fetchChapterPages(manga, chapter);
    if (pages.isEmpty) return null;
    final entry = MangaDownloadEntry(
      source: manga.source,
      mangaId: manga.id,
      mangaTitle: manga.title,
      coverUrl: manga.coverUrl,
      chapterId: chapter.id,
      chapterLabel: chapter.displayLabel,
      pageCount: pages.length,
      downloadedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final dir = await chapterDir(entry);
    await dir.create(recursive: true);
    final dio = Dio();
    try {
      // Batch 16: three pages in parallel (was strictly
      // sequential), each via a .part file renamed on success,
      // and pages already on disk are skipped — an interrupted
      // download now resumes instead of starting over, and a
      // failed run keeps its partial pages for next time (the
      // index entry is only written on full success, so partial
      // chapters never surface as downloaded).
      var done = 0;
      // Batch 185: a stored page only counts as downloaded
      // when its head bytes are really an image. Downloads
      // used to skip any non-empty file and save any 200
      // response verbatim — an HTML error page served for
      // one page became a permanent broken page that
      // resume would never refetch.
      Future<bool> storedPageIsImage(File file) async {
        try {
          if (!await file.exists() || await file.length() < 12) {
            return false;
          }
          final head = await file
              .openRead(0, 16)
              .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
          return looksLikeImageBytes(head);
        } catch (_) {
          return false;
        }
      }

      Future<void> fetchPage(int i) async {
        final name = i.toString().padLeft(4, '0');
        final target = File('${dir.path}/$name.img');
        if (await storedPageIsImage(target)) {
          done++;
          onProgress?.call(done, pages.length);
          return;
        }
        if (await target.exists()) {
          // Present but not a valid image (an error page
          // from an earlier run): drop it and refetch.
          await target.delete();
        }
        final page = pages[i];
        final spec = mangaPageLoadSpec(
          manga: manga,
          chapter: chapter,
          page: page,
        );
        if (spec != null) {
          // Batch 104: pages that need processing
          // (an `onResponse` transform, a `modifyImage`
          // descramble, an `onLoadFailed` fallback) must be
          // stored as their DISPLAYABLE bytes. Downloading
          // the raw wire bytes saved the scrambled form —
          // the "download" succeeded but the chapter read as
          // garbage offline.
          final bytes = await loadProcessedImageBytes(
            cacheManager: null,
            spec: spec,
          );
          await target.writeAsBytes(bytes, flush: true);
        } else {
          final part = File('${dir.path}/$name.img.part');
          await dio.download(
            page.url,
            part.path,
            options: Options(headers: page.headers),
          );
          await part.rename(target.path);
          if (!await storedPageIsImage(target)) {
            await target.delete();
            throw const FormatException('downloaded page was not an image');
          }
        }
        done++;
        onProgress?.call(done, pages.length);
      }

      for (var i = 0; i < pages.length; i += 3) {
        await Future.wait([
          for (var j = i; j < i + 3 && j < pages.length; j++) fetchPage(j),
        ]);
      }
    } catch (_) {
      return null;
    }
    // Batch 104: build the next index instead of mutating
    // the loaded one in place (see loadIndex).
    final current = await loadIndex();
    await _saveIndex([
      for (final e in current)
        if (e.key != entry.key) e,
      entry,
    ]);
    return entry;
  }

  static Future<void> deleteEntry(MangaDownloadEntry entry) async {
    final dir = await chapterDir(entry);
    if (await dir.exists()) await dir.delete(recursive: true);
    final current = await loadIndex();
    await _saveIndex([
      for (final e in current)
        if (e.key != entry.key) e,
    ]);
  }

  /// Total size of the downloads folder in bytes.
  static Future<int> totalSizeBytes() async {
    final base = await root();
    var total = 0;
    await for (final entity in base.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  static Future<void> clearAll() async {
    final base = await root();
    await base.delete(recursive: true);
    _rootCache = null;
    await root();
  }
}
