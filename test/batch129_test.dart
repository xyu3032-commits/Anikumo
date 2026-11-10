import 'package:flutter_test/flutter_test.dart';

import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

void main() {
  group('parseTmdbSeasonEpisodes (batch 129)', () {
    test('maps episode numbers to stills with the w500 prefix', () {
      final stills = parseTmdbSeasonEpisodes({
        'episodes': [
          {
            'episode_number': 1,
            'still_path': '/abc.jpg',
            'name': '第一话',
            'air_date': '2024-07-05',
            'runtime': 24,
          },
          {
            'episode_number': 2,
            'still_path': null,
            'name': '第二话',
            'air_date': '2024-07-12',
            'runtime': null,
          },
        ],
      });
      expect(stills[1]?.imageUrl, 'https://image.tmdb.org/t/p/w500/abc.jpg');
      expect(stills[1]?.name, '第一话');
      expect(stills[1]?.airDate, '2024-07-05');
      expect(stills[1]?.runtimeMinutes, 24);
      // A missing still stays empty (the picker falls back to
      // the series cover) but the metadata still lands.
      expect(stills[2]?.imageUrl, '');
      expect(stills[2]?.runtimeMinutes, 0);
    });

    test('garbage payloads parse to an empty map', () {
      expect(parseTmdbSeasonEpisodes({}), isEmpty);
      expect(parseTmdbSeasonEpisodes({'episodes': 'nope'}), isEmpty);
    });
  });

  group('pickTmdbShowId (batch 129)', () {
    final results = [
      {'id': 10, 'name': '别的番', 'first_air_date': '2024-01-01'},
      {'id': 20, 'name': '目标番', 'first_air_date': '2020-04-01'},
      {'id': 30, 'name': '目标番', 'first_air_date': '2024-04-01'},
    ];

    test('an exact title match beats recency', () {
      expect(
        pickTmdbShowId(results, name: '', nameCn: '目标番', year: null),
        20,
      );
    });

    test('the premiere year breaks title ties', () {
      expect(
        pickTmdbShowId(results, name: '', nameCn: '目标番', year: 2024),
        30,
      );
    });

    test('no results resolves to null', () {
      expect(pickTmdbShowId([], name: 'x', nameCn: 'x', year: 2024), isNull);
    });
  });

  group('pickTmdbSeason (batch 129)', () {
    final seasons = [
      (number: 0, episodeCount: 3),
      (number: 1, episodeCount: 12),
      (number: 2, episodeCount: 24),
    ];

    test('a season stated in the title wins (Arabic and Chinese)', () {
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
          title: '',
          titleCn: '某番 第三季',
          episodeCount: 12,
        ),
        1, // no season 3 exists — falls through to count match
      );
    });

    test('episode count match comes next', () {
      expect(
        pickTmdbSeason(
          seasons: seasons,
          title: 'Some Show',
          titleCn: '某番',
          episodeCount: 24,
        ),
        2,
      );
    });

    test('defaults to the first real season, never specials', () {
      expect(
        pickTmdbSeason(
          seasons: seasons,
          title: 'Some Show',
          titleCn: '某番',
          episodeCount: 99,
        ),
        1,
      );
    });
  });

  group('statedSeasonNumber (batch 129)', () {
    test('parses the common forms', () {
      expect(statedSeasonNumber('某番 第2期'), 2);
      expect(statedSeasonNumber('某番 第二季'), 2);
      expect(statedSeasonNumber('Show Season 3'), 3);
      expect(statedSeasonNumber('普通标题'), isNull);
    });
  });
}
