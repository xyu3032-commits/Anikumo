// Batch 101 local verification (no external site):
// 1. Read calls from ONE source now run concurrently
//    (batch 31's strict per-source queue is gone for reads).
// 2. login/logout stay serialized.
// 3. The timeout liveness probe spares a host that is
//    merely busy (a slow async call in flight).
// 4. The probe kills a truly wedged host (synchronous JS
//    infinite loop) and the wedged call self-heals through
//    the batch-43 retry on the fresh host.
//
// Run: LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/engine_batch101_probe.dart
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
  var slowHits = 0;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('batch101_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      if (request.uri.path == '/slow' ||
          request.uri.path == '/slowlogin') {
        slowHits++;
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      if (request.uri.path == '/slowlogin') {
        // A session-issuing response: the batch-101 GET
        // cache must never store these (cookie rotation).
        request.response.headers.add('Set-Cookie', 'sess=abc; Path=/');
      }
      request.response.write('{"ok": true}');
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  String concCode() => '''
class ConcProbe extends ComicSource {
  name = "ConcProbe";
  key = "conc_probe";
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
        return { "part": [{ id: "1", title: "conc", cover: "", tags: [] }] };
      },
    },
  ];

  account = {
    login: async (username, password) => {
      const res = await Network.get("http://127.0.0.1:$port/slowlogin", {});
      if (res.status !== 200) throw "status " + res.status;
    },
    logout: async () => {},
  };
}
''';

  test('read calls from one source run concurrently', () async {
    final engine = VeneraEngine(sourceKey: 'conc_probe', code: concCode());
    await engine.ensureInitialized();
    final hitsBefore = slowHits;
    final sw = Stopwatch()..start();
    final results = await Future.wait([
      engine.call('explore', {'page': 1}),
      engine.call('explore', {'page': 1}),
    ]);
    sw.stop();
    expect(results, hasLength(2));
    expect(slowHits - hitsBefore, 2);
    // Serialized (the old behaviour) this takes >= 2400 ms;
    // concurrent calls overlap the network wait.
    expect(sw.elapsedMilliseconds, lessThan(2100),
        reason: 'two 1200 ms reads took ${sw.elapsedMilliseconds} ms');
  });

  test('login calls stay serialized', () async {
    final engine = VeneraEngine(sourceKey: 'conc_probe', code: concCode());
    await engine.ensureInitialized();
    final sw = Stopwatch()..start();
    await Future.wait([
      engine.call('login', {'username': 'a', 'password': 'p'}),
      engine.call('login', {'username': 'a', 'password': 'p'}),
    ]);
    sw.stop();
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(2300),
        reason: 'two logins overlapped: ${sw.elapsedMilliseconds} ms');
  });

  test('probe spares a live host with a slow call in flight', () async {
    final engine = VeneraEngine(sourceKey: 'conc_probe', code: concCode());
    await engine.ensureInitialized();
    final gen = QjsEngineHost.instance.generation;
    final future = engine.call('explore', {'page': 1});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final reset = await QjsEngineHost.instance.probeAndKillIfWedged();
    expect(reset, isFalse);
    expect(QjsEngineHost.instance.generation, gen);
    final result = await future;
    expect(result, isA<Map>());
  });

  test('probe kills a wedged host; the call self-heals', () async {
    final code = '''
class WedgeProbe extends ComicSource {
  name = "WedgeProbe";
  key = "wedge_probe";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";

  explore = [
    {
      title: "probe",
      type: "singlePageWithMultiPart",
      load: async (page) => {
        if (this.loadData("w1") === "yes") {
          return { "part": [{ id: "1", title: "healed", cover: "", tags: [] }] };
        }
        this.saveData("w1", "yes");
        while (true) {}
      },
    },
  ];
}
''';
    final engine = VeneraEngine(sourceKey: 'wedge_probe', code: code);
    await engine.ensureInitialized();
    final gen = QjsEngineHost.instance.generation;
    final future = engine.call('explore', {'page': 1});
    // Let the wedge take the thread, then probe.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final reset = await QjsEngineHost.instance.probeAndKillIfWedged();
    expect(reset, isTrue);
    expect(QjsEngineHost.instance.generation, greaterThan(gen));
    // The batch-43 self-repair retries the call on the fresh
    // host; the persisted KV flag makes it return this time.
    final result = await future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw StateError('wedged call never settled'),
    );
    final part = (result as Map)['part'] as List;
    expect((part.single as Map)['title'], 'healed');
  });
}
