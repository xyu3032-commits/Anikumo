// Batch 181: the four device failures from the B180 field
// diagnostics — (1) a form POST whose keyword never reached
// the server (no form content-type on raw string bodies),
// (2) top-level `return` in rule scripts through the host
// evaluator, (3) explore kinds that failed once and stayed
// failed (and must never fall back to the bogus static
// entry), (4) the Fanqie/Copy-shaped dynamic kinds through
// the real host as standing regression coverage.
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

Future<Map<String, dynamic>> _transport(
  String url,
  Map<String, dynamic> options,
) async {
  if (url.contains('theme/book/count')) {
    return {
      'status': 200,
      'headers': {},
      'body': jsonEncode({
        'results': {
          'list': [
            {'name': '熱血', 'path_word': 'rexue'},
            {'name': '戀愛', 'path_word': 'lianai'},
          ]
        }
      }),
      'url': url,
    };
  }
  if (url.contains('/read/1')) {
    return {
      'status': 200,
      'headers': {},
      'body': '<html><body><div id="c">正文一段。</div></body></html>',
      'url': url,
    };
  }
  if (url.contains('/book/1')) {
    return {
      'status': 200,
      'headers': {},
      'body': '<html><body><ul id="toc"><li><a href="/read/1">第1章</a></li></ul></body></html>',
      'url': url,
    };
  }
  return {'status': 200, 'headers': {}, 'body': '{}', 'url': url};
}

const _fqExplore = '@js:\n'
    'var C = {"m":[["西方奇幻",1141],["东方仙侠",1140]],"f":[["古风世情",1139]],"a":[["西方奇幻",1141],["古风世情",1139]]};\n'
    'var groups = [["男生", 1, C.m], ["女生", 0, C.f], ["全部", -1, C.a]];\n'
    'var api = "https://fanqienovel.com/api/author/library/book_list/v0/?page_count=18&page_index={{page-1}}";\n'
    'var opt = JSON.stringify({bodyJs: "fqDecL(result)"});\n'
    'var out = [];\n'
    'for (var i = 0; i < groups.length; i++) {\n'
    '  var g = groups[i];\n'
    '  out.push({title: g[0], url: "", style: {layout_flexBasisPercent: 1, layout_flexGrow: 1}});\n'
    '  var list = [["全部", -1]].concat(g[2]);\n'
    '  for (var j = 0; j < list.length; j++) {\n'
    '    out.push({title: list[j][0], url: api + "&gender=" + g[1] + "&category_id=" + list[j][1] + "&book_type=-1{{fqFilter(source.getLoginInfo())}}," + opt, style: {layout_flexGrow: 1, layout_flexBasisPercent: 0.25}});\n'
    '  }\n'
    '}\n'
    'JSON.stringify(out);';

const _copyExplore = '@js:\n'
    'sort = [];\n'
    'push = (title, url, type) => sort.push({title: title, url: url, style: {layout_flexGrow: 1, layout_flexBasisPercent: type}});\n'
    'url = (theme) => `@js:\n"https://api.mangacopy.com/api/v3/books?ordering=-datetime_updated&limit=21&offset={{(page-1)*21}}&free_type=1&theme=\${theme}&_update=true"`\n'
    'push("全部题材", "", 1)\n'
    "tagUrl = 'https://api.mangacopy.com/api/v3/theme/book/count?free_type=1&limit=500&offset=0&_update=true'\n"
    'let \$ = JSON.parse(java.ajax(tagUrl)).results.list\n'
    '\$.forEach((\$) => { push(\$.name, url(\$.path_word), 0.25) })\n'
    'JSON.stringify(sort)';

