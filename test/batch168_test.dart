// Batch 168: reference-implementation dispatch alignment —
// 1. a rule starting with @js: is JS in its entirety ('||'
//    inside is the script's own operator, never a fallback
//    separator — the Fanqie-shaped kind/content rules),
// 2. top-level '||' splitting is group/quote aware,
// 3. JsonPath [*][*] flattens nested arrays,
// 4. UrlOption bodyJs transforms the response body,
// 5. java.setContent swaps the document mid-rule,
// 6. RSS: @js sortUrl returns "name::url" text; rule-less
//    feed documents fall back to standard item parsing.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_dom.dart';
import 'package:anikumo/services/novel/legado_engine.dart';
import 'package:anikumo/services/novel/legado_js.dart';
import 'package:anikumo/services/novel/legado_parse.dart';
import 'package:anikumo/services/novel/rss_engine.dart';
import 'package:anikumo/services/novel/rss_sources.dart';
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
    final dir = await Directory.systemTemp.createTemp('b168_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final path = req.uri.path;
      if (path == '/search') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': {
            'ret_data': [
              {
                'book_id': '42',
                'title': '示例之书',
                'author': '某作者',
                'thumb_url': '/cover.jpg',
                'abstract': '简介',
                'category': '玄幻',
              },
            ],
          },
        }));
      } else if (path == '/info') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': {
            'bookId': '42',
            'bookName': '示例之书',
            'author': '某作者',
            'thumbUrl': '/cover.jpg',
            'abstract': '简介',
            'categoryV2': '[{"Name":"玄幻"},{"Name":"热血"}]',
            'creationStatus': '1',
            'lastChapterTitle': '第三章',
            'wordNumber': 12345,
          },
        }));
      } else if (path == '/toc') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': {
            'chapterListWithVolume': [
              [
                {'title': '第一章', 'itemId': '1001', 'volume_name': '卷一'},
                {'title': '第二章', 'itemId': '1002', 'volume_name': '卷一'},
              ],
              [
                {'title': '第三章', 'itemId': '1003', 'volume_name': '卷二'},
              ],
            ],
          },
        }));
      } else if (path.startsWith('/reader/')) {
        req.response.headers.contentType = ContentType.html;
        req.response.write(
          '<html><body><div id="c"><p>甲一</p><p>乙二</p></div></body></html>',
        );
      } else if (path == '/list') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': {
            'ret_data': [
              {'book_id': '7', 'title': 'X-示例之书', 'author': '甲'},
            ],
          },
        }));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  group('splitAlternatives (batch 168)', () {
    test('top-level || splits, grouped || does not', () {
      expect(LegadoParse.splitAlternatives(r'$.a||$.b'), [r'$.a', r'$.b']);
      expect(LegadoParse.splitAlternatives(r'$.a||$.b||$.c').length, 3);
      expect(
        LegadoParse.splitAlternatives(r'$.a[?(@.t=="x||y")]||$.b'),
        [r'$.a[?(@.t=="x||y")]', r'$.b'],
      );
      expect(LegadoParse.splitAlternatives('(a||b)'), ['(a||b)']);
      expect(LegadoParse.splitAlternatives(r'$.a'), [r'$.a']);
    });
  });

  group('JsonPath double wildcard (batch 168)', () {
    test('[*][*] flattens volume -> chapter arrays', () {
      final root = {
        'data': {
          'chapterListWithVolume': [
            [
              {'title': '第一章'},
              {'title': '第二章'},
            ],
            [
              {'title': '第三章'},
            ],
          ],
        },
      };
      final out =
          JsonPathLite.eval(root, r'$.data.chapterListWithVolume[*][*]');
      expect(out, isA<List>());
      expect(
        (out as List).map((e) => (e as Map)['title']).toList(),
        ['第一章', '第二章', '第三章'],
      );
    });
  });

  group('Fanqie-shaped source end to end (batch 168)', () {
    LegadoSourceDef buildDef() => LegadoSourceDef.fromJson({
          'bookSourceName': '示例测试源',
          'bookSourceUrl': base,
          'searchUrl': '$base/search?q={{key}}',
          'ruleSearch': {
            'bookList': r'$.data.ret_data[*]',
            'name': r'$.title',
            'author': r'$.author',
            'bookUrl': '$base/info?bookId={{' r'$.book_id}}',
            'coverUrl': r'$.thumb_url',
            'intro': r'$.abstract',
            'kind': r'$.category',
          },
          'ruleBookInfo': {
            'name': r'$.data.bookName',
            'author': r'$.data.author',
            'kind': "@js:var d=JSON.parse(String(result)).data;"
                "var a=[];try{var c=JSON.parse(d.categoryV2||'[]');"
                "for(var i=0;i<c.length;i++)a.push(c[i].Name);}catch(e){}"
                "a.push(String(d.creationStatus)=='0'?'已完结':'连载中');"
                "a.join(',')",
            'tocUrl': '$base/toc?bookId={{' r'$.data.bookId}}',
          },
          'ruleToc': {
            'chapterList': r'$.data.chapterListWithVolume[*][*]',
            'chapterName': r'$.title',
            'chapterUrl': '$base/reader/{{' r'$.itemId}}',
            'updateTime': r'$.volume_name',
          },
          'ruleContent': {
            'content': "@js:var s=String(result);"
                "var a=s.indexOf('<div id=\"c\">');"
                "var body=(a>=0?s.substring(a):'')||'空';"
                "body.replace(/<[^>]+>/g,' ').replace(/\\s+/g,' ').trim()",
          },
        })!;

    test('search -> bookInfo (|| in @js) -> toc ([*][*]) -> content',
        () async {
      final engine = LegadoEngine(buildDef());
      final found = await engine.search('示例');
      expect(found.length, 1);
      final (item, tocUrl) = await engine.bookInfo(found.first);
      expect(item.title, '示例之书');
      expect(item.kind, '玄幻,热血,连载中');
      final chapters = await engine.chapters(item, tocUrl: tocUrl);
      expect(
        chapters.map((c) => c.title).toList(),
        ['第一章', '第二章', '第三章'],
      );
      final blocks = await engine.content(chapters.first);
      final text = blocks
          .map((b) => b is NovelTextBlock ? b.text : '')
          .join(' ');
      expect(text, contains('甲一'));
      expect(text, contains('乙二'));
    });

    test('UrlOption bodyJs rewrites the body before rules run', () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例测试源二',
        'bookSourceUrl': base,
        'searchUrl': '$base/list,{"bodyJs":"result.replace(/X-/g, \'\')"}',
        'ruleSearch': {
          'bookList': r'$.data.ret_data[*]',
          'name': r'$.title',
          'bookUrl': '$base/info?bookId={{' r'$.book_id}}',
        },
      })!;
      final found = await LegadoEngine(def).search('示例');
      expect(found.length, 1);
      expect(found.first.title, '示例之书');
    });
  });

  group('java.setContent (batch 168)', () {
    test('swaps the document for later getElements calls', () async {
      final host = LegadoJsHost.forSource('b168-doc', null);
      final dom = LegadoDom.serializeDocument(
        LegadoDom.parseHtml('<div class="old">旧文档</div>'),
      );
      final out = await host.run(
        code: "var before = java.getElements('.old')[0].text();"
            "java.setContent('<div class=\"fresh\">新文档</div>');"
            "var after = java.getElements('.fresh')[0].text();"
            "before + '|' + after",
        domJson: dom,
        baseUrl: 'http://x/',
      );
      expect(out, '旧文档|新文档');
    });
  });

  group('RSS alignment (batch 168)', () {
    test('@js sortUrl returning name::url text parses', () async {
      final def = RssSourceDef({
        'sourceName': '示例订阅',
        'sourceUrl': 'https://example.com/feed',
        'sortUrl': '@js:"最新::/new\\n热门::/hot"',
        'ruleArticles': 'ul li',
      });
      final categories = await RssEngine.categories(def);
      expect(categories, [
        ('最新', 'https://example.com/new'),
        ('热门', 'https://example.com/hot'),
      ]);
    });

    test('rule-less feed document falls back to item parsing', () async {
      final def = RssSourceDef({
        'sourceName': '示例订阅',
        'sourceUrl': 'https://example.com/feed.xml',
        'ruleArticles': 'ul li',
        'ruleTitle': 'h3',
        'ruleLink': 'a@href',
      });
      const body = '<?xml version="1.0"?><rss><channel>'
          '<item><title>其一</title><link>https://example.com/1</link>'
          '<pubDate>Mon, 01 Jan 2026</pubDate>'
          '<description>摘要一</description></item>'
          '<item><title>其二</title><link>/2</link>'
          '<pubDate>Tue, 02 Jan 2026</pubDate></item>'
          '</channel></rss>';
      final articles = await RssEngine.articlesFromBody(
        def,
        body,
        'https://example.com/feed.xml',
        const {},
      );
      expect(articles.length, 2);
      expect(articles[0].title, '其一');
      expect(articles[0].pubDate, contains('2026'));
      expect(articles[1].link, 'https://example.com/2');
    });
  });
}
