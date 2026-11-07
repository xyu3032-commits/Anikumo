import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/pages/history/history_other_media.dart';
import 'package:anikumo/services/manga/cross_media.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';

/// Batch 80: the anime-zone history page gained 全部 /
/// 漫画 / 小说 modes. The 全部 merge is a pure projection
/// of the three zones' records into one newest-first
/// stream.
void main() {
  BangumiItem bangumi(int id, String name) => BangumiItem(
        id: id,
        type: 2,
        name: name,
        nameCn: name,
        summary: '',
        airDate: '',
        airWeekday: 0,
        rank: 0,
        images: const {},
        tags: const [],
        alias: const [],
        ratingScore: 0,
        votes: 0,
        votesCount: const [],
        info: '',
      );

  History anime(int id, String name, int timeMs) => History(
        bangumi(id, name),
        3,
        'ruleA',
        DateTime.fromMillisecondsSinceEpoch(timeMs),
        '',
        '',
      );

  MangaProgress manga(String id, int timeMs) => MangaProgress(
        mangaId: id,
        mangaTitle: '漫画$id',
        coverUrl: '',
        chapterId: 'c1',
        chapterLabel: '第 1 话',
        page: 0,
        totalPages: 10,
        updatedAtMs: timeMs,
        mangaSource: 'js:s',
      );

  NovelProgress novel(String title, int timeMs) => NovelProgress(
        item: NovelItem(bookUrl: 'u-$title', title: title),
        chapterIndex: 0,
        chapterTitle: '第一章',
        updatedAt: timeMs,
      );

  group('buildAllHistoryEntries', () {
    test('merges all three media newest first, tagged by kind', () {
      final entries = buildAllHistoryEntries(
        anime: [anime(1, '番A', 100)],
        manga: [manga('m1', 300)],
        novel: [novel('书A', 200)],
      );
      expect(entries.map((e) => e.mode), [
        CrossSearchMode.manga,
        CrossSearchMode.novel,
        CrossSearchMode.anime,
      ]);
      expect(entries.map((e) => e.kindLabel), ['漫画', '小说', '动漫']);
      expect(entries.first.title, '漫画m1');
      expect(entries.first.subtitle, contains('第 1 话'));
    });

    test('respects the limit after sorting', () {
      final entries = buildAllHistoryEntries(
        anime: [anime(1, '番A', 100), anime(2, '番B', 400)],
        manga: [manga('m1', 300)],
        novel: const [],
        limit: 2,
      );
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.timeMs), [400, 300]);
    });

    test('empty inputs give an empty stream', () {
      expect(
        buildAllHistoryEntries(anime: const [], manga: const [], novel: const []),
        isEmpty,
      );
    });
  });

  group('single-medium projections', () {
    test('manga entries carry resume info in the subtitle', () {
      final entries = mangaHistoryEntries([manga('m9', 5)]);
      expect(entries.single.subtitle, '第 1 话 · 第 1 页');
      expect(entries.single.mangaProgress?.mangaId, 'm9');
    });

    test('novel entries use the chapter title', () {
      final entries = novelHistoryEntries([novel('书B', 5)]);
      expect(entries.single.title, '书B');
      expect(entries.single.subtitle, '第一章');
      expect(entries.single.novelProgress?.item.title, '书B');
    });
  });
}
