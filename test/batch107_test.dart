// Batch 107: foreign anime-source formats at the rule
// importer.
//  1. A TVBox config's type-1 (MacCMS JSON API) sites
//     convert to api-mode rules carrying the fixed
//     protocol mapping; type 0/3/4 and broken entries are
//     per-site skips with reasons, never whole-file noise.
//  2. The converted rule parses real MacCMS-shaped
//     responses end to end at the strategy layer: search
//     items, then delimited roads/episodes from a detail
//     payload.
//  3. PluginImportParser routes a TVBox file to the
//     converter, a Legado package to a named guidance
//     failure, and leaves Kazumi rule files untouched.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/plugins/api_rule_config.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/services/plugin/api_rule_strategy.dart';
import 'package:anikumo/services/plugin/plugin_import_parser.dart';
import 'package:anikumo/services/plugin/external_config_import.dart';

const _tvboxConfig = {
  'spider': 'https://example.com/spider.jar',
  'sites': [
    {
      'key': 'cms_a',
      'name': '示例资源A',
      'type': 1,
      'api': 'https://a.example.com/api.php/provide/vod/',
      'searchable': 1,
    },
    {
      'key': 'cms_b',
      'name': '示例资源B',
      'type': 1,
      'api': 'https://b.example.com/inc/apijson_vod.php',
      'header': {'User-Agent': 'okhttp/4.0'},
    },
    {'key': 'xml_c', 'name': '示例XML', 'type': 0, 'api': 'https://c.example.com/xml'},
    {'key': 'drpy_d', 'name': '示例爬虫', 'type': 3, 'api': 'https://d.example.com/drpy.js'},
    {'key': 'broken', 'name': '', 'type': 1, 'api': ''},
  ],
  'lives': [],
};

