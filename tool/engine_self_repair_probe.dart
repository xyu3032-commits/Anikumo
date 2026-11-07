// Batch 43 local verification (no external site): a source
// call is IN FLIGHT when the shared engine isolate is
// killed (what another source's 40 s timeout does). Before
// the self-repair, that call died with "JS 引擎已重置" even
// though a fresh isolate serves the same call fine. Now
// the engine re-registers and retries once, internally.
//
// Run: LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/engine_self_repair_probe.dart
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

  late HttpServer server;
  late int port;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('repair_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      // Slow enough that the kill lands mid-flight.
      await Future<void>.delayed(const Duration(seconds: 2));
      request.response.write('{"ok": true}');
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('in-flight call survives a host kill via internal retry',
      () async {
    final code = '''
class RepairProbe extends ComicSource {
  name = "RepairProbe";
  key = "repair_probe";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";

  explore = [
    {
      title: "probe",
      type: "singlePageWithMultiPart",
      load: async (page) => {
        const res = await Network.get("http://127.0.0.1:$port/slow", {});
        if (res.status !== 200) throw "status " + res.status;
        return { "part": [{ id: "1", title: "survived", cover: "", tags: [] }] };
      },
    },
  ];
}
''';
    final engine = VeneraEngine(sourceKey: 'repair_probe', code: code);
    // Warm registration so the kill hits the CALL, not setup.
    await engine.ensureInitialized();

    final future = engine.call('explore', {'page': 1});
    // Let the request get going, then kill the host exactly
    // like another source's timeout would.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    QjsEngineHost.instance.kill();

    final explore = await future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw StateError('call never settled'),
    );
    expect(explore, isA<Map>());
    final part = (explore as Map)['part'] as List;
    expect((part.single as Map)['title'], 'survived');
  });
}
