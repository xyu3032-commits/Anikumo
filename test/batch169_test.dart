// Batch 169: the login system — login form parsing, the
// per-source login-info store, the JS bridge accessors
// (raw string / materialized map), login-script functions
// joining the shared scope, and browse suspensions.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/services/novel/legado_js.dart';
import 'package:anikumo/services/novel/login_info.dart';
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

const _loginUiJson = '''
[
  {"name": "状态", "type": "select", "chars": "[\\"连载中\\",\\"已完结\\"]"},
  {"name": "字数", "type": "select", "chars": "30万以下,30-50万,50-100万", "default": "30-50万"},
  {"name": "备注", "type": "text"},
  {"name": "密码", "type": "password"},
  {"name": "网页登录", "type": "button", "action": "webLogin()"}
]
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b169_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  group('login form parsing (batch 169)', () {
    test('rows, select chars in both shapes, defaults', () {
      final rows = LoginUi.parse(_loginUiJson);
      expect(rows.length, 5);
      expect(rows[0].chars, ['连载中', '已完结']);
      expect(rows[0].initialValue, '连载中');
      expect(rows[1].chars, ['30万以下', '30-50万', '50-100万']);
      expect(rows[1].initialValue, '30-50万');
      expect(rows[3].isPassword, isTrue);
      expect(rows[4].isButton, isTrue);
      expect(rows[4].action, 'webLogin()');
    });

    test('inline list form parses too, junk yields no rows', () {
      final rows = LoginUi.parse([
        {'name': '账号', 'type': 'text'},
      ]);
      expect(rows.length, 1);
      expect(LoginUi.parse('not json'), isEmpty);
      expect(LoginUi.parse(null), isEmpty);
    });
  });

  group('login info store (batch 169)', () {
    test('defaults materialize, saves overlay, clear resets', () async {
      final rows = LoginUi.parse(_loginUiJson);
      const id = 'https://example.com/src';
      expect(NovelLoginInfo.rawFor(id), isNull);
      var values = NovelLoginInfo.valuesFor(id, rows);
      expect(values['状态'], '连载中');
      expect(values['字数'], '30-50万');
      expect(values.containsKey('网页登录'), isFalse);

      await NovelLoginInfo.save(id, {'状态': '已完结', '备注': 'x'});
      final raw = NovelLoginInfo.rawFor(id);
      expect(raw, isNotNull);
      expect(jsonDecode(raw!), {'状态': '已完结', '备注': 'x'});
      values = NovelLoginInfo.valuesFor(id, rows);
      expect(values['状态'], '已完结');
      expect(values['字数'], '30-50万');

      await NovelLoginInfo.clear(id);
      expect(NovelLoginInfo.rawFor(id), isNull);
    });
  });

  group('JS bridge (batch 169)', () {
    test('getLoginInfo is null before save, the string after; map '
        'materializes defaults either way', () async {
      const id = 'https://example.com/bridge';
      final host = LegadoJsHost.forSource(id, null, loginUi: _loginUiJson);
      var out = await host.run(
        code: 'source.getLoginInfo() === null ? "null" : "set"',
        baseUrl: 'https://example.com/',
      );
      expect(out, 'null');
      out = await host.run(
        code: 'source.getLoginInfoMap()["状态"]',
        baseUrl: 'https://example.com/',
      );
      expect(out, '连载中');
      await NovelLoginInfo.save(id, {'状态': '已完结'});
      out = await host.run(
        code: 'JSON.parse(source.getLoginInfo())["状态"]',
        baseUrl: 'https://example.com/',
      );
      expect(out, '已完结');
      await NovelLoginInfo.clear(id);
    });

    test('login script functions join the shared scope', () async {
      final host = LegadoJsHost.forSource(
        'https://example.com/fns',
        null,
        loginUrl: '<js>function loginHelper(x) { return x + 1; }</js>',
      );
      final out = await host.run(
        code: 'loginHelper(41)',
        baseUrl: 'https://example.com/',
      );
      expect(out, 42);
    });

    test('startBrowserAwait routes to the registered handler', () async {
      String? seenUrl;
      LegadoJsHost.browseHandler = (url, title) async {
        seenUrl = url;
      };
      addTearDown(() => LegadoJsHost.browseHandler = null);
      final host = LegadoJsHost.forSource('https://example.com/browse', null);
      final out = await host.run(
        code: 'java.startBrowserAwait("https://example.com/login", "登录");'
            '"done"',
        baseUrl: 'https://example.com/',
      );
      expect(out, 'done');
      expect(seenUrl, 'https://example.com/login');
    });

    test('with no handler, browse requests degrade to empty', () async {
      LegadoJsHost.browseHandler = null;
      final host = LegadoJsHost.forSource('https://example.com/browse2', null);
      final out = await host.run(
        code: 'var r = java.startBrowserAwait("https://example.com/x");'
            'r === "" ? "empty" : "other"',
        baseUrl: 'https://example.com/',
      );
      expect(out, 'empty');
    });
  });
}
