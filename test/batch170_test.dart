// Batch 170: reference-flow completeness — loginCheckJs
// on every fetch, TOC pagination via nextTocUrl, the
// '-'/'+' list order prefixes, formatJs title rewriting,
// and the key/page/title/src + book/chapter bindings rule
// scripts read (including a book.tocUrl rewrite).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
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
    final dir = await Directory.systemTemp.createTemp('b170_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final path = req.uri.path;
      if (path == '/s') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': [
            {'title': '甲书', 'url': '/b/1'},
            {'title': '乙书', 'url': '/b/2'},
            {'title': '丙书', 'url': '/b/3'},
          ],
        }));
      } else if (path == '/walled') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': [
            {'title': '登录墙', 'url': '/b/9'},
          ],
        }));
      } else if (path == '/info') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': {'name': '示例之书'},
        }));
      } else if (path == '/toc/1') {
        req.response.headers.contentType = ContentType.html;
        req.response.write(
          '<ul>'
          '<li><a href="/c/1">第一章</a></li>'
          '<li><a href="/c/2">第二章</a></li>'
          '</ul><a class="next" href="/toc/2">下一页</a>',
        );
      } else if (path == '/toc/2') {
        req.response.headers.contentType = ContentType.html;
        req.response.write(
          '<ul>'
          '<li><a href="/c/3">第三章</a></li>'
          '<li><a href="/c/4">第四章</a></li>'
          '</ul><a class="next" href="/toc/1">回第一页</a>',
        );
      } else if (path == '/toc/desc') {
        req.response.headers.contentType = ContentType.html;
        req.response.write(
          '<ul>'
          '<li><a href="/c/1">第一章</a></li>'
          '<li><a href="/c/2">第二章</a></li>'
          '<li><a href="/c/3">第三章</a></li>'
          '</ul>',
        );
      } else if (path == '/c/1') {
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body><p>正文占位</p></body></html>');
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  group('TOC pagination and order prefixes (batch 170)', () {
    test('nextTocUrl chain appends pages and stops on revisit', () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'ruleToc': {
          'chapterList': 'ul li',
          'chapterName': 'a@text',
          'chapterUrl': 'a@href',
          'nextTocUrl': '.next@href',
        },
      })!;
      final chapters = await LegadoEngine(def).chapters(
        NovelItem(bookUrl: '$base/toc/1', title: '示例之书'),
      );
      expect(
        chapters.map((c) => c.title).toList(),
        ['第一章', '第二章', '第三章', '第四章'],
      );
    });

    test("'-' chapterList reverses the assembled list", () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'ruleToc': {
          'chapterList': '-ul li',
          'chapterName': 'a@text',
          'chapterUrl': 'a@href',
        },
      })!;
      final chapters = await LegadoEngine(def).chapters(
        NovelItem(bookUrl: '$base/toc/desc', title: '示例之书'),
      );
      expect(
        chapters.map((c) => c.title).toList(),
        ['第三章', '第二章', '第一章'],
      );
    });

    test("'-' bookList reverses search results", () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'searchUrl': '$base/s?q={{key}}',
        'ruleSearch': {
          'bookList': r'-$.data[*]',
          'name': r'$.title',
          'bookUrl': '$base{{' r'$.url}}',
        },
      })!;
      final found = await LegadoEngine(def).search('x');
      expect(found.map((b) => b.title).toList(), ['丙书', '乙书', '甲书']);
    });

    test('formatJs rewrites titles with the final index bound', () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'ruleToc': {
          'chapterList': 'ul li',
          'chapterName': 'a@text',
          'chapterUrl': 'a@href',
          'formatJs': '"[" + index + "]" + title',
        },
      })!;
      final chapters = await LegadoEngine(def).chapters(
        NovelItem(bookUrl: '$base/toc/desc', title: '示例之书'),
      );
      expect(
        chapters.map((c) => c.title).toList(),
        ['[0]第一章', '[1]第二章', '[2]第三章'],
      );
    });
  });

  group('loginCheckJs (batch 170)', () {
    test('runs on the fetch and its string return replaces the body',
        () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'searchUrl': '$base/walled?q={{key}}',
        'loginCheckJs': 'result.body().replace("登录墙", "示例之书")',
        'ruleSearch': {
          'bookList': r'$.data[*]',
          'name': r'$.title',
          'bookUrl': '$base{{' r'$.url}}',
        },
      })!;
      final found = await LegadoEngine(def).search('x');
      expect(found.length, 1);
      expect(found.first.title, '示例之书');
    });
  });

  group('flow bindings (batch 170)', () {
    test('search field scripts see key and page', () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'searchUrl': '$base/s?q={{key}}',
        'ruleSearch': {
          'bookList': r'$.data[*]',
          'name': r'$.title',
          'bookUrl': '$base{{' r'$.url}}',
          'kind': '@js:key + ":" + page',
        },
      })!;
      final found = await LegadoEngine(def).search('斗罗大陆', page: 2);
      expect(found.first.kind, '斗罗大陆:2');
    });

    test('bookInfo scripts read book.* and a tocUrl rewrite is adopted',
        () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'ruleBookInfo': {
          'name': r'$.data.name',
          'kind': '@js:book.name',
          'tocUrl': '@js:book.tocUrl = "/toc/1"; ""',
        },
      })!;
      final (item, tocUrl) = await LegadoEngine(def).bookInfo(
        NovelItem(bookUrl: '$base/info', title: '原标题'),
      );
      expect(item.kind, '原标题');
      expect(tocUrl, '$base/toc/1');
    });

    test('content scripts see chapter/title/src/nextChapterUrl', () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'ruleContent': {
          'content': '@js:chapter.title + "|" + title + "|" +'
              ' (typeof src) + "," + (typeof nextChapterUrl)',
        },
      })!;
      final blocks = await LegadoEngine(def).content(
        NovelChapter(title: '第一章', url: '$base/c/1'),
      );
      final text = blocks
          .map((b) => b is NovelTextBlock ? b.text : '')
          .join(' ');
      expect(text, contains('第一章|第一章|string,string'));
    });
  });
}
