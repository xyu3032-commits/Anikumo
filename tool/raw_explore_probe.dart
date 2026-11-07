import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';
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
    final dir = await Directory.systemTemp.createTemp('rawexp');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  for (final key in ['wnacg', 'copy_manga']) {
    test('$key raw explore', () async {
      final code = await File('/tmp/plaza/$key.js').readAsString();
      final engine = VeneraEngine(sourceKey: key, code: code);
      final result = await engine.call('explore', {'page': 1});
      print('== $key type=${result.runtimeType}');
      final text = result.toString();
      print('== $key head: ${text.substring(0, text.length > 300 ? 300 : text.length)}');
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
