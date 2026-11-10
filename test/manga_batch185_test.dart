// Batch 185: manga engine hardening from the full audit —
// page/chapter/comic mapper validation, the JS DOM shim's
// implied end tags + selector engine + lazy-src + cookie
// paths, the validating cache file service, and numeric
// ordering of downloaded pages.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/js/venera_scripts.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_image_pipeline.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const goodPngBytes = <int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0,
  0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120,
  218, 99, 100, 248, 207, 80, 15, 0, 3, 134, 1, 128, 90, 52, 125, 107, 0, 0, 0,
  0, 73, 69, 78, 68, 174, 66, 96, 130,
];

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

  group('mapper validation (batch 185)', () {
    test('mapJsPages drops junk, keeps order, dedupes', () {
      final pages = mapJsPages({
        'images': [
          'https://i/1.jpg',
          '',
          '   ',
          '/relative/2.jpg',
          'javascript:alert(1)',
          {'url': ''},
          {'url': 'https://i/2.jpg'},
          'https://i/1.jpg',
          ' https://i/3.jpg ',
          {'url': 'https://i/2.jpg', 'headers': {'X': 'y'}},
          'file:///local/4.jpg',
        ],
      });
      expect(pages.map((p) => p.url), [
        'https://i/1.jpg',
        'https://i/2.jpg',
        'https://i/3.jpg',
        'file:///local/4.jpg',
      ]);
    });

    test('mapJsChapters dedupes repeated episode ids, order kept', () {
      final chapters = mapJsChapters({
        'chapters': {
          '正文': {'1': '第1话', '2': '第2话'},
          '番外': {'2': '第2话（重）', '3': '第3话'},
        },
      });
      expect(chapters.map((c) => c.id), ['1', '2', '3']);
      expect(chapters[1].title, '第2话');
    });

    test('mapJsComicList drops entries whose id never materialized', () {
      final items = mapJsComicList([
        {'id': 'a', 'title': 'A', 'cover': 'ca'},
        {'title': 'NoId', 'cover': 'cb'},
        {'id': '  ', 'title': 'BlankId', 'cover': 'cc'},
        {'id': 'd', 'title': 'D', 'cover': 'cd'},
      ], sourceId: 'js:x');
      expect(items.map((e) => e.id), ['a', 'd']);
    });
  });

  group('downloaded page order (batch 185)', () {
    test('localPages sorts by page number, not lexicographically', () async {
      final dir = await Directory.systemTemp.createTemp('batch185_dl');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      PathProviderPlatform.instance = _TestPaths(dir.path);
      final base = Directory('${dir.path}/manga_downloads');
      final chapterDir = Directory('${base.path}/src/m1/c1');
      await chapterDir.create(recursive: true);
      for (final name in ['10000', '0002', '0010', '0001']) {
        await File('${chapterDir.path}/$name.img')
            .writeAsBytes(goodPngBytes);
      }
      await File('${base.path}/index.json').writeAsString(jsonEncode([
        {
          'source': 'src',
          'mangaId': 'm1',
          'mangaTitle': 'T',
          'coverUrl': '',
          'chapterId': 'c1',
          'chapterLabel': 'C1',
          'pageCount': 4,
          'downloadedAtMs': 0,
        },
      ]));
      final pages = await MangaDownloadStore.localPages('src', 'm1', 'c1');
      expect(pages, isNotNull);
      expect(pages!.map((p) => p.url.split('/').last), [
        '0001.img',
        '0002.img',
        '0010.img',
        '10000.img',
      ]);
    });
  });

  group('validating cache file service (batch 185)', () {
    late HttpServer server;
    late int port;

    setUpAll(() async {
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((request) async {
        switch (request.uri.path) {
          case '/ok.png':
            request.response.headers.contentType =
                ContentType('image', 'png');
            request.response.add(goodPngBytes);
          case '/bad.png':
            request.response.headers.contentType =
                ContentType('text', 'html');
            request.response.write('<html><body>challenge</body></html>');
          default:
            request.response.statusCode = 404;
            request.response.write('nope');
        }
        await request.response.close();
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    test('real image bytes pass through', () async {
      final resp =
          await MangaImageFileService().get('http://127.0.0.1:$port/ok.png');
      final bytes = await resp.content
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
      expect(bytes, goodPngBytes);
      expect(resp.statusCode, 200);
    });

    test('a 200 HTML page is rejected instead of cached as an image',
        () async {
      await expectLater(
        MangaImageFileService().get('http://127.0.0.1:$port/bad.png'),
        throwsA(isA<HttpExceptionWithStatus>()),
      );
    });

    test('HTTP error statuses pass through for the manager to raise',
        () async {
      final resp = await MangaImageFileService()
          .get('http://127.0.0.1:$port/missing.png');
      expect(resp.statusCode, 404);
    });
  });

  group('JS DOM shim (batch 185)', () {
    late JavascriptRuntime runtime;

    setUpAll(() {
      runtime = QuickJsRuntime2();
      runtime.evaluate(
        'globalThis.__dartSendMessage = function () {};',
      );
      runtime.evaluate(veneraBridgeScript);
      // Production spawn order is bridge, library, compat
      // (which polyfills URL), overrides. The desktop
      // QuickJS build used by this probe rejects the
      // compat script's syntax (a pre-existing harness
      // limitation — the same script parses on device),
      // so the harness supplies the small URL surface the
      // jar code actually consumes.
      runtime.evaluate(r'''
        globalThis.URL = class {
          constructor(u) {
            const m = /^(\w+):\/\/([^\/:?#]+)(?::(\d+))?([^?#]*)/.exec(u);
            if (!m) throw new Error('bad url');
            this.protocol = m[1] + ':';
            this.hostname = m[2];
            this.host = m[3] ? m[2] + ':' + m[3] : m[2];
            this.pathname = m[4] || '/';
          }
        };
      ''');
      runtime.evaluate(veneraOverridesScript);
    });

    String evalJson(String expr) {
      final result = runtime.evaluate('JSON.stringify($expr)');
      expect(result.isError, isFalse, reason: result.stringResult);
      return result.stringResult;
    }

    test('implied end tags: unclosed li/p/td nest no longer', () {
      expect(
        evalJson(
          "new HtmlDocument('<ul><li>一<li>二<li>三</ul>')"
          ".querySelectorAll('ul > li').map(e => e.text).join(',')",
        ),
        '"一,二,三"',
      );
      expect(
        evalJson(
          "new HtmlDocument('<p>甲<div>乙</div>')"
          ".querySelectorAll('p div').length",
        ),
        '0',
      );
      expect(
        evalJson(
          "new HtmlDocument('<table><tr><td>1<td>2<tr><td>3</table>')"
          ".querySelectorAll('td').length",
        ),
        '3',
      );
    });

    test('selector splitting respects commas/spaces inside brackets', () {
      const html = '<a data-x="a,b" title="hello world" class="lnk">x</a>';
      expect(
        evalJson(
          "new HtmlDocument('$html')"
          ".querySelectorAll('a[data-x=\"a,b\"]').length",
        ),
        '1',
      );
      expect(
        evalJson(
          "new HtmlDocument('$html')"
          ".querySelectorAll('a[title=\"hello world\"]').length",
        ),
        '1',
      );
    });

    test('sibling combinators and :not match browser semantics', () {
      const html =
          '<div><h1>t</h1><p class="x">1</p><p>2</p><span>3</span></div>';
      expect(
        evalJson(
          "new HtmlDocument('$html')"
          ".querySelectorAll('h1 + p').map(e => e.text).join(',')",
        ),
        '"1"',
      );
      expect(
        evalJson(
          "new HtmlDocument('$html')"
          ".querySelectorAll('h1 ~ p').length",
        ),
        '2',
      );
      expect(
        evalJson(
          "new HtmlDocument('$html')"
          ".querySelectorAll('p:not(.x)').map(e => e.text).join(',')",
        ),
        '"2"',
      );
    });

    test('nth-child with spaces in the expression works', () {
      expect(
        evalJson(
          "new HtmlDocument('<ul><li>1<li>2<li>3<li>4</ul>')"
          ".querySelectorAll('li:nth-child(2n + 1)').length",
        ),
        '2',
      );
    });

    test('attribute names are case-insensitive; lazy src resolves', () {
      expect(
        evalJson(
          "new HtmlDocument('<div DATA-ID=\"7\"></div>')"
          ".querySelectorAll('[data-id=\"7\"]').length",
        ),
        '1',
      );
      expect(
        evalJson(
          "new HtmlDocument('<img data-src=\"https://i/real.jpg\">')"
          ".querySelector('img').getAttribute('src')",
        ),
        '"https://i/real.jpg"',
      );
      expect(
        evalJson(
          "new HtmlDocument('<img src=\"a.jpg\" data-src=\"b.jpg\">')"
          ".querySelector('img').getAttribute('src')",
        ),
        '"a.jpg"',
      );
    });

    test('cookie jar scopes cookies by path, legacy entries still read',
        () {
      runtime.evaluate(
        "__anikumoCookieApply('h.example', "
        "['sess=1; Path=/api', 'wide=2; Path=/']);",
      );
      expect(
        evalJson(
          "__anikumoCookiesFor('http://h.example/api/x')"
          ".map(c => c.name).join(',')",
        ),
        '"sess,wide"',
      );
      expect(
        evalJson(
          "__anikumoCookiesFor('http://h.example/static/y')"
          ".map(c => c.name).join(',')",
        ),
        '"wide"',
      );
      runtime.evaluate(
        "globalThis.__anikumoJar['old.example'] = {legacy: 'v9'};",
      );
      expect(
        evalJson(
          "__anikumoCookiesFor('http://old.example/any')"
          ".map(c => c.name + '=' + c.value).join(',')",
        ),
        '"legacy=v9"',
      );
    });
  });
}
