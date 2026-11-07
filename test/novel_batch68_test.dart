// Batch 68: the LegadoHttp cookie jar — Set-Cookie
// harvesting, host/subdomain matching, Domain attribute
// re-keying, WebView-login import, clearing, and
// persistence through the settings store.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/novel/legado_http.dart';
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

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('batch68');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    // Seed the persisted jar BEFORE any jar access in
    // this file: the first test proves a cold start reads
    // it back.
    await GStorage.putSetting(
      SettingsKeys.novelCookieJarJson,
      '{"seeded.example.com":{"sess":"abc"}}',
    );
  });

  test('persisted jar is read back on first access', () {
    expect(
      LegadoHttp.cookieHeaderFor('https://seeded.example.com/list'),
      contains('sess=abc'),
    );
    expect(LegadoHttp.cookieCountFor('seeded.example.com'), 1);
  });

  test('storeCookies records name=value and matches subdomains', () async {
    await LegadoHttp.storeCookies(
      'https://www.reads.example.org/search',
      ['sid=xyz123; Path=/; HttpOnly', 'pref=dark; Path=/'],
    );
    final header =
        LegadoHttp.cookieHeaderFor('https://www.reads.example.org/x');
    expect(header, contains('sid=xyz123'));
    expect(header, contains('pref=dark'));
    // Stored under the response host: subdomains do NOT
    // inherit host-only cookies.
    expect(
      LegadoHttp.cookieHeaderFor('https://sub.reads.example.org/x'),
      isNot(contains('sid=xyz123')),
    );
    expect(
      LegadoHttp.cookieHeaderFor('https://other.example.net/x'),
      isEmpty,
    );
  });

  test('Domain attribute re-keys the cookie to the parent domain',
      () async {
    await LegadoHttp.storeCookies(
      'https://www.wenku.example.net/login',
      ['uid=42; Domain=.wenku.example.net; Path=/'],
    );
    expect(
      LegadoHttp.cookieHeaderFor('https://www.wenku.example.net/a'),
      contains('uid=42'),
    );
    expect(
      LegadoHttp.cookieHeaderFor('https://api.wenku.example.net/a'),
      contains('uid=42'),
    );
  });

  test('empty value deletes the cookie', () async {
    await LegadoHttp.storeCookies(
      'https://www.reads.example.org/logout',
      ['sid=; Path=/'],
    );
    expect(
      LegadoHttp.cookieHeaderFor('https://www.reads.example.org/x'),
      isNot(contains('sid=')),
    );
  });

  test('importCookies + clearCookiesFor roundtrip (login page path)',
      () async {
    await LegadoHttp.importCookies('login.example.com', {'token': 't-1'});
    expect(LegadoHttp.cookieCountFor('login.example.com'), 1);
    expect(
      LegadoHttp.cookieHeaderFor('https://login.example.com/'),
      contains('token=t-1'),
    );
    await LegadoHttp.clearCookiesFor('login.example.com');
    expect(LegadoHttp.cookieCountFor('login.example.com'), 0);
  });
}
