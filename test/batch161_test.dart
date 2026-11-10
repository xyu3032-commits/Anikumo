// Batch 161: device-diagnosis follow-ups —
// 1. the novel HTTP client accepts broken certificate
//    chains like the rest of the app (a self-signed local
//    server must be fetchable),
// 2. ES2022 polyfills in the JS prelude (Array/String at,
//    findLast(Index), Object.hasOwn) — the bundled
//    QuickJS lacks them and sources died with
//    "not a function",
// 3. JS errors thrown by the host carry the failing
//    script's head, so a device report shows WHICH code
//    raised "not a function" / "'sz' is not defined" /
//    "invalid first character of private name".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/services/novel/legado_http.dart';
import 'package:anikumo/services/novel/legado_js.dart';
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

  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('b161_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  group('ES2022 polyfills (batch 161)', () {
    late LegadoJsHost host;
    setUpAll(() {
      host = LegadoJsHost.forSource('b161-poly', null);
    });

    test('Array.prototype.at', () async {
      expect(await host.run(code: '([1, 2, 3].at(-1))', baseUrl: 'http://x/'), 3);
      expect(await host.run(code: '([1, 2, 3].at(0))', baseUrl: 'http://x/'), 1);
      expect(await host.run(code: '([1, 2, 3].at(9))', baseUrl: 'http://x/'), isNull);
    });

    test('String.prototype.at', () async {
      expect(await host.run(code: '("abc".at(-1))', baseUrl: 'http://x/'), 'c');
    });

    test('findLast / findLastIndex / Object.hasOwn', () async {
      expect(
        await host.run(
          code: '([1, 2, 3, 4].findLast(function (v) { return v % 2 === 0; }))',
          baseUrl: 'http://x/',
        ),
        4,
      );
      expect(
        await host.run(
          code: '([1, 2, 3, 4].findLastIndex(function (v) { return v % 2 === 0; }))',
          baseUrl: 'http://x/',
        ),
        3,
      );
      expect(
        await host.run(
          code: '(Object.hasOwn({a: 1}, "a"))',
          baseUrl: 'http://x/',
        ),
        isTrue,
      );
    });
  });

  group('JS error carries the script (batch 161)', () {
    late LegadoJsHost host;
    setUpAll(() {
      host = LegadoJsHost.forSource('b161-err', null);
    });

    test('runtime throw includes the code head', () async {
      Object? caught;
      try {
        await host.run(
          code: '(function () { throw new Error("boom"); })()',
          baseUrl: 'http://x/',
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>());
      final msg = caught.toString();
      expect(msg, contains('boom'));
      expect(msg, contains('脚本：'));
      expect(msg, contains('throw new Error'));
    });

    test('private-name syntax error includes the code head', () async {
      Object? caught;
      try {
        await host.run(code: '#1;', baseUrl: 'http://x/');
      } catch (e) {
        caught = e;
      }
      final msg = caught.toString();
      expect(msg, contains('invalid first character of private name'));
      expect(msg, contains('#1'));
    });

    test('undefined variable error includes the code head', () async {
      Object? caught;
      try {
        await host.run(code: '(sz + 1)', baseUrl: 'http://x/');
      } catch (e) {
        caught = e;
      }
      expect(caught.toString(), contains("'sz' is not defined"));
      expect(caught.toString(), contains('(sz + 1)'));
    });
  });

  group('TLS acceptance (batch 161)', () {
    test('self-signed local server is fetchable', () async {
      final certDir = await Directory.systemTemp.createTemp('b161_cert');
      final gen = await Process.run('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
        '-keyout', '${certDir.path}/key.pem',
        '-out', '${certDir.path}/cert.pem',
        '-days', '1', '-subj', '/CN=localhost',
      ]);
      expect(gen.exitCode, 0, reason: 'openssl: ${gen.stderr}');
      final context = SecurityContext()
        ..useCertificateChain('${certDir.path}/cert.pem')
        ..usePrivateKey('${certDir.path}/key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      server.listen((req) async {
        req.response.write('tls-ok');
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));
      final res = await LegadoHttp.fetchRaw(
        'https://127.0.0.1:${server.port}/',
      );
      expect(res.statusCode, 200);
      expect(res.body, contains('tls-ok'));
    });
  });
}
