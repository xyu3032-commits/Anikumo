// Batch 64 pins: cross-zone dedicated modes must behave like
// the target zone's own search. The bug: the anime-zone manga
// and novel modes reused the companion-section STRICT filter —
// when returned titles didn't literally contain the keyword
// (alternate / translated names), the dedicated mode rendered
// empty while the same search inside the manga/novel zone
// showed the results. These tests pin the two-view contract
// the search pages now implement: strict for sections,
// unfiltered-but-ranked for dedicated modes.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:anikumo/services/novel/novel_api.dart';

MangaItem _manga(String id, String title) => MangaItem(
      id: id,
      title: title,
      description: '',
      coverUrl: '',
      author: '',
      status: '',
      year: 0,
      tags: const [],
      source: 'test',
    );

NovelItem _novel(String id, String title) => NovelItem(
      bookUrl: id,
      title: title,
      source: 'test',
      sourceName: '测试源',
    );

void main() {
  group('manga two-view contract', () {
    // The source answered a search for the Chinese name with
    // editions titled in Japanese — nothing "contains" the
    // keyword, so every item scores 3.
    final returned = [
      _manga('1', '進撃の巨人'),
      _manga('2', '進撃の巨人 Before the fall'),
    ];

    test('strict section view empties (by design)', () {
      final section = filterRelevantMangaResults(
        rankMangaResults(returned, '进击的巨人'),
        '进击的巨人',
        strict: true,
      );
      expect(section, isEmpty);
    });

    test('dedicated mode view keeps the ranked source results', () {
      final mode = rankMangaResults(returned, '进击的巨人');
      expect(mode.map((e) => e.id), ['1', '2']);
    });
  });

  group('novel two-view contract', () {
    final returned = [
      _novel('1', 'Re:ゼロから始める異世界生活'),
      _novel('2', 'ようこそ実力至上主義の教室へ'),
    ];

    test('strict ranking drops every non-matching title', () {
      final section =
          rankNovels('从零开始的异世界生活', returned, strict: true);
      expect(section, isEmpty);
    });

    test('non-strict ranking keeps all results, best first', () {
      final withHit = [
        _novel('3', '从零开始的异世界生活 外传'),
        ...returned,
      ];
      final mode = rankNovels('从零开始的异世界生活', withHit);
      expect(mode.length, 3);
      expect(mode.first.id, '3');
    });
  });
}
