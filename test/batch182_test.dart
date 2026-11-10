// Batch 182: built-in danmaku restored (B163 reapplied)
// plus two fixes — the season the full-title search can
// no longer see (strict pick + widened retry), and sent
// danmaku persisting locally (they used to be a one-shot
// echo: the providers have no send API).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/modules/danmaku/danmaku_search_response.dart';
import 'package:anikumo/modules/danmaku/danmaku_module.dart';
import 'package:anikumo/services/danmaku/builtin_danmu.dart';
import 'package:anikumo/services/danmaku/local_danmaku.dart';
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

DanmakuSearchAnime _anime(int id, String title) => DanmakuSearchAnime(
    animeId: id, animeTitle: title, typeDescription: '动画');

void main() {
  group('season pick widening (batch 182)', () {
    // The service's real full-title results for the bare
    // first-season title (field-verified 2026-11-10): the
    // first season is NOT among them.
    final recentOnly = [
      _anime(59070, '药屋少女的呢喃 第三季(2026)【动画】from renren'),
      _anime(51476, '药屋少女的呢喃 第二季(2025)【动画】from renren'),
    ];
    final withFirst = [
      ...recentOnly,
      _anime(45973, '药屋少女的呢喃(2023)【动画】from renren'),
    ];

    test('strict pick refuses a wrong-season pool', () {
      expect(BuiltinDanmu.pickAnimeIdStrict(recentOnly, '药屋少女的呢喃'), 0);
      // The lenient fallback still takes the first hit —
      // it is the last resort, after the widened retry.
      expect(BuiltinDanmu.pickAnimeId(recentOnly, '药屋少女的呢喃'), 59070);
    });

    test('strict pick finds season 1 once the pool is widened', () {
      expect(BuiltinDanmu.pickAnimeIdStrict(withFirst, '药屋少女的呢喃'), 45973);
      expect(
          BuiltinDanmu.pickAnimeIdStrict(withFirst, '药屋少女的呢喃 第三季'),
          59070);
      expect(
          BuiltinDanmu.pickAnimeIdStrict(withFirst, '药屋少女的呢喃 第二季'),
          51476);
    });

    test('short query is the first four characters', () {
      expect(BuiltinDanmu.shortQueryOf('药屋少女的呢喃'), '药屋少女');
      expect(BuiltinDanmu.shortQueryOf('三体'), '');
      expect(BuiltinDanmu.shortQueryOf(''), '');
    });
  });

  group('local sent danmaku (batch 182)', () {
    setUpAll(() async {
      HttpOverrides.global = null;
      final dir = await Directory.systemTemp.createTemp('anikumo_b182_');
      Hive.init(dir.path);
      PathProviderPlatform.instance = _FakePathProvider(dir.path);
      await GStorage.init();
    });

    test('sent items round-trip per episode', () async {
      const key = '45973|probe|1|药屋少女的呢喃';
      LocalDanmakuStore.add(
        key,
        DanmakuEntry(
          message: '前面忘了后面忘了',
          time: 12.5,
          type: 1,
          color: const Color(0xFFFFFFFF),
          source: 'Local',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final items = LocalDanmakuStore.forEpisode(key);
      expect(items.length, 1);
      expect(items.single.message, '前面忘了后面忘了');
      expect(items.single.time, 12.5);
      expect(items.single.type, 1);
      expect(items.single.source, 'Local');
      expect(LocalDanmakuStore.forEpisode('other|key'), isEmpty);
      expect(LocalDanmakuStore.totalCount, 1);
    });

    test('per-episode cap keeps the newest 200', () async {
      const key = 'cap|probe|1|测试';
      for (var i = 0; i < 205; i++) {
        LocalDanmakuStore.add(
          key,
          DanmakuEntry(
            message: '第$i条',
            time: i.toDouble(),
            type: 1,
            color: const Color(0xFFFFFFFF),
            source: 'Local',
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final items = LocalDanmakuStore.forEpisode(key);
      expect(items.length, LocalDanmakuStore.maxPerEpisode);
      expect(items.first.message, '第5条');
      expect(items.last.message, '第204条');
    });

    test('clearAll wipes every episode', () async {
      LocalDanmakuStore.clearAll();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(LocalDanmakuStore.totalCount, 0);
    });
  });
}
