import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/novel_source.dart';

// Batch 40 regressions for the v12 device report: a novel
// from 速读谷 showed 最新章节第350章 in the header yet the
// chapter area said "这个源暂时没有可读的章节". Two engine
// defects combined:
//  1. LegadoNovelSource.chapters depended on bookInfo having
//     run first (tocUrl cache) while the detail page loads
//     the two in parallel — the TOC rule was evaluated
//     against the info page, where the list does not live.
//  2. An empty chapterList match silently returned [], so
//     the page could not tell failure from a book that
//     genuinely has no chapters.
void main() {
  late HttpServer server;
  late String base;

  LegadoSourceDef defFor() {
    return LegadoSourceDef.fromJson({
      'bookSourceName': '目录测试源',
      'bookSourceUrl': base,
      'bookSourceType': 0,
      'ruleBookInfo': {
        'name': '@css: h1@text',
        'tocUrl': '@css: a.toc@href',
      },
      'ruleToc': {
        'chapterList': '@css: .chapters a',
        'chapterName': '@text',
        'chapterUrl': '@href',
      },
      'ruleContent': {'content': '@css: .content@text'},
    })!;
  }

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.host}:${server.port}';
    server.listen((request) {
      final path = request.uri.path;
      String body;
      if (path == '/book/1') {
        // Info page: NO chapter list here; the TOC lives on
        // its own page, linked via the toc anchor.
        body = '<html><body><h1>测试之书</h1>'
            '<a class="toc" href="/toc/1">目录</a></body></html>';
      } else if (path == '/toc/1') {
        body = '<html><body><div class="chapters">'
            '<a href="/read/1">第一章 起始</a>'
            '<a href="/read/2">第二章 推进</a>'
            '<a href="/read/3">第三章 高潮</a>'
            '</div></body></html>';
      } else if (path == '/toc/empty') {
        body = '<html><body><p>验证页面</p></body></html>';
      } else {
        request.response.statusCode = 404;
        body = 'not found';
      }
      request.response.headers.contentType =
          ContentType.html;
      request.response.write(body);
      request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('chapters resolve tocUrl themselves when bookInfo never ran',
      () async {
    final source = LegadoNovelSource(defFor());
    final item = NovelItem(bookUrl: '$base/book/1', title: '测试之书');
    // Deliberately NO bookInfo call first — the cold-cache
    // path the detail page races into.
    final chapters = await source.chapters(item);
    expect(chapters.map((c) => c.title),
        ['第一章 起始', '第二章 推进', '第三章 高潮']);
    expect(chapters.first.url, '$base/read/1');
  });

  test('empty chapterList match throws instead of returning []',
      () async {
    final source = LegadoNovelSource(defFor());
    final item = NovelItem(bookUrl: '$base/toc/empty', title: '空目录');
    await expectLater(
      source.chapters(item),
      throwsA(isA<StateError>()),
    );
  });
}
