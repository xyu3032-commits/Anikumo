// Batch 153 (user v41 test): a combined Bangumi subject
// carrying all three seasons (60 episodes) but titled
// 第三季 showed every season in the picker, and tapping
// 第52集 landed on the source's 第49集 — the franchise
// numbering never matched the season entry's own. The
// plan now slices the subject's episode list to the
// season its title states, located by air-date clusters,
// and renumbers the kept episodes from 1.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/bangumi/episode_item.dart';
import 'package:anikumo/pages/info/episode_plan.dart';

String fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

EpisodeInfo ep(int sort, DateTime? date, {int type = 0}) => EpisodeInfo(
      id: sort * 10,
      episode: sort,
      type: type,
      name: 'ep$sort',
      nameCn: '第$sort集标题',
      airDate: date == null ? '' : fmt(date),
    );

List<EpisodeInfo> season(int startSort, DateTime start, int count) => [
      for (var i = 0; i < count; i++)
        ep(startSort + i, start.add(Duration(days: 7 * i))),
    ];

void main() {
  // The 药屋 shape: one subject, three seasons, sorts 1..60.
  final combined = [
    ...season(1, DateTime(2023, 10, 7), 24),
    ...season(25, DateTime(2025, 1, 11), 24),
    ...season(49, DateTime(2026, 10, 3), 12),
  ];

  group('season slicing by air-date clusters (batch 153)', () {
    test('a third-season title keeps only the third cluster', () {
      final plan = planEpisodes(episodes: combined, statedSeason: 3);
      expect(plan.count, 12);
      expect(plan.episodes.first.sort, 49);
      expect(plan.episodes.first.number, 1);
      expect(plan.episodes.last.sort, 60);
      expect(plan.episodes.last.number, 12);
      expect(plan.scoped, isTrue);
      expect(plan.sortToNumber[52], 4);
    });

    test('a second-season title keeps the second cluster', () {
      final plan = planEpisodes(episodes: combined, statedSeason: 2);
      expect(plan.count, 24);
      expect(plan.episodes.first.sort, 25);
      expect(plan.episodes.last.sort, 48);
      expect(plan.episodes.last.number, 24);
      expect(plan.scoped, isTrue);
    });

    test('a first-season title keeps the first cluster', () {
      final plan = planEpisodes(episodes: combined, statedSeason: 1);
      expect(plan.count, 24);
      expect(plan.episodes.last.sort, 24);
      expect(plan.scoped, isTrue);
    });

    test('no stated season keeps everything, unscoped', () {
      final plan = planEpisodes(episodes: combined, statedSeason: null);
      expect(plan.count, 60);
      expect(plan.episodes.every((e) => e.sort == e.number), isTrue);
      expect(plan.scoped, isFalse);
    });

    test('a stated season beyond the clusters keeps everything', () {
      final plan = planEpisodes(episodes: combined, statedSeason: 5);
      expect(plan.count, 60);
      expect(plan.scoped, isFalse);
    });
  });

  group('renumbering without slicing (batch 153)', () {
    test('a sequel subject whose sorts continue the series renumbers', () {
      final plan = planEpisodes(
        episodes: season(49, DateTime(2026, 10, 3), 12),
        statedSeason: 3,
      );
      expect(plan.count, 12);
      expect(plan.episodes.first.sort, 49);
      expect(plan.episodes.first.number, 1);
      expect(plan.scoped, isTrue);
    });

    test('an ordinary single-season subject stays identical', () {
      final plan = planEpisodes(
        episodes: season(1, DateTime(2026, 10, 3), 12),
        statedSeason: 2,
      );
      expect(plan.count, 12);
      expect(plan.episodes.every((e) => e.sort == e.number), isTrue);
      expect(plan.scoped, isFalse);
    });
  });

  group('cluster edges (batch 153)', () {
    test('a three-week mid-season break does not split a cluster', () {
      final eps = [
        ep(1, DateTime(2026, 1, 3)),
        ep(2, DateTime(2026, 1, 10)),
        ep(3, DateTime(2026, 1, 31)), // 21 days later
        ep(4, DateTime(2026, 2, 7)),
        ep(5, DateTime(2026, 9, 5)), // ~7 months later
        ep(6, DateTime(2026, 9, 12)),
      ];
      final plan = planEpisodes(episodes: eps, statedSeason: 2);
      expect(plan.count, 2);
      expect(plan.episodes.first.sort, 5);
    });

    test('undated episodes stay with the previous dated one', () {
      final eps = [
        ep(1, null),
        ep(2, DateTime(2026, 1, 3)),
        ep(3, null),
        ep(4, DateTime(2026, 1, 10)),
        ep(5, DateTime(2026, 9, 5)),
        ep(6, DateTime(2026, 9, 12)),
      ];
      final plan = planEpisodes(episodes: eps, statedSeason: 2);
      expect(plan.count, 2);
      expect(plan.episodes.first.sort, 5);
      final whole = planEpisodes(episodes: eps, statedSeason: null);
      expect(whole.count, 6);
    });

    test('specials are excluded from the plan', () {
      final eps = [
        ...season(1, DateTime(2026, 10, 3), 3),
        ep(99, DateTime(2026, 10, 5), type: 1),
      ];
      final plan = planEpisodes(episodes: eps, statedSeason: null);
      expect(plan.count, 3);
    });
  });
}
