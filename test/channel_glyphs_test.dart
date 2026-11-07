// Batch 62 (appendix): the custom channel glyph set —
// every string must be a self-contained SVG carrying the
// COLOR token the widget substitutes, and the widget must
// render the whole set without exceptions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/channel_glyphs.dart';

const _allGlyphs = [
  ChannelGlyphs.homeOutline,
  ChannelGlyphs.homeFilled,
  ChannelGlyphs.featuredOutline,
  ChannelGlyphs.featuredFilled,
  ChannelGlyphs.discoverOutline,
  ChannelGlyphs.discoverFilled,
  ChannelGlyphs.momentsOutline,
  ChannelGlyphs.momentsFilled,
  ChannelGlyphs.scheduleOutline,
  ChannelGlyphs.scheduleFilled,
  ChannelGlyphs.followingOutline,
  ChannelGlyphs.followingFilled,
  ChannelGlyphs.mineOutline,
  ChannelGlyphs.mineFilled,
];

void main() {
  test('all 14 glyphs are COLOR-token SVGs', () {
    expect(_allGlyphs, hasLength(14));
    for (final svg in _allGlyphs) {
      expect(svg, startsWith('<svg'));
      expect(svg, endsWith('</svg>'));
      expect(svg, contains('COLOR'));
    }
  });

  testWidgets('ChannelGlyph renders every glyph', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final svg in _allGlyphs)
                ChannelGlyph(
                  svg: svg,
                  color: const Color(0xFF33304A),
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ChannelGlyph), findsNWidgets(14));
  });
}
