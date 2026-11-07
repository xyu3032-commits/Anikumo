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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('fixes');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  for (final entry in [
    ('jm', 'jm.js'),
    ('mh18', 'mh18.js'),
  ]) {
    test('${entry.$1} after batch-37 engine fixes', () async {
      final code = await File('/tmp/plaza/${entry.$2}').readAsString();
      final source = JsMangaSource(
        jsKey: entry.$1,
        displayName: entry.$1,
        version: '',
        fileName: entry.$2,
        code: code,
      );
      try {
        final items = await source.popular();
        print('== ${entry.$1} popular=${items.length}');
      } catch (e) {
        print('== ${entry.$1} EXPLORE-ERR>>> ${e.toString().replaceAll('\n', ' | ')}');
      }
      try {
        final results = await source.search('test');
        print('== ${entry.$1} search=${results.length}');
      } catch (e) {
        print('== ${entry.$1} SEARCH-ERR>>> ${e.toString().replaceAll('\n', ' | ')}');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
