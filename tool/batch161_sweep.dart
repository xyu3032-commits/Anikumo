// ignore_for_file: avoid_print
// Batch 161 sweep (desktop QuickJS + local HTTP only):
// run explore (first URL category) and search for EVERY
// source in the 1332 bundle against a local server, and
// report any failure mentioning "private name" — hunting
// the construct behind the device report "书源 JS 报错：
// invalid first character of private name" on every
// category of the QQ阅读标签 source.
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

const payload = {
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
    'list': [
      {'name': '测试之书', 'author': '作者甲', 'id': 7},
    ],
    'state': [
      {
        'dataName': 'novel_search_list',
        'items': [
          {
            'docId': '888_424242',
            'title': '测试之书',
            'author': '作者甲',
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
  'books': [
    {'name': '测试之书', 'author': '作者甲', 'bookId': 5},
  ],
  'list': [
    {'name': '测试之书', 'author': '作者甲', 'id': 3},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late HttpServer server;
  late String base;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b161_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(payload));
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('bundle sweep', () async {
    final raw = await File(
      '/home/hatch/workspace/novel_source_fix/src1332.json',
    ).readAsString();
    final list = jsonDecode(raw) as List;
    var privateNameHits = 0;
    var otherErrors = 0;
    var ok = 0;
    for (final entry in list) {
      final def = LegadoSourceDef.fromJson(
        Map<String, dynamic>.from(entry as Map),
      );
      if (def == null) continue;
      final engine = LegadoEngine(def);
      String rewrite(String u) =>
          u.replaceAll(RegExp(r'https?://[^/,}\s]+'), base);
      // Explore: first category with a URL.
      final cats =
          def.exploreCategories.where((c) => c.url.isNotEmpty).toList();
      if (cats.isNotEmpty) {
        try {
          await engine.explore(
            NovelExploreCategory(
              title: cats.first.title,
              url: rewrite(cats.first.url),
            ),
          );
          ok++;
        } catch (e) {
          final msg = e.toString();
          if (msg.contains('private name')) {
            privateNameHits++;
            print('PRIVATE-NAME [explore] ${def.name}: $msg');
          } else {
            otherErrors++;
          }
        }
      }
      // Search.
      if (def.searchUrl.isNotEmpty) {
        try {
          // searchUrl lives on the def; engine.search uses
          // it verbatim — rewrite via a copied def is not
          // available, so search is only probed when the
          // URL is relative or already local. Skip: explore
          // is the reported surface.
        } catch (_) {}
      }
    }
    print('SWEEP DONE ok=$ok privateName=$privateNameHits other=$otherErrors');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
