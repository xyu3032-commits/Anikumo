// Batch 151 (user v39 test): a third-season entry still
// showed the whole series — 60 episodes, season 2 stills
// and 2025 air dates, and tapping an episode played the
// wrong one. Root cause on the TMDB side: the matched
// TMDB entry files every cour under ONE 60-episode
// season, so batch 150's picker, finding no season 3,
// fell back to that merged season and borrowed all of
// it. seasonForStills makes a title-stated season a hard
// boundary: stated but missing means NO stills at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

void main() {
  group('stated season is a hard boundary (batch 151)', () {
    // The pathological TMDB entry: one merged season.
    final merged = [
      (number: 0, episodeCount: 3),
      (number: 1, episodeCount: 60),
    ];

    test('third-season subject over a merged entry gets no stills', () {
      expect(
        seasonForStills(
          seasons: merged,
          title: '',
          titleCn: '药屋少女的呢喃 第三季',
          episodeCount: 12,
        ),
        isNull,
      );
    });

    test('second-season subject over split entries picks season 2', () {
      expect(
        seasonForStills(
          seasons: const [
            (number: 1, episodeCount: 24),
            (number: 2, episodeCount: 24),
            (number: 3, episodeCount: 12),
          ],
          title: '',
          titleCn: '某番 第二季',
          episodeCount: 24,
        ),
        2,
      );
    });

    test('stated season present wins over the episode-count match', () {
      expect(
        seasonForStills(
          seasons: const [
            (number: 1, episodeCount: 12),
            (number: 2, episodeCount: 12),
          ],
          title: '',
          titleCn: '某番 第二季',
          episodeCount: 12,
        ),
        2,
      );
    });

    test('a stated season 0 is not honoured as a real season', () {
      expect(
        seasonForStills(
          seasons: const [
            (number: 0, episodeCount: 4),
            (number: 1, episodeCount: 12),
          ],
          title: 'Some Show Season 0',
          titleCn: '某番',
          episodeCount: 4,
        ),
        isNull,
      );
    });

    test('unstated title keeps the count-match behaviour', () {
      expect(
        seasonForStills(
          seasons: const [
            (number: 1, episodeCount: 24),
            (number: 2, episodeCount: 12),
          ],
          title: '',
          titleCn: '某番',
          episodeCount: 12,
        ),
        2,
      );
    });

    test('unstated title with no count match takes the first season', () {
      expect(
        seasonForStills(
          seasons: merged,
          title: '',
          titleCn: '某番',
          episodeCount: 0,
        ),
        1,
      );
    });
  });
}
