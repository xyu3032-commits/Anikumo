// Batch 175 regression: the v49 device diagnostics for
// the Fanqie-shaped source — search succeeded, then the
// chapters step fetched the SEARCH path with
// '[object Object]' appended and 404'd. Root cause: the
// JS engine never assembled {{...}} templates inside
// field rules, so a bookUrl rule of the form
// 'https://host/page/{{$.book_id}}' evaluated to the
// whole result element object, was stringified to
// '[object Object]', and resolved against the search
// page address. The Dart engine (B157) assembled these
// templates; the JS engine now does too (its
// _assembleTemplates in the rule context). This test
// walks the same shape through the REAL bundle in
// QuickJS. Fixtures are synthetic; no real source is
// bundled.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/moyuan_host.dart';
import 'package:anikumo/services/novel/novel_source.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

Map<String, dynamic> fanqieShapeDef() => {
      'bookSourceName': '模板形夹具源',
      'bookSourceUrl': 'https://fanqie.example',
      'bookSourceType': 0,
      'searchUrl':
          'https://api.example/search/v1/?offset={{(page-1)*10}}&q={{key}}',
      'ruleSearch': {
        'bookList': r'$.data.ret_data[*]',
        'name': r'$.title',
        'author': r'$.author',
        'bookUrl': r'https://fanqie.example/page/{{$.book_id}}',
      },
      'ruleBookInfo': {
        'name': r'$.data.bookName',
        'tocUrl':
            r'https://fanqie.example/api/reader/directory/detail?bookId={{$.data.bookId}}',
      },
      'ruleToc': {
        'chapterList': r'$.data.chapterListWithVolume[*][*]',
        'chapterName': r'$.title',
        'chapterUrl': r'https://fanqie.example/reader/{{$.itemId}}',
      },
      'ruleContent': {'content': r'$.text'},
    };

Future<Map<String, dynamic>> fakeTransport(
  String url,
  Map<String, dynamic> options,
) async {
  String body;
  if (url.contains('/search/v1/')) {
    body = jsonEncode({
      'code': 0,
      'data': {
        'ret_data': [
          {'book_id': '123', 'title': '模板之书', 'author': '某作者'},
        ],
      },
    });
  } else if (url.contains('fanqie.example/page/')) {
    body = jsonEncode({
      'data': {'bookId': '123', 'bookName': '模板之书', 'author': '某作者'},
    });
  } else if (url.contains('/directory/detail')) {
    body = jsonEncode({
      'data': {
        'chapterListWithVolume': [
          [
            {'itemId': 'a1', 'title': '第一章'},
          ],
        ],
      },
    });
  } else if (url.contains('fanqie.example/reader/')) {
    body = jsonEncode({'text': '正文一。'});
  } else {
    return {'status': 404, 'headers': {}, 'body': 'not found', 'url': url};
  }
  return {'status': 200, 'headers': {}, 'body': body, 'url': url};
}

final jiujiuCalls = <String>[];

/// Jiujiu-shaped transport: the line root serves a page
/// whose search form action is /search9x.html — NOT the
/// template's baked-in fallback /search7e.html — so a
/// passing search proves the probe response was really
/// fetched (host prime) and read back (replay).
Future<Map<String, dynamic>> jiujiuTransport(
  String url,
  Map<String, dynamic> options,
) async {
  jiujiuCalls.add('${options['method'] ?? 'GET'} $url');
  if (url == 'http://line.example/') {
    return {
      'status': 200,
      'headers': {},
      'body': '<html><form action="/search9x.html"></form></html>',
      'url': url,
    };
  }
  if (url == 'http://line.example/search9x.html') {
    return {
      'status': 200,
      'headers': {},
      'body': '<html><body><div class="bookbox">'
          '<div class="bookname"><a href="/book/1.html">斗罗大陆</a></div>'
          '<div class="author">唐家三少</div></div></body></html>',
      'url': url,
    };
  }
  return {'status': 404, 'headers': {}, 'body': 'not found', 'url': url};
}

Map<String, dynamic> jiujiuShapeDef() => {
      'bookSourceName': '久久形夹具源',
      'bookSourceUrl': 'http://www.ijjxs.example/',
      'bookSourceType': 0,
      'searchUrl': r'''{{(function(){var L='';try{L=String(source.get('ijLine')||'')}catch(e){}if(!L||L==='null'||L==='undefined'||L.indexOf('http')!==0)L='http://line.example';L=L.replace(/\/+$/,'');try{var h=String(java.ajax(L+'/'));var m=h.match(/action=['"](\/search[^'"]*\.html)['"]/);if(m)return L+m[1]}catch(e){}return L+'/search7e.html'})()}},{"method":"POST","body":"searchkey={{key}}","headers":{"Content-Type":"application/x-www-form-urlencoded"}}''',
      'ruleSearch': {
        'bookList': 'class.bookbox',
        'name': 'class.bookname@tag.a@text',
        'bookUrl': 'class.bookname@tag.a@href',
        'author': 'class.author@text',
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('anikumo_b175_');
    Hive.init(dir.path);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    await GStorage.init();
    MoyuanHost.debugTransportOverride = fakeTransport;
  });

  testWidgets('template field rules: search -> chapters -> content',
      (tester) async {
    await tester.runAsync(() async {
      final src = LegadoNovelSource(
        LegadoSourceDef.fromJson(fanqieShapeDef())!,
      );
      final items = await src
          .search('模板')
          .timeout(const Duration(seconds: 30));
      expect(items.single.title, '模板之书');
      // The regression: this was the search address with
      // '[object Object]' appended.
      expect(
        items.single.bookUrl,
        'https://fanqie.example/page/123',
      );
      final chapters = await src
          .chapters(items.single)
          .timeout(const Duration(seconds: 30));
      expect(chapters.single.title, '第一章');
      expect(
        chapters.single.url,
        'https://fanqie.example/reader/a1',
      );
      final blocks = await src
          .content(items.single, chapters.single)
          .timeout(const Duration(seconds: 30));
      expect(
        blocks.whereType<NovelTextBlock>().map((b) => b.text),
        contains('正文一。'),
      );
    });
  });

  testWidgets('jiujiu shape: probe template primes and replays',
      (tester) async {
    MoyuanHost.debugTransportOverride = jiujiuTransport;
    try {
      await tester.runAsync(() async {
        jiujiuCalls.clear();
        final src = LegadoNovelSource(
          LegadoSourceDef.fromJson(jiujiuShapeDef())!,
        );
        final items = await src
            .search('斗罗大陆')
            .timeout(const Duration(seconds: 30));
        expect(items.single.title, '斗罗大陆');
        // The probe target was really fetched (host prime)…
        expect(
          jiujiuCalls,
          contains('GET http://line.example/'),
        );
        // …and the search POST went to the DISCOVERED
        // action, not the template's fallback — proof the
        // recorded attempt was primed and the call
        // replayed (the script itself catches the
        // suspension, so round one alone can only ever
        // reach the fallback).
        expect(
          jiujiuCalls,
          contains('POST http://line.example/search9x.html'),
        );
        expect(
          jiujiuCalls.where((c) => c.contains('{{')),
          isEmpty,
        );
      });
    } finally {
      MoyuanHost.debugTransportOverride = fakeTransport;
    }
  });
}
