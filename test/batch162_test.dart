// Batch 162: the three device-diagnosis root causes —
// 1. a rule's trailing `##regex##replacement` pairs are
//    rule syntax, not JS: feeding them into an @js: script
//    killed chapter lists with "invalid first character
//    of private name" (QQ阅读标签),
// 2. `source.loginUrl` is bound so scripts can eval() it
//    for shared globals （霹雳书屋's 'sz' is not defined),
// 3. java.webView / java.toNumChapter exist （起点男频's
//    "not a function", and the chapter-name cleaner).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_engine.dart';
import 'package:anikumo/services/novel/legado_js.dart';
import 'package:anikumo/services/storage/storage.dart';

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
  HttpOverrides.global = null;

  late HttpServer server;
  late String base;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b162_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      req.response.headers.contentType =
          ContentType.html;
      req.response.write(
        '<html><body><ul>'
        '<li><a href="/c/1">第3章••试炼</a></li>'
        '<li><a href="/c/2">第十章••风暴</a></li>'
        '</ul></body></html>',
      );
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  group('trailing ## pairs after @js: (batch 162)', () {
    test('chapterName JS + ## pair both apply, no private-name error',
        () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '测试源',
        'bookSourceUrl': base,
        'ruleToc': {
          'chapterList': 'li',
          'chapterName':
              'a@text@js:result.replace("••","")\n##(章)(.+)##\$1 \$2',
          'chapterUrl': 'a@href',
        },
      })!;
      final chapters = await LegadoEngine(def).chapters(
        NovelItem(bookUrl: '$base/toc', title: '测试之书'),
      );
      expect(
        chapters.map((c) => c.title).toList(),
        ['第3章 试炼', '第十章 风暴'],
      );
      expect(
        chapters.map((c) => c.url).toList(),
        ['$base/c/1', '$base/c/2'],
      );
    });
  });

  group('source.loginUrl binding (batch 162)', () {
    test('eval of loginUrl defines shared globals', () async {
      final host = LegadoJsHost.forSource(
        'b162-login',
        null,
        loginUrl: 'var sz = "mirror-a"; var url = "https://example.com";',
      );
      final out = await host.run(
        code: 'eval(String(source.loginUrl)); (sz + "|" + url)',
        baseUrl: 'http://x/',
      );
      expect(out, 'mirror-a|https://example.com');
    });

    test('an @js: marker on loginUrl is stripped for eval', () async {
      final host = LegadoJsHost.forSource(
        'b162-login2',
        null,
        loginUrl: '@js:var sz2 = 7;',
      );
      final out = await host.run(
        code: 'eval(String(source.loginUrl)); (sz2)',
        baseUrl: 'http://x/',
      );
      expect(out, 7);
    });
  });

  group('java surface additions (batch 162)', () {
    late LegadoJsHost host;
    setUpAll(() {
      host = LegadoJsHost.forSource('b162-java', null);
    });

    test('java.webView exists and answers document.cookie reads',
        () async {
      expect(
        await host.run(code: '(typeof java.webView)', baseUrl: 'http://x/'),
        'function',
      );
      // Empty jar: an empty string, not a crash.
      expect(
        await host.run(
          code: '(java.webView(null, baseUrl, "document.cookie"))',
          baseUrl: 'http://x/',
        ),
        '',
      );
      expect(
        await host.run(
          code: '(java.webView(null, baseUrl, "document.title"))',
          baseUrl: 'http://x/',
        ),
        '',
      );
    });

    test('java.toNumChapter converts Chinese chapter numerals',
        () async {
      expect(
        await host.run(
          code: '(java.toNumChapter("第十二章 试炼"))',
          baseUrl: 'http://x/',
        ),
        '第12章 试炼',
      );
      expect(
        await host.run(
          code: '(java.toNumChapter("第一百二十三章"))',
          baseUrl: 'http://x/',
        ),
        '第123章',
      );
      expect(
        await host.run(
          code: '(java.toNumChapter("第十章"))',
          baseUrl: 'http://x/',
        ),
        '第10章',
      );
      expect(
        await host.run(
          code: '(java.toNumChapter("第二十章与第三章"))',
          baseUrl: 'http://x/',
        ),
        '第20章与第3章',
      );
    });
  });
}
