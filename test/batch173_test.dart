// Batch 173: dynamic explore categories (the study's
// D6). Script exploreUrls are EVALUATED into kinds —
// group headers, layout styles, templated URLs — instead
// of the script being read as one bogus category whose
// "URL" was the script itself; infoMap persists across
// runs of a source's host.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_engine.dart';
import 'package:anikumo/services/novel/legado_js.dart';
import 'package:anikumo/services/novel/novel_source.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

/// A dynamic-explore source in the shape of the failing
/// one: the exploreUrl script builds group headers plus
/// items whose URLs carry a login-filter template, sized
/// via style hints (fixtures are synthetic; no real
/// source is bundled).
Map<String, dynamic> dynamicDef() => {
      'bookSourceName': '动态分类源',
      'bookSourceUrl': 'https://dyn.example.com',
      'bookSourceType': 0,
      'jsLib': 'function fqFilter(info) { return "&f=" + (info || ""); }',
      'loginUrl': '',
      'exploreUrl': '@js:\n'
          'var groups = [["男生", 1, [["东方仙侠", 1140], ["都市高武", 1014]]], ["女生", 0, [["青春甜宠", 749]]]];\n'
          'var api = "https://dyn.example.com/api/list?page_index={{page-1}}";\n'
          'var out = [];\n'
          'for (var i = 0; i < groups.length; i++) {\n'
          '  var g = groups[i];\n'
          '  out.push({title: g[0], url: "", style: {layout_flexBasisPercent: 1, layout_flexGrow: 1}});\n'
          '  var list = [["全部", -1]].concat(g[2]);\n'
          '  for (var j = 0; j < list.length; j++) {\n'
          '    out.push({title: list[j][0], url: api + "&gender=" + g[1] + "&category_id=" + list[j][1] + "{{fqFilter(source.getLoginInfo())}}", style: {layout_flexGrow: 1, layout_flexBasisPercent: 0.25}});\n'
          '  }\n'
          '}\n'
          'JSON.stringify(out);',
      'searchUrl': '/s/{{key}}',
      'ruleSearch': {'bookList': r'$.data[*]', 'name': r'$.title'},
      'ruleExplore': {'bookList': r'$.data[*]', 'name': r'$.title'},
      'ruleBookInfo': {'name': r'$.name'},
      'ruleToc': {'chapterList': r'$.list[*]', 'chapterName': r'$.t'},
      'ruleContent': {'content': r'$.text'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('anikumo_b173_');
    Hive.init(dir.path);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    await GStorage.init();
  });

  group('batch173 dynamic explore kinds', () {
    test('script exploreUrl evaluates into kinds with headers and styles',
        () async {
      final def = LegadoSourceDef.fromJson(dynamicDef())!;
      final kinds = await LegadoEngine(def).exploreKinds();
      // 2 headers + (全部+2) + (全部+1) items.
      expect(kinds.length, 7);
      expect(kinds[0].title, '男生');
      expect(kinds[0].isHeader, isTrue);
      expect(kinds[0].flexBasis, 1.0);
      expect(kinds[4].title, '女生');
      expect(kinds[4].isHeader, isTrue);
      final items = kinds.where((k) => !k.isHeader).toList();
      expect(items.length, 5);
      expect(items[0].title, '全部');
      expect(items[0].flexBasis, 0.25);
      expect(items[1].url, contains('category_id=1140'));
      expect(items[1].url, contains('{{fqFilter(source.getLoginInfo())}}'));
    });

    test('source wrapper: static reading is bogus, resolved list swaps in',
        () async {
      final source = LegadoNovelSource(
        LegadoSourceDef.fromJson(dynamicDef())!,
      );
      expect(source.hasDynamicExplore, isTrue);
      expect(source.exploreKindsResolved, isFalse);
      // The static fallback is the single bogus entry the
      // old explore page tried to fetch as an address.
      expect(source.exploreCategories.length, 1);
      await source.ensureExploreKinds();
      expect(source.exploreKindsResolved, isTrue);
      expect(source.exploreCategories.length, 7);
      expect(source.exploreCategories.first.isHeader, isTrue);
    });

    test('static sources keep the sync path (no resolution needed)',
        () async {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '静态源',
        'bookSourceUrl': 'https://static.example.com',
        'bookSourceType': 0,
        'exploreUrl': '玄幻::https://static.example.com/xh\n都市::https://static.example.com/ds',
        'searchUrl': '/s/{{key}}',
        'ruleSearch': {'bookList': 'class.item', 'name': 'text'},
      })!;
      final source = LegadoNovelSource(def);
      expect(source.hasDynamicExplore, isFalse);
      expect(source.exploreKindsResolved, isTrue);
      await source.ensureExploreKinds();
      expect(source.exploreCategories.length, 2);
      final kinds = await LegadoEngine(def).exploreKinds();
      expect(kinds.length, 2);
    });

    test('infoMap persists across runs of one host', () async {
      final host = LegadoJsHost.forSource('https://infomap.example.com', '');
      await host.run(code: 'infoMap.marker = "kept";', baseUrl: 'x');
      final out = await host.run(code: 'infoMap.marker', baseUrl: 'x');
      expect(out, 'kept');
    });

    test('kind parser keeps headers, drops untitled entries', () {
      final kinds = NovelExploreCategory.listFromKinds([
        {'title': '组', 'url': '', 'style': {'layout_flexBasisPercent': 1}},
        {'title': '', 'url': 'https://x.example.com'},
        {'title': '项', 'url': 'https://x.example.com/a'},
      ]);
      expect(kinds.length, 2);
      expect(kinds[0].isHeader, isTrue);
      expect(kinds[1].isHeader, isFalse);
    });
  });
}