void main() {
  group('convertExternalSiteConfig', () {
    final conversion = convertExternalSiteConfig(_tvboxConfig);

    test('converts the two JSON-API sites, skips the rest with reasons', () {
      expect(conversion.plugins.map((p) => p.name), ['示例资源A', '示例资源B']);
      expect(conversion.skipped, hasLength(3));
      expect(conversion.skipped.join(), contains('XML 接口'));
      expect(conversion.skipped.join(), contains('爬虫'));
      expect(conversion.skipped.join(), contains('缺少名称或接口地址'));
    });

    test('converted rule carries the MacCMS api-mode mapping', () {
      final plugin = conversion.plugins.first;
      expect(plugin.searchMode, RuleMode.api);
      expect(plugin.chapterMode, RuleMode.api);
      expect(
        plugin.searchApiConfig.request.url,
        'https://a.example.com/api.php/provide/vod/?ac=videolist&wd=@keyword',
      );
      expect(plugin.searchApiConfig.listPath, r'$.list[*]');
      expect(plugin.searchApiConfig.namePath, r'$.vod_name');
      expect(plugin.searchApiConfig.sourcePath, r'$.vod_id');
      final chapters = plugin.chapterApiConfig;
      expect(
        chapters.request.url,
        'https://a.example.com/api.php/provide/vod/?ac=detail&ids=@source',
      );
      expect(chapters.format, ApiChapterFormat.delimited);
      expect(chapters.roadNamesPath, r'$.list[0].vod_play_from');
      expect(chapters.roadEpisodesPath, r'$.list[0].vod_play_url');
      expect(chapters.roadSeparator, r'$$$');
      expect(chapters.episodeSeparator, '#');
      expect(chapters.fieldSeparator, r'$');
      expect(plugin.baseUrl, 'https://a.example.com/');
    });

    test('site headers land on both requests', () {
      final plugin = conversion.plugins[1];
      expect(
        plugin.searchApiConfig.request.headers['User-Agent'],
        'okhttp/4.0',
      );
      expect(
        plugin.chapterApiConfig.request.headers['User-Agent'],
        'okhttp/4.0',
      );
    });
  });

  group('converted rule against MacCMS-shaped payloads', () {
    const strategy = ApiRuleStrategy();
    final plugin = convertExternalSiteConfig(_tvboxConfig).plugins.first;

    test('search parses list items (numeric vod_id stringified)', () {
      const raw = '{"code":1,"msg":"数据列表","page":1,"list":['
          '{"vod_id":1234,"vod_name":"示例动画 第一季","vod_remarks":"更新至第3集"},'
          '{"vod_id":5678,"vod_name":"示例动画 第二季","vod_remarks":"全24集"}'
          ']}';
      final result = strategy.parseSearch(raw, plugin.searchApiConfig);
      expect(result.items.map((e) => e.name), ['示例动画 第一季', '示例动画 第二季']);
      expect(result.items.map((e) => e.src), ['1234', '5678']);
    });

    test('chapters split play sources into roads and episodes', () {
      const detail = {
        'code': 1,
        'list': [
          {
            'vod_id': 1234,
            'vod_name': '示例动画 第一季',
            'vod_play_from': r'线路甲$$$线路乙',
            'vod_play_url': '第1集\$https://cdn.example.com/a/1.m3u8'
                '#第2集\$https://cdn.example.com/a/2.m3u8'
                r'$$$第1集$https://cdn.example.com/b/1.m3u8',
          },
        ],
      };
      final result = strategy.parseChapters(
        jsonEncode(detail),
        plugin.chapterApiConfig,
        source: '1234',
        baseUrl: plugin.baseUrl,
      );
      expect(result.roads, hasLength(2));
      expect(result.roads[0].name, '线路甲');
      expect(result.roads[0].identifier, ['第1集', '第2集']);
      expect(
        result.roads[0].data,
        [
          'https://cdn.example.com/a/1.m3u8',
          'https://cdn.example.com/a/2.m3u8',
        ],
      );
      expect(result.roads[1].name, '线路乙');
      expect(result.roads[1].data.single,
          'https://cdn.example.com/b/1.m3u8');
    });

    test('prepared requests render the protocol URLs', () {
      final search = strategy.prepareRequest(
        plugin.searchApiConfig.request,
        {'keyword': '动画'},
      );
      expect(
        search.url,
        'https://a.example.com/api.php/provide/vod/'
        '?ac=videolist&wd=${Uri.encodeComponent('动画')}',
      );
      final chapters = strategy.prepareRequest(
        plugin.chapterApiConfig.request,
        {'source': '1234'},
      );
      expect(
        chapters.url,
        'https://a.example.com/api.php/provide/vod/?ac=detail&ids=1234',
      );
    });
  });

  group('PluginImportParser routing', () {
    test('a TVBox file imports its convertible sites', () {
      final result = PluginImportParser.parse(jsonEncode(_tvboxConfig));
      expect(result.plugins.map((p) => p.name), ['示例资源A', '示例资源B']);
      expect(result.failures.join(), contains('已跳过'));
    });

    test('a Legado video package gets named guidance, not rule errors', () {
      final legado = jsonEncode([
        {
          'bookSourceName': '示例视频源',
          'bookSourceUrl': 'https://example.com',
          'searchUrl': 'https://example.com/search?q={{key}}',
          'ruleSearch': {'bookList': '.item', 'name': '.name'},
          'ruleVideo': {'episodeList': '.ep', 'playUrl': '.play'},
        },
      ]);
      final result = PluginImportParser.parse(legado);
      expect(result.plugins, isEmpty);
      expect(result.failures.single, contains('视频书源格式'));
    });

    test('a Legado book package points at the novel/manga zones', () {
      final legado = jsonEncode([
        {
          'bookSourceName': '示例书源',
          'bookSourceUrl': 'https://example.com',
          'searchUrl': 'https://example.com/search?q={{key}}',
          'ruleSearch': {'bookList': '.item', 'name': '.name'},
        },
      ]);
      final result = PluginImportParser.parse(legado);
      expect(result.plugins, isEmpty);
      expect(result.failures.single, contains('小说区或漫画区'));
    });

    test('no user-facing string names an origin format (batch 108)', () {
      final result = PluginImportParser.parse(jsonEncode(_tvboxConfig));
      final allText = [
        ...result.failures,
        for (final p in result.plugins) p.version,
      ].join();
      for (final brand in ['TVBox', 'Legado', 'MacCMS', '苹果CMS']) {
        expect(allText, isNot(contains(brand)), reason: brand);
      }
      expect(result.plugins.first.version, isEmpty);
    });

    test('a Kazumi rule file still parses as before', () {
      final rule = jsonEncode([
        {
          'api': '5',
          'type': 'anime',
          'name': '示例规则',
          'baseURL': 'https://example.com/',
          'searchURL': 'https://example.com/s/@keyword',
          'searchList': '//div',
          'searchName': '//a',
          'searchResult': '//a/@href',
          'chapterRoads': '//ul',
          'chapterResult': '//a',
        },
      ]);
      final result = PluginImportParser.parse(rule);
      expect(result.plugins.single.name, '示例规则');
      expect(result.failures, isEmpty);
    });

    test('a converted plugin survives the persistence round trip', () {
      final plugin = convertExternalSiteConfig(_tvboxConfig).plugins.first;
      final restored = Plugin.fromJson(
        jsonDecode(jsonEncode(plugin.toJson())) as Map<String, dynamic>,
      );
      expect(restored.name, plugin.name);
      expect(restored.searchMode, RuleMode.api);
      expect(restored.chapterApiConfig.format, ApiChapterFormat.delimited);
      expect(
        restored.chapterApiConfig.roadEpisodesPath,
        r'$.list[0].vod_play_url',
      );
    });
  });
}
