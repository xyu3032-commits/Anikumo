// Batch 150 (user call): seasons stay separate in the
// episode picker — batch 148's automatic merging of
// season 1 + 2 + … into one continuous stills map is
// reverted. A subject only ever resolves to its OWN
// season: a third-season entry must not show season 1/2
// content. The picker below is the exact decision the
// service makes before fetching a single season.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

void main() {
  group('seasons stay separate (batch 150)', () {
    final seasons = [
      (number: 0, episodeCount: 2),
      (number: 1, episodeCount: 12),
      (number: 2, episodeCount: 12),
      (number: 3, episodeCount: 13),
    ];

    test('a third-season subject picks season 3 only', () {
      expect(
        pickTmdbSeason(
          seasons: seasons,
          title: '',
          titleCn: '某番 第三季',
          episodeCount: 13,
        ),
        3,
      );
    });

    test('a second-season subject picks season 2 only', () {
      expect(
        pickTmdbSeason(
          seasons: seasons,
          title: '',
          titleCn: '某番 第2期',
          episodeCount: 12,
        ),
        2,
      );
      expect(
        pickTmdbSeason(
          seasons: seasons,
          title: 'Some Show Season 2',
          titleCn: '某番',
          episodeCount: 12,
        ),
        2,
      );
    });

    test('an unstated subject resolves to one single season', () {
      // No merging: whatever wins, it is exactly one season
      // of the show — never a blend of several.
      final picked = pickTmdbSeason(
        seasons: seasons,
        title: 'Some Show',
        titleCn: '某番',
        episodeCount: 12,
      );
      expect(picked, 1);
    });

    test('specials (season 0) are never picked', () {
      expect(
        pickTmdbSeason(
          seasons: seasons,
          title: '',
          titleCn: '某番',
          episodeCount: 2,
        ),
        1, // count 2 matches the specials — still not chosen
      );
    });
  });
}
