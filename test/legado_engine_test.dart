import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_dom.dart';
import 'package:anikumo/services/novel/legado_gbk.dart';
import 'package:anikumo/services/novel/legado_parse.dart';
import 'package:anikumo/services/novel/novel_api.dart';

void main() {
  group('LegadoParse', () {
    test('decodes base16 payloads and leaves JSON alone', () {
      final original = '[{"bookSourceName":"x"}]';
      final hex = utf8
          .encode(original)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(LegadoParse.decodePossibleBase16(hex), original);
      expect(LegadoParse.decodePossibleBase16(original), original);
      expect(
        LegadoParse.parseSourceArray(hex).single['bookSourceName'],
        'x',
      );
    });

    test('parses single-quoted JS object literals', () {
      final parsed = LegadoParse.parseLooseObject(
        "{'User-Agent': 'Mozilla/5.0', 'Cookie': 'night=0'}",
      );
      expect(parsed['User-Agent'], 'Mozilla/5.0');
      expect(parsed['Cookie'], 'night=0');
      final nested = LegadoParse.parseLooseObject(
        "{'headers': {'Referer': 'https://x/'}, 'webView': true}",
      );
      expect((nested['headers'] as Map)['Referer'], 'https://x/');
      expect(nested['webView'], true);
    });

    test('splits URL options and fills templates', () {
      final (url, options) = LegadoParse.splitUrlOptions(
        'https://m.dumanwu.com/s, { "method": "POST", "body": "k={{key}}" }',
      );
      expect(url, 'https://m.dumanwu.com/s');
      expect(options['method'], 'POST');
      expect(
        LegadoParse.fillTemplate(
          'https://www.bilinovel.com/search/{{key}}_{{page}}.html',
          key: '魔女',
          page: 2,
        ),
        'https://www.bilinovel.com/search/%E9%AD%94%E5%A5%B3_2.html',
      );
      expect(
        LegadoParse.fillTemplate('https://x/l?page={{page-1}}', key: '', page: 3),
        'https://x/l?page=2',
      );
    });

    test('applies ## replacements with group references', () {
      final (base, pairs) =
          LegadoParse.splitReplacements(r'url##$##, {"webView": true}');
      expect(base, 'url');
      expect(
        LegadoParse.applyReplacements('/123/1.html', pairs),
        '/123/1.html, {"webView": true}',
      );
      final (base2, pairs2) =
          LegadoParse.splitReplacements(r'@css:.a@text##作者：##');
      expect(base2, '@css:.a@text');
      expect(LegadoParse.applyReplacements('作者：张三', pairs2), '张三');
    });
  });

  group('JsonPathLite', () {
    final data = jsonDecode(
      '{"data":[{"id":1,"name":"a"},{"id":2,"name":"b"}],"meta":{"total":2}}',
    );
    test('dot, index, wildcard and recursive paths', () {
      expect(JsonPathLite.eval(data, r'$.meta.total'), 2);
      expect(JsonPathLite.eval(data, r'$.data[1].name'), 'b');
      expect(JsonPathLite.eval(data, r'$.data[*].id'), [1, 2]);
      expect(JsonPathLite.eval(data, r'$..name'), ['a', 'b']);
      expect(JsonPathLite.eval(data, r'$.missing.deep'), isNull);
    });
  });

  group('LegadoDom CSS', () {
    const html = '''
      <ul>
        <li class="book-li">
          <div class="book-cover"><img data-src="https://img/x.jpg"></div>
          <h3 class="book-title">  魔女的夜宴 </h3>
          <div class="book-author">作者 <span>张三</span></div>
          <p class="book-desc">简介文字</p>
          <a href="/novel/123.html">link</a>
        </li>
      </ul>''';
    test('selects and extracts like jsoup rules', () {
      final doc = LegadoDom.parseHtml(html);
      final items = LegadoDom.queryAll(doc, '.book-li');
      expect(items, hasLength(1));
      final item = items.single;
      expect(
        LegadoDom.extract(
          LegadoDom.queryFirst(item, '.book-title')!,
          'text',
        ),
        '魔女的夜宴',
      );
      expect(
        LegadoDom.extract(
          LegadoDom.queryFirst(item, '.book-cover > img')!,
          'data-src',
        ),
        'https://img/x.jpg',
      );
      expect(
        LegadoDom.extract(LegadoDom.queryFirst(item, 'a')!, 'href'),
        '/novel/123.html',
      );
      final (selector, attr) =
          LegadoDom.splitSelectorAttr('.book-author@ownText');
      expect(selector, '.book-author');
      expect(attr, 'ownText');
      expect(
        LegadoDom.extract(LegadoDom.queryFirst(item, selector)!, attr),
        '作者',
      );
    });

    test('serializes a document for the JS bridge', () {
      final doc = LegadoDom.parseHtml(html);
      final serialized = LegadoDom.serializeDocument(doc);
      final encoded = jsonEncode(serialized);
      expect(encoded, contains('book-li'));
      expect(encoded, contains('data-src'));
    });
  });

  // Batch 59: the app no longer bundles these sources;
  // the recorded definitions live on as test fixtures.
  group('recorded liruohrh definitions (fixtures)', () {
    test('both sources parse with their rules intact', () async {
      final biliText =
          await File('test/fixtures/bilinovel.json').readAsString();
      final bili = LegadoSourceDef.fromJson(
        LegadoParse.parseSourceArray(biliText).single,
        builtin: true,
      )!;
      expect(bili.name, contains('哔哩哔哩轻小说'));
      expect(bili.ruleSearch['bookList'], '@css:.book-li');
      expect(bili.ruleToc['chapterList'], contains('getElements'));
      expect(bili.jsLib, contains('HashMap'));
      expect(bili.exploreCategories.length, greaterThan(5));
      expect(
        bili.exploreCategories.first.url,
        contains('monthvisit'),
      );

      final dumanText =
          await File('test/fixtures/dumanwu.json').readAsString();
      final duman = LegadoSourceDef.fromJson(
        LegadoParse.parseSourceArray(dumanText).single,
        builtin: true,
      )!;
      expect(duman.name, '读漫屋');
      expect(duman.ruleSearch['bookList'], r'$.data');
      expect(duman.ruleSearch['bookUrl'], contains('<js>'));
      expect(duman.exploreCategories, isEmpty);
    });
  });

  group('novel relevance ranking', () {
    test('exact beats contains; strict drops unrelated', () {
      expect(novelRelevanceScore('魔女的夜宴', '魔女的夜宴'), 0);
      // Season markers are stripped: a season-2 anime title
      // matches the base novel exactly.
      expect(novelRelevanceScore('魔女的夜宴 第二季', '魔女的夜宴'), 0);
      expect(novelRelevanceScore('魔女的夜宴', '魔女的夜宴外传'), 1);
      expect(novelRelevanceScore('夜宴', '魔女的夜宴'), 2);
      expect(novelRelevanceScore('斗破苍穹', '魔女的夜宴'), 3);
    });
  });

  test('legado: url spec classification', () {
    final js = LegadoParse.classifyUrlSpec('@js:url=baseUrl+"/so/{{key}}.html"');
    expect(js.kind, 'js');
    expect(js.body, startsWith('url=baseUrl'));
    final embedded = LegadoParse.classifyUrlSpec(
      "<js>/modules/article/search.php,{'charset':'gbk','method':'POST'};result='';result;</js>",
    );
    expect(embedded.kind, 'literal');
    expect(embedded.body, startsWith('/modules/article/search.php'));
    expect(embedded.body, contains("'charset':'gbk'"));
    final realJs = LegadoParse.classifyUrlSpec(
      '<js>if(java.ajax(baseUrl).match(/x/)){result=1}result;</js>',
    );
    expect(realJs.kind, 'js');
    final plain = LegadoParse.classifyUrlSpec('/search/?q={{key}}');
    expect(plain.kind, 'literal');
    expect(plain.body, '/search/?q={{key}}');
  });

  test('gb2312: codec vectors and form encoding', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Gb2312.ensureLoaded();
    // 斗罗大陆 in GB2312 bytes.
    const bytes = [
      0xB6, 0xB7, 0xC2, 0xDE, 0xB4, 0xF3, 0xC2, 0xBD,
    ];
    expect(Gb2312.decode(bytes), '斗罗大陆');
    expect(Gb2312.encode('斗罗大陆'), bytes);
    expect(
      Gb2312.percentEncodeNonAscii('searchkey=斗罗大陆&type=all'),
      'searchkey=%B6%B7%C2%DE%B4%F3%C2%BD&type=all',
    );
    expect(Gb2312.decode([0x41, 0xB6, 0xB7, 0x42]), 'A斗B');
  });

  test('legado: selector chains (class/tag/id shorthand)', () {
    final doc = LegadoDom.parseHtml('''
<html><body>
<div class="bookbox"><a href="/b1">书一</a><span class="author">甲</span></div>
<div class="bookbox"><a href="/b2">书二</a><span class="author">乙</span></div>
<table><tbody><tr><td>x</td><td><a href="/b3">书三</a></td></tr>
<tr><td>y</td><td><a href="/b4">书四</a></td></tr></tbody></table>
</body></html>''');
    expect(LegadoDom.selectChain(doc, 'class.bookbox').length, 2);
    final (authorEls, authorAttr) =
        LegadoDom.fieldElements(doc, 'class.author.1@text');
    expect(authorAttr, 'text');
    expect(LegadoDom.extract(authorEls.first, authorAttr), '乙');
    // tbody chain: first tbody, then all its rows
    expect(LegadoDom.selectChain(doc, 'tag.tbody.0@tag.tr').length, 2);
    final (linkEls, linkAttr) =
        LegadoDom.fieldElements(doc, 'class.bookbox@tag.a.0@href');
    expect(linkAttr, 'href');
    expect(LegadoDom.extract(linkEls.first, linkAttr), '/b1');
    // plain CSS with numeric step index
    expect(LegadoDom.selectChain(doc, 'div.bookbox.1').length, 1);
    // bare trailing token falls back to a tag step when the
    // attr reading matches nothing
    final (tdEls, tdAttr) = LegadoDom.fieldElements(doc, 'tag.tr.0@td');
    expect(tdAttr, '');
    expect(tdEls.length, 2);
  });

  test('legado: webView flag detection on chapter url specs', () {
    expect(
      LegadoParse.urlRequestsWebView(
          'https://m.example.com/1/2.html,{"webView": true}'),
      isTrue,
    );
    expect(
      LegadoParse.urlRequestsWebView('https://m.example.com/1/2.html'),
      isFalse,
    );
    expect(
      LegadoParse.urlRequestsWebView(
          'https://m.example.com/1/2.html,{"webView": false}'),
      isFalse,
    );
  });
}
