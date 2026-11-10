// Batch 174: the MoYuan JS engine drives the novel
// zone. These tests run the REAL bundle (the asset copy)
// in QuickJS with a fake host transport and walk a
// synthetic source through the full chain the app uses:
// search -> bookInfo -> chapters -> content, plus
// script-generated explore kinds. Fixtures are
// synthetic; no real source is bundled.
//
// The host bridge settles its promises through REAL
// timers and IO (asset load, the storage box), so the
// scenarios run inside tester.runAsync: pumping fake
// time instead would starve the very completions the
// bridge waits on.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/moyuan_host.dart';
import 'package:anikumo/services/novel/moyuan_rss.dart';
import 'package:anikumo/services/novel/novel_source.dart';
import 'package:anikumo/services/novel/rss_sources.dart';
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

Map<String, dynamic> fixtureDef() => {
      'bookSourceName': '墨源夹具源',
      'bookSourceUrl': 'https://fx.example.com',
      'bookSourceType': 0,
      'searchUrl': 'https://fx.example.com/s?q={{key}}&p={{page}}',
      'exploreUrl': '@js:\n'
          'var out = [];\n'
          'out.push({title: "男生", url: "", style: {layout_flexBasisPercent: 1, layout_flexGrow: 1}});\n'
          'out.push({title: "玄幻", url: "https://fx.example.com/api/list?cat=xh", style: {layout_flexGrow: 1, layout_flexBasisPercent: 0.25}});\n'
          'JSON.stringify(out);',
      'ruleSearch': {
        'bookList': r'$.data[*]',
        'name': r'$.title',
        'author': r'$.author',
        'kind': r'$.kind',
        'bookUrl': r'$.url',
      },
      'ruleExplore': {
        'bookList': r'$.data[*]',
        'name': r'$.title',
        'bookUrl': r'$.url',
      },
      'ruleBookInfo': {
        'name': r'$.data.name',
        'author': r'$.data.author',
        'intro': r'$.data.intro',
        'kind': r'$.data.kind',
        'tocUrl': r'$.data.toc',
      },
      'ruleToc': {
        'chapterList': r'$.chapters[*]',
        'chapterName': r'$.t',
        'chapterUrl': r'$.u',
      },
      'ruleContent': {'content': r'$.text'},
    };

