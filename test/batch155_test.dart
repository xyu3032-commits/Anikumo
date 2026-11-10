// Batch 155 (user report: "some episodes have no
// image"): three still-losing holes are closed —
// 1. the persistent cache moves to v5: v4's date-aligned
//    entries were keyed by the franchise numbering batch
//    153 replaced, so combined subjects read back a map
//    whose keys never matched the renumbered grid;
// 2. cache entries now carry a write time and go stale
//    after a week (TMDB adds stills for airing shows
//    after the first fetch; a partial map used to be
//    permanent);
// 3. air-date alignment gains a guarded ±1-day second
//    pass (the two databases disagree by a day on some
//    episodes: late-night broadcasts).
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

TmdbEpisodeStill still(String date, String tag) => TmdbEpisodeStill(
      imageUrl: 'https://img/$tag.jpg',
      name: tag,
      airDate: date,
      runtimeMinutes: 24,
    );

void main() {
  group('one-day tolerance pass (batch 155)', () {
    test('an episode one day off in TMDB still aligns', () {
      final out = alignStillsByAirDate(
        subjectEpisodeDates: {4: '2026-10-03'},
        tmdbEpisodes: [still('2026-10-04', 's3e4')],
      );
      expect(out[4]?.name, 's3e4');
    });

    test('an episode one day earlier in TMDB aligns too', () {
      final out = alignStillsByAirDate(
        subjectEpisodeDates: {4: '2026-10-03'},
        tmdbEpisodes: [still('2026-10-02', 's3e4')],
      );
      expect(out[4]?.name, 's3e4');
    });

    test('candidates on BOTH neighbouring days are ambiguous: no guess', () {
      final out = alignStillsByAirDate(
        subjectEpisodeDates: {4: '2026-10-03'},
        tmdbEpisodes: [
          still('2026-10-02', 'before'),
          still('2026-10-04', 'after'),
        ],
      );
      expect(out, isEmpty);
    });

    test('exact matches win and are never stolen by the shifted pass', () {
      final out = alignStillsByAirDate(
        subjectEpisodeDates: {1: '2026-10-03', 2: '2026-10-04'},
        tmdbEpisodes: [still('2026-10-03', 'e1')],
      );
      expect(out[1]?.name, 'e1');
      expect(out.containsKey(2), isFalse);
    });

    test('a shifted group must match in count, like the exact pass', () {
      final out = alignStillsByAirDate(
        subjectEpisodeDates: {4: '2026-10-03', 5: '2026-10-03'},
        tmdbEpisodes: [still('2026-10-04', 'only-one')],
      );
      expect(out, isEmpty);
    });

    test('a shifted double episode zips in order', () {
      final out = alignStillsByAirDate(
        subjectEpisodeDates: {4: '2026-10-03', 5: '2026-10-03'},
        tmdbEpisodes: [
          still('2026-10-02', 'e4'),
          still('2026-10-02', 'e5'),
        ],
      );
      expect(out[4]?.name, 'e4');
      expect(out[5]?.name, 'e5');
    });

    test('two days off is still too far', () {
      final out = alignStillsByAirDate(
        subjectEpisodeDates: {4: '2026-10-03'},
        tmdbEpisodes: [still('2026-10-05', 'far')],
      );
      expect(out, isEmpty);
    });
  });

  group('tmdbCacheEntryIsFresh (batch 155)', () {
    const now = 1762000000000;
    const day = 24 * 60 * 60 * 1000;

    test('a v5 entry written now is fresh', () {
      expect(
        tmdbCacheEntryIsFresh(version: 5, writtenAtMs: now, nowMs: now),
        isTrue,
      );
      expect(
        tmdbCacheEntryIsFresh(
          version: 5,
          writtenAtMs: now - 6 * day,
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('a v5 entry a week old is stale', () {
      expect(
        tmdbCacheEntryIsFresh(
          version: 5,
          writtenAtMs: now - 7 * day,
          nowMs: now,
        ),
        isFalse,
      );
    });

    test('older formats and missing/future stamps are stale', () {
      expect(
        tmdbCacheEntryIsFresh(version: 4, writtenAtMs: now, nowMs: now),
        isFalse,
      );
      expect(
        tmdbCacheEntryIsFresh(version: 5, writtenAtMs: 0, nowMs: now),
        isFalse,
      );
      expect(
        tmdbCacheEntryIsFresh(
          version: 5,
          writtenAtMs: now + day,
          nowMs: now,
        ),
        isFalse,
      );
    });
  });
}
