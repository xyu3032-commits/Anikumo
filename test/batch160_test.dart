// Batch 160: source-sheet result ordering — the result
// for the season the subject states leads its plugin
// group (and therefore the auto-preview), instead of the
// site's newest-first top hit.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

void main() {
  group('orderByStatedSeason (batch 160)', () {
    test('second-season subject: S2 leads, wrong seasons sink', () {
      final ordered = orderByStatedSeason<String>(
        ['药屋少女的呢喃 第三季', '药屋少女的呢喃 第二季', '药屋少女的呢喃 第一季'],
        statedSeason: 2,
        titleOf: (s) => s,
      );
      expect(ordered, [
        '药屋少女的呢喃 第二季',
        '药屋少女的呢喃 第三季',
        '药屋少女的呢喃 第一季',
      ]);
    });

    test('season-less results sit between match and mismatch', () {
      final ordered = orderByStatedSeason<String>(
        ['某番 第3期', '某番', '某番 第2期'],
        statedSeason: 2,
        titleOf: (s) => s,
      );
      expect(ordered, ['某番 第2期', '某番', '某番 第3期']);
    });

    test('first-season subject: base entry and S1 lead together', () {
      final ordered = orderByStatedSeason<String>(
        ['某番 第二季', '某番', '某番 第一季'],
        statedSeason: 1,
        titleOf: (s) => s,
      );
      expect(ordered, ['某番', '某番 第一季', '某番 第二季']);
    });

    test('english ordinal markers count as stated seasons', () {
      final ordered = orderByStatedSeason<String>(
        ['Show 3rd Season', 'Show 2nd Season'],
        statedSeason: 2,
        titleOf: (s) => s,
      );
      expect(ordered, ['Show 2nd Season', 'Show 3rd Season']);
    });

    test('no stated season leaves the order untouched', () {
      const input = ['某番 第三季', '某番 第二季'];
      expect(
        orderByStatedSeason<String>(input,
            statedSeason: null, titleOf: (s) => s),
        input,
      );
    });

    test('order inside a rank is stable', () {
      final ordered = orderByStatedSeason<String>(
        ['甲 第二季 A站版', '乙 第二季', '甲 第三季'],
        statedSeason: 2,
        titleOf: (s) => s,
      );
      expect(ordered, ['甲 第二季 A站版', '乙 第二季', '甲 第三季']);
    });
  });
}
