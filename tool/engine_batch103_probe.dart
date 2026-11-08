// Batch 103 local verification (no external site): engine
// adaptation additions on the real engine —
// 1. Convert.sha512 matches the published 'abc' vector.
// 2. Structural selector pseudo-classes (:nth-child,
//    :first/:last-child, :nth-of-type) and the |= attribute
//    operator return the right nodes (previously the pseudo
//    was silently dropped and every sibling matched).
// 3. modifyImage: pages() flags the code string; running it
//    over a real 2x1 PNG rotates it to 1x2 through the
//    host's synchronous Image bridge (width getter +
//    copyAndRotate90 exercised).
// 4. onLoadFailed: pages() flags the fallback; the engine
//    returns the replacement config; applying it retargets
//    the page.
// 5. loadThumbnails returns the source's preview urls; a
//    hookless source returns an empty list.
//
// Run: LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/engine_batch103_probe.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:image/image.dart' as img;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late int port;
  late List<int> modPng;

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
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('batch103_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    // A real 2x1 PNG: left pixel red, right pixel blue.
    final image = img.Image(width: 2, height: 1);
    img.fill(image, color: img.ColorRgb8(255, 0, 0));
    image.setPixel(1, 0, img.ColorRgb8(0, 0, 255));
    modPng = img.encodePng(image);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      final bytes = switch (request.uri.path) {
        '/mod' => modPng,
        '/good' => utf8.encode('GOOD-PAGE'),
        _ => const <int>[],
      };
      request.response.add(bytes);
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  String adaptCode() => '''
class AdaptProbe extends ComicSource {
  name = "AdaptProbe";
  key = "adapt_probe";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";

  search = {
    load: async (keyword, page) => {
      const hash = Convert.hexEncode(Convert.sha512("abc"));
      const doc = new HtmlDocument(
        '<ul><li>one</li><li>two</li><li>three</li></ul>' +
        '<div><p data-x="hello">A</p><p>B</p></div>');
      const parts = [
        doc.querySelector('li:nth-child(2)').text,
        doc.querySelector('li:first-child').text,
        doc.querySelector('li:last-child').text,
        doc.querySelector('p:nth-of-type(2)').text,
        doc.querySelector('[data-x*="ell"]').text,
        doc.querySelector('[data-x|="hello"]').text,
        doc.querySelectorAll('li:nth-child(odd)').length.toString(),
      ];
      return { comics: [{ id: hash, title: parts.join("|"), cover: "", tags: [] }] };
    }
  };

  comic = {
    loadEp: async (id, ep) => {
      return { images: [
        "http://127.0.0.1:$port/mod",
        "http://127.0.0.1:$port/dead"
      ]};
    },
    onImageLoad: async (url, id, ep) => {
      if (url.endsWith("/mod")) {
        return { modifyImage: "let modifyImage = (image) => { " +
          "if (image.width !== 2) { throw new Error('bad width'); } " +
          "return image.copyAndRotate90(); }" };
      }
      if (url.endsWith("/dead")) {
        return { onLoadFailed: async () => {
          return { url: "http://127.0.0.1:$port/good" };
        }};
      }
      return null;
    },
    loadThumbnails: async (id) => {
      return ["http://127.0.0.1:$port/t1", "http://127.0.0.1:$port/t2"];
    }
  };
}
''';

  String plainCode() => '''
class PlainProbe103 extends ComicSource {
  name = "PlainProbe103";
  key = "plain_probe103";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";
  comic = {
    loadEp: async (id, ep) => {
      return { images: ["http://127.0.0.1:$port/mod"] };
    }
  };
}
''';

  MangaItem item(String source) => MangaItem(
        id: 'm1',
        title: 'adaptbook',
        description: '',
        coverUrl: '',
        author: '',
        status: '',
        year: null,
        tags: [],
        source: source,
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

  test('batch 103 engine adaptation', () async {
    final source = JsMangaSource(
      jsKey: 'adapt_probe',
      displayName: 'AdaptProbe',
      version: '1.0.0',
      fileName: 'adapt_probe.js',
      code: adaptCode(),
    );

    // 1+2: sha512 vector and selector results ride back in
    // the search result.
    final results = await source.search('x');
    expect(results.length, 1);
    expect(
      results[0].id,
      'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
      '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
    );
    expect(results[0].title, 'two|one|three|B|A|A|2');

    // 3+4: page markers from the image hook.
    final pages = await source.pages(item('js:adapt_probe'), chapter);
    expect(pages.length, 2);
    expect(pages[0].modifyCode, contains('copyAndRotate90'));
    expect(pages[0].fallbackOf, isNull);
    expect(pages[1].fallbackOf, 'http://127.0.0.1:$port/dead');
    expect(pages[1].modifyCode, isNull);

    // 3: the modify snippet really edits the image.
    final rawMod = await getBytes('http://127.0.0.1:$port/mod');
    expect(rawMod, modPng);
    final modified = await source.modifyImageBytes(
      code: pages[0].modifyCode!,
      raw: rawMod,
    );
    expect(modified, isNotNull);
    final decoded = img.decodeImage(Uint8List.fromList(modified!));
    expect(decoded, isNotNull);
    expect(decoded!.width, 1);
    expect(decoded.height, 2);

    // 4: the fallback hook retargets the dead page.
    final fallbackConfig = await source.loadFailedConfig(
      originalUrl: pages[1].fallbackOf!,
      id: 'm1',
      ep: 'e1',
    );
    expect(fallbackConfig, isNotNull);
    expect(fallbackConfig!['url'], 'http://127.0.0.1:$port/good');
    final retargeted = applyImageConfigToPage(pages[1], fallbackConfig);
    expect(retargeted.url, 'http://127.0.0.1:$port/good');

    // 5: thumbnails, and the hookless source's empty list.
    final thumbs = await source.loadThumbnails(item('js:adapt_probe'));
    expect(thumbs, [
      'http://127.0.0.1:$port/t1',
      'http://127.0.0.1:$port/t2',
    ]);
    final plain = JsMangaSource(
      jsKey: 'plain_probe103',
      displayName: 'PlainProbe103',
      version: '1.0.0',
      fileName: 'plain_probe103.js',
      code: plainCode(),
    );
    expect(await plain.loadThumbnails(item('js:plain_probe103')), isEmpty);
    final plainPages = await plain.pages(item('js:plain_probe103'), chapter);
    expect(plainPages[0].modifyCode, isNull);
    expect(plainPages[0].fallbackOf, isNull);
  }, timeout: const Timeout(Duration(seconds: 120)));
}
