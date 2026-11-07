import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/services/browse/rank_order.dart';

BangumiItem _item(int id, {int rank = 0, int votes = 0}) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
    summary: '',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: rank,
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
    votes: votes,
    votesCount: const [],
    info: '',
  );
}

void main() {
  test('orders by Bangumi rank ascending', () {
    final sorted = sortByBangumiRank([
      _item(1, rank: 30),
      _item(2, rank: 5),
      _item(3, rank: 12),
    ]);
    expect(sorted.map((e) => e.id), [2, 3, 1]);
  });

  test('unranked titles sink below ranked ones regardless of votes', () {
    final sorted = sortByBangumiRank([
      _item(1, rank: 0, votes: 99999),
      _item(2, rank: 800),
    ]);
    expect(sorted.map((e) => e.id), [2, 1]);
  });

  test('votes break ties, both for ranked and unranked titles', () {
    final sorted = sortByBangumiRank([
      _item(1, rank: 10, votes: 100),
      _item(2, rank: 10, votes: 500),
      _item(3, rank: 0, votes: 50),
      _item(4, rank: 0, votes: 900),
    ]);
    expect(sorted.map((e) => e.id), [2, 1, 4, 3]);
  });

  test('does not mutate the input list', () {
    final input = [_item(1, rank: 9), _item(2, rank: 1)];
    sortByBangumiRank(input);
    expect(input.map((e) => e.id), [1, 2]);
  });
}
