import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/novel_item.dart';
import 'novel_api.dart';

/// One downloaded novel chapter (batch 31: the novel zone
/// gets the manga zone's download capability). Content blocks
/// are stored as JSON; image blocks additionally download
/// their image file so image chapters read offline too. The
/// index is a JSON file next to the chapter folders, so
/// wiping the folder wipes everything consistently.
class NovelDownloadEntry {
  const NovelDownloadEntry({
    required this.source,
    required this.bookUrl,
    required this.bookTitle,
    required this.coverUrl,
    required this.chapterUrl,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.blockCount,
    required this.downloadedAtMs,
  });

  final String source;
  final String bookUrl;
  final String bookTitle;
  final String coverUrl;
  final String chapterUrl;
  final String chapterTitle;
  final int chapterIndex;
  final int blockCount;
  final int downloadedAtMs;

  String get key => '$source::$bookUrl::$chapterUrl';

  Map<String, dynamic> toJson() => {
        'source': source,
        'bookUrl': bookUrl,
        'bookTitle': bookTitle,
        'coverUrl': coverUrl,
        'chapterUrl': chapterUrl,
        'chapterTitle': chapterTitle,
        'chapterIndex': chapterIndex,
        'blockCount': blockCount,
        'downloadedAtMs': downloadedAtMs,
      };

