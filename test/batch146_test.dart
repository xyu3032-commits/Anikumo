// Batch 146: original icon set policy.
//
// Two rules are pinned here:
//  1. Universally recognised glyphs (next-episode/skip,
//     play, arrows, heart/star/bookmark states, search,
//     the settings gear, ...) alias the Material icons so
//     they stay instantly readable.
//  2. Everything else comes from the bundled original
//     AnikumoIcons font.
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batch146 icon policy', () {
    test('high-recognition icons alias Material', () {
      expect(AnikumoIcons.skip_next_rounded, Icons.skip_next_rounded);
      expect(AnikumoIcons.skip_previous, Icons.skip_previous);
      expect(AnikumoIcons.play_arrow_rounded, Icons.play_arrow_rounded);
      expect(AnikumoIcons.pause_rounded, Icons.pause_rounded);
      expect(AnikumoIcons.arrow_back_rounded, Icons.arrow_back_rounded);
      expect(AnikumoIcons.close_rounded, Icons.close_rounded);
      expect(AnikumoIcons.check_rounded, Icons.check_rounded);
      expect(AnikumoIcons.search_rounded, Icons.search_rounded);
      expect(AnikumoIcons.settings_outlined, Icons.settings_outlined);
      expect(AnikumoIcons.favorite_rounded, Icons.favorite_rounded);
      expect(AnikumoIcons.star_rounded, Icons.star_rounded);
      expect(AnikumoIcons.bookmark_rounded, Icons.bookmark_rounded);
      expect(AnikumoIcons.home_rounded, Icons.home_rounded);
    });

    test('original icons come from the AnikumoIcons font', () {
      const originals = <IconData>[
        AnikumoIcons.cloud_rounded,
        AnikumoIcons.cloud_off_rounded,
        AnikumoIcons.movie_outlined,
        AnikumoIcons.menu_book_rounded,
        AnikumoIcons.library_books,
        AnikumoIcons.emoji_events_outlined,
        AnikumoIcons.rocket_launch_rounded,
        AnikumoIcons.tune_rounded,
        AnikumoIcons.subtitles_outlined,
        AnikumoIcons.extension_rounded,
      ];
      for (final icon in originals) {
        expect(icon.fontFamily, AnikumoIcons.family,
            reason: 'codepoint 0x${icon.codePoint.toRadixString(16)}');
        expect(icon.codePoint, inInclusiveRange(0xE001, 0xF8FF));
      }
    });

    test('custom directional icons keep text-direction matching', () {
      expect(AnikumoIcons.swap_horiz_rounded.matchTextDirection, isTrue);
      expect(AnikumoIcons.cloud_rounded.matchTextDirection, isFalse);
    });
  });
}
