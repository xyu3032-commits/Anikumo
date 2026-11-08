// Batch 102 local verification (no external site):
// onResponse byte transforms, end to end on the real engine.
// A synthetic source "encrypts" its images two ways:
//   pages  — bytes reversed; onImageLoad returns a signed
//            url plus an onResponse that reverses them back.
//   covers — bytes XORed with 0x5A; onThumbnailLoad returns
//            only an onResponse (the {data} return shape).
// Checks:
// 1. pages() carries transformOf = the original url while
//    the display url is the signed one.
// 2. transformImageBytes('image') restores the plaintext.
// 3. details() marks the cover; transformImageBytes('thumb')
//    restores the cover plaintext.
// 4. A registry-cold transform (url never passed through
//    imageConfigs) re-runs the hook lazily and still works.
// 5. A hookless source yields null (raw-bytes fallback).
//
// Run: LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/engine_batch102_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

List<int> reversed(List<int> bytes) => bytes.reversed.toList();
List<int> xored(List<int> bytes) => [for (final b in bytes) b ^ 0x5A];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pagePlain = utf8.encode('PAGE-ONE-PLAINTEXT-0123456789');
  final page9Plain = utf8.encode('PAGE-NINE-PLAINTEXT-9876543210');
  final coverPlain = utf8.encode('COVER-PLAINTEXT-0123456789');

  late HttpServer server;
  late int port;

  Future<List<int>> getBytes(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes =
          await response.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  setUpAll(() async {
    // The test binding mocks HttpClient; the probe's own
    // fetches must hit the real loopback server. (Engine-side
    // HTTP was never mocked: it runs in the QJS isolate.)
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('batch102_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      final bytes = switch (request.uri.path) {
        '/p1' => reversed(pagePlain),
        '/p9' => reversed(page9Plain),
        '/cover' => xored(coverPlain),
        _ => const <int>[],
      };
      request.response.add(bytes);
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  String txCode() => '''
class TxProbe extends ComicSource {
  name = "TxProbe";
  key = "tx_probe";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";

  search = {
    load: async (keyword, page) => {
      return { comics: [{ id: "m1", title: "txbook", cover: "http://127.0.0.1:$port/cover", tags: [] }] };
    }
  };

  comic = {
    loadInfo: async (id) => {
      return {
        title: "txbook",
        cover: "http://127.0.0.1:$port/cover",
        description: "",
        tags: [],
        chapters: { "e1": "第一话" }
      };
    },
    loadEp: async (id, ep) => {
      return { images: ["http://127.0.0.1:$port/p1", "http://127.0.0.1:$port/p2"] };
    },
    onImageLoad: async (url, id, ep) => {
      return {
        url: url + "?signed=1",
        onResponse: (res) => {
          const d = res.data;
          const out = new Uint8Array(d.length);
          for (let i = 0; i < d.length; i++) out[i] = d[d.length - 1 - i];
          res.data = out;
          return res;
        }
      };
    },
    onThumbnailLoad: async (url) => {
      return {
        onResponse: (res) => {
          const d = res.data;
          const out = new Uint8Array(d.length);
          for (let i = 0; i < d.length; i++) out[i] = d[i] ^ 0x5A;
          return { data: out };
        }
      };
    }
  };
}
''';

  String plainCode() => '''
class PlainProbe extends ComicSource {
  name = "PlainProbe";
  key = "plain_probe";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";
  comic = {
    loadEp: async (id, ep) => {
      return { images: ["http://127.0.0.1:$port/p1"] };
    }
  };
}
''';

  MangaItem item() => const MangaItem(
        id: 'm1',
        title: 'txbook',
        description: '',
        coverUrl: '',
        author: '',
        status: '',
        year: null,
        tags: [],
        source: 'js:tx_probe',
      );

  const chapter = MangaChapter(
    id: 'e1',
    volume: null,
    chapter: '1',
    title: '第一话',
    language: '',
    pages: 2,
    publishedAt: null,
  );

  test('onResponse transforms run end to end', () async {
    final source = JsMangaSource(
      jsKey: 'tx_probe',
      displayName: 'TxProbe',
      version: '1.0.0',
      fileName: 'tx_probe.js',
      code: txCode(),
    );

    // 1+2: pages carry the transform marker; the transform
    // restores the plaintext from the served (reversed) bytes.
    final pages = await source.pages(item(), chapter);
    expect(pages.length, 2);
    expect(pages[0].url, 'http://127.0.0.1:$port/p1?signed=1');
    expect(pages[0].transformOf, 'http://127.0.0.1:$port/p1');
    final rawPage = await getBytes(pages[0].url);
    expect(rawPage, reversed(pagePlain));
    final fixedPage = await source.transformImageBytes(
      mode: 'image',
      originalUrl: pages[0].transformOf!,
      id: 'm1',
      ep: 'e1',
      raw: rawPage,
    );
    expect(fixedPage, pagePlain);

    // 3: cover via details(); the {data} return shape and the
    // transform-only config (no url change) both work.
    final detailed = await source.details(item());
    expect(detailed, isNotNull);
    expect(detailed!.coverUrl, 'http://127.0.0.1:$port/cover');
    expect(detailed.coverTransformOf, 'http://127.0.0.1:$port/cover');
    final rawCover = await getBytes(detailed.coverUrl);
    expect(rawCover, xored(coverPlain));
    final fixedCover = await source.transformImageBytes(
      mode: 'thumb',
      originalUrl: detailed.coverTransformOf!,
      raw: rawCover,
    );
    expect(fixedCover, coverPlain);

    // 4: registry-cold url (never configured) — the hook is
    // re-run lazily and the transform still applies.
    final raw9 = await getBytes('http://127.0.0.1:$port/p9');
    final fixed9 = await source.transformImageBytes(
      mode: 'image',
      originalUrl: 'http://127.0.0.1:$port/p9',
      id: 'm1',
      ep: 'e1',
      raw: raw9,
    );
    expect(fixed9, page9Plain);

    // 5: a hookless source reports no transform.
    final plain = JsMangaSource(
      jsKey: 'plain_probe',
      displayName: 'PlainProbe',
      version: '1.0.0',
      fileName: 'plain_probe.js',
      code: plainCode(),
    );
    final none = await plain.transformImageBytes(
      mode: 'image',
      originalUrl: 'http://127.0.0.1:$port/p1',
      raw: const [1, 2, 3],
    );
    expect(none, isNull);
  }, timeout: const Timeout(Duration(seconds: 120)));
}
