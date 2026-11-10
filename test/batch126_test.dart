import 'package:flutter_test/flutter_test.dart';

import 'package:anikumo/bean/widget/mini_player_overlay.dart'
    show decodePipCatImages;
import 'package:anikumo/pages/video/video_playback_args.dart'
    show resolveInitialEpisode;

void main() {
  group('decodePipCatImages (batch 126)', () {
    test('empty and corrupt payloads decode to no images', () {
      expect(decodePipCatImages(''), isEmpty);
      expect(decodePipCatImages('not json'), isEmpty);
      expect(decodePipCatImages('{"a":1}'), isEmpty);
    });

    test('a JSON list decodes, dropping blanks and non-strings', () {
      expect(
        decodePipCatImages('["/a/1.png", "", 42, "/a/2.png"]'),
        ['/a/1.png', '/a/2.png'],
      );
    });
  });

  group('resolveInitialEpisode (batch 127)', () {
    test('no pick resolves to null (history resume wins)', () {
      expect(
        resolveInitialEpisode(
          initialEpisode: null,
          initialRoad: null,
          roadLengths: [12],
        ),
        isNull,
      );
    });

    test('a valid pick resolves with the road clamped in range', () {
      final resolved = resolveInitialEpisode(
        initialEpisode: 7,
        initialRoad: 9,
        roadLengths: [12, 24],
      );
      expect(resolved?.episode, 7);
      expect(resolved?.road, 1);
    });

    test('out-of-range picks resolve to null', () {
      expect(
        resolveInitialEpisode(
          initialEpisode: 0,
          initialRoad: 0,
          roadLengths: [12],
        ),
        isNull,
      );
      expect(
        resolveInitialEpisode(
          initialEpisode: 13,
          initialRoad: 0,
          roadLengths: [12],
        ),
        isNull,
      );
      expect(
        resolveInitialEpisode(
          initialEpisode: 1,
          initialRoad: 0,
          roadLengths: const [],
        ),
        isNull,
      );
    });
  });
}
