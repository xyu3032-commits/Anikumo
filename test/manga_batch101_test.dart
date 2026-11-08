import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/js/venera_bridge.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Batch 101: the bridge's 5-second GET cache and the
// persisted cookie jar. The cache must serve a repeated
// bodiless GET from memory, stay out of the way of
// cookie-issuing responses and non-GET verbs, and key on
// headers (cookies ride there). The jar must round-trip
// through storage.
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
  final hits = <String, int>{};

  setUpAll(() async {
    // The widgets binding mocks every HttpClient (400s);
    // this suite talks to a real loopback server through
    // the bridge's Dio, so restore real clients.
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('batch101_bridge');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      final path = request.uri.path;
      hits[path] = (hits[path] ?? 0) + 1;
      if (path == '/issuer') {
        request.response.headers.add('Set-Cookie', 'sess=x; Path=/');
      }
      request.response.write('{"path": "$path", "n": ${hits[path]}}');
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  Future<Map<String, dynamic>> http(
    String method,
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final raw = await VeneraBridge.handle(jsonEncode({
      'method': 'http',
      'http_method': method,
      'url': 'http://127.0.0.1:$port$path',
      'headers': headers,
      'data': null,
    }));
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  test('a repeated GET is served from the 5 s cache', () async {
    final first = await http('GET', '/plain');
    final second = await http('GET', '/plain');
    expect(hits['/plain'], 1);
    expect(first['body'], second['body']);
  });

  test('a different Cookie header is a different cache entry', () async {
    await http('GET', '/keyed', headers: {'Cookie': 'a=1'});
    await http('GET', '/keyed', headers: {'Cookie': 'a=2'});
    expect(hits['/keyed'], 2);
  });

  test('cookie-issuing responses are never cached', () async {
    await http('GET', '/issuer');
    await http('GET', '/issuer');
    expect(hits['/issuer'], 2);
  });

  test('POST is never cached', () async {
    await http('POST', '/posted');
    await http('POST', '/posted');
    expect(hits['/posted'], 2);
  });

  test('the cookie jar persists through storage', () async {
    VeneraEngine.persistCookies('{"example.com":{"sess":"abc"}}');
    // The write is debounced (800 ms) by design.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(VeneraEngine.cookiesJson(), contains('example.com'));
    // Garbage in storage degrades to an empty jar, not a crash.
    await GStorage.putSetting(
      SettingsKeys.mangaJsCookiesJson,
      'not json',
    );
    expect(VeneraEngine.cookiesJson(), '{}');
  });
}
