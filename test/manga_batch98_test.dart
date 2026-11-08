import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Batch 98: per-record browsing-history deletion in the
// manga and novel stores (the history pages' delete
// buttons sit on these). Removal must keep the persisted
// JSON and the in-memory memo in agreement, ignore
// unknown keys, and leave sibling records untouched.
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

MangaProgress _manga(String id, int at) => MangaProgress(
      mangaId: id,
      mangaTitle: '漫画$id',
      coverUrl: '',
      chapterId: 'c1',
      chapterLabel: '第 1 话',
      page: 0,
      totalPages: 10,
      updatedAtMs: at,
      mangaSource: 'src',
    );

NovelProgress _novel(String url, int at) => NovelProgress(
      item: NovelItem(bookUrl: url, title: '小说$url', source: 'src'),
      chapterIndex: 0,
      chapterTitle: '第一章',
      updatedAt: at,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('batch98_store');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  setUp(() async {
    await MangaLibraryStore.clearProgress();
    await NovelLibraryStore.clearProgress();
  });

  test('manga removeProgress deletes one, keeps the rest', () async {
    await MangaLibraryStore.recordProgress(_manga('a', 1));
    await MangaLibraryStore.recordProgress(_manga('b', 2));
    await MangaLibraryStore.removeProgress('src:a');
    final list = MangaLibraryStore.loadProgressList();
    expect(list.map((p) => p.mangaId), ['b']);
    // Unknown keys are a no-op, not an error.
    await MangaLibraryStore.removeProgress('src:missing');
    expect(MangaLibraryStore.loadProgressList(), hasLength(1));
  });

  test('novel removeProgress deletes one, keeps the rest', () async {
    await NovelLibraryStore.recordProgress(_novel('u1', 1));
    await NovelLibraryStore.recordProgress(_novel('u2', 2));
    final key = _novel('u1', 1).item.storageKey;
    await NovelLibraryStore.removeProgress(key);
    final list = NovelLibraryStore.loadProgressList();
    expect(list.map((p) => p.item.bookUrl), ['u2']);
    await NovelLibraryStore.removeProgress('src:missing');
    expect(NovelLibraryStore.loadProgressList(), hasLength(1));
  });

  test('clearProgress empties both stores', () async {
    await MangaLibraryStore.recordProgress(_manga('a', 1));
    await NovelLibraryStore.recordProgress(_novel('u1', 1));
    await MangaLibraryStore.clearProgress();
    await NovelLibraryStore.clearProgress();
    expect(MangaLibraryStore.loadProgressList(), isEmpty);
    expect(NovelLibraryStore.loadProgressList(), isEmpty);
  });
}
