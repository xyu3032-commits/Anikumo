import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/manga/reader_settings.dart';

void main() {
  group('MangaItem.fromApi', () {
    test('prefers the Chinese title and builds the cover URL', () {
      final item = MangaItem.fromApi({
        'id': 'abc-123',
        'attributes': {
          'title': {'en': 'English Title', 'zh': '中文标题'},
          'description': {'en': 'A story.', 'zh': '一个故事。'},
          'status': 'ongoing',
          'year': 2023,
          'tags': [
            {
              'attributes': {
                'name': {'en': 'Action', 'zh': '动作'},
              },
            },
          ],
        },
        'relationships': [
          {
            'type': 'cover_art',
            'attributes': {'fileName': 'cover.jpg'},
          },
          {
            'type': 'author',
            'attributes': {'name': '某作者'},
          },
        ],
      });
      expect(item.title, '中文标题');
      expect(item.description, '一个故事。');
      expect(
        item.coverUrl,
        'https://uploads.mangadex.org/covers/abc-123/cover.jpg.512.jpg',
      );
      expect(item.author, '某作者');
      expect(item.statusLabel, '连载中');
      expect(item.tags, ['动作']);
    });

    test('falls back to alt titles and tolerates missing data', () {
      final item = MangaItem.fromApi({
        'id': 'x',
        'attributes': {
          'title': <String, String>{},
          'altTitles': [
            {'ja': '日本語タイトル'},
          ],
          'status': 'completed',
        },
        'relationships': [],
      });
      expect(item.title, '日本語タイトル');
      expect(item.coverUrl, '');
      expect(item.statusLabel, '已完结');
    });
  });

  group('MangaChapter.fromApi', () {
    test('builds labels and readability', () {
      final chapter = MangaChapter.fromApi({
        'id': 'ch-1',
        'attributes': {
          'volume': '3',
          'chapter': '12.5',
          'title': '决战',
          'translatedLanguage': 'zh',
          'pages': 24,
          'publishAt': '2026-01-01T00:00:00+00:00',
        },
      });
      expect(chapter.displayLabel, '第 12.5 话 决战');
      expect(chapter.languageLabel, '简中');
      expect(chapter.isReadable, isTrue);
    });

    test('zero-page chapters are not readable', () {
      final chapter = MangaChapter.fromApi({
        'id': 'ch-2',
        'attributes': {'pages': 0, 'translatedLanguage': 'en'},
      });
      expect(chapter.isReadable, isFalse);
      expect(chapter.displayLabel, '番外/单话');
    });
  });

  test('buildChapterPageUrls joins base, hash and file names', () {
    final urls = buildChapterPageUrls(
      'https://node.example',
      'hash9',
      ['1.jpg', '2.jpg'],
    );
    expect(urls, [
      'https://node.example/data/hash9/1.jpg',
      'https://node.example/data/hash9/2.jpg',
    ]);
  });

  group('MangaLibraryCodec', () {
    test('favorites round-trip and drop broken entries', () {
      final encoded = MangaLibraryCodec.encodeFavorites(const [
        MangaFavorite(id: 'm1', title: '标题', coverUrl: 'https://c'),
      ]);
      final decoded = MangaLibraryCodec.decodeFavorites(encoded);
      expect(decoded.single.id, 'm1');
      expect(MangaLibraryCodec.decodeFavorites('junk'), isEmpty);
      expect(MangaLibraryCodec.decodeFavorites('[{"title":"无id"}]'), isEmpty);
    });

    test('progress round-trips keyed by source-scoped manga key', () {
      final encoded = MangaLibraryCodec.encodeProgress(const {
        'm1': MangaProgress(
          mangaId: 'm1',
          mangaTitle: '标题',
          coverUrl: '',
          chapterId: 'c1',
          chapterLabel: '第 1 话',
          page: 3,
          totalPages: 20,
          updatedAtMs: 42,
        ),
      });
      final decoded = MangaLibraryCodec.decodeProgress(encoded);
      // Keys are source-scoped since batch 11; a progress entry
      // without an explicit source belongs to mangadex.
      expect(decoded['mangadex:m1']?.page, 3);
      expect(decoded['mangadex:m1']?.chapterLabel, '第 1 话');
    });
  });

  group('Venera-style reader settings', () {
    test('mode normalization migrates legacy values', () {
      expect(normalizeMangaReaderMode('paged'), MangaReaderModes.galleryLtr);
      expect(normalizeMangaReaderMode('scroll'), MangaReaderModes.continuous);
      expect(normalizeMangaReaderMode('galleryRTL'),
          MangaReaderModes.galleryRtl);
      expect(normalizeMangaReaderMode('whatever'), MangaReaderModes.galleryLtr);
    });

    test('content ratings follow the suggestive toggle', () {
      expect(mangaContentRatings(true), ['safe', 'suggestive']);
      expect(mangaContentRatings(false), ['safe']);
    });

    test('data-saver page URLs use the data-saver segment', () {
      final urls = buildChapterPageUrls(
        'https://node.example',
        'h1',
        ['a.jpg'],
        saver: true,
      );
      expect(urls, ['https://node.example/data-saver/h1/a.jpg']);
    });

    test('tags parse with group labels', () {
      final tag = MangaTag.fromApi({
        'id': 't1',
        'attributes': {
          'name': {'en': 'Action'},
          'group': 'genre',
        },
      });
      expect(tag.name, 'Action');
      expect(tag.groupLabel, '题材');
    });

    test('library export/import round-trips and rejects foreign docs', () {
      final raw = MangaLibraryCodec.buildExport(
        const [MangaFavorite(id: 'm9', title: 'T', coverUrl: '')],
        const {
          'm9': MangaProgress(
            mangaId: 'm9',
            mangaTitle: 'T',
            coverUrl: '',
            chapterId: 'c1',
            chapterLabel: '第 1 话',
            page: 2,
            totalPages: 9,
            updatedAtMs: 7,
          ),
        },
      );
      final parsed = MangaLibraryCodec.parseExport(raw);
      expect(parsed?.favorites.single.id, 'm9');
      expect(parsed?.progress['mangadex:m9']?.page, 2);
      expect(MangaLibraryCodec.parseExport('{"app":"other"}'), isNull);
      expect(MangaLibraryCodec.parseExport('junk'), isNull);
    });
  });
}

