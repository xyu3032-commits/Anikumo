import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/modules/history/history_sync.dart';
import 'package:anikumo/services/backup/local_backup.dart';

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

void main() {
  Map<String, dynamic> samplePayload() {
    final history = History(
      _item(42),
      3,
      'test-source',
      DateTime(2026, 11, 1),
      '',
      '第三集',
    );
    history.progresses[3] = Progress(3, 0, 60000, updatedAtMs: 1000);
    return {
      'app': 'anikumo',
      'formatVersion': 1,
      'histories': [HistorySyncCodec.historyToJson(history)],
      'collectibles': [
        {
          'bangumiItem': HistorySyncCodec.bangumiItemToJson(_item(42)),
          'time': '2026-11-01T00:00:00.000',
          'type': 1,
        },
      ],
      'searchHistories': [
        {'keyword': '芙莉莲', 'timestamp': 123},
      ],
      'userLists': [
        {'id': 'x1', 'name': '神作', 'bangumiIds': [42]},
      ],
      'notes': {'42': '第 8 集封神'},
      'glassLevel': 2,
    };
  }

  test('parses a full backup payload', () {
    final data = LocalBackup.parse(jsonEncode(samplePayload()));
    expect(data, isNotNull);
    expect(data!.histories.length, 1);
    expect(data.histories.single.bangumiItem.id, 42);
    expect(data.histories.single.lastWatchEpisode, 3);
    expect(data.collectibles.single.type, 1);
    expect(data.searchHistories.single.keyword, '芙莉莲');
    expect(data.userLists.single.bangumiIds, [42]);
    expect(data.notes[42], '第 8 集封神');
    expect(data.glassLevel, 2);
  });

  test('rejects non-backup content', () {
    expect(LocalBackup.parse('not json'), isNull);
    expect(LocalBackup.parse('[1,2]'), isNull);
    expect(LocalBackup.parse('{}'), isNull);
    expect(
      LocalBackup.parse(jsonEncode({'formatVersion': 99})),
      isNull,
    );
  });

  test('accepts a backup with missing optional sections', () {
    final data = LocalBackup.parse(
      jsonEncode({'formatVersion': 1, 'histories': []}),
    );
    expect(data, isNotNull);
    expect(data!.collectibles, isEmpty);
    expect(data.notes, isEmpty);
    expect(data.glassLevel, isNull);
  });
}
