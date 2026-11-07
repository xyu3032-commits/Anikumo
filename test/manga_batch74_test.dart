import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Batch 74: manga source account login — the pure mapping
/// and the host session store. The engine-side account /
/// login / logout dispatcher kinds are covered by the
/// desktop probe (tool/manga_login_probe_test.dart), which
/// needs the real QuickJS library.
void main() {
  group('mapJsAccountInfo', () {
    test('token in KV means logged in', () {
      final info = mapJsAccountInfo(
        const {
          'hasLogin': true,
          'hasLogout': true,
          'registerWebsite': 'https://example.com/reg',
          'hasToken': true,
        },
        sessionOpen: false,
      );
      expect(info.hasLogin, isTrue);
      expect(info.hasLogout, isTrue);
      expect(info.isLoggedIn, isTrue);
      expect(info.registerWebsite, 'https://example.com/reg');
    });

    test('host session flag means logged in without a token', () {
      final info = mapJsAccountInfo(
        const {'hasLogin': true, 'hasToken': false},
        sessionOpen: true,
      );
      expect(info.isLoggedIn, isTrue);
    });

    test('neither token nor session means logged out', () {
      final info = mapJsAccountInfo(
        const {'hasLogin': true, 'hasToken': false},
        sessionOpen: false,
      );
      expect(info.isLoggedIn, isFalse);
      expect(info.hasLogout, isFalse);
      expect(info.registerWebsite, isNull);
    });

    test('empty register website normalizes to null', () {
      final info = mapJsAccountInfo(
        const {'hasLogin': true, 'registerWebsite': ''},
        sessionOpen: false,
      );
      expect(info.registerWebsite, isNull);
    });

    test('missing fields stay conservative', () {
      final info = mapJsAccountInfo(const {}, sessionOpen: false);
      expect(info.hasLogin, isFalse);
      expect(info.isLoggedIn, isFalse);
    });
  });

  group('MangaAccountSessions', () {
    late Directory directory;
    late PathProviderPlatform originalPathProvider;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('anikumo_b74_');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(directory.path);
      Hive.init(directory.path);
      await GStorage.init();
    });

    tearDownAll(() async {
      PathProviderPlatform.instance = originalPathProvider;
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('mark in/out round-trips per source key', () async {
      expect(MangaAccountSessions.isLoggedIn('probe_a'), isFalse);
      await MangaAccountSessions.markLoggedIn('probe_a');
      await MangaAccountSessions.markLoggedIn('probe_b');
      expect(MangaAccountSessions.isLoggedIn('probe_a'), isTrue);
      expect(MangaAccountSessions.isLoggedIn('probe_b'), isTrue);
      await MangaAccountSessions.markLoggedIn('probe_a');
      await MangaAccountSessions.markLoggedOut('probe_a');
      expect(MangaAccountSessions.isLoggedIn('probe_a'), isFalse);
      expect(MangaAccountSessions.isLoggedIn('probe_b'), isTrue);
      await MangaAccountSessions.markLoggedOut('probe_b');
      expect(MangaAccountSessions.isLoggedIn('probe_b'), isFalse);
    });
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
