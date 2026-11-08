// Batch 103: hook-config markers for modifyImage /
// onLoadFailed, the spec loader's fallback chain and
// process-failure rule, and the tightened shared image
// cache configuration.
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/manga_image_pipeline.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/network/proxy_aware_image_cache_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Batch 112: the spec loader validates image magic bytes
/// before caching, so the fixture serves a real 1x1 PNG.
final goodPngBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 218, 99, 100, 248, 207, 80, 15, 0, 3, 134, 1, 128, 90, 52, 125, 107, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hook config markers', () {
    const page = MangaPage('http://x.test/p1', headers: {'A': '1'});

    test('initial pass flags fallback and modify', () {
      final out = applyImageConfigs([
        page,
      ], [
        {'fallback': true, 'modify': 'let modifyImage = (i) => i;'},
      ]);
      expect(out[0].fallbackOf, 'http://x.test/p1');
      expect(out[0].modifyCode, contains('modifyImage'));
      expect(out[0].url, 'http://x.test/p1');
    });

    test('initial pass keys the transform by the original url', () {
      final out = applyImageConfigs([
        page,
      ], [
        {'transform': true, 'url': 'http://cdn.test/signed'},
      ]);
      expect(out[0].url, 'http://cdn.test/signed');
      expect(out[0].transformOf, 'http://x.test/p1');
    });

    test('fallback pass keys markers by the replacement url', () {
      const original = MangaPage(
        'http://x.test/dead',
        fallbackOf: 'http://x.test/dead',
      );
      final out = applyImageConfigToPage(original, {
        'url': 'http://mirror.test/p1',
        'transform': true,
      });
      expect(out.url, 'http://mirror.test/p1');
      expect(out.transformOf, 'http://mirror.test/p1');
      // The original fallback registration is kept when the
      // replacement carries none of its own.
      expect(out.fallbackOf, 'http://x.test/dead');
    });

    test('plain pages pass through untouched', () {
      final out = applyImageConfigs([page], [null]);
      expect(out[0].modifyCode, isNull);
      expect(out[0].fallbackOf, isNull);
      expect(out[0].transformOf, isNull);
    });
  });

  group('spec loader', () {
    late HttpServer server;
    late int port;
    late CacheManager cache;
    final hits = <String, int>{};

    setUpAll(() async {
      HttpOverrides.global = null;
      final dir = await Directory.systemTemp.createTemp('batch103_test');
      PathProviderPlatform.instance = _TestPaths(dir.path);
      cache = CacheManager(Config('batch103_loader_test'));
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((request) async {
        hits[request.uri.path] = (hits[request.uri.path] ?? 0) + 1;
        if (request.uri.path == '/good') {
          request.response.add(goodPngBytes);
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
    });

    tearDownAll(() async {
      await cache.dispose();
      await server.close(force: true);
    });

    String url(String path) => 'http://127.0.0.1:$port$path';

    test('a failed download falls back and caches the rescue', () async {
      MangaImageLoadSpec good() =>
          MangaImageLoadSpec(url: url('/good'));
      final spec = MangaImageLoadSpec(
        url: url('/bad'),
        fallback: () async => good(),
      );
      final bytes = await loadProcessedImageBytes(
        cacheManager: cache,
        spec: spec,
      );
      expect(bytes, goodPngBytes);
      expect(hits['/good'], 1);
      // Second load: the rescue is served from cache (the
      // primary is retried and 404s again, the fallback's
      // cache entry answers).
      final again = await loadProcessedImageBytes(
        cacheManager: cache,
        spec: spec,
      );
      expect(again, goodPngBytes);
      expect(hits['/good'], 1);
    });

    test('a null process result returns raw bytes uncached', () async {
      final before = hits['/raw'] ?? 0;
      final spec = MangaImageLoadSpec(
        url: url('/good'),
        process: (raw) async => null,
      );
      // Use a distinct url per run via the query string so
      // the /good cache from the previous test cannot answer.
      final specA = MangaImageLoadSpec(
        url: '${url('/good')}?a=1',
        process: (raw) async => null,
      );
      final specB = MangaImageLoadSpec(
        url: '${url('/good')}?a=1',
        process: (raw) async => null,
      );
      expect(spec.url, isNot(specA.url));
      final first = await loadProcessedImageBytes(
        cacheManager: cache,
        spec: specA,
      );
      expect(first, goodPngBytes);
      final hitsAfterFirst = hits['/good'] ?? 0;
      final second = await loadProcessedImageBytes(
        cacheManager: cache,
        spec: specB,
      );
      expect(second, goodPngBytes);
      // Uncached: the second load downloaded again.
      expect(hits['/good'], hitsAfterFirst + 1);
      expect(before, 0);
    });

    test('the fallback chain stops at depth two', () async {
      var fallbackCalls = 0;
      MangaImageLoadSpec chain() => MangaImageLoadSpec(
            url: url('/bad'),
            fallback: () async {
              fallbackCalls++;
              return chain();
            },
          );
      await expectLater(
        loadProcessedImageBytes(cacheManager: cache, spec: chain()),
        throwsA(anything),
      );
      expect(fallbackCalls, 2);
    });
  });

  group('shared image cache tightening', () {
    test('proxy-aware cache is capped at 800 objects / 14 days', () {
      final config = ProxyAwareImageCacheManager.instance.config;
      expect(config.maxNrOfCacheObjects, 800);
      expect(config.stalePeriod, const Duration(days: 14));
    });
  });
}
