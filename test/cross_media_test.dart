import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/cross_media.dart';

BangumiItem _anime(int id, String name, String nameCn) {
  return BangumiItem(
    id: id,
    type: 2,
    name: name,
    nameCn: nameCn,
    summary: '',
    airDate: '',
    airWeekday: 1,
    rank: 0,
    images: const {},
    tags: const [],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

MangaItem _manga(String id, String title) {
  return MangaItem(
    id: id,
    title: title,
    description: '',
    coverUrl: '',
    author: '',
    status: '',
    year: null,
    tags: const [],
  );
}

void main() {
  group('buildCrossQueries', () {
    test('orders primary, fallback and season-stripped bases', () {
      final queries = buildCrossQueries(
        primary: '间谍过家家 第二季',
        fallback: 'SPY×FAMILY',
      );
      expect(queries.first, '间谍过家家 第二季');
      expect(queries, contains('SPY×FAMILY'));
      expect(queries, contains('间谍过家家'));
      expect(queries.toSet().length, queries.length);
    });

    test('stripSeasonSuffix handles Chinese and English markers', () {
      expect(stripSeasonSuffix('某番 第3期'), '某番');
      expect(stripSeasonSuffix('Some Show Season 2'), 'Some Show');
      expect(stripSeasonSuffix('普通标题'), '普通标题');
    });
  });

  group('cross ranking', () {
    test('exact manga title matches come first', () {
      final ranked = rankCrossManga(
        [_manga('a', '间谍过家家 外传'), _manga('b', '间谍过家家')],
        '间谍过家家',
      );
      expect(ranked.map((m) => m.id), ['b', 'a']);
    });

    test('anime ranking checks both Chinese and original names', () {
      final ranked = rankCrossAnime(
        [_anime(1, 'Other', '别的'), _anime(2, 'SPY×FAMILY', '间谍过家家')],
        '间谍过家家',
      );
      expect(ranked.first.id, 2);
    });
  });
}
