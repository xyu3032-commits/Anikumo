// Batch 167: subscription (RSS-format) sources — entry
// classification, import routing, and the article engine
// driven by fixture pages (no network).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/services/novel/novel_sources.dart';
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

const _rssEntry = {
  'sourceName': '示例订阅',
  'sourceUrl': 'https://example.com/feed',
  'ruleArticles': 'ul li',
  'ruleTitle': 'h3',
  'ruleLink': 'a@href',
};

const _bookEntry = {
  'bookSourceName': '示例书源',
  'bookSourceUrl': 'https://books.example.com',
  'searchUrl': 'https://books.example.com/s?q={{key}}',
  'ruleSearch': {'bookList': r'$.data[*]', 'name': r'$.name'},
};

void main() {
  group('classification', () {
    test('rss entries classify by sourceName/sourceUrl', () {
      expect(isRssSourceEntry(_rssEntry), isTrue);
      expect(isRssSourceEntry(_bookEntry), isFalse);
      expect(isRssSourceEntry({'sourceName': 'x'}), isFalse);
      expect(
        isRssSourceEntry({..._rssEntry, 'bookSourceName': '兼有'}),
        isFalse,
      );
      // A foreign book format that names itself with
      // sourceName but CAN search stays a book source.
      expect(
        isRssSourceEntry({
          'sourceName': '外来书源',
          'sourceUrl': 'https://x.example.com',
          'searchUrl': 'https://x.example.com/s?q={{key}}',
        }),
        isFalse,
      );
    });

    test('foreign pack magic is detected', () {
      expect(isForeignPackPayload('@header:v1binary'), isTrue);
      expect(isForeignPackPayload('  @header:v1'), isTrue);
      expect(isForeignPackPayload('[{"a":1}]'), isFalse);
    });

    test('probe counts rss entries and foreign packs', () {
      final probe = NovelSources.probeImport(
        jsonEncode([_rssEntry, _bookEntry]),
      );
      expect(probe.entries, 2);
      expect(probe.rss, 1);
      expect(probe.recognized, 1);
      final packProbe = NovelSources.probeImport('@header:v1xyz');
      expect(packProbe.foreignPack, isTrue);
      expect(packProbe.entries, 0);
    });
  });

  group('sortUrl parsing', () {
    test('name::url lines and && separators', () {
      final out = RssEngine.parseSortUrlText(
        '最新::/new\n热门::https://example.com/hot&&排行::/rank',
        'https://example.com/feed',
      );
      expect(out.length, 3);
      expect(out[0], ('最新', 'https://example.com/new'));
      expect(out[2].$2, 'https://example.com/rank');
    });
  });

  group('article engine (fixtures)', () {
    test('DOM list rules extract title/link/date', () async {
      final def = RssSourceDef({
        ..._rssEntry,
        'rulePubDate': '.d',
        'ruleDescription': '.s',
      });
      const body = '''
<ul>
  <li><h3>第一篇</h3><a href="/a1">link</a><span class="d">2026-01-01</span><p class="s">摘要一</p></li>
  <li><h3>第二篇</h3><a href="https://example.com/a2">link</a><span class="d">2026-01-02</span><p class="s">摘要二</p></li>
</ul>''';
      final articles = await RssEngine.articlesFromBody(
        def,
        body,
        'https://example.com/feed',
        const {},
      );
      expect(articles.length, 2);
      expect(articles[0].title, '第一篇');
      expect(articles[0].link, 'https://example.com/a1');
      expect(articles[0].pubDate, '2026-01-01');
      expect(articles[1].description, '摘要二');
    });

    test('JSON list rules with bare-key fields', () async {
      final def = RssSourceDef({
        'sourceName': '示例聚合',
        'sourceUrl': 'https://example.com/api',
        'ruleArticles': r'$.items[*]',
        'ruleTitle': 'name',
        'ruleLink': 'url',
      });
      final body = jsonEncode({
        'items': [
          {'name': '甲', 'url': '/x1'},
          {'name': '乙', 'url': '/x2'},
        ],
      });
      final articles = await RssEngine.articlesFromBody(
        def,
        body,
        'https://example.com/api',
        const {},
      );
      expect(articles.map((a) => a.title), ['甲', '乙']);
      expect(articles[1].link, 'https://example.com/x2');
    });

    test('content rule splits paragraphs', () async {
      final def = RssSourceDef({
        ..._rssEntry,
        'ruleContent': '.article',
      });
      const body =
          '<div class="article"><p>第一段。</p><p>第二段。</p></div>';
      final paragraphs = await RssEngine.contentFromBody(
        def,
        body,
        'https://example.com/a1',
        const {},
      );
      expect(paragraphs, ['第一段。', '第二段。']);
    });

    test('map headers pass through', () async {
      final def = RssSourceDef({
        ..._rssEntry,
        'header': {'User-Agent': 'X/1.0', 'Referer': 'https://example.com/'},
      });
      final headers = await RssEngine.headersOf(def);
      expect(headers['User-Agent'], 'X/1.0');
    });
  });

  group('import routing (storage)', () {
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('batch167');
      PathProviderPlatform.instance = _TestPaths(dir.path);
      Hive.init(dir.path);
      await GStorage.init();
    });

    test('mixed payload splits book and rss, dedupes on reimport', () async {
      final payload = jsonEncode([_bookEntry, _rssEntry, {
        'sourceName': '示例目录',
        'sourceUrl': 'http://yck.example.com',
        'singleUrl': true,
      }]);
      final (book, rss) = await NovelSources.importFromTextSplit(payload);
      expect(book, 1);
      expect(rss, 2);
      expect(NovelSources.all().length, 1);
      expect(RssSources.all().length, 2);
      final ruleLess = RssSources.byId('http://yck.example.com');
      expect(ruleLess?.hasArticleRules, isFalse);
      final (book2, rss2) = await NovelSources.importFromTextSplit(payload);
      expect((book2, rss2), (0, 0));
      await RssSources.remove('https://example.com/feed');
      expect(RssSources.all().length, 1);
    });
  });
}
