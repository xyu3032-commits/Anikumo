import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/danmaku/danmaku_module.dart';
import 'package:anikumo/services/player/danmaku_thinning.dart';
import 'package:anikumo/services/player/road_preference.dart';
import 'package:anikumo/services/player/skip_settings.dart';
import 'package:flutter/material.dart';

DanmakuEntry _entry(int i) => DanmakuEntry(
      message: '弹幕 $i',
      time: i.toDouble(),
      type: 1,
      color: Colors.white,
      source: 'test',
    );

void main() {
  group('SkipSettings.resolve', () {
    test('falls back to defaults without an override', () {
      final resolved =
          SkipSettings.resolve(override: null, defaultOp: 90, defaultEd: 60);
      expect(resolved.opSeconds, 90);
      expect(resolved.edSeconds, 60);
    });

    test('override wins field by field and clamps outliers', () {
      final resolved = SkipSettings.resolve(
        override: (opSeconds: 5000, edSeconds: -5),
        defaultOp: 90,
        defaultEd: 60,
      );
      expect(resolved.opSeconds, SkipSettings.maxSeconds);
      expect(resolved.edSeconds, 0);
    });

    test('override codec round-trips', () {
      final encoded = SkipSettings.encodeOverrides({
        1: (opSeconds: 85, edSeconds: 0),
        2: (opSeconds: 0, edSeconds: 45),
      });
      final decoded = SkipSettings.decodeOverrides(encoded);
      expect(decoded[1], (opSeconds: 85, edSeconds: 0));
      expect(decoded[2], (opSeconds: 0, edSeconds: 45));
      expect(SkipSettings.decodeOverrides('junk'), isEmpty);
    });
  });

  group('RoadPreference.order', () {
    test('preferred road goes first, current second', () {
      final order = RoadPreference.order(totalRoads: 4, preferred: 2, current: 0);
      expect(order, [2, 0, 1, 3]);
    });

    test('drops out-of-range and duplicates', () {
      final order = RoadPreference.order(totalRoads: 2, preferred: 9, current: 1);
      expect(order, [1, 0]);
    });

    test('no hints yields plain order', () {
      expect(RoadPreference.order(totalRoads: 3), [0, 1, 2]);
    });
  });

  group('thinDanmaku', () {
    test('returns the list untouched below the cap', () {
      final entries = [for (var i = 0; i < 100; i++) _entry(i)];
      expect(thinDanmaku(entries, cap: 3000).length, 100);
    });

    test('thins uniformly to the cap preserving time order', () {
      final entries = [for (var i = 0; i < 9000; i++) _entry(i)];
      final thinned = thinDanmaku(entries, cap: 3000);
      expect(thinned.length, 3000);
      expect(thinned.first.time, 0);
      expect(thinned[1].time, 3);
      expect(thinned.last.time, lessThan(9000));
    });
  });
}
