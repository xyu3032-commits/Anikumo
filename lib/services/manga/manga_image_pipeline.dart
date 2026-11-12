import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/manga/manga_sources.dart';

/// Batch 102: the manga zone's image pipeline additions —
/// a concurrency gate for cover downloads and the byte
/// transform path for sources whose image hooks carry an
/// `onResponse` (encrypted-image sources, batch 88's known
/// gap).

/// A FIFO counting semaphore bounding how many manga image
/// downloads run at once.
class MangaImageGate {
  MangaImageGate({this.maxConcurrent = 8});

  final int maxConcurrent;
  int _running = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  int get running => _running;
  int get waiting => _waiters.length;

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= maxConcurrent) {
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
      // The finishing task handed its slot over directly:
      // _running already counts this task.
    } else {
      _running++;
    }
    try {
      return await task();
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}

/// The one gate shared by cover downloads and transformed
/// image fetches: a grid refresh must never open dozens of
/// sockets at once (the batch-100 lesson, applied to images).
final MangaImageGate mangaImageGate = MangaImageGate();

class _BufferedImageResponse implements FileServiceResponse {
  _BufferedImageResponse(this._inner, this._bytes);

  final FileServiceResponse _inner;
  final List<int> _bytes;

  @override
  Stream<List<int>> get content => Stream<List<int>>.value(_bytes);

  @override
  int? get contentLength => _bytes.length;

  @override
  int get statusCode => _inner.statusCode;

  @override
  DateTime get validTill => _inner.validTill;

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;
}

/// Batch 185: the cache stores' file service. Downloads
/// are checked against the image magic bytes BEFORE the
/// cache manager may persist them: a CDN/WAF answering an
/// image URL with a 200 HTML challenge or error page used
/// to be cached as an "image" for the store's whole stale
/// period (10 days), and every later view re-served the
/// same garbage. Non-image bytes now fail the fetch, so
/// nothing is stored and a retry really refetches. HTTP
/// error statuses pass through untouched (the cache
/// manager raises for those itself). [gated] keeps the
/// cover store's existing concurrency gate.
class MangaImageFileService extends FileService {
  MangaImageFileService({this.gated = false});

  final bool gated;
  final FileService _inner = HttpFileService();

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = gated
        ? await mangaImageGate.run(() => _inner.get(url, headers: headers))
        : await _inner.get(url, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return response;
    }
    final bytes = <int>[];
    await for (final chunk in response.content) {
      bytes.addAll(chunk);
    }
    if (!looksLikeImageBytes(bytes)) {
      throw HttpExceptionWithStatus(
        response.statusCode,
        'image response was not image data',
      );
    }
    return _BufferedImageResponse(response, bytes);
  }
}

/// Manga covers get their own cache store (batch 102),
/// gated to 8 concurrent downloads. Covers used to share
/// CachedNetworkImage's default store with every other zone
/// (batch 51 split the reader's pages out for the same
/// reason): one queue for the whole app meant a manga grid
/// refresh fought anime covers and danmaku images for the
/// same 10 slots, and evictions crossed zones too.
final CacheManager mangaCoverCacheManager = CacheManager(
  Config(
    'anikumoMangaCovers',
    // Batch 239: 10 days / 600 -> 7 days / 400 ("less
    // cache" pass; byte budget tightened alongside).
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 400,
    fileService: MangaImageFileService(gated: true),
  ),
);

/// Runs raw downloaded bytes through a source transform and
/// returns the displayable bytes, or null when no transform
/// applied (callers then use the raw bytes).
typedef MangaByteTransform = Future<List<int>?> Function(List<int> raw);

/// Batch 185: the image fetcher gets a browser baseline:
/// a desktop User-Agent and real timeouts. It used to be
/// a bare Dio() — no UA (anti-leech CDNs 403 the default
/// or empty UA) and no timeouts at all (a wedged
/// connection could hang a prefetch indefinitely).
final Dio _imageDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: const {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    },
  ),
);

