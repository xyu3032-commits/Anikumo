// Batch 74 desktop probe: drive the real QuickJS engine
// with stub sources to verify the account dispatcher kinds
// (account / login / logout) and the UI channel round trip.
//
// Run with:
//   LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/manga_login_probe_test.dart
//
// No network and no real UI: the UI case asserts the
// graceful failure (界面尚未就绪) that proves the
// isolate → UI isolate → gateway → back relay works and
// never hangs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _accountSource = r'''
class ProbeAccount extends ComicSource {
  name = "probe";
  key = "probe_account";
  version = "1.0.0";
  account = {
    login: async (u, p) => {
      if (p !== 'pw123') throw new Error('密码错误');
      this.saveData('token', 'tok-' + u);
      return 'ok';
    },
    logout: () => { this.deleteData('token'); },
    registerWebsite: 'https://example.com/register',
  };
  search = {
    load: async (kw, opts, page) => ({comics: [], maxPage: 1}),
  };
}
''';

const _captchaSource = r'''
class ProbeCaptcha extends ComicSource {
  name = "probe2";
  key = "probe_captcha";
  version = "1.0.0";
  account = {
    login: async (u, p) => {
      let code = await UI.showInputDialog('输入验证码', null, null);
      this.saveData('token', 'tok-' + code);
      return 'ok';
    },
    registerWebsite: null,
  };
  search = {
    load: async (kw, opts, page) => ({comics: [], maxPage: 1}),
  };
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('qjs_login_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('account probe → wrong password → login → token → logout', () async {
    final engine = VeneraEngine(sourceKey: 'probe_account', code: _accountSource);

    final before = await engine.call('account', const {});
    print('account before: $before');
    expect(before, isA<Map>());
    final beforeMap = (before as Map).cast<String, dynamic>();
    expect(beforeMap['hasLogin'], isTrue);
    expect(beforeMap['hasLogout'], isTrue);
    expect(beforeMap['registerWebsite'], 'https://example.com/register');
    expect(beforeMap['hasToken'], isFalse);

    await expectLater(
      engine.call('login', {'username': 'alice', 'password': 'nope'}),
      throwsA(
        predicate((e) => e.toString().contains('密码错误'), 'wrong password'),
      ),
    );

    final loginResult = await engine.call('login', {
      'username': 'alice',
      'password': 'pw123',
    });
    expect(loginResult, isTrue);

    final after = await engine.call('account', const {});
    expect((after as Map)['hasToken'], isTrue);

    final logoutResult = await engine.call('logout', const {});
    expect(logoutResult, isTrue);
    final afterLogout = await engine.call('account', const {});
    expect((afterLogout as Map)['hasToken'], isFalse);
  });

  test('UI channel: captcha input fails gracefully without a UI', () async {
    final engine = VeneraEngine(sourceKey: 'probe_captcha', code: _captchaSource);
    await expectLater(
      engine.call('login', {'username': 'bob', 'password': 'pw123'}),
      throwsA(
        predicate(
          (e) => e.toString().contains('界面尚未就绪'),
          'ui not ready error crosses back',
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
