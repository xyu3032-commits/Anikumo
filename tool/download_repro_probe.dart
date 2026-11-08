// Batch 104 reproduction probe (no external site): manga
// chapter downloads end to end against a local server.
// Variant A: onImageLoad signs the page urls (extra header
// the server demands; 403 without it) — the classic hook
// source shape.
// Variant B: onResponse-transformed pages (bytes reversed
// on the wire) — what lands on disk decides whether a
// downloaded chapter is actually readable offline.
// Run: LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/download_repro_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
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

List<int> reversed(List<int> bytes) => bytes.reversed.toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final plain = utf8.encode('PAGE-PLAINTEXT-0123456789');
  late HttpServer server;
  late int port;

  MangaItem item(String source) => MangaItem(
        id: 'm1',
        title: 'dlbook',
        description: '',
        coverUrl: '',
        author: '',
        status: '',
        year: null,
        tags: const [],
        source: source,
      );

  const chapter = MangaChapter(
    id: 'e1',
    volume: null,
    chapter: '1',
    title: '第一话',
    language: '',
    pages: 3,
    publishedAt: null,
  );

  setUpAll(() async {
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('download_repro');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      if (request.uri.path == '/signed') {
        if (request.headers.value('x-sign') != 'ok') {
          request.response.statusCode = HttpStatus.forbidden;
        } else {
          request.response.add(plain);
        }
      } else if (request.uri.path == '/enc') {
        request.response.add(reversed(plain));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final signCode = '''
class DlSign extends ComicSource {
  name = "DlSign";
  key = "dl_sign";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";
  comic = {
    loadEp: async (id, ep) => {
      return { images: [
        "http://127.0.0.1:$port/signed",
        "http://127.0.0.1:$port/signed",
        "http://127.0.0.1:$port/signed"
      ]};
    },
    onImageLoad: async (url, id, ep) => {
      return { url: url, headers: { "x-sign": "ok" } };
    }
  };
}
''';
    final txCode = '''
class DlTx extends ComicSource {
  name = "DlTx";
  key = "dl_tx";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:$port";
  comic = {
    loadEp: async (id, ep) => {
      return { images: ["http://127.0.0.1:$port/enc"] };
    },
    onImageLoad: async (url, id, ep) => {
      return {
        onResponse: (res) => {
          const d = res.data;
          const out = new Uint8Array(d.length);
          for (let i = 0; i < d.length; i++) out[i] = d[d.length - 1 - i];
          return { data: out };
        }
      };
    }
  };
}
''';
    // Install both into the facade registry the API layer
    // consults (downloads resolve the source by id).
    await GStorage.putSetting(
      SettingsKeys.mangaJsSourcesJson,
      jsonEncode([
        {
          'key': 'dl_sign',
          'name': 'DlSign',
          'version': '1.0.0',
          'fileName': 'dl_sign.js',
          'code': signCode,
        },
        {
          'key': 'dl_tx',
          'name': 'DlTx',
          'version': '1.0.0',
          'fileName': 'dl_tx.js',
          'code': txCode,
        },
      ]),
    );
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('variant A: signed-hook chapter downloads', () async {
    final entry = await MangaDownloadStore.downloadChapter(
      manga: item('js:dl_sign'),
      chapter: chapter,
    );
    expect(entry, isNotNull, reason: 'signed download returned null');
    expect(entry!.pageCount, 3);
    final pages = await MangaDownloadStore.localPages(
      'js:dl_sign',
      'm1',
      'e1',
    );
    expect(pages, isNotNull);
    expect(pages!.length, 3);
    final file = File(Uri.parse(pages[0].url).toFilePath());
    expect(await file.readAsBytes(), plain);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('variant B: transformed chapter downloads readable bytes', () async {
    const txChapter = MangaChapter(
      id: 'e9',
      volume: null,
      chapter: '9',
      title: '第九话',
      language: '',
      pages: 1,
      publishedAt: null,
    );
    final entry = await MangaDownloadStore.downloadChapter(
      manga: item('js:dl_tx'),
      chapter: txChapter,
    );
    expect(entry, isNotNull, reason: 'transform download returned null');
    final pages = await MangaDownloadStore.localPages(
      'js:dl_tx',
      'm1',
      'e9',
    );
    expect(pages, isNotNull);
    final file = File(Uri.parse(pages![0].url).toFilePath());
    final stored = await file.readAsBytes();
    // The stored bytes must be the DECODED page (what the
    // reader shows online), not the reversed wire bytes.
    expect(stored, plain,
        reason: 'downloaded page is still in wire (encrypted) form');
  }, timeout: const Timeout(Duration(seconds: 120)));
}
