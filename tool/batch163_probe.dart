// ignore_for_file: avoid_print
// Batch 163 probe — LIVE check against the real service.
// Requires the token to be injected first:
//   dart ~/workspace/kazumi_analysis/inject_danmu_token.dart inject
// and a restore afterwards. Not part of the shipped tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:anikumo/request/apis/danmaku_api.dart';
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

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b163_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('builtin service answers end to end', () async {
    expect(DanmakuApi.builtinActive, isTrue,
        reason: 'token injected + no user credentials + switch on');

    final search = await DanmakuApi.searchAnimes('药屋少女的呢喃');
    print('search hits: ${search.animes.length}');
    expect(search.animes, isNotEmpty);

    final (entries, animeId) = await DanmakuApi.fetchAutoDanmaku(
      bgmBangumiId: 0,
      title: '药屋少女的呢喃',
      episode: 1,
    );
    print('S1E1: anime=$animeId comments=${entries.length}');
    expect(animeId, 45973);
    expect(entries, isNotEmpty);

    final (entries3, animeId3) = await DanmakuApi.fetchAutoDanmaku(
      bgmBangumiId: 0,
      title: '药屋少女的呢喃 第三季',
      episode: 1,
    );
    print('S3E1: anime=$animeId3 comments=${entries3.length}');
    expect(animeId3, 59070);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
