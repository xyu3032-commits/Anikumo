// Batch 176: per-source variables (source.get/put) work
// end-to-end through the real host — seeded from the
// persisted store before the engine starts, honored by a
// line-switching source's search template, updated by its
// login hook, and harvested back to storage after calls.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/moyuan_host.dart';
import 'package:anikumo/services/novel/novel_source.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

final _requestedUrls = <String>[];

Future<Map<String, dynamic>> _transport(
  String url,
  Map<String, dynamic> options,
) async {
  _requestedUrls.add(url);
  const list = '<html><body><div class="bookbox">'
      '<div class="bookname"><a href="/book/1.html">斗罗大陆</a></div>'
      '<div class="author">唐家三少</div></div></body></html>';
  return {'status': 200, 'headers': {}, 'body': list, 'url': url};
}

Map<String, dynamic> _lineDef() => {
      'bookSourceName': '线路夹具源',
      'bookSourceUrl': 'http://www.ijjxs.org/',
      'bookSourceType': 0,
      'searchUrl': "{{(function(){var L=String(source.get('ijLine')||'');"
          "if(!L||L.indexOf('http')!==0)L='http://177.5.49.192';"
          r"return L.replace(/\/+$/,'')+'/search7e.html'})()}}",
      'loginUrl': "function login(){ "
          "source.put('ijLine', 'http://203.0.113.9'); }",
      'ruleSearch': {
        'bookList': 'class.bookbox',
        'name': 'class.bookname@tag.a@text',
        'bookUrl': 'class.bookname@tag.a@href',
        'author': 'class.author@text',
      },
      'ruleBookInfo': <String, dynamic>{},
      'ruleToc': <String, dynamic>{},
      'ruleContent': <String, dynamic>{},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('anikumo_b176_');
    Hive.init(dir.path);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    await GStorage.init();
    MoyuanHost.debugTransportOverride = _transport;
    await GStorage.putSetting(
      SettingsKeys.novelInstalledSourcesJson,
      jsonEncode([_lineDef()]),
    );
    // A line chosen in a previous app run.
    await GStorage.putSetting(
      SettingsKeys.novelSourceVarsJson,
      jsonEncode({
        'http://www.ijjxs.org/': {'ijLine': 'http://198.51.100.7/'},
      }),
    );
  });

  testWidgets('seeded line is used, login switch applies and persists',
      (tester) async {
    await tester.runAsync(() async {
      final src = LegadoNovelSource(
        LegadoSourceDef.fromJson(_lineDef())!,
      );
      final items =
          await src.search('斗罗大陆').timeout(const Duration(seconds: 30));
      expect(items.length, 1);
      expect(_requestedUrls.last,
          'http://198.51.100.7/search7e.html');

      await MoyuanHost.instance
          .submitLoginForm('http://www.ijjxs.org/', const {})
          .timeout(const Duration(seconds: 30));
      _requestedUrls.clear();
      final items2 =
          await src.search('斗罗大陆').timeout(const Duration(seconds: 30));
      expect(items2.length, 1);
      expect(_requestedUrls.last,
          'http://203.0.113.9/search7e.html');

      // Harvested back to the persisted store.
      final stored = jsonDecode(
        GStorage.getSetting(SettingsKeys.novelSourceVarsJson),
      ) as Map<String, dynamic>;
      expect(
        (stored['http://www.ijjxs.org/'] as Map)['ijLine'],
        'http://203.0.113.9',
      );
    });
  });
}