/// Batch 185: headers for one spec fetch — the spec's own
/// headers win; a missing Referer defaults to the image
/// host's root, which is what same-host anti-leech checks
/// ask for (sources that need the chapter page itself as
/// Referer set it in their image headers, as before).
Map<String, String> _specHeaders(MangaImageLoadSpec spec) {
  final hasReferer =
      spec.headers.keys.any((k) => k.toLowerCase() == 'referer');
  if (hasReferer) return spec.headers;
  final uri = Uri.tryParse(spec.url);
  if (uri == null || uri.host.isEmpty) return spec.headers;
  return {
    'Referer': '${uri.scheme}://${uri.host}/',
    ...spec.headers,
  };
}

String _extensionOf(String url) {
  final path = Uri.tryParse(url)?.path ?? '';
  final dot = path.lastIndexOf('.');
  if (dot >= 0 && dot > path.lastIndexOf('/')) {
    final ext = path.substring(dot + 1).toLowerCase();
    if (const {'jpg', 'jpeg', 'png', 'webp', 'gif', 'avif'}
        .contains(ext)) {
      return ext;
    }
  }
  return 'jpg';
}

/// Batch 103: one page image's full load recipe — where to
/// fetch it, how to post-process the bytes (an `onResponse`
/// transform and/or a `modifyImage` edit, composed by
/// [mangaPageLoadSpec]), and what to try instead when the
/// fetch fails (the source's `onLoadFailed` replacement,
/// itself expressed as another spec).
class MangaImageLoadSpec {
  const MangaImageLoadSpec({
    required this.url,
    this.headers = const {},
    this.process,
    this.fallback,
    this.cacheKeySuffix,
  });

  final String url;
  final Map<String, String> headers;
  final MangaByteTransform? process;
  final Future<MangaImageLoadSpec?> Function()? fallback;

  /// Batch 185: distinguishes processed variants of the
  /// same URL in the page cache. Processed bytes used to
  /// be stored under the bare URL, so a source update that
  /// changed its transform kept serving the old processing
  /// until the entry expired.
  final String? cacheKeySuffix;

  String get cacheKey =>
      cacheKeySuffix == null ? url : '$url#$cacheKeySuffix';
}

