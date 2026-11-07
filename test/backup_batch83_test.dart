import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/modules/download/download_module.dart';
import 'package:anikumo/services/backup/local_backup.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Batch 83: local backup used to contain nothing from the
/// manga / novel zones and no download records at all.
/// Export → wipe → restore must bring back both libraries,
/// the source registries, and the download records whose
/// media files still exist on the device — and honestly
/// skip the ones whose files are gone.
void main() {
  group('LocalBackup batch-83 sections', () {
    late Directory directory;
    late PathProviderPlatform originalPathProvider;

    const mangaEntry = MangaDownloadEntry(
      source: 'js:s',
      mangaId: 'm1',
      mangaTitle: '下载漫画',
      coverUrl: '',
      chapterId: 'c1',
      chapterLabel: '第 1 话',
      pageCount: 12,
      downloadedAtMs: 42,
    );
    const ghostEntry = MangaDownloadEntry(
      source: 'js:s',
      mangaId: 'ghost',
      mangaTitle: '文件已删',
      coverUrl: '',
      chapterId: 'c9',
      chapterLabel: '第 9 话',
      pageCount: 3,
      downloadedAtMs: 43,
    );

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('anikumo_b83_');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(directory.path);
      Hive.init(directory.path);
      await GStorage.init();
    });

    tearDownAll(() async {
      PathProviderPlatform.instance = originalPathProvider;
      await Hive.close();
      await directory.delete(recursive: true);
    });

    Future<void> wipe() async {
      await MangaLibraryStore.clearProgress();
      await MangaLibraryStore.clearFavorites();
      await NovelLibraryStore.saveFavorites(const []);
      await GStorage.putSetting(SettingsKeys.novelProgressJson, '');
      await GStorage.downloads.clear();
      final indexFile =
          File('${directory.path}/manga_downloads/index.json');
      if (await indexFile.exists()) await indexFile.delete();
      await GStorage.putSetting(SettingsKeys.mangaJsSourcesJson, '');
      await GStorage.putSetting(SettingsKeys.novelInstalledSourcesJson, '');
    }

    test('round trip restores libraries, sources and live downloads',
        () async {
      await wipe();
      // Seed manga + novel libraries.
      await MangaLibraryStore.toggleFavorite(
        const MangaFavorite(
          id: 'm1',
          title: '收藏漫画',
          coverUrl: '',
          source: 'js:s',
        ),
      );
      await MangaLibraryStore.recordProgress(
        const MangaProgress(
          mangaId: 'm1',
          mangaTitle: '收藏漫画',
          coverUrl: '',
          chapterId: 'c2',
          chapterLabel: '第 2 话',
          page: 1,
          totalPages: 9,
          updatedAtMs: 7,
          mangaSource: 'js:s',
        ),
      );
      const novelItem = NovelItem(
        bookUrl: 'https://x/book1',
        title: '收藏小说',
        source: 'src1',
      );
      await NovelLibraryStore.toggleFavorite(novelItem);
      await NovelLibraryStore.recordProgress(
        const NovelProgress(
          item: novelItem,
          chapterIndex: 2,
          chapterTitle: '第三章',
          updatedAt: 9,
        ),
      );
      // Seed registries.
      await GStorage.putSetting(
        SettingsKeys.mangaJsSourcesJson,
        '[{"key":"s","code":"x"}]',
      );
      await GStorage.putSetting(
        SettingsKeys.novelInstalledSourcesJson,
        '[{"bookSourceUrl":"src1"}]',
      );
      // Seed an anime download whose file exists, and one
      // whose file is gone.
      final m3u8 = File('${directory.path}/ep1.m3u8');
      await m3u8.writeAsString('#EXTM3U');
      DownloadEpisode episode(String path) => DownloadEpisode(
            1,
            '第一集',
            0,
            DownloadStatus.completed,
            100,
            4,
            4,
            path,
            directory.path,
            'https://x/e1.m3u8',
            DateTime.fromMillisecondsSinceEpoch(5),
            '',
            1000,
            '',
          );
      await GStorage.downloads.put(
        'ruleA_11',
        DownloadRecord(
          11,
          '下载番',
          '',
          'ruleA',
          {1: episode(m3u8.path)},
          DateTime.fromMillisecondsSinceEpoch(5),
        ),
      );
      await GStorage.downloads.put(
        'ruleA_12',
        DownloadRecord(
          12,
          '已删番',
          '',
          'ruleA',
          {1: episode('${directory.path}/missing.m3u8')},
          DateTime.fromMillisecondsSinceEpoch(5),
        ),
      );
      // Seed manga downloads: one with its chapter dir on
      // disk, one without. Seed via a hand-built backup
      // payload below instead of the store (its public API
      // is download-driven), by exporting after writing the
      // index through a restore of a synthetic backup.
      final chapterDir = await MangaDownloadStore.chapterDir(mangaEntry);
      await chapterDir.create(recursive: true);

      final exported = await LocalBackup.exportJson();
      final parsed = LocalBackup.parse(exported);
      expect(parsed, isNotNull);
      expect(parsed!.mangaFavorites, hasLength(1));
      expect(parsed.mangaProgress, hasLength(1));
      expect(parsed.novelFavorites, hasLength(1));
      expect(parsed.novelProgress, hasLength(1));
      expect(parsed.animeDownloads, hasLength(2));
      expect(parsed.mangaJsSourcesJson, contains('"key":"s"'));
      expect(parsed.novelSourcesJson, contains('src1'));

      // Inject manga download records into the parsed data
      // (export had none to give), then wipe and restore.
      final data = LocalBackupData(
        histories: parsed.histories,
        collectibles: parsed.collectibles,
        searchHistories: parsed.searchHistories,
        userLists: parsed.userLists,
        notes: parsed.notes,
        glassLevel: parsed.glassLevel,
        mangaFavorites: parsed.mangaFavorites,
        mangaProgress: parsed.mangaProgress,
        novelFavorites: parsed.novelFavorites,
        novelProgress: parsed.novelProgress,
        mangaDownloads: const [mangaEntry, ghostEntry],
        animeDownloads: parsed.animeDownloads,
        mangaJsSourcesJson: parsed.mangaJsSourcesJson,
        novelSourcesJson: parsed.novelSourcesJson,
      );
      await wipe();
      expect(MangaLibraryStore.loadFavorites(), isEmpty);
      expect(GStorage.downloads.length, 0);

      final report = await LocalBackup.apply(data);
      expect(MangaLibraryStore.loadFavorites(), hasLength(1));
      expect(MangaLibraryStore.loadProgressList(), hasLength(1));
      expect(NovelLibraryStore.loadFavorites(), hasLength(1));
      expect(NovelLibraryStore.loadProgressList(), hasLength(1));
      expect(
        GStorage.getSetting(SettingsKeys.mangaJsSourcesJson),
        contains('"key":"s"'),
      );
      expect(
        GStorage.getSetting(SettingsKeys.novelInstalledSourcesJson),
        contains('src1'),
      );
      // Downloads: the two with files come back (1 anime
      // record + 1 manga chapter); the two ghosts skip.
      expect(GStorage.downloads.length, 1);
      expect(GStorage.downloads.values.single.bangumiId, 11);
      final index = await MangaDownloadStore.loadIndex();
      expect(index.map((e) => e.mangaId), ['m1']);
      expect(report.downloadsRestored, 2);
      expect(report.downloadsSkipped, 2);
    });

    test('format v1 backups still parse, new sections empty', () {
      final parsed = LocalBackup.parse(
        '{"app":"anikumo","formatVersion":1,"histories":[],'
        '"collectibles":[],"searchHistories":[],"userLists":[],'
        '"notes":{},"glassLevel":null}',
      );
      expect(parsed, isNotNull);
      expect(parsed!.mangaFavorites, isEmpty);
      expect(parsed.animeDownloads, isEmpty);
      expect(parsed.mangaJsSourcesJson, isEmpty);
    });

    test('future format versions are rejected', () {
      expect(
        LocalBackup.parse('{"formatVersion":99}'),
        isNull,
      );
    });
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
