// Batch 172: the reference's element-label grammar —
// bare extraction tokens ('text' / 'href' read the item
// element itself), the 'text.x' step (own text contains),
// index specs ('!a:b' exclusion, 'a:b[:c]' ranges,
// '[...]' lists), and list combinators ('&&' / '%%' /
// '||'). Fixture-shaped like a real TOC-heavy source
// whose chapterName is 'text' and chapterUrl is 'href'.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_dom.dart';
import 'package:anikumo/services/novel/legado_engine.dart';
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
    final dir = await Directory.systemTemp.createTemp('b172_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final path = req.uri.path;
      req.response.headers.contentType = ContentType.html;
      if (path == '/book/1.html') {
        req.response.write(
          '<div class="booktitle">示例之书</div>'
          '<a class="bookchapter" href="/chapter/xyz/9.html">第九章</a>',
        );
      } else if (path == '/chapter/xyz/1.html') {
        req.response.write(
          '<div id="allchapter">'
          '<a href="/r/1">第一章</a>'
          '<a href="/r/2">第二章</a>'
          '</div>'
          '<a class="pager" href="/chapter/xyz/2.html">下一页</a>',
        );
      } else if (path == '/chapter/xyz/2.html') {
        req.response.write(
          '<div id="allchapter">'
          '<a href="/r/3">第三章</a>'
          '<a href="/r/4">第四章</a>'
          '</div>'
          '<a class="pager" href="/chapter/xyz/1.html">下一页</a>',
        );
      } else if (path == '/r/1') {
        req.response.write('<div id="content"><p>正文一</p></div>');
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  group('bare extraction tokens (batch 172)', () {
    test("fieldElements: 'text' and 'href' read the element itself",
        () {
      final doc = LegadoDom.parseHtml(
        '<div id="allchapter"><a href="/c/1">第一章</a></div>',
      );
      final anchor = LegadoDom.selectChain(doc, 'id.allchapter@tag.a').single;
      final (textEls, textAttr) = LegadoDom.fieldElements(anchor, 'text');
      expect(textAttr, 'text');
      expect(LegadoDom.extract(textEls.single, textAttr), '第一章');
      final (hrefEls, hrefAttr) = LegadoDom.fieldElements(anchor, 'href');
      expect(hrefAttr, 'href');
      expect(LegadoDom.extract(hrefEls.single, hrefAttr), '/c/1');
    });

    test('a lone selector still selects (no false extraction)', () {
      final doc = LegadoDom.parseHtml(
        '<div class="bookbox"><span>甲</span></div>'
        '<div class="bookbox"><span>乙</span></div>',
      );
      final (els, attr) = LegadoDom.fieldElements(doc, 'class.bookbox');
      expect(attr, '');
      expect(els.length, 2);
    });
  });

  group('step grammar (batch 172)', () {
    final doc = LegadoDom.parseHtml(
      '<div id="list">'
      '<a href="/1">甲</a><a href="/2">乙</a>'
      '<a href="/3">丙</a><a href="/4">丁</a>'
      '</div>'
      '<a class="pager" href="/next">下一页</a>',
    );

    test("'text.x' step matches by contained own text", () {
      final els = LegadoDom.selectChain(doc, 'text.下一页');
      expect(els.length, 1);
      expect(els.single.attributes['href'], '/next');
    });

    test('index specs: exclusion, range, brackets, reversal', () {
      List<String> hrefs(String chain) => [
            for (final el in LegadoDom.selectChain(doc, chain))
              el.attributes['href']!,
          ];
      expect(hrefs('id.list@tag.a!0'), ['/2', '/3', '/4']);
      expect(hrefs('id.list@tag.a.0:1'), ['/1', '/2']);
      expect(hrefs('id.list@tag.a[-1]'), ['/4']);
      expect(hrefs('id.list@tag.a[0,2]'), ['/1', '/3']);
      expect(hrefs('id.list@tag.a[-1:0]'), ['/4', '/3', '/2', '/1']);
      expect(hrefs('id.list@tag.a[!1]'), ['/1', '/3', '/4']);
    });

    test("combinators: '&&' unions, '%%' interleaves, '||' falls back",
        () {
      final doc2 = LegadoDom.parseHtml(
        '<div class="x"><i>1</i><i>2</i></div>'
        '<div class="y"><i>3</i><i>4</i></div>',
      );
      List<String> texts(String chain) => [
            for (final el in LegadoDom.selectChain(doc2, chain))
              LegadoDom.elementText(el),
          ];
      expect(texts('class.x@tag.i&&class.y@tag.i'), ['1', '2', '3', '4']);
      expect(texts('class.x@tag.i%%class.y@tag.i'), ['1', '3', '2', '4']);
      expect(texts('class.none@tag.i||class.y@tag.i'), ['3', '4']);
    });
  });

  group('TOC-heavy source end to end (batch 172)', () {
    test('bare text/href fields + text-step pagination yield all chapters',
        () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'ruleBookInfo': {
          'name': 'class.booktitle@text',
          'tocUrl': "@js:\n(() => {\n"
              "    var h = java.getString('class.bookchapter@href');\n"
              "    var m = h.match(/\\/chapter\\/([^\\/]+)\\//);\n"
              "    return m ? '/chapter/' + m[1] + '/1.html' : '';\n"
              '})()',
        },
        'ruleToc': {
          'chapterList': 'id.allchapter@tag.a',
          'chapterName': 'text',
          'chapterUrl': 'href',
          'nextTocUrl': 'text.下一页@href',
        },
        'ruleContent': {'content': 'id.content@html'},
      })!;
      final engine = LegadoEngine(def);
      final (item, tocUrl) = await engine.bookInfo(
        NovelItem(bookUrl: '$base/book/1.html', title: ''),
      );
      expect(item.title, '示例之书');
      expect(tocUrl, '$base/chapter/xyz/1.html');
      final chapters = await engine.chapters(item, tocUrl: tocUrl);
      expect(
        chapters.map((c) => c.title).toList(),
        ['第一章', '第二章', '第三章', '第四章'],
      );
      expect(
        chapters.map((c) => c.url).toList(),
        ['$base/r/1', '$base/r/2', '$base/r/3', '$base/r/4'],
      );
    });

    test("JS bridge: getString with a 'text.' step resolves the pager",
        () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'ruleToc': {
          'chapterList': 'id.allchapter@tag.a',
          'chapterName': 'text',
          'chapterUrl': 'href',
          'nextTocUrl': '@js:java.getString("text.下一页@href")',
        },
      })!;
      final chapters = await LegadoEngine(def).chapters(
        NovelItem(bookUrl: '$base/chapter/xyz/1.html', title: '示例之书'),
      );
      expect(
        chapters.map((c) => c.title).toList(),
        ['第一章', '第二章', '第三章', '第四章'],
      );
    });
  });
}
