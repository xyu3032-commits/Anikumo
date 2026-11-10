import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anikumo/bean/widget/fade_slide_in.dart';
import 'package:anikumo/services/ui/app_extras.dart';

void main() {
  testWidgets('rank entrance animates even with smooth mode on (batch 133)',
      (tester) async {
    SmoothMode.notifier.value = true;
    addTearDown(() => SmoothMode.notifier.value = false);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RankEntrance3D(index: 0, child: SizedBox(width: 10, height: 10)),
        ),
      ),
    );
    // The entrance wrapper must exist (the old gate returned
    // the bare child): at t=0 the row starts fully transparent.
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 0);
    // Batch 138: the start is visibility-gated with a small
    // base delay, so pump real durations instead of settling.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 700));
    final settled = tester.widget<Opacity>(find.byType(Opacity));
    expect(settled.opacity, 1);
  });
}
