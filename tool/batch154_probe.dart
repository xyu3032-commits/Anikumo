// Batch 154 local verification (real QuickJS, no external
// site): the init-failure heal.
// 1. A source whose init() fails on a transient network
//    error, then succeeds, heals on the first failing call
//    via a forced clean re-registration — no app restart.
// 2. A source whose init fails benignly while its calls
//    work is left alone (no heal on successful calls).
// 3. A failing call on that benign source pays exactly
//    one heal attempt per cooldown, and the original
//    error still surfaces.
//
// Run: LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/batch154_probe.dart
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
  var flakyHits = 0;
  var initHits = 0;

  setUpAll(() async {
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('batch154_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      switch (request.uri.path) {
        case '/flaky':
          flakyHits++;
          request.response.statusCode =
              flakyHits == 1 ? 500 : 200;
        case '/inithit':
          initHits++;
          request.response.statusCode = 200;
          // The bridge's 5 s GET cache skips responses that
          // set cookies — without this, repeat init probes
          // would be served from memory and the hit counter
          // would under-report re-registrations.
          request.response.headers.add('Set-Cookie', 'probe=1; Path=/');
        default:
          request.response.statusCode = 200;
      }
      request.response.write('{"ok": true}');
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  String healCode() => '''
class HealProbe extends ComicSource {
  name = "HealProbe";
  key = "heal_probe";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";

  init = async () => {
    const res = await Network.get("http://127.0.0.1:$port/flaky", {});
    if (res.status !== 200) throw new Error("flaky " + res.status);
    globalThis.__healReady = true;
  };

  comic = {
    loadInfo: async (id) => {
      if (!globalThis.__healReady) {
        throw new Error("init state missing");
      }
      return { id: id, title: "healed-info" };
    },
  };
}
''';

  String benignCode() => '''
class BenignProbe extends ComicSource {
  name = "BenignProbe";
  key = "benign_probe";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";

  init = async () => {
    await Network.get("http://127.0.0.1:$port/inithit", {});
    throw new Error("benign init failure");
  };

  comic = {
    loadInfo: async (id) => {
      return { id: id, title: "benign-info" };
    },
    loadEp: async (id, ep) => {
      throw new Error("site down");
    },
  };
}
''';

  test('a transiently failed init heals on the first failing call',
      () async {
    final engine =
        VeneraEngine(sourceKey: 'heal_probe', code: healCode());
    await engine.ensureInitialized();
    // Registration "succeeded" even though init failed —
    // exactly the pre-154 wedge: without the heal this
    // source would error for the whole process lifetime.
    expect(flakyHits, 1);
    expect(
      (await QjsEngineHost.instance.initState('heal_probe')).state,
      'failed',
    );
    final result = await engine.call('loadInfo', {'id': 'x'});
    expect((result as Map)['title'], 'healed-info');
    // The heal re-ran init exactly once, against the now
    // healthy endpoint.
    expect(flakyHits, 2);
    expect(
      (await QjsEngineHost.instance.initState('heal_probe')).state,
      'ok',
    );
  });

  test('a benign init failure never disturbs working calls', () async {
    final engine =
        VeneraEngine(sourceKey: 'benign_probe', code: benignCode());
    await engine.ensureInitialized();
    expect(initHits, 1);
    final result = await engine.call('loadInfo', {'id': 'y'});
    expect((result as Map)['title'], 'benign-info');
    // No call failed, so no heal was attempted.
    expect(initHits, 1);
  });

  test('a failing call pays one heal per cooldown; the error surfaces',
      () async {
    final engine =
        VeneraEngine(sourceKey: 'benign_probe', code: benignCode());
    await expectLater(
      engine.call('loadEp', {'id': 'y', 'ep': '1'}),
      throwsA(
        predicate((e) => e.toString().contains('site down')),
      ),
    );
    // One heal attempt: init ran once more, still failed,
    // and the original error surfaced unchanged.
    expect(initHits, 2);
    await expectLater(
      engine.call('loadEp', {'id': 'y', 'ep': '1'}),
      throwsA(
        predicate((e) => e.toString().contains('site down')),
      ),
    );
    // Inside the cooldown: no second re-registration.
    expect(initHits, 2);
  });
}