  static NovelDownloadEntry? fromJson(Map<dynamic, dynamic> json) {
    final bookUrl = json['bookUrl']?.toString() ?? '';
    final chapterUrl = json['chapterUrl']?.toString() ?? '';
    if (bookUrl.isEmpty || chapterUrl.isEmpty) return null;
    return NovelDownloadEntry(
      source: json['source']?.toString() ?? '',
      bookUrl: bookUrl,
      bookTitle: json['bookTitle']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      chapterUrl: chapterUrl,
      chapterTitle: json['chapterTitle']?.toString() ?? '',
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      blockCount: (json['blockCount'] as num?)?.toInt() ?? 0,
      downloadedAtMs: (json['downloadedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class NovelDownloadStore {
  NovelDownloadStore._();

  static Directory? _rootCache;

  static Future<Directory> root() async {
    if (_rootCache != null) return _rootCache!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/novel_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _rootCache = dir;
  }

  /// FNV-1a hash for directory names: book/chapter URLs are
  /// far too long (and slashy) to be path segments.
  static String _hash(String input) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static Future<Directory> chapterDir(NovelDownloadEntry entry) async {
    final base = await root();
    return Directory('${base.path}/${_hash(entry.key)}');
  }

  static Future<File> _indexFile() async {
    final base = await root();
    return File('${base.path}/index.json');
  }

  static Future<List<NovelDownloadEntry>> loadIndex() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map) ?NovelDownloadEntry.fromJson(entry),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _saveIndex(List<NovelDownloadEntry> entries) async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  static String keyFor(NovelItem item, NovelChapter chapter) =>
      '${item.source}::${item.bookUrl}::${chapter.url}';

  static Future<Set<String>> downloadedKeys() async {
    final entries = await loadIndex();
    return {for (final e in entries) e.key};
  }

  /// Download one chapter's blocks (and its image files).
  /// Returns the entry on success, null on failure. WebView
  /// chapters cannot be downloaded — their content only
  /// exists inside a browser rendering.
  static Future<NovelDownloadEntry?> downloadChapter({
    required NovelItem item,
    required NovelChapter chapter,
    required int chapterIndex,
    void Function(int done, int total)? onProgress,
  }) async {
    if (chapter.webView) return null;
    // Batch 33: failures used to collapse into a silent null
    // and a generic "check your network" toast — imported
    // sources whose rules the engine subset cannot run were
    // indistinguishable from a network blip. Propagate the
    // real reason; the caller shows it.
    final List<NovelBlock> blocks;
    try {
      // Batch 195: downloads need the completeness signal,
      // not just blocks — a flagged chapter (pagination cut
      // short, or only a verification wall's preview) must
      // fail loudly instead of being stored as complete.
      final result = await NovelApi.contentDetailed(item, chapter);
      if (result.verificationRequired) {
        throw StateError('源站要求完成验证后才能阅读全文，这一章暂时下不了');
      }
      if (result.possiblyTruncated) {
        throw StateError('这一章没有取完整，已跳过（可稍后重试）');
      }
      blocks = result.blocks;
    } on StateError {
      rethrow;
    } catch (e) {
      throw StateError('这一章的内容抓取失败：$e');
    }
    // Batch 184: whitespace-only or otherwise unreadable
    // block lists are not content either — never cache a
    // blank chapter and call it downloaded.
    if (!novelBlocksHaveContent(blocks)) {
      throw StateError('这一章没有抓到内容（源规则可能用到了暂不支持的写法）');
    }
    final entry = NovelDownloadEntry(
      source: item.source,
      bookUrl: item.bookUrl,
      bookTitle: item.title,
      coverUrl: item.coverUrl,
      chapterUrl: chapter.url,
      chapterTitle: chapter.title,
      chapterIndex: chapterIndex,
      blockCount: blocks.length,
      downloadedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final dir = await chapterDir(entry);
    await dir.create(recursive: true);
    final dio = Dio();
    try {
      final serialized = <Map<String, dynamic>>[];
      var imageIndex = 0;
      var done = 0;
      for (final block in blocks) {
        switch (block) {
          case NovelTextBlock(:final text):
            serialized.add({'t': 'text', 'text': text});
          case NovelImageBlock(:final url, :final headers):
            final name = '${imageIndex.toString().padLeft(4, '0')}.img';
            imageIndex++;
            final target = File('${dir.path}/$name');
            if (!await target.exists() || await target.length() == 0) {
              await dio.download(
                url,
                target.path,
                // Batch 252: same header completion as
                // the reader (UA / Referer / cookies) —
                // a bare fetch stored the CDN's refusal
                // page as the image.
                options: Options(
                  headers: novelImageRequestHeaders(
                    blockHeaders: headers,
                    sourceHeaders: NovelApi.headersFor(item),
                    chapterUrl: chapter.url,
                    imageUrl: url,
                    cookieHeader: novelCookieHeaderFor(url),
                  ),
                ),
              );
            }
            serialized.add({'t': 'img', 'file': name});
        }
        done++;
        onProgress?.call(done, blocks.length);
      }
      await File('${dir.path}/content.json')
          .writeAsString(jsonEncode(serialized));
    } catch (_) {
      return null;
    }
    final entries = await loadIndex();
    entries.removeWhere((e) => e.key == entry.key);
    entries.add(entry);
    await _saveIndex(entries);
    return entry;
  }

  /// Load a downloaded chapter's blocks (image blocks point
  /// at their local files via file:// URLs), or null when
  /// the chapter is not on disk.
  static Future<List<NovelBlock>?> loadLocal(
    NovelItem item,
    NovelChapter chapter,
  ) async {
    final probe = NovelDownloadEntry(
      source: item.source,
      bookUrl: item.bookUrl,
      bookTitle: item.title,
      coverUrl: item.coverUrl,
      chapterUrl: chapter.url,
      chapterTitle: chapter.title,
      chapterIndex: 0,
      blockCount: 0,
      downloadedAtMs: 0,
    );
    final dir = await chapterDir(probe);
    final file = File('${dir.path}/content.json');
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return null;
      return [
        for (final raw in decoded)
          if (raw is Map && raw['t'] == 'text')
            NovelTextBlock(raw['text']?.toString() ?? '')
          else if (raw is Map && raw['t'] == 'img')
            NovelImageBlock('file://${dir.path}/${raw['file']}'),
      ];
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(NovelDownloadEntry entry) async {
    final dir = await chapterDir(entry);
    if (await dir.exists()) await dir.delete(recursive: true);
    final entries = await loadIndex();
    entries.removeWhere((e) => e.key == entry.key);
    await _saveIndex(entries);
  }

  static Future<void> clearAll() async {
    final base = await root();
    if (await base.exists()) await base.delete(recursive: true);
    await base.create(recursive: true);
    _rootCache = base;
  }

  static Future<int> totalSizeBytes() async {
    final base = await root();
    var total = 0;
    await for (final entity in base.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}
