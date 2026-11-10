// Batch 152 (user call, after looking at how other
// players keep numbering in one universe): when TMDB's
// entry has no season matching the subject's stated one
// (batch 151's hard boundary), stills are aligned by AIR
// DATE instead of episode number. The subject's Bangumi
// air dates — newly parsed into EpisodeInfo — are the
// key; only exact, unambiguous date groups attach.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/bangumi/episode_item.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

TmdbEpisodeStill still(String name, String airDate) => TmdbEpisodeStill(
      imageUrl: 'img/$name',
      name: name,
      airDate: airDate,
      runtimeMinutes: 24,
    );

void main() {
  group('EpisodeInfo air date (batch 152)', () {
    test('fromJson reads the airdate field', () {
      final info = EpisodeInfo.fromJson({
        'id': 1,
        'sort': 3,
        'type': 0,
        'name': 'x',
        'name_cn': 'y',
        'airdate': '2026-10-16',
      });
      expect(info.airDate, '2026-10-16');
    });

    test('fromJson defaults to empty without an airdate', () {
      final info = EpisodeInfo.fromJson({'id': 1, 'sort': 1, 'type': 0});
      expect(info.airDate, '');
    });
  });

  group('air-date alignment (batch 152)', () {
    test('a merged-season show yields this season\u2019s stills only', () {
      // The 药屋 case: the subject is season 3 (12 episodes,
      // 2026 dates); TMDB's single season runs 1..60 across
      // all cours, so eps 49..60 carry the 2026 dates.
      final aligned = alignStillsByAirDate(
        subjectEpisodeDates: const {
          1: '2026-10-02',
          2: '2026-10-09',
          3: '2026-10-16',
        },
        tmdbEpisodes: [
          still('S2 finale', '2025-07-04'),
          still('S3 opener', '2026-10-02'),
          still('S3 second', '2026-10-09'),
          still('S3 third', '2026-10-16'),
          still('undated special', ''),
        ],
      );
      expect(aligned.keys.toList()..sort(), [1, 2, 3]);
      expect(aligned[1]!.name, 'S3 opener');
      expect(aligned[3]!.name, 'S3 third');
    });

    test('a double-episode premiere zips in order', () {
      final aligned = alignStillsByAirDate(
        subjectEpisodeDates: const {1: '2026-01-05', 2: '2026-01-05'},
        tmdbEpisodes: [
          still('part one', '2026-01-05'),
          still('part two', '2026-01-05'),
        ],
      );
      expect(aligned[1]!.name, 'part one');
      expect(aligned[2]!.name, 'part two');
    });

    test('a date group with mismatched sizes is left unaligned', () {
      // TMDB lists two episodes on the date, the subject
      // one (a special exists only on TMDB's side) —
      // guessing would risk the wrong still, so none.
      final aligned = alignStillsByAirDate(
        subjectEpisodeDates: const {1: '2026-01-05'},
        tmdbEpisodes: [
          still('episode', '2026-01-05'),
          still('special', '2026-01-05'),
        ],
      );
      expect(aligned, isEmpty);
    });

    test('subject episodes without dates never align', () {
      final aligned = alignStillsByAirDate(
        subjectEpisodeDates: const {1: '', 2: '2026-01-12'},
        tmdbEpisodes: [still('dated', '2026-01-12')],
      );
      expect(aligned.keys.toList(), [2]);
    });

    test('no overlapping dates means no stills', () {
      final aligned = alignStillsByAirDate(
        subjectEpisodeDates: const {1: '2026-10-02'},
        tmdbEpisodes: [still('other show era', '2023-04-01')],
      );
      expect(aligned, isEmpty);
    });
  });
}
