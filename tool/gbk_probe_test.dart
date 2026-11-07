// Batch 76 desktop probe: GBK codec against the real
// QuickJS engine. A stub source runs Convert.encodeGbk /
// decodeGbk inside its search and reports the results as a
// comic, so the whole path (overrides + gbk script +
// dispatcher) is exercised exactly as a real GBK source
// would use it.
//
// Run with:
//   LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/gbk_probe_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _gbkSource = r'''
class ProbeGbk extends ComicSource {
  name = "probe gbk";
  key = "probe_gbk";
  version = "1.0.0";
  search = {
    load: async (kw, opts, page) => {
      const enc = new Uint8Array(Convert.encodeGbk(kw));
      const hex = Array.from(enc)
          .map((b) => b.toString(16).padStart(2, '0')).join('');
      const dec = Convert.decodeGbk(new Uint8Array(
          [0xd6, 0xd0, 0xce, 0xc4, 0xb2, 0xe2, 0xca, 0xd4]).buffer);
      const euro = Convert.decodeGbk(new Uint8Array([0x80]).buffer);
      const round = Convert.decodeGbk(Convert.encodeGbk('漫画搜索'));
      const mixed = Convert.decodeGbk(new Uint8Array(
          [0x41, 0xc2, 0xfe, 0x42]).buffer);
      return {
        comics: [{
          id: hex,
          title: dec + '|' + euro + '|' + round + '|' + mixed,
          cover: '',
          subtitle: '',
        }],
        maxPage: 1,
      };
    },
  };
}
''';

const _cfbSource = r'''
class ProbeCfb extends ComicSource {
  name = "probe cfb";
  key = "probe_cfb";
  version = "1.0.0";
  search = {
    load: async (kw, opts, page) => {
      Convert.decryptAesCfb(new Uint8Array(16).buffer,
          new Uint8Array(16).buffer, new Uint8Array(16).buffer);
      return {comics: [], maxPage: 1};
    },
  };
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('qjs_gbk_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('encodeGbk produces standard GBK bytes; decodeGbk reads them back',
      () async {
    final engine = VeneraEngine(sourceKey: 'probe_gbk', code: _gbkSource);
    final result = await engine.call('search', {'keyword': '漫画', 'page': 1});
    print('gbk search result: $result');
    expect(result, isA<Map>());
    final comics = (result as Map)['comics'] as List;
    expect(comics, hasLength(1));
    final comic = (comics.first as Map).cast<String, dynamic>();
    // 漫画 in GBK is C2 FE BB AD.
    expect(comic['id'], 'c2febbad');
    expect(comic['title'], '中文测试|€|漫画搜索|A漫B');
  });

  test('CFB still fails loudly with the updated message', () async {
    final engine = VeneraEngine(sourceKey: 'probe_cfb', code: _cfbSource);
    await expectLater(
      engine.call('search', {'keyword': 'x', 'page': 1}),
      throwsA(
        predicate(
          (e) => e.toString().contains('RSA 或 CFB/OFB'),
          'updated unsupported message',
        ),
      ),
    );
  });
}

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
