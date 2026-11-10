import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/widget/zone_switcher.dart';

void main() {
  group('zone wheel backdrop accent (batch 140)', () {
    const scheme = ColorScheme.light(
      primary: Color(0xFFAA0000),
      secondary: Color(0xFF00AA00),
      tertiary: Color(0xFF0000AA),
    );

    test('a centred page wears exactly that zone colour', () {
      // Page 3000 = anime (3000 % 3 == 0), 3001 manga, 3002 novel.
      expect(zoneWheelBackdropAccent(3000, scheme), scheme.primary);
      expect(zoneWheelBackdropAccent(3001, scheme), scheme.tertiary);
      expect(zoneWheelBackdropAccent(3002, scheme), scheme.secondary);
    });

    test('halfway between two zones the colour is the blend', () {
      final mid = zoneWheelBackdropAccent(3000.5, scheme);
      expect(mid, Color.lerp(scheme.primary, scheme.tertiary, 0.5));
    });

    test('the wheel wraps: after novel comes anime again', () {
      final mid = zoneWheelBackdropAccent(3002.5, scheme);
      expect(mid, Color.lerp(scheme.secondary, scheme.primary, 0.5));
    });
  });
}
