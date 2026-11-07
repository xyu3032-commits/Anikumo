// Batch 34 live check: drive the NEW qjs isolate engine with
// the real plaza sources — register, explore, search, info,
// chapters, pages. This is the first host-fidelity test the
// manga JS layer has ever had (real QuickJS + real bridge,
// not a simulated host).
//
// Run with a locally built plugin library on the path:
//   LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/qjs_engine_live_test.dart
// (build libflutter_qjs_plugin.so from the flutter_qjs
// package's cxx/ sources — see batch 34 notes.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('qjs_live');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('qjs engine: copy_manga full chain', () async {
    final code = await File(
      '/home/hatch/workspace/anikumo_analysis/js_harness/sources/copy_manga.js',
    ).readAsString();
    final engine = VeneraEngine(sourceKey: 'copy_manga', code: code);

    final explore = await engine.call('explore', {'page': 1});
    print('explore type: ${explore.runtimeType}');
    if (explore is Map) {
      print('explore sections: ${explore.keys.toList()}');
      final firstKey = explore.keys.first;
      final list = explore[firstKey];
      print('first section size: ${list is List ? list.length : list}');
    }

    final search = await engine.call('search', {
      'keyword': '海贼王',
      'page': 1,
    });
    print('search type: ${search.runtimeType}');
    if (search is Map && search['comics'] is List) {
      final comics = search['comics'] as List;
      print('search comics: ${comics.length}, first=${comics.firstOrNull}');
    }

    // Full chain on the same engine: info + chapters + pages.
    final info = await engine.call('loadInfo', {'id': 'haizeiwang'});
    if (info is Map && info['chapters'] is Map) {
      final groups = info['chapters'] as Map;
      var total = 0;
      for (final g in groups.values) {
        if (g is Map) total += g.length;
      }
      print('loadInfo chapters total: $total');
      final firstGroup = groups.values.first as Map;
      final firstEp = firstGroup.keys.first.toString();
      final pages = await engine.call('loadEp', {
        'id': 'haizeiwang',
        'ep': firstEp,
      });
      print(
        'loadEp images: ${pages is Map && pages['images'] is List ? (pages['images'] as List).length : pages}',
      );
    } else {
      print('loadInfo unexpected: ${info.runtimeType}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('qjs engine: baozi shares the same runtime', () async {
    // baozi's default mirror (cn.bzmgcn.com) refuses this
    // host's datacenter IP; pick the webmota mirror through
    // the source's own setting, exactly as a user would.
    VeneraEngine.persistKv(
      'baozi',
      '{"data":{},"settings":{"domains":"webmota.com"}}',
    );
    final code = await File(
      '/home/hatch/workspace/anikumo_analysis/js_harness/sources/baozi.js',
    ).readAsString();
    final engine = VeneraEngine(sourceKey: 'baozi', code: code);
    final explore = await engine.call('explore', {'page': 1});
    print('baozi explore type: ${explore.runtimeType}');
    if (explore is Map) {
      print('baozi explore keys: ${explore.keys.toList()}');
    }
    final search = await engine.call('search', {
      'keyword': '斗罗大陆',
      'page': 1,
    });
    if (search is Map && search['comics'] is List) {
      print('baozi search comics: ${(search['comics'] as List).length}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('qjs engine: copy_manga multi-accounts variant', () async {
    final code = await File(
      '/home/hatch/workspace/anikumo_analysis/js_harness/sources/copy_manga_multi_accounts.js',
    ).readAsString();
    final engine = VeneraEngine(
      sourceKey: 'copy_manga_multi_accounts',
      code: code,
    );
    final search = await engine.call('search', {
      'keyword': '海贼王',
      'page': 1,
    });
    if (search is Map && search['comics'] is List) {
      print('multi search comics: ${(search['comics'] as List).length}');
    } else {
      print('multi search unexpected: $search');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
