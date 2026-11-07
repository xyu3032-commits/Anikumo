// DOM dump helper for the Node JS harness — not part of the
// default suite. Two modes:
//  * builds synthetic bilinovel catalog/chapter DOMs from
//    the documented page structure (the live site blocks
//    this host's IP, so its JS is verified against fixtures
//    here and on-device for real pages);
//  * when /tmp/legado_dom/duman_first_chapter.txt exists
//    (written by the Node harness from the real TOC), dumps
//    that live chapter page's DOM.
// Run: flutter test tool/legado_dump_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/novel/legado_dom.dart';
import 'package:anikumo/services/novel/legado_http.dart';
import 'package:anikumo/services/novel/legado_parse.dart';

void main() {
  test('dump bilinovel fixture DOMs', () {
    const catalogHtml = '''
      <html><body>
        <ul class="chapter-list">
          <li class="chapter-li chapter-bar">第一卷 起始</li>
          <li class="chapter-li jsChapter"><a href="/novel/9/1.html">第一章 开始</a></li>
          <li class="chapter-li jsChapter"><a href="/novel/9/2.html">第二章 继续</a></li>
          <li class="chapter-li chapter-bar">第二卷 发展</li>
          <li class="chapter-li jsChapter"><a href="/novel/9/3.html">第三章 转折</a></li>
        </ul>
      </body></html>''';
    const chapterHtml = '''
      <html><head>
        <script>var ReadParams={url_next:'/novel/9/2_2.html',chapter_id:2};</script>
      </head><body>
        <div id="acontent">
          <p>第一段文字。</p>
          <p>第二段文字，继续。</p>
          <img data-src="https://img3.readpai.com/x.jpg">
          <p>第三段，图后。</p>
        </div>
      </body></html>''';
    final dir = Directory('/tmp/legado_dom')..createSync(recursive: true);
    File('${dir.path}/bili_toc.json').writeAsStringSync(
      jsonEncode({
        'dom': LegadoDom.serializeDocument(LegadoDom.parseHtml(catalogHtml)),
        'baseUrl': 'https://www.bilinovel.com/novel/9.html',
        'fixture': true,
      }),
    );
    File('${dir.path}/bili_chapter.json').writeAsStringSync(
      jsonEncode({
        'dom': LegadoDom.serializeDocument(LegadoDom.parseHtml(chapterHtml)),
        'body': chapterHtml,
        'baseUrl': "https://www.bilinovel.com/novel/9/2.html,{'webView': true}",
        'fixture': true,
      }),
    );
  });

  test('dump dumanwu chapter DOM when a URL was provided', () async {
    final marker = File('/tmp/legado_dom/duman_first_chapter.txt');
    if (!marker.existsSync()) return;
    final url = marker.readAsStringSync().trim();
    if (url.isEmpty) return;
    final def = LegadoParse.parseSourceArray(
      await File('assets/legado/dumanwu.json').readAsString(),
    ).single;
    final headers = LegadoParse.parseLooseObject(def['header']?.toString());
    final page = await LegadoHttp.fetch(
      url,
      sourceHeaders: {
        for (final e in headers.entries) e.key: e.value.toString(),
      },
    );
    File('/tmp/legado_dom/duman_chapter.json').writeAsStringSync(
      jsonEncode({
        'dom': LegadoDom.serializeDocument(LegadoDom.parseHtml(page.body)),
        'baseUrl': page.url,
      }),
    );
    // ignore: avoid_print
    print('DUMAN chapter dumped: ${page.url} status=${page.statusCode}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
