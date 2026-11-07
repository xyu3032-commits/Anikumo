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
    final dir = await Directory.systemTemp.createTemp('wnacg');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  for (final key in ['ehentai']) {
    test('$key first error', () async {
      final fileName = {'ehentai': 'ehentai.js'}[key]!;
      final code = await File('/tmp/plaza/$fileName').readAsString();
      final source = JsMangaSource(
        jsKey: key,
        displayName: key,
        version: '',
        fileName: fileName,
        code: code,
      );
      try {
        final items = await source.popular();
        print('== $key popular=${items.length}');
      } catch (e) {
        print('== $key ERR>>> ${e.toString().replaceAll('\n', ' | ')}');
      }
      try {
        final results = await source.search('test');
        print('== $key search=${results.length}');
      } catch (e) {
        print('== $key SEARCH-ERR>>> ${e.toString().replaceAll('\n', ' | ')}');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
