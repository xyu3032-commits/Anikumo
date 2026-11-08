// Batch 110/112: the search-stage kit (flattened in
// batch 112) — PillSwitch renders
// every option and reports taps, the mode switch adapter
// keeps its API, the section bar shows its count badge,
// and the hero shell renders its child.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/search_stage.dart';
import 'package:anikumo/pages/search/cross_search_widgets.dart';
import 'package:anikumo/services/manga/cross_media.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('PillSwitch renders options and reports the tap',
      (tester) async {
    bool? picked;
    await tester.pumpWidget(_host(PillSwitch<bool>(
      options: const [
        PillSwitchOption(value: false, label: '当前源'),
        PillSwitchOption(value: true, label: '全部源'),
      ],
      value: false,
      onChanged: (value) => picked = value,
    )));
    expect(find.text('当前源'), findsOneWidget);
    expect(find.text('全部源'), findsOneWidget);
    await tester.tap(find.text('全部源'));
    expect(picked, isTrue);
  });

  testWidgets('CrossSearchModeSwitch shows all four modes', (tester) async {
    CrossSearchMode? picked;
    await tester.pumpWidget(_host(CrossSearchModeSwitch(
      mode: CrossSearchMode.all,
      onChanged: (mode) => picked = mode,
    )));
    for (final label in ['全部', '动漫', '漫画', '小说']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('漫画'));
    expect(picked, CrossSearchMode.manga);
  });

  testWidgets('CrossSectionHeader shows title and count badge',
      (tester) async {
    await tester.pumpWidget(_host(const CrossSectionHeader(
      title: '漫画',
      count: 42,
    )));
    expect(find.text('漫画'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('SearchHeroShell renders its child', (tester) async {
    await tester.pumpWidget(_host(const SearchHeroShell(
      child: Text('里面'),
    )));
    expect(find.text('里面'), findsOneWidget);
  });

}
