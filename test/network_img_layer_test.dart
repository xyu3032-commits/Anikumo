// Batch 72: cover images used to be single-attempt — one
// transient CDN failure pinned the placeholder until the
// card happened to rebuild (device report: 发现页封面有几率
// 失败). NetworkImgLayer now retries each candidate URL
// once and then falls back to an alternate size of the same
// cover. These tests pin the candidate sequence and that
// the retry machinery settles back to the placeholder
// without throwing when every attempt fails.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';

void main() {
  group('imageRetryCandidates', () {
    test('src only', () {
      expect(imageRetryCandidates('a.jpg', null), ['a.jpg']);
      expect(imageRetryCandidates('a.jpg', ''), ['a.jpg']);
    });

    test('distinct fallback is appended', () {
      expect(imageRetryCandidates('l.jpg', 'c.jpg'), ['l.jpg', 'c.jpg']);
    });

    test('identical fallback is not duplicated', () {
      expect(imageRetryCandidates('a.jpg', 'a.jpg'), ['a.jpg']);
    });

    test('empty src falls back, both empty yields none', () {
      expect(imageRetryCandidates('', 'c.jpg'), ['c.jpg']);
      expect(imageRetryCandidates('', null), isEmpty);
      expect(imageRetryCandidates('', ''), isEmpty);
    });
  });

  testWidgets('failed loads retry, fall back, then settle on placeholder',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NetworkImgLayer(
            // The test HTTP stack refuses every request, so
            // each attempt fails fast and deterministically.
            src: 'https://example.invalid/large.jpg',
            fallbackSrc: 'https://example.invalid/common.jpg',
            width: 100,
            height: 140,
          ),
        ),
      ),
    );
    // Walk through the retry schedule (700ms retry of the
    // first candidate, 400ms advance to the fallback, 700ms
    // retry of the fallback) and any internal image-stream
    // round trips in between.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    // No exception, and the widget is still showing its
    // placeholder (the asset-backed paw) rather than a
    // broken image or an empty box.
    expect(tester.takeException(), isNull);
    expect(find.byType(NetworkImgLayer), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('changing src resets the retry state without error',
      (tester) async {
    Widget layer(String src) => MaterialApp(
          home: Scaffold(
            body: NetworkImgLayer(
              src: src,
              width: 100,
              height: 140,
            ),
          ),
        );
    await tester.pumpWidget(layer('https://example.invalid/one.jpg'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(layer('https://example.invalid/two.jpg'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(NetworkImgLayer), findsOneWidget);
  });
}
