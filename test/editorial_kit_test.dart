import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/pages/settings/toolbox_page.dart';
import 'package:anikumo/services/storage/storage.dart';

BangumiItem _item(int id) => BangumiItem(
      id: id,
      type: 2,
      name: 'Item $id',
      nameCn: '条目 $id',
      summary: '',
      airDate: '2026-01-01',
      airWeekday: 1,
      rank: 42,
      images: const {},
      tags: const [],
      alias: const [],
      ratingScore: 8.4,
      votes: 1234,
      votesCount: const [],
      info: '',
    );

void main() {
  // Batch 55: the toolbox now renders inside
  // SettingsDetailScaffold, whose subtree reads GStorage —
  // initialize Hive-backed storage like the golden tests do.
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_editorial');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    Hive.init(dir.path);
    await GStorage.init();
  });

  testWidgets('editorial kit widgets render with real data', (tester) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Object? error;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                EditorialSectionHeader(
                  index: '01',
                  label: 'RANKING',
                  title: '本日榜单',
                  subtitle: '大家正在追的五部',
                  actionLabel: '更多',
                  onAction: () {},
                ),
                EditorialHero(
                  item: _item(1),
                  kicker: '今日主视觉 · TOP STORY',
                  onTap: () {},
                ),
                EditorialRankRow(rank: 1, item: _item(2), onTap: () {}),
                EditorialIndexRow(
                  index: '01',
                  icon: Icons.list_alt_outlined,
                  title: '我的榜单',
                  subtitle: '自建片单',
                  trailingText: '3 个',
                  onTap: () {},
                ),
                const EditorialHairline(),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }).catchError((Object e) => error = e);
    expect(error, isNull);
    expect(tester.takeException(), isNull);
    expect(find.text('本日榜单'), findsOneWidget);
    expect(find.text('条目 1'), findsOneWidget);
    expect(find.text('我的榜单'), findsOneWidget);
  });

  testWidgets('toolbox page renders all seven entries', (tester) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: ToolboxPage()),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final title in [
      '命令面板',
      '卡片样式',
      '玻璃效果',
      '本地备份与恢复',
      '弹幕屏蔽',
      '规则管理',
      '下载设置',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });
}
