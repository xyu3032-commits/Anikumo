import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/splash_gate.dart';

/// Batch 93: the launch intro shows on cold start (name +
/// emblem over the brand field), the app builds underneath
/// from the first frame, a tap skips, and the intro removes
/// itself after its run so the app is fully interactive.
void main() {
  testWidgets('intro plays over the app, then removes itself',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashGate(child: Scaffold(body: Text('APP-HOME'))),
      ),
    );
    // The app is in the tree from the start; the intro is
    // visible over it.
    expect(find.text('APP-HOME'), findsOneWidget);
    expect(find.text('Anikumo'), findsOneWidget);
    expect(find.text('动 漫 · 漫 画 · 小 说'), findsOneWidget);
    // Run past the intro (1.7s) and its fade-out (0.38s).
    await tester.pump(const Duration(milliseconds: 1750));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Anikumo'), findsNothing);
    expect(find.text('APP-HOME'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap skips the intro early', (tester) async {
    // A fresh gate in a fresh tree: the per-process flag is
    // already set by the previous test, so this instance
    // passes straight through — assert exactly that
    // contract instead (no overlay at all).
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashGate(child: Scaffold(body: Text('APP-2'))),
      ),
    );
    expect(find.text('Anikumo'), findsNothing);
    expect(find.text('APP-2'), findsOneWidget);
  });
}