/// Batch 112: whether [bytes] carry a real image format's
/// magic number (JPEG / PNG / GIF / WebP / AVIF / BMP).
/// Some sources answer image URLs with HTML challenge
/// pages or error text under a 200 status; treating those
/// bytes as an image both breaks the page on screen and —
/// worse — poisons the cache, so every retry serves the
/// same garbage. The loader validates before caching.
bool looksLikeImageBytes(List<int> bytes) {
  if (bytes.length < 12) return false;
  bool at(List<int> sig, [int offset = 0]) {
    for (var i = 0; i < sig.length; i++) {
      if (bytes[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(const [0xFF, 0xD8, 0xFF])) return true; // JPEG
  if (at(const [0x89, 0x50, 0x4E, 0x47])) return true; // PNG
  if (at(const [0x47, 0x49, 0x46])) return true; // GIF
  if (at(const [0x42, 0x4D])) return true; // BMP
  // WebP: RIFF....WEBP
  if (at(const [0x52, 0x49, 0x46, 0x46]) &&
      at(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return true;
  }
  // AVIF: ....ftyp + avif/avis brand
  if (at(const [0x66, 0x74, 0x79, 0x70], 4) &&
      (at(const [0x61, 0x76, 0x69, 0x66], 8) ||
          at(const [0x61, 0x76, 0x69, 0x73], 8))) {
    return true;
  }
  return false;
}

/// Loads the DISPLAYABLE bytes for a spec: the cache
/// manager's store first (it holds the already processed
/// bytes under the image url), otherwise a gated download +
/// processing, cached for next time. A failed PROCESS
/// returns the raw bytes WITHOUT caching them, so the next
/// view retries instead of pinning a broken result for the
/// store's stale period. A failed DOWNLOAD asks the spec's
/// fallback for a replacement (at most twice down the
/// chain) before giving up.
Future<Uint8List> loadProcessedImageBytes({
  required CacheManager? cacheManager,
  required MangaImageLoadSpec spec,
  int depth = 0,
}) async {
  // Batch 104: [cacheManager] is nullable — chapter
  // downloads pass null because they persist the processed
  // bytes into their own download folder; double-storing
  // them in the page cache too would just waste space.
  final store = cacheManager;
  try {
    if (store != null) {
      final cached = await store.getFileFromCache(spec.cacheKey);
      if (cached != null) {
        final cachedBytes = await cached.file.readAsBytes();
        if (looksLikeImageBytes(cachedBytes)) {
          return cachedBytes;
        }
        // Batch 112: a poisoned entry (non-image bytes
        // cached by an earlier version or a bad fetch) —
        // evict it and fall through to a real download
        // instead of serving the same broken page forever.
        await store.removeFile(spec.cacheKey);
      }
    }
    final raw = await mangaImageGate.run(() async {
      final response = await _imageDio.get<List<int>>(
        spec.url,
        options: Options(
          headers: _specHeaders(spec),
          responseType: ResponseType.bytes,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      return response.data ?? const <int>[];
    });
    final process = spec.process;
    if (process == null) {
      final bytes = Uint8List.fromList(raw);
      // Batch 112: never cache non-image bytes. With a
      // fallback available, garbage counts as a failed
      // load so the rescue runs; without one, return the
      // bytes uncached — the display fails visibly and a
      // retry really refetches.
      if (!looksLikeImageBytes(bytes)) {
        if (spec.fallback != null) {
          throw const FormatException('image bytes invalid');
        }
        return bytes;
      }
      if (store != null) {
        await store.putFile(
          spec.cacheKey,
          bytes,
          fileExtension: _extensionOf(spec.url),
        );
      }
      return bytes;
    }
    final processed = await process(raw);
    if (processed == null) {
      // Batch 185: "no transform applied" still has to
      // prove the raw bytes are an image — this branch
      // used to return them unchecked, bypassing the
      // batch-112 validation every other path enforces.
      // (Still uncached, per the batch-103 contract: a
      // declined transform is retried next view, never
      // pinned.)
      final rawBytes = Uint8List.fromList(raw);
      if (!looksLikeImageBytes(rawBytes) && spec.fallback != null) {
        throw const FormatException('image bytes invalid');
      }
      return rawBytes;
    }
    final bytes = Uint8List.fromList(processed);
    // Batch 112: a transform that yields non-image bytes
    // failed, whatever it returned — run the fallback
    // chain (or surface the error) instead of caching
    // and displaying garbage.
    if (!looksLikeImageBytes(bytes)) {
      throw const FormatException('processed image bytes invalid');
    }
    if (store != null) {
      await store.putFile(
        spec.cacheKey,
        bytes,
        fileExtension: _extensionOf(spec.url),
      );
    }
    return bytes;
  } catch (e) {
    final fallback = spec.fallback;
    if (fallback != null && depth < 2) {
      final next = await fallback();
      if (next != null && next.url.isNotEmpty) {
        return loadProcessedImageBytes(
          cacheManager: cacheManager,
          spec: next,
          depth: depth + 1,
        );
      }
    }
    rethrow;
  }
}

/// Loads a transformed image's displayable bytes (batch
/// 102's entry point, kept for covers; now a thin wrapper
/// over [loadProcessedImageBytes]).
Future<Uint8List> loadTransformedImageBytes({
  required CacheManager cacheManager,
  required String url,
  required Map<String, String> headers,
  required MangaByteTransform transform,
}) {
  return loadProcessedImageBytes(
    cacheManager: cacheManager,
    spec: MangaImageLoadSpec(
      url: url,
      headers: headers,
      process: transform,
      cacheKeySuffix: 'cover',
    ),
  );
}

/// Fire-and-forget warm-up for [loadTransformedImageBytes]
/// (reader prefetch of transformed pages).
void prefetchTransformedImage({
  required CacheManager cacheManager,
  required String url,
  required Map<String, String> headers,
  required MangaByteTransform transform,
}) {
  unawaited(
    loadTransformedImageBytes(
      cacheManager: cacheManager,
      url: url,
      headers: headers,
      transform: transform,
    ).catchError((_) => Uint8List(0)),
  );
}

/// Fire-and-forget warm-up for a page load spec (reader
/// prefetch; the fallback chain warms too if the primary
/// url is dead).
void prefetchProcessedImage({
  required CacheManager cacheManager,
  required MangaImageLoadSpec spec,
}) {
  unawaited(
    loadProcessedImageBytes(cacheManager: cacheManager, spec: spec)
        .catchError((_) => Uint8List(0)),
  );
}

bool _stringMapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// The load spec for one chapter page, or null when the
/// page needs no special handling (the ordinary
/// CachedNetworkImage path) or its source is not a JS
/// source. Composes the page's markers: `onResponse` bytes
/// first, then the `modifyImage` edit (the reference
/// pipeline's order), plus the `onLoadFailed` fallback.
MangaImageLoadSpec? mangaPageLoadSpec({
  required MangaItem manga,
  required MangaChapter chapter,
  required MangaPage page,
}) {
  if (page.transformOf == null &&
      page.modifyCode == null &&
      page.fallbackOf == null) {
    return null;
  }
  final source = MangaSources.byId(manga.source);
  if (source is! JsBackedMangaSource) return null;
  var process = pageTransformCallback(
    manga: manga,
    chapter: chapter,
    page: page,
  );
  final modifyCode = page.modifyCode;
  if (modifyCode != null) {
    final inner = process;
    process = (raw) async {
      var bytes = raw;
      if (inner != null) {
        bytes = await inner(bytes) ?? bytes;
      }
      return source.modifyImageBytes(code: modifyCode, raw: bytes);
    };
  }
  final fallbackOf = page.fallbackOf;
  return MangaImageLoadSpec(
    url: page.url,
    headers: page.headers,
    process: process,
    cacheKeySuffix: (page.transformOf == null && page.modifyCode == null)
        ? null
        : 'p${Object.hash(page.transformOf, page.modifyCode)}',
    fallback: fallbackOf == null
        ? null
        : () async {
            final config = await source.loadFailedConfig(
              originalUrl: fallbackOf,
              id: manga.id,
              ep: chapter.id,
            );
            if (config == null) return null;
            final nextPage = applyImageConfigToPage(page, config);
            // A replacement that changes nothing (same url,
            // headers and markers) would just fail again —
            // stop the chain here.
            if (nextPage.url == page.url &&
                nextPage.transformOf == page.transformOf &&
                nextPage.modifyCode == page.modifyCode &&
                _stringMapEquals(nextPage.headers, page.headers)) {
              return null;
            }
            return mangaPageLoadSpec(
              manga: manga,
              chapter: chapter,
              page: nextPage,
            );
          },
  );
}

/// The transform callback for one chapter page, or null when
/// the page needs none (the ordinary path) or its source is
/// not a JS source.
MangaByteTransform? pageTransformCallback({
  required MangaItem manga,
  required MangaChapter chapter,
  required MangaPage page,
}) {
  final original = page.transformOf;
  if (original == null) return null;
  final source = MangaSources.byId(manga.source);
  if (source is! JsBackedMangaSource) return null;
  return (raw) => source.transformImageBytes(
        mode: 'image',
        originalUrl: original,
        id: manga.id,
        ep: chapter.id,
        raw: raw,
      );
}

/// The transform callback for an item's cover, or null under
/// the same conditions as [pageTransformCallback].
MangaByteTransform? coverTransformCallback(MangaItem item) {
  final original = item.coverTransformOf;
  if (original == null) return null;
  final source = MangaSources.byId(item.source);
  if (source is! JsBackedMangaSource) return null;
  return (raw) => source.transformImageBytes(
        mode: 'thumb',
        originalUrl: original,
        raw: raw,
      );
}
