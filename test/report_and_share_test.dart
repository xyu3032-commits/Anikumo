import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/bangumi/bangumi_tag.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/services/share/share_builders.dart';
import 'package:anikumo/services/stats/report_stats.dart';

BangumiItem _item(int id, {List<String> tags = const []}) {
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
    tags: [for (final name in tags) BangumiTag(name: name, count: 1, totalCount: 1)],
    alias: const [],
    ratingScore: 8.0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

History _history(int id, DateTime at, {List<String> tags = const []}) {
  final history = History(_item(id, tags: tags), 1, 'src', at, '', '');
  history.progresses[1] = Progress(
    1,
    0,
    const Duration(minutes: 20).inMilliseconds,
    updatedAtMs: at.millisecondsSinceEpoch,
  );
  return history;
}

void main() {
  test('monthly report aggregates one month only', () {
    final histories = [
      _history(1, DateTime(2026, 11, 3), tags: ['科幻']),
      _history(2, DateTime(2026, 11, 3), tags: ['科幻', '战斗']),
      _history(3, DateTime(2026, 10, 3), tags: ['日常']),
    ];
    final report = computeMonthlyReport(histories, year: 2026, month: 11);
    expect(report.episodes, 2);
    expect(report.minutes, 40);
    expect(report.activeDays, 1);
    expect(report.topTags.first.name, '科幻');
  });

  test('daily counts include zero days and recent activity', () {
    final counts = dailyEpisodeCounts(
      [_history(1, DateTime(2026, 11, 6))],
      today: DateTime(2026, 11, 6),
      days: 7,
    );
    expect(counts.length, 7);
    expect(counts[DateTime(2026, 11, 6)], 1);
    expect(counts[DateTime(2026, 11, 5)], 0);
  });

  test('list share text is numbered with a summary header', () {
    final text = buildListShareText('我的片单', [_item(1), _item(2)]);
    expect(text, contains('共 2 部'));
    expect(text, contains('1. 条目 1 · 评分 8.0'));
    expect(text, contains('2. 条目 2'));
  });

  test('ics export emits weekly rules per show', () {
    final ics = buildBangumiCalendarIcs(
      [(item: _item(9), weekday: 5)],
      fromDate: DateTime(2026, 11, 2), // a Monday
    );
    expect(ics, contains('BEGIN:VCALENDAR'));
    expect(ics, contains('RRULE:FREQ=WEEKLY;BYDAY=FR'));
    // Next Friday on/after Mon 2026-11-02 is 2026-11-06.
    expect(ics, contains('DTSTART:20261106T200000'));
    expect(ics, contains('SUMMARY:条目 9 更新'));
  });
}
