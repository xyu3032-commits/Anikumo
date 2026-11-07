// Regression (batch 72, device report 2026-11-08): the 追番
// page rendered NOTHING on a per-status tab and rendered the
// same entry repeatedly on the grouped 全部 tab while every
// count said 1. Root cause: in the slivers collection
// literal, the trailing `else` of
// `else if (type == null) for (...) if (...) ...[...]`
// bound to the INNER if (verified against the Dart grammar
// with a minimal repro) — status pages lost their only
// sliver and the "all" page re-appended the flat list once
// per non-matching status. _results now builds its slivers
// imperatively; these tests pin the visible outcome.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/collect/collect_layout.dart';
import 'package:anikumo/modules/collect/collect_module.dart';
import 'package:anikumo/pages/collect/collect_library_view.dart';

BangumiItem _item(int id, String nameCn) => BangumiItem(
      id: id,
      type: 2,
      name: 'Test Anime $id',
      nameCn: nameCn,
      summary: '',
      airDate: '2026-01-01',
      airWeekday: 1,
      rank: 0,
      images: const {},
      tags: const [],
      alias: const [],
      ratingScore: 5.3,
      votes: 0,
      votesCount: const [],
      info: '',
    );

Future<void> _pump(WidgetTester tester, List<CollectedBangumi> entries) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CollectLibraryView(
          entries: entries,
          showRating: true,
          layout: CollectLayout.list,
          onLayoutChanged: (_) {},
          canEdit: (_) => true,
          onOpen: (_) {},
          onChangeType: (_, __) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('status tab shows its entry exactly once', (tester) async {
    await _pump(tester, [
      CollectedBangumi(_item(42, '测试番剧'), DateTime(2026, 1, 1), 1),
    ]);
    // The page opens on the 在看 tab.
    expect(find.text('测试番剧'), findsOneWidget);
  });

  testWidgets('grouped all tab shows the entry exactly once',
      (tester) async {
    await _pump(tester, [
      CollectedBangumi(_item(42, '测试番剧'), DateTime(2026, 1, 1), 1),
    ]);
    await tester.tap(find.textContaining('全部'));
    await tester.pumpAndSettle();
    expect(find.text('测试番剧'), findsOneWidget);
  });

  testWidgets('empty status tab shows its empty state', (tester) async {
    await _pump(tester, [
      CollectedBangumi(_item(42, '测试番剧'), DateTime(2026, 1, 1), 1),
    ]);
    // Swipe the page view twice: 在看 → 想看 → 看过. (The
    // later category tabs can sit outside the tab strip's
    // visible width, so tapping their labels is unreliable.)
    await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    // The empty state of the watched tab is what the user
    // sees. (A neighbouring page kept alive in the PageView
    // cache extent may still hold its tile in the tree, so
    // the title is not asserted absent here.)
    expect(find.text('还没有看过的番剧'), findsOneWidget);
  });
}
