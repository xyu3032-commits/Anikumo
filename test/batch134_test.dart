import 'package:flutter_test/flutter_test.dart';

import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/bangumi/bangumi_tag.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/services/player/watch_history_lookup.dart';

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
    tags: const <BangumiTag>[],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

History _history(
  int bangumiId,
  String plugin,
  DateTime when, {
  String src = 'src',
  Map<int, Progress> progresses = const {},
}) {
  final history = History(
    _item(bangumiId),
    1,
    plugin,
    when,
    src,
    '',
  );
  history.progresses = progresses;
  return history;
}

Progress _progress(int episode, int road, int minutes, int updatedAtMs) {
  return Progress(
    episode,
    road,
    Duration(minutes: minutes).inMilliseconds,
    updatedAtMs: updatedAtMs,
  );
}

void main() {
  group('episode picker memory (batch 134)', () {
    test('the newest record across sources is the default line', () {
      final older = _history(7, '源A', DateTime(2026, 1, 1));
      final newer = _history(7, '源B', DateTime(2026, 2, 1));
      final other = _history(8, '源C', DateTime(2026, 3, 1));
      expect(latestOnlineHistory([older, newer, other], 7), newer);
      expect(latestOnlineHistory([older, newer], 99), isNull);
      expect(historyForPlugin([older, newer], 7, '源A'), older);
    });

    test('offline records never become the online default', () {
      final offline = _history(
        7,
        '源A',
        DateTime(2026, 3, 1),
      )..entryKind = HistoryEntryKind.offline;
      expect(latestOnlineHistory([offline], 7), isNull);
    });

    test('preferred road follows the most recent progress', () {
      final history = _history(
        7,
        '源A',
        DateTime(2026, 2, 1),
        progresses: {
          3: _progress(3, 0, 20, 100),
          9: _progress(9, 2, 5, 900),
        },
      );
      expect(preferredRoadIndex(history, 3), 2);
      expect(preferredRoadIndex(history, 2), 1, reason: 'clamped');
      expect(preferredRoadIndex(null, 3), 0);
    });

    test('watched durations are per-road and skip zero progress', () {
      final history = _history(
        7,
        '源A',
        DateTime(2026, 2, 1),
        progresses: {
          1: _progress(1, 0, 24, 100),
          2: _progress(2, 0, 0, 200),
          3: _progress(3, 1, 10, 300),
        },
      );
      expect(watchedDurations(history, 0), {
        1: const Duration(minutes: 24),
      });
      expect(watchedDurations(history, 1), {
        3: const Duration(minutes: 10),
      });
      expect(watchedDurations(null, 0), isEmpty);
    });
  });

  group('grey fill + duration label (batch 134)', () {
    test('half watched of a 24-minute episode fills half', () {
      expect(watchFraction(const Duration(minutes: 12), 24), 0.5);
      expect(watchFraction(const Duration(minutes: 30), 24), 1.0);
      expect(watchFraction(const Duration(minutes: 12), 0), 0);
      expect(watchFraction(Duration.zero, 24), 0);
    });

    test('labels combine watched and total clocks', () {
      expect(
        episodeDurationLabel(
          watched: const Duration(minutes: 12, seconds: 34),
          totalMinutes: 24,
        ),
        '12:34 / 24:00',
      );
      expect(
        episodeDurationLabel(
          watched: const Duration(minutes: 3),
          totalMinutes: 0,
        ),
        '已看 3:00',
      );
      expect(
        episodeDurationLabel(watched: null, totalMinutes: 24),
        '24:00',
      );
      expect(episodeDurationLabel(watched: null, totalMinutes: 0), '');
      expect(formatWatchClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
  });
}
