// Batch 165: the four fixes from the B163 device
// diagnostics forensics —
// 1. a Map/List URL-option body is a JSON body
//    (QQ阅读标签 chapter content came back silently empty),
// 2. GBK sources: the template-filled keyword arrives
//    UTF-8 percent-encoded and must be re-encoded as GBK
//    （飘天文学 search returned 0 rows),
// 3. java.getElements results carry the Jsoup Elements
//    method surface (.size()/.get()/...) — its absence was
//    the surviving "not a function" （起点男频）,
// 4. HTTP error states name the final URL （霹雳书屋 404
//    forensics).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_dom.dart';
import 'package:anikumo/services/novel/legado_engine.dart';
import 'package:anikumo/services/novel/legado_gbk.dart';
import 'package:anikumo/services/novel/legado_http.dart';
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
  String? capturedBody;
  String? capturedContentType;
  String? capturedUri;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b165_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      capturedUri = req.requestedUri.toString();
      capturedContentType = req.headers.contentType?.toString();
      capturedBody = await utf8.decoder.bind(req).join();
      if (req.uri.path == '/missing') {
        req.response.statusCode = HttpStatus.notFound;
      } else {
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body>ok</body></html>');
      }
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  group('GBK percent runs (batch 165)', () {
    test('UTF-8 runs decode back to characters', () {
      expect(
        Gb2312.decodeUtf8PercentRuns('%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86'),
        '斗罗大陆',
      );
      expect(Gb2312.decodeUtf8PercentRuns('a%E6%96%97b'), 'a斗b');
    });

    test('preset GBK bytes and ASCII escapes stay untouched', () {
      expect(Gb2312.decodeUtf8PercentRuns('%CB%D1%CB%F7'), '%CB%D1%CB%F7');
      expect(Gb2312.decodeUtf8PercentRuns('a%20b'), 'a%20b');
      // Valid char followed by GBK bytes: only the char decodes.
      expect(
        Gb2312.decodeUtf8PercentRuns('%E6%96%97%CB%D1'),
        '斗%CB%D1',
      );
    });

    test('round trip re-encodes the keyword as GBK only', () async {
      await Gb2312.ensureLoaded();
      final spec =
          'searchkey=%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86&submit=%CB%D1%CB%F7';
      final out = Gb2312.percentEncodeNonAscii(
          Gb2312.decodeUtf8PercentRuns(spec));
      expect(
        out,
        'searchkey=${Gb2312.percentEncodeNonAscii('斗罗大陆')}'
        '&submit=%CB%D1%CB%F7',
      );
      expect(out.contains('%E6%96%97'), isFalse);
    });
  });

  group('URL option bodies (batch 165)', () {
    test('a Map body goes out as JSON with its content type', () async {
      await LegadoHttp.fetch(
        '$base/content,{"method":"POST","body":'
        '{"Scene":"chapter","ChapterSeqNo":[1]}}',
      );
      expect(capturedContentType, contains('application/json'));
      expect(
        jsonDecode(capturedBody!),
        {'Scene': 'chapter', 'ChapterSeqNo': [1]},
      );
    });

    test('a string body stays a form body', () async {
      await LegadoHttp.fetch(
        '$base/content,{"method":"POST","body":"a=1&b=2"}',
      );
      expect(
          capturedContentType, contains('application/x-www-form-urlencoded'));
      expect(capturedBody, 'a=1&b=2');
    });

    test('a gbk search reaches the server GBK-encoded', () async {
      await LegadoHttp.fetch(
        '$base/search.php?searchkey=%E6%96%97%E7%BD%97'
        '&submit=%CB%D1%CB%F7,{"charset":"gbk"}',
      );
      expect(
        capturedUri,
        contains(Gb2312.percentEncodeNonAscii('斗罗')),
      );
      expect(capturedUri, isNot(contains('%E6%96%97')));
      expect(capturedUri, contains('submit=%CB%D1%CB%F7'));
    });
  });

  group('Elements surface (batch 165)', () {
    late LegadoJsHost host;
    late Map<String, dynamic> dom;

    setUpAll(() {
      host = LegadoJsHost.forSource('b165-elements', null);
      dom = LegadoDom.serializeDocument(LegadoDom.parseHtml(
        '<html><body>'
        '<div class="book-img-text"><ul>'
        '<li>甲</li><li>乙</li>'
        '</ul></div>'
        '</body></html>',
      ));
    });

    test('getElements results answer size/get/eachText/first/last',
        () async {
      final out = await host.run(
        code: "var list = java.getElements('.book-img-text@ul@li');"
            "(list.size() + '|' + list.get(0).text() + '|'"
            " + list.get(1).text() + '|' + list.eachText().join(',')"
            " + '|' + list.first().text() + '|' + list.last().text()"
            " + '|' + list.length)",
        domJson: dom,
        baseUrl: 'http://x/',
      );
      expect(out, '2|甲|乙|甲,乙|甲|乙|2');
    });

    test('element helpers: selectFirst/children/tag/hasAttr/parent',
        () async {
      final out = await host.run(
        code: "var el = java.getElement('.book-img-text');"
            "(el.selectFirst('li').text() + '|'"
            " + el.children().size() + '|'"
            " + el.getElementsByTag('li').size() + '|'"
            " + el.getElementsByClass('book-img-text').size() + '|'"
            " + String(el.hasAttr('class')) + '|'"
            " + el.selectAll('li').size() + '|'"
            " + java.getElements('.book-img-text@ul@li')"
            ".get(0).parent().tagName())",
        domJson: dom,
        baseUrl: 'http://x/',
      );
      expect(out, '甲|1|2|0|true|2|ul');
    });
  });

  group('HTTP errors name the URL (batch 165)', () {
    test('a 404 search reports the final address', () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '测试源',
        'bookSourceUrl': base,
        'searchUrl': '$base/missing?key={{key}}',
        'ruleSearch': {'bookList': 'li', 'name': 'a@text'},
      })!;
      await expectLater(
        LegadoEngine(def).search('斗罗大陆'),
        throwsA(predicate(
          (e) =>
              e.toString().contains('源站返回 404') &&
              e.toString().contains('/missing'),
        )),
      );
    });
  });
}
