import 'dart:async';

import 'package:anikumo/webview/video/video_webview_controller.dart';
import 'package:anikumo/services/video_source/resolved_source_cache.dart';
import 'package:anikumo/services/video_source/video_source_service.dart';

/// WebView 视频源解析服务
///
/// 使用 WebView 解析视频页面，提取视频源 URL。
/// WebView 实例在服务生命周期内复用，切换集数时调用 unloadPage 释放页面资源，
/// 仅在 [dispose] 时才真正销毁 WebView。
class WebViewVideoSourceService implements IVideoSourceService {
  WebViewVideoSourceService({ResolvedSourceCache? cache})
      : _cache = cache ?? ResolvedSourceCache.instance;

  /// Resolved stream URLs shared across service instances, so re-entering
  /// an episode (or opening one that was prefetched) skips the WebView
  /// round entirely while the entry is fresh.
  final ResolvedSourceCache _cache;

  VideoWebviewController? _webview;
  StreamSubscription? _logSubscription;

  // 单个服务实例持有一个 WebView，因此解析任务按实例串行执行。
  // 下载并行通过多个服务实例实现。
  Future<void>? _resolveTail = Future<void>.value();
  _ResolveRequest? _activeRequest;

  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  Stream<String> get onLog => _logController.stream;

  @override
  Future<VideoSource> resolve(
    String episodeUrl, {
    required bool useLegacyParser,
    int offset = 0,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // Fast path: a fresh cached stream URL costs no WebView load at all.
    // The cached entry carries no offset (it echoes the original request),
    // so the result is rebuilt with this call's [offset].
    final hit = _cache.lookup(episodeUrl, useLegacyParser);
    if (hit != null) {
      if (!_logController.isClosed) {
        _logController.add('Resolved video URL from cache: ${hit.url}');
      }
      return VideoSource(
        url: hit.url,
        offset: offset,
        type: VideoSourceType.online,
        format: hit.format,
      );
    }

    final resolveTail = _resolveTail;
    if (resolveTail == null) {
      throw const VideoSourceCancelledException();
    }

    _activeRequest?.cancel();
    final request = _ResolveRequest();
    _activeRequest = request;

    final resolveFuture = resolveTail.then(
      (_) => _runResolve(
        request,
        episodeUrl,
        useLegacyParser: useLegacyParser,
        offset: offset,
        timeout: timeout,
      ),
    );

    _resolveTail = resolveFuture.then<void>((_) {}, onError: (_) {});
    return resolveFuture;
  }

  Future<VideoSource> _runResolve(
    _ResolveRequest request,
    String episodeUrl, {
    required bool useLegacyParser,
    required int offset,
    required Duration timeout,
  }) async {
    request.throwIfNotCurrent(_activeRequest);

    if (_webview == null) {
      _webview = VideoWebviewControllerFactory.getController();
      await _webview!.init();

      _logSubscription = _webview!.onLog.listen((log) {
        if (!_logController.isClosed) {
          _logController.add(log);
        }
      });
    }

    var didStartLoad = false;
    try {
      request.throwIfNotCurrent(_activeRequest);
      didStartLoad = true;
      await _webview!.loadUrl(
        episodeUrl,
        useLegacyParser,
        offset: offset,
      );

      request.throwIfNotCurrent(_activeRequest);

      final parserFuture = _webview!.onVideoURLParser.first.timeout(
        timeout,
        onTimeout: () {
          request.throwIfNotCurrent(_activeRequest);
          throw VideoSourceTimeoutException(timeout);
        },
      );
      final cancelFuture = request.cancelled.then<VideoParserEvent>((_) {
        throw const VideoSourceCancelledException();
      });
      final event = await Future.any([parserFuture, cancelFuture]);

      request.throwIfNotCurrent(_activeRequest);

      _cache.store(
        episodeUrl,
        useLegacyParser,
        ResolvedSourceEntry(url: event.url, format: event.format),
      );

      // Batch 143: the parser event echoes the webview
      // controller's mutable offset field, which a concurrent
      // load (prefetch, another resolve) can overwrite before
      // the event lands — silently dropping the resume point.
      // The request's offset is the caller's intent and is
      // authoritative, exactly as on the cache path above.
      return VideoSource(
        url: event.url,
        offset: offset,
        type: VideoSourceType.online,
        format: event.format,
      );
    } catch (e) {
      if (e is VideoSourceCancelledException) {
        rethrow;
      }
      request.throwIfNotCurrent(_activeRequest);
      rethrow;
    } finally {
      if (didStartLoad) {
        await _webview?.unloadPage();
      }
      if (identical(_activeRequest, request)) {
        _activeRequest = null;
      }
    }
  }

  /// Warms the shared resolved-source cache for [episodeUrl] so a later
  /// [resolve] of the same episode returns instantly.
  ///
  /// Resolving cancels this instance's in-flight request, so prefetching
  /// must run on a dedicated instance, never on the one playing video.
  /// Failures are swallowed: prefetching is speculative.
  Future<bool> prefetch(
    String episodeUrl, {
    required bool useLegacyParser,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_cache.lookup(episodeUrl, useLegacyParser) != null) return true;
    try {
      await resolve(
        episodeUrl,
        useLegacyParser: useLegacyParser,
        timeout: timeout,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void cancel() {
    _activeRequest?.cancel();
  }

  @override
  Future<void> dispose() async {
    final resolveTail = _resolveTail;
    _resolveTail = null;
    cancel();
    await resolveTail;
    _activeRequest = null;
    await _logSubscription?.cancel();
    _logSubscription = null;
    if (!_logController.isClosed) {
      await _logController.close();
    }
    await _webview?.dispose();
    _webview = null;
  }
}

class _ResolveRequest {
  final Completer<void> _cancelled = Completer<void>();

  Future<void> get cancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  void throwIfNotCurrent(_ResolveRequest? current) {
    if (_cancelled.isCompleted || !identical(current, this)) {
      throw const VideoSourceCancelledException();
    }
  }
}
