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
    final dir = await Directory.systemTemp.createTemp('calib');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('line calibration', () async {
    // The marker call sits on file line 10 (count exactly).
    final code = [
      'class Calib extends ComicSource {', // 1
      '  name = "calib";', // 2
      '  key = "calib";', // 3
      '  explore = [{', // 4
      '    title: "t",', // 5
      '    type: "multiPartPage",', // 6
      '    load: async (page) => {', // 7
      '      let x = null;', // 8
      '      let y = 1;', // 9
      '      return x.missingFn();', // 10
      '    }', // 11
      '  }]', // 12
      '}', // 13
    ].join('\n');
    final engine = VeneraEngine(sourceKey: 'calib', code: code);
    try {
      await engine.call('explore', {'page': 1});
      print('== no error?!');
    } catch (e) {
      print('== ERR>>> ${e.toString().replaceAll('\n', ' | ')}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