Future<Map<String, dynamic>> fakeTransport(
  String url,
  Map<String, dynamic> options,
) async {
  String body;
  if (url.contains('sync.example.com/s?q=')) {
    body = jsonEncode({
      'data': [
        {'title': '同步之书', 'url': 'https://sync.example.com/book/1'},
      ],
    });
  } else if (url.contains('/s?q=')) {
    body = jsonEncode({
      'data': [
        {
          'title': '星海武途',
          'author': '测作者',
          'kind': '玄幻',
          'url': 'https://fx.example.com/book/1',
        },
      ],
    });
  } else if (url.contains('/api/list')) {
    body = jsonEncode({
      'data': [
        {'title': '星海武途', 'url': 'https://fx.example.com/book/1'},
      ],
    });
  } else if (url.endsWith('fx.example.com/book/1')) {
    body = jsonEncode({
      'data': {
        'name': '星海武途',
        'author': '测作者',
        'intro': '简介一',
        'kind': '玄幻,热血',
        'toc': 'https://fx.example.com/toc/1',
      },
    });
  } else if (url.endsWith('fx.example.com/toc/1')) {
    body = jsonEncode({
      'chapters': [
        {'t': '第一章 起', 'u': 'https://fx.example.com/read/1'},
        {'t': '第二章 承', 'u': 'https://fx.example.com/read/2'},
      ],
    });
  } else if (url.endsWith('fx.example.com/read/1')) {
    body = jsonEncode({'text': '第一段。\n\n第二段。'});
  } else if (url.endsWith('fx.example.com/read/2')) {
    body = jsonEncode({'text': '第三段。'});
  } else if (url.endsWith('sync.example.com/book/1')) {
    body = jsonEncode({
      'data': {
        'name': '同步之书',
        'toc': 'https://sync.example.com/toc/1',
      },
    });
  } else if (url.endsWith('sync.example.com/toc/1')) {
    body = jsonEncode({
      'chapters': [
        {'t': '第一章', 'u': 'https://sync.example.com/read/1'},
      ],
    });
  } else if (url.endsWith('sync.example.com/read/1')) {
    body = jsonEncode({'ignored': true});
  } else if (url.endsWith('sync.example.com/dyn')) {
    body = '动态正文段落。';
  } else if (url.contains('rss.example.com/feed')) {
    body = '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<rss version="2.0"><channel><title>夹具频道</title>\n'
        '<item><title>文章甲</title>'
        '<link>https://rss.example.com/a/1</link>'
        '<pubDate>Mon, 10 Nov 2026 01:00:00 GMT</pubDate>'
        '<description>甲摘要</description></item>\n'
        '<item><title>文章乙</title>'
        '<link>https://rss.example.com/a/2</link>'
        '<description>乙摘要</description></item>\n'
        '</channel></rss>';
  } else if (url.endsWith('rss.example.com/a/1')) {
    body = '<html><body><div class="article-body">'
        '<p>正文第一段</p><p>正文第二段</p></div></body></html>';
  } else {
    return {'status': 404, 'headers': {}, 'body': 'not found', 'url': url};
  }
  return {'status': 200, 'headers': {}, 'body': body, 'url': url};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('anikumo_b174_');
    Hive.init(dir.path);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    await GStorage.init();
    MoyuanHost.debugTransportOverride = fakeTransport;
    await GStorage.putSetting(
      SettingsKeys.novelInstalledSourcesJson,
      jsonEncode([fixtureDef()]),
    );
  });

  LegadoNovelSource source() =>
      LegadoNovelSource(LegadoSourceDef.fromJson(fixtureDef())!);

  testWidgets('full chain on the MoYuan engine: search/info/toc/content',
      (tester) async {
    await tester.runAsync(() async {
      final src = source();
      final items = await src
          .search('星海')
          .timeout(const Duration(seconds: 30));
      expect(items.length, 1);
      expect(items.single.title, '星海武途');
      expect(items.single.author, '测作者');
      expect(items.single.kind, '玄幻');
      expect(items.single.source, 'https://fx.example.com');

      final info = await src
          .bookInfo(items.single)
          .timeout(const Duration(seconds: 30));
      expect(info.intro, '简介一');
      // kind carries the merged classification/tag string.
      expect(info.kind, contains('玄幻'));
      expect(info.kind, contains('热血'));

      final chapters = await src
          .chapters(items.single)
          .timeout(const Duration(seconds: 30));
      expect(chapters.map((c) => c.title), ['第一章 起', '第二章 承']);

      final blocks = await src
          .content(items.single, chapters.first)
          .timeout(const Duration(seconds: 30));
      expect(blocks.whereType<NovelTextBlock>().map((b) => b.text),
          ['第一段。', '第二段。']);
    });
  });

  testWidgets('script explore kinds resolve with headers and styles',
      (tester) async {
    await tester.runAsync(() async {
      final src = source();
      expect(src.hasDynamicExplore, isTrue);
      await src.ensureExploreKinds().timeout(const Duration(seconds: 30));
      expect(src.exploreKindsResolved, isTrue);
      final categories = src.exploreCategories;
      expect(categories.length, 2);
      expect(categories.first.title, '男生');
      expect(categories.first.isHeader, isTrue);
      expect(categories.last.title, '玄幻');
      expect(categories.last.flexBasis, 0.25);

      final items = await src
          .explore(categories.last)
          .timeout(const Duration(seconds: 30));
      expect(items.single.title, '星海武途');
    });
  });

  testWidgets('subscriptions run on the engine rss registry',
      (tester) async {
    await tester.runAsync(() async {
      final rssDef = {
        'sourceName': '夹具订阅',
        'sourceUrl': 'https://rss.example.com',
        'sortUrl': '推荐::/feed',
        'ruleContent': 'class.article-body',
      };
      await GStorage.putSetting(
        SettingsKeys.novelRssSourcesJson,
        jsonEncode([rssDef]),
      );
      final def = RssSourceDef(rssDef);
      final categories = await MoyuanRssEngine.categories(def)
          .timeout(const Duration(seconds: 30));
      expect(categories, [('推荐', 'https://rss.example.com/feed')]);

      final articles = await MoyuanRssEngine.articles(
        def,
        categories.single.$2,
      ).timeout(const Duration(seconds: 30));
      expect(articles.map((a) => a.title), ['文章甲', '文章乙']);
      expect(articles.first.description, '甲摘要');

      final paragraphs = await MoyuanRssEngine.contentParagraphs(
        def,
        articles.first,
      ).timeout(const Duration(seconds: 30));
      expect(paragraphs, isNotNull);
      expect(paragraphs!.join(' '), contains('正文第一段'));
      expect(paragraphs.join(' '), contains('正文第二段'));
    });
  });

  testWidgets('login form submit, cookie plant and clear',
      (tester) async {
    await tester.runAsync(() async {
      final loginDef = {
        'bookSourceName': '登录夹具源',
        'bookSourceUrl': 'https://login.example.com',
        'bookSourceType': 0,
        'searchUrl': 'https://login.example.com/s?q={{key}}',
        'loginUrl': '@js:function login() { '
            'globalThis.__loginHookRan = '
            '(globalThis.__loginHookRan || 0) + 1; }',
        'loginUi': jsonEncode([
          {'name': 'user', 'type': 'text'},
          {'name': 'pass', 'type': 'password'},
        ]),
        'ruleSearch': {
          'bookList': r'$.data[*]',
          'name': r'$.title',
          'bookUrl': r'$.url',
        },
      };
      await GStorage.putSetting(
        SettingsKeys.novelInstalledSourcesJson,
        jsonEncode([fixtureDef(), loginDef]),
      );
      final host = MoyuanHost.instance;
      final result = await host
          .submitLoginForm(
            'https://login.example.com',
            {'user': 'u1', 'pass': 'p1'},
          )
          .timeout(const Duration(seconds: 30));
      expect(result['stored'], isTrue);
      expect(result['hookExecuted'], isTrue);
      expect(
        host.evalJson(
          '__moyuanEngine.loginInfo("https://login.example.com")',
        )['user'],
        'u1',
      );
      expect(host.evalJson('globalThis.__loginHookRan'), 1);

      await host.setCookie('https://login.example.com/', 'sid', 'abc');
      expect(
        host.evalJson(
          '__moyuanEngine.requests.cookieJar'
          '.getCookieHeader("https://login.example.com/x")',
        ),
        contains('sid=abc'),
      );
      await host.clearSourceLogin(
        'https://login.example.com',
        ['login.example.com'],
      );
      expect(
        host.evalJson(
          '__moyuanEngine.requests.cookieJar'
          '.getCookieHeader("https://login.example.com/x")',
        ),
        isNot(contains('sid')),
      );
      expect(
        host.evalJson(
          '__moyuanEngine.loginInfo("https://login.example.com")',
        ),
        {},
      );
    });
  });

  testWidgets('timer shim: setTimeout promises settle under the pump',
      (tester) async {
    await tester.runAsync(() async {
      final host = MoyuanHost.instance;
      await host.ensureStarted().timeout(const Duration(seconds: 30));
      expect(host.evalJson('typeof MoYuan.ajaxCacheKey'), 'function');
      final value = await host
          .callAsync(
            'new Promise(function (res) {'
            '  var id = setTimeout(function () { res("bad"); }, 5);'
            '  clearTimeout(id);'
            '  setTimeout(function () { res("good"); }, 15);'
            '})',
          )
          .timeout(const Duration(seconds: 30));
      expect(value, 'good');
    });
  });

  testWidgets('sync ajax with a built URL replays and returns content',
      (tester) async {
    await tester.runAsync(() async {
      final syncDef = {
        'bookSourceName': '同步夹具源',
        'bookSourceUrl': 'https://sync.example.com',
        'bookSourceType': 0,
        'searchUrl': 'https://sync.example.com/s?q={{key}}',
        'ruleSearch': {
          'bookList': r'$.data[*]',
          'name': r'$.title',
          'bookUrl': r'$.url',
        },
        'ruleBookInfo': {
          'name': r'$.data.name',
          'tocUrl': r'$.data.toc',
        },
        'ruleToc': {
          'chapterList': r'$.chapters[*]',
          'chapterName': r'$.t',
          'chapterUrl': r'$.u',
        },
        'ruleContent': {
          'content': '@js:var u = "https://sync.example.com" + "/dyn";'
              ' var r = java.ajax(u); result = String(r);',
        },
      };
      final src = LegadoNovelSource(LegadoSourceDef.fromJson(syncDef)!);
      final items = await src
          .search('同步')
          .timeout(const Duration(seconds: 30));
      expect(items.single.title, '同步之书');
      final chapters = await src
          .chapters(items.single)
          .timeout(const Duration(seconds: 30));
      expect(chapters.single.title, '第一章');
      // The content rule's java.ajax target is built by
      // concatenation, so the literal prefetch cannot see
      // it: only the suspension/replay channel can serve
      // it. The paragraph must be the fetched text, not
      // the empty fallback.
      final blocks = await src
          .content(items.single, chapters.single)
          .timeout(const Duration(seconds: 60));
      expect(
        blocks.whereType<NovelTextBlock>().map((b) => b.text),
        contains('动态正文段落。'),
      );
      final syncEvents = MoyuanHost.instance.unsupportedLog.where(
        (e) => e['sourceId'] == 'https://sync.example.com',
      );
      expect(
        syncEvents.where((e) => e['feature'] == 'java.ajax-sync'),
        isEmpty,
      );
    });
  });
}