Map<String, dynamic> _def(String name, String url,
        {String? explore, String? login, Map<String, dynamic>? content}) =>
    {
      'bookSourceName': name,
      'bookSourceUrl': url,
      'bookSourceType': 0,
      'exploreUrl': ?explore,
      'loginUrl': ?login,
      'ruleSearch': {'bookList': 'x'},
      'ruleExplore': <String, dynamic>{},
      'ruleBookInfo': <String, dynamic>{},
      'ruleToc': {'chapterList': '#toc li', 'chapterName': 'a@text', 'chapterUrl': 'a@href'},
      'ruleContent': content ?? <String, dynamic>{},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('anikumo_b181_');
    Hive.init(dir.path);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    await GStorage.init();
  });

  testWidgets('form POST carries the form content-type (loopback)',
      (tester) async {
    await tester.runAsync(() async {
      MoyuanHost.debugTransportOverride = null;
      String? seenContentType;
      String seenBody = '';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sub = server.listen((req) async {
        seenContentType = req.headers.contentType?.mimeType;
        seenBody = await utf8.decoder.bind(req).join();
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body><ul>'
            '<li class="searchresult"><h3>斗罗大陆</h3></li>'
            '</ul></body></html>');
        await req.response.close();
      });
      try {
        final base = 'http://127.0.0.1:${server.port}/';
        final def = {
          'bookSourceName': '22k形探针',
          'bookSourceUrl': base,
          'bookSourceType': 0,
          'searchUrl':
              '/search/,{"body":"searchkey={{key}}&searchtype=all","charset":"UTF-8","method":"POST"}',
          'ruleSearch': {'bookList': 'li.searchresult', 'name': 'h3@text'},
          'ruleToc': <String, dynamic>{},
        };
        await GStorage.putSetting(
          SettingsKeys.novelInstalledSourcesJson,
          jsonEncode([def]),
        );
        final src = LegadoNovelSource(LegadoSourceDef.fromJson(def)!);
        final items =
            await src.search('斗罗大陆').timeout(const Duration(seconds: 30));
        expect(items.length, 1);
        expect(items.first.title, '斗罗大陆');
        expect(seenContentType, 'application/x-www-form-urlencoded');
        expect(seenBody, contains('searchkey='));
      } finally {
        await sub.cancel();
        await server.close(force: true);
      }
    });
  });

  testWidgets('return-style content script works through the host',
      (tester) async {
    await tester.runAsync(() async {
      MoyuanHost.debugTransportOverride = _transport;
      final def = _def('return探针', 'https://ret.example',
          content: {'content': '#c@html@js:return result + "（完）";'});
      await GStorage.putSetting(
        SettingsKeys.novelInstalledSourcesJson,
        jsonEncode([def]),
      );
      final src = LegadoNovelSource(LegadoSourceDef.fromJson(def)!);
      final item = NovelItem(
        bookUrl: 'https://ret.example/book/1',
        title: '探针书',
        source: 'https://ret.example',
      );
      final chapters = await src
          .chapters(item)
          .timeout(const Duration(seconds: 30));
      expect(chapters.length, 1);
      final blocks = await src
          .content(item, chapters.first)
          .timeout(const Duration(seconds: 30));
      final joined =
          blocks.whereType<NovelTextBlock>().map((b) => b.text).join('\n');
      expect(joined, contains('正文一段。'));
      expect(joined, contains('（完）'));
    });
  });

  testWidgets('fanqie/copy-shaped kinds resolve via the real host',
      (tester) async {
    await tester.runAsync(() async {
      MoyuanHost.debugTransportOverride = _transport;
      final fq = _def('番茄探针', 'https://fanqienovel.com',
          explore: _fqExplore);
      final cp = _def('拷贝探针', 'https://www.mangacopy.com',
          explore: _copyExplore);
      await GStorage.putSetting(
        SettingsKeys.novelInstalledSourcesJson,
        jsonEncode([fq, cp]),
      );
      final fqSrc = LegadoNovelSource(LegadoSourceDef.fromJson(fq)!);
      await fqSrc.ensureExploreKinds();
      expect(fqSrc.exploreCategories.length, 11);
      expect(fqSrc.exploreCategories.first.title, '男生');
      final cpSrc = LegadoNovelSource(LegadoSourceDef.fromJson(cp)!);
      await cpSrc.ensureExploreKinds();
      expect(
          cpSrc.exploreCategories.map((k) => k.title).toList(),
          ['全部题材', '熱血', '戀愛']);
    });
  });

  testWidgets('failed kinds: resolved-empty, never bogus, retry works',
      (tester) async {
    await tester.runAsync(() async {
      MoyuanHost.debugTransportOverride = _transport;
      final def = _def('重试探针', 'https://retry.example',
          explore:
              '@js:if(source.get("kindsOk")!=="1") throw new Error("kinds not ready"); JSON.stringify([{title:"甲类",url:"https://retry.example/list/1"}]);',
          login: 'function login(){ source.put("kindsOk", "1"); }');
      await GStorage.putSetting(
        SettingsKeys.novelInstalledSourcesJson,
        jsonEncode([def]),
      );
      final src = LegadoNovelSource(LegadoSourceDef.fromJson(def)!);
      await src.ensureExploreKinds();
      expect(src.exploreKindsResolved, isTrue);
      expect(src.exploreCategories, isEmpty);
      await MoyuanHost.instance
          .submitLoginForm('https://retry.example', const {})
          .timeout(const Duration(seconds: 30));
      await src.ensureExploreKinds();
      expect(src.exploreCategories.map((k) => k.title).toList(), ['甲类']);
    });
  });
}
