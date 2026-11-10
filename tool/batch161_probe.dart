// ignore_for_file: avoid_print
// Batch 161 probe (desktop QuickJS + local HTTP only):
// reproduce the QQ阅读标签 explore failure — every榜单
// category errors with QuickJS "invalid first character
// of private name". The source def is loaded from
// QQ_TAG_DEF (a JSON file with the single source object);
// its category URLs are rewritten to a local server that
// answers a QQ-rank-shaped JSON payload.
import 'dart:convert';
import 'dart:io';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_engine.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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
  final seen = <String>[];

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b161_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      seen.add('${req.method} ${req.uri}');
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'rows': [
          {
            'resourceID': 424242,
            'resourceName': '测试之书',
            'author': '作者甲',
            'picurl': 'http://img.example/cover.jpg',
            'summary': '简介文本',
            'lastSerialname': '第9章 转折',
            'lastUpdatetime': 1700000000,
            'subject': '玄幻',
            'subtype': '东方玄幻',
          },
        ],
        'data': {
          'state': [
            {
              'dataName': 'novel_search_list',
              'items': [
                {
                  'docId': '888_424242',
                  'title': '测试之书',
                  'cover_url': 'http://img.example/cover.jpg',
                  'abstract': '简介文本',
                  'label_text': '标签',
                  'tag_views': '玄幻',
                  'is_finished': 0,
                },
              ],
            },
          ],
        },
      }));
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('qq tag explore repro', () async {
    final defPath = Platform.environment['QQ_TAG_DEF'] ?? '';
    final raw = await File(defPath).readAsString();
    final parsed = jsonDecode(raw);
    final map = parsed is List ? parsed.first : parsed;
    final def = LegadoSourceDef.fromJson(
      Map<String, dynamic>.from(map as Map),
    )!;
    print('SOURCE: ${def.name} url=${def.url}');
    print('jsLib length: ${def.jsLib?.length ?? -1}');
    final cats = def.exploreCategories
        .where((c) => c.url.isNotEmpty)
        .toList();
    print('categories with url: ${cats.length}');
    for (final c in cats.take(8)) {
      print('  CAT ${c.title} -> ${c.url.substring(0, c.url.length > 110 ? 110 : c.url.length)}');
    }
    final engine = LegadoEngine(def);
    // Rewrite the first category's URL host to the local
    // server so no real site is touched.
    final cat = cats.first;
    final rewritten = cat.url.replaceAll(
      RegExp(r'https?://[^/,}]+'),
      base,
    );
    print('REWRITTEN: $rewritten');
    try {
      final books = await engine.explore(
        NovelExploreCategory(title: cat.title, url: rewritten),
      );
      print('BOOKS: ${books.length}');
      for (final b in books) {
        print('  BOOK ${b.title} | ${b.author} | ${b.bookUrl}');
      }
    } catch (e, st) {
      print('EXPLORE ERROR: $e');
      print(st.toString().split('\n').take(6).join('\n'));
    }
    print('SEEN: $seen');
  });
}
