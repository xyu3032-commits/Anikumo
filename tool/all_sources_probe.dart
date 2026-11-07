import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/storage/storage.dart';
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

// Batch 37 diagnosis: run EVERY plaza source through the
// production JsMangaSource path (explore first sections +
// search) to find which fail and why — matching the v11
// device screenshots (wnacg "not a function at load
// <eval>:231:26", copy_manga JS empty, ehentai empty).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('allprobe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('all plaza sources explore+search', () async {
    final index =
        (jsonDecode(await File('/tmp/plaza_index.json').readAsString())
                as List)
            .cast<Map<String, dynamic>>();
    for (final entry in index) {
      final fileName = entry['fileName'] as String?;
      final key = entry['key'] as String? ?? '';
      if (fileName == null) continue;
      if (const {'lanraragi', 'komga', 'kavita'}.contains(key)) {
        print('== $fileName: SKIP local-server source');
        continue;
      }
      final file = File('/tmp/plaza/$fileName');
      if (!await file.exists()) {
        print('== $fileName: MISSING FILE');
        continue;
      }
      final code = await file.readAsString();
      final source = JsMangaSource(
        jsKey: key,
        displayName: entry['name'] as String? ?? key,
        version: entry['version'] as String? ?? '',
        fileName: fileName,
        code: code,
      );
      String exploreLine;
      try {
        final items = await source.popular();
        exploreLine = 'popular=${items.length}';
      } catch (e) {
        exploreLine =
            'EXPLORE-ERR>>> ${e.toString().replaceAll('\n', ' | ')}';
      }
      String searchLine;
      try {
        final results = await source.search('海贼王');
        searchLine = 'search=${results.length}';
      } catch (e) {
        searchLine = 'SEARCH-ERR>>> ${e.toString().replaceAll('\n', ' | ')}';
      }
      print('== $fileName [$key]: $exploreLine ; $searchLine');
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}
