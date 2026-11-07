import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/services/stats/watch_stats.dart';

BangumiItem _item(int id) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
    summary: '',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: 0,
    images: const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    tags: const [],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

History _history(int id, Map<int, Progress> progresses, DateTime lastWatch) {
  final history = History(_item(id), 1, 'test-source', lastWatch, '', '');
  history.progresses.addAll(progresses);
  return history;
}

Progress _prog(int episode, int minutes, DateTime at) {
  return Progress(
    episode,
    0,
    Duration(minutes: minutes).inMilliseconds,
    updatedAtMs: at.millisecondsSinceEpoch,
  );
}

void main() {
  // 2026-11-06 is a Friday.
  final now = DateTime(2026, 11, 6, 20);

  test('empty history gives empty stats', () {
    final stats = computeWatchStats(const [], now: now);
    expect(stats.totalEpisodes, 0);
    expect(stats.totalMinutes, 0);
    expect(stats.distinctAnime, 0);
    expect(stats.last7DaysEpisodes, [0, 0, 0, 0, 0, 0, 0]);
    expect(stats.mostWatchedWeekday, 0);
  });

  test('aggregates episodes, minutes and anime count', () {
    final stats = computeWatchStats([
      _history(1, {1: _prog(1, 10, now), 2: _prog(2, 20, now)}, now),
      _history(2, {1: _prog(1, 30, now)}, now),
    ], now: now);
    expect(stats.totalEpisodes, 3);
    expect(stats.totalMinutes, 60);
    expect(stats.distinctAnime, 2);
  });

  test('buckets the last 7 days oldest-first and finds the top weekday',
      () {
    final yesterday = now.subtract(const Duration(days: 1));
    final stats = computeWatchStats([
      _history(
        1,
        {
          1: _prog(1, 5, now),
          2: _prog(2, 5, yesterday),
          3: _prog(3, 5, yesterday),
        },
        now,
      ),
    ], now: now);
    expect(stats.last7DaysEpisodes, [0, 0, 0, 0, 0, 2, 1]);
    // Thursday (4) has two episodes, Friday (5) has one.
    expect(stats.mostWatchedWeekday, 4);
  });

  test('activity older than 7 days leaves the week buckets empty', () {
    final old = now.subtract(const Duration(days: 10));
    final stats = computeWatchStats([
      _history(1, {1: _prog(1, 5, old)}, now),
    ], now: now);
    expect(stats.last7DaysEpisodes, [0, 0, 0, 0, 0, 0, 0]);
    expect(stats.totalEpisodes, 1);
  });
}
