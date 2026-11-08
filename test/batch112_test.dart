// Batch 112: image-pipeline hardening — non-image bytes
// must never poison the page cache, a poisoned entry is
// evicted and refetched, garbage with a fallback runs the
// rescue, and a transform yielding garbage fails loudly.
// Plus the flattened search kit's switch still works.
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:anikumo/bean/widget/search_stage.dart';
import 'package:anikumo/services/manga/manga_image_pipeline.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
  @override
  Future<String?> getExternalStoragePath() async => root;
  @override
  Future<List<String>?> getExternalCachePaths() async => [root];
  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      [root];
  @override
  Future<String?> getDownloadsPath() async => root;
}

final pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);
final htmlBytes = '<html><body>verify you are human</body></html>'.codeUnits;

void main() {
  group('looksLikeImageBytes', () {
    test('accepts the real formats', () {
      expect(looksLikeImageBytes(pngBytes), isTrue);
      expect(
        looksLikeImageBytes(const [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]),
        isTrue,
      );
      expect(
        looksLikeImageBytes('GIF89a......'.codeUnits),
        isTrue,
      );
      expect(
        looksLikeImageBytes(
            'RIFF\x00\x00\x00\x00WEBP'.codeUnits),
        isTrue,
      );
    });

    test('rejects html, text and empty', () {
      expect(looksLikeImageBytes(htmlBytes), isFalse);
      expect(looksLikeImageBytes('GOOD-BYTES'.codeUnits), isFalse);
      expect(looksLikeImageBytes(const []), isFalse);
    });
  });

  group('loader validation (loopback)', () {
    late HttpServer server;
    late int port;
    late CacheManager cache;
    final hits = <String, int>{};

    setUpAll(() async {
      HttpOverrides.global = null;
      final dir = await Directory.systemTemp.createTemp('batch112_test');
      PathProviderPlatform.instance = _TestPaths(dir.path);
      cache = CacheManager(Config('batch112_loader_test'));
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((request) async {
        hits[request.uri.path] = (hits[request.uri.path] ?? 0) + 1;
        if (request.uri.path == '/html') {
          request.response.add(htmlBytes);
        } else {
          request.response.add(pngBytes);
        }
        await request.response.close();
      });
    });

    tearDownAll(() async {
      await cache.dispose();
      await server.close(force: true);
    });

    String url(String path) => 'http://127.0.0.1:$port$path';

    test('html with a fallback runs the rescue and caches it', () async {
      final spec = MangaImageLoadSpec(
        url: url('/html'),
        fallback: () async => MangaImageLoadSpec(url: url('/img')),
      );
      final bytes = await loadProcessedImageBytes(
        cacheManager: cache,
        spec: spec,
      );
      expect(bytes, pngBytes);
      expect(hits['/img'], 1);
    });

    test('html without a fallback is returned but never cached', () async {
      // A query string gives /html a fresh cache key.
      final htmlSpec = MangaImageLoadSpec(url: '${url('/html')}?q=1');
      final first = await loadProcessedImageBytes(
        cacheManager: cache,
        spec: htmlSpec,
      );
      expect(first, htmlBytes);
      final hitsAfterFirst = hits['/html'] ?? 0;
      final second = await loadProcessedImageBytes(
        cacheManager: cache,
        spec: htmlSpec,
      );
      expect(second, htmlBytes);
      expect(hits['/html'], hitsAfterFirst + 1,
          reason: 'uncached garbage must be refetched');
    });

    test('a poisoned cache entry is evicted and refetched', () async {
      final poisonedUrl = url('/img2');
      await cache.putFile(poisonedUrl, Uint8List.fromList(htmlBytes),
          fileExtension: 'jpg');
      final bytes = await loadProcessedImageBytes(
        cacheManager: cache,
        spec: MangaImageLoadSpec(url: poisonedUrl),
      );
      expect(bytes, pngBytes);
      expect(hits['/img2'], 1);
    });

    test('a transform yielding garbage fails instead of caching it',
        () async {
      final spec = MangaImageLoadSpec(
        url: url('/img3'),
        process: (raw) async => htmlBytes,
      );
      await expectLater(
        loadProcessedImageBytes(cacheManager: cache, spec: spec),
        throwsA(isA<FormatException>()),
      );
      expect(await cache.getFileFromCache(url('/img3')), isNull);
    });
  });

  testWidgets('the flattened PillSwitch still switches', (tester) async {
    var value = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => PillSwitch<bool>(
            options: const [
              PillSwitchOption(value: false, label: '当前源'),
              PillSwitchOption(value: true, label: '全部源'),
            ],
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('全部源'));
    await tester.pump();
    expect(value, isTrue);
  });
}
