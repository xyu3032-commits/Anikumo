import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/bangumi/bangumi_tag.dart';
import 'package:anikumo/services/browse/daily_picks.dart';
import 'package:anikumo/services/browse/similarity.dart';
import 'package:anikumo/services/hub/command_registry.dart';

BangumiItem _item(int id, {List<String> tags = const [], double score = 0}) {
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
    ratingScore: score,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

void main() {
  test('daily picks are stable within a day and exclude watched ids', () {
    final pool = [for (var i = 1; i <= 20; i++) _item(i)];
    final date = DateTime(2026, 11, 6);
    final first = dailyPicks(pool, date: date, count: 5, excludeIds: {1, 2});
    final second = dailyPicks(pool, date: date, count: 5, excludeIds: {1, 2});
    expect(first.map((e) => e.id), second.map((e) => e.id));
    expect(first.length, 5);
    expect(first.any((e) => e.id == 1 || e.id == 2), isFalse);
  });

  test('rankSimilar orders by shared tags then score', () {
    final source = _item(1, tags: ['科幻', '机器人', '战斗']);
    final ranked = rankSimilar(source, [
      _item(2, tags: ['科幻'], score: 9.0),
      _item(3, tags: ['科幻', '机器人'], score: 7.0),
      _item(4, tags: ['日常']),
      _item(1, tags: ['科幻', '机器人', '战斗']),
    ]);
    expect(ranked.map((e) => e.id), [3, 2]);
  });

  test('command matcher ranks title hits above keyword hits', () {
    final results = matchCommands('备份');
    expect(results.first.title, '本地备份与恢复');
    final byKeyword = matchCommands('rank');
    expect(byKeyword.single.title, '排行榜');
    expect(matchCommands('').length, hubCommands.length);
    expect(matchCommands('不存在的功能xyz'), isEmpty);
  });
}
