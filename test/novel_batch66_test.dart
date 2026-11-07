// Batch 66: foreign book-source formats. The classic
// 阅读 (YueDu) distribution is base64(zlib(JSON)) with
// FLAT rule keys (ruleSearchList / ruleChapterList /
// ruleBookContent), literal searchKey/searchPage
// placeholders, `enable` instead of `enabled`, a string
// bookSourceType （漫画）, and an httpUserAgent field.
// None of it parsed before this batch: the payload decode
// failed silently and the flat keys matched nothing the
// def reads — "imported" sources had no rules at all
// (no search results, no chapters).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_parse.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const yueduEntry = {
  'bookSourceName': '示例漫画源',
  'bookSourceUrl': 'https://m.example.com',
  'bookSourceType': '漫画',
  'enable': true,
  'httpUserAgent': 'Mozilla/5.0 (Test)',
  'ruleSearchUrl':
      'https://m.example.com/search?q=searchKey&page=searchPage',
  'ruleSearchList': 'class.item',
  'ruleSearchName': 'tag.h3@text',
  'ruleSearchAuthor': 'class.au@text',
  'ruleSearchCoverUrl': 'tag.img@data-src',
  'ruleSearchNoteUrl': 'tag.a@href',
  'ruleFindUrl': '最近更新::https://m.example.com/new\r热门::https://m.example.com/hot',
  'ruleBookName': 'class.name@text',
  'ruleBookAuthor': 'class.author@text',
  'ruleCoverUrl': 'tag.img@src',
  'ruleIntroduce': 'class.intro@text',
  'ruleContentUrl': 'tag.a@href',
  'ruleChapterList': 'class.chapters@tag.a',
  'ruleChapterName': 'text',
  'ruleChapterUrl': '',
  'ruleBookContent': 'class.pages@tag.img@src',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('novel_b66');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  group('payload decoding', () {
    test('base64(zlib(JSON)) round-trips', () {
      final payload = jsonEncode([yueduEntry]);
      final wrapped =
          base64Encode(ZLibCodec().encode(utf8.encode(payload)));
      expect(LegadoParse.decodePayload(wrapped), payload);
      expect(LegadoParse.parseSourceArray(wrapped), hasLength(1));
    });

    test('plain base64 JSON decodes', () {
      final payload = jsonEncode([yueduEntry]);
      final wrapped = base64Encode(utf8.encode(payload));
      expect(LegadoParse.parseSourceArray(wrapped), hasLength(1));
    });

    test('BOM + JSONC comments + trailing commas parse', () {
      const text = '\uFEFF[\n'
          '  // a comment\n'
          '  {"bookSourceName": "甲", "bookSourceUrl": "https://x.cn",},\n'
          ']';
      final out = LegadoParse.parseSourceArray(text);
      expect(out, hasLength(1));
      expect(out.single['bookSourceName'], '甲');
    });

    test('wrapper object unwraps', () {
      final text = jsonEncode({'sources': [yueduEntry]});
      expect(LegadoParse.parseSourceArray(text), hasLength(1));
    });
  });

  group('YueDu flat format conversion', () {
    final def = LegadoSourceDef.fromJson(yueduEntry)!;

    test('identity fields map across', () {
      expect(def.name, '示例漫画源');
      expect(def.id, 'https://m.example.com');
      expect(def.type, 2); // 漫画 → image type
      expect(def.headers['User-Agent'], 'Mozilla/5.0 (Test)');
    });

    test('search url placeholders are rewritten', () {
      expect(
        def.searchUrl,
        'https://m.example.com/search?q={{key}}&page={{page}}',
      );
    });

    test('flat rules land in the nested sections', () {
      expect(def.ruleSearch['bookList'], 'class.item');
      expect(def.ruleSearch['bookUrl'], 'tag.a@href');
      expect(def.ruleBookInfo['tocUrl'], 'tag.a@href');
      expect(def.ruleToc['chapterList'], 'class.chapters@tag.a');
      expect(def.ruleContent['content'], 'class.pages@tag.img@src');
    });

    test('find url becomes explore categories (\\r separated)', () {
      expect(
        def.exploreCategories.map((c) => c.title),
        ['最近更新', '热门'],
      );
    });

    test('explore rules fall back to the search rules', () {
      expect(def.ruleExplore['bookList'], 'class.item');
    });
  });

  test('stringified rule sections are parsed back', () {
    final def = LegadoSourceDef.fromJson({
      'bookSourceName': '串化源',
      'bookSourceUrl': 'https://s.example.com',
      'ruleToc': '{"chapterList": ".list", "chapterName": "text"}',
    })!;
    expect(def.ruleToc['chapterList'], '.list');
    expect(def.ruleToc['chapterName'], 'text');
  });

  test('a YueDu payload imports end to end', () async {
    final payload = jsonEncode([yueduEntry]);
    final wrapped =
        base64Encode(ZLibCodec().encode(utf8.encode(payload)));
    final added = await NovelSources.importFromText(wrapped);
    expect(added, 1);
    final source = NovelSources.byId('https://m.example.com');
    expect(source, isNotNull);
    expect(source!.type, 2);
  });

  test('probeImport reports entries / recognized / encrypted', () {
    final probe = NovelSources.probeImport(jsonEncode([
      yueduEntry,
      {'bookSourceName': '缺地址'},
      {
        'bookSourceName': '加密源',
        'bookSourceUrl': 'https://e.example.com',
        'ruleChapterList': ':_H006_abcdef',
      },
    ]));
    expect(probe.entries, 3);
    expect(probe.recognized, 2);
    expect(probe.encrypted, 1);
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
