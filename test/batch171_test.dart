// Batch 171: diagnostics evidence for short chapter
// lists — the engine keeps the raw fetched bodies while
// the diagnostics page runs (debugCapture), and the page
// quotes a compacted excerpt of the directory response.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/pages/novel/novel_diagnostics_page.dart';
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
    final dir = await Directory.systemTemp.createTemp('b171_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      if (req.uri.path == '/directory') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': {
            'chapterListWithVolume': [
              [
                {'title': '唯一章', 'itemId': 'c1'},
              ],
            ],
          },
        }));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  setUp(() {
    LegadoEngine.debugCapture = false;
    LegadoEngine.debugBodies.clear();
  });

  tearDown(() {
    LegadoEngine.debugCapture = false;
    LegadoEngine.debugBodies.clear();
  });

  LegadoSourceDef tocDef() => LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': base,
        'ruleToc': {
          'chapterList': r'$.data.chapterListWithVolume[*][*]',
          'chapterName': r'$.title',
          'chapterUrl': '$base/reader/{{' r'$.itemId}}',
        },
      })!;

  group('engine capture (batch 171)', () {
    test('records the TOC body while enabled, nothing while disabled',
        () async {
      final item = NovelItem(bookUrl: '$base/directory', title: '示例之书');
      await LegadoEngine(tocDef()).chapters(item);
      expect(LegadoEngine.debugBodies, isEmpty);

      LegadoEngine.debugCapture = true;
      final chapters = await LegadoEngine(tocDef()).chapters(item);
      expect(chapters.length, 1);
      final body = LegadoEngine.debugBodies['$base/directory'];
      expect(body, isNotNull);
      expect(body, contains('chapterListWithVolume'));
    });
  });

  group('debugTocExcerpt (batch 171)', () {
    test('prefers the directory body and compacts whitespace', () {
      final excerpt = debugTocExcerpt({
        '$base/search': '{"a":  1}',
        '$base/api/reader/directory/detail?bookId=1':
            '{\n  "data":   [1,\n2]\n}',
        '$base/reader/1': '<p>x</p>',
      });
      expect(excerpt, '{ "data": [1, 2] }');
    });

    test('falls back to the latest body and truncates', () {
      final excerpt = debugTocExcerpt(
        {'$base/a': 'x' * 40},
        limit: 10,
      );
      expect(excerpt, '${'x' * 10}…');
    });

    test('empty map yields empty excerpt', () {
      expect(debugTocExcerpt(const {}), '');
    });
  });
}
