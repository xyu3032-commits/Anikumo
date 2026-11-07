// Batch 41 local verification (no external site is called):
// drives the REAL engine + bridge with a synthetic source
// whose explore() does exactly what hitomi does —
// Network.fetchBytes on a binary payload, then DataView
// int32 parsing and Uint8Array length checks — against a
// LOCAL HttpServer. Before the base64 byte channel this
// died with "ArrayBuffer object expected" / garbage ids.
//
// Run: LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/bytes_channel_probe.dart
import 'dart:io';
import 'dart:typed_data';

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
    final dir = await Directory.systemTemp.createTemp('bytes_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();

    // nozomi-style payload: three big-endian int32 gallery
    // ids, including values whose bytes are invalid UTF-8
    // (0xFF / 0x80 range) so a string round-trip MUST corrupt
    // them — the old bridge path cannot pass this test.
    final ids = [694327, 0xFF10, 16777215];
    final bytes = Uint8List(ids.length * 4);
    final view = ByteData.view(bytes.buffer);
    for (var i = 0; i < ids.length; i++) {
      view.setInt32(i * 4, ids[i], Endian.big);
    }
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) {
      request.response.headers.set('content-range', 'bytes 0-11/12');
      request.response.add(bytes);
      request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('fetchBytes survives the bridge byte-exactly', () async {
    final code = '''
class BytesProbe extends ComicSource {
  name = "BytesProbe";
  key = "bytes_probe";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";

  explore = [
    {
      title: "probe",
      type: "singlePageWithMultiPart",
      load: async (page) => {
        const res = await Network.fetchBytes(
            "GET", "http://127.0.0.1:$port/nozomi", { referer: "http://x/" });
        if (res.status !== 200) throw "status " + res.status;
        const arr = new Uint8Array(res.body);
        const view = new DataView(res.body);
        const ids = [];
        for (let i = 0; i < view.byteLength / 4; i++) {
          ids.push(view.getInt32(i * 4, false));
        }
        return {
          "part": ids.map((id) => ({
            id: String(id),
            title: "len=" + arr.length + " id=" + id,
            cover: "",
            tags: [],
          })),
        };
      },
    },
  ];
}
''';
    final engine = VeneraEngine(sourceKey: 'bytes_probe', code: code);
    final explore = await engine.call('explore', {'page': 1});
    expect(explore, isA<Map>());
    final part = (explore as Map)['part'] as List;
    final titles = part.map((e) => (e as Map)['title']).toList();
    print('probe titles: $titles');
    expect(titles, [
      'len=12 id=694327',
      'len=12 id=65296',
      'len=12 id=16777215',
    ]);
  });
}
