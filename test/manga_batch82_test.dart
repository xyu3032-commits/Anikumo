import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Batch 82: on a fresh install (or right after clearing
/// progress) the stored progress JSON is empty, and
/// MangaLibraryCodec.decodeProgress answered with a const,
/// unmodifiable map. MangaLibraryStore.recordProgress mutates
/// the decoded map in place, so the very first save threw
/// UnsupportedError inside the reader's fire-and-forget call —
/// and because the store memo kept handing back that same
/// const map, NO reading ever recorded history again, and
/// with no progress saved there was nothing to resume or
/// jump back into. Regression coverage for that trap.
void main() {
  MangaProgress progress({String id = 'm1', int updatedAtMs = 1000}) {
    return MangaProgress(
      mangaId: id,
      mangaTitle: '测试漫画',
      coverUrl: '',
      chapterId: 'c3',
      chapterLabel: '第 3 话',
      page: 4,
      totalPages: 20,
      updatedAtMs: updatedAtMs,
      mangaSource: 'js:src1',
    );
  }

  group('MangaLibraryCodec.decodeProgress mutability', () {
    test('empty input decodes to a writable map', () {
      final map = MangaLibraryCodec.decodeProgress('');
      map['k'] = progress();
      expect(map.length, 1);
    });

    test('garbage input decodes to a writable map', () {
      final map = MangaLibraryCodec.decodeProgress('{not json');
      map['k'] = progress();
      expect(map.length, 1);
    });

    test('non-map JSON decodes to a writable map', () {
      final map = MangaLibraryCodec.decodeProgress('[1,2]');
      map['k'] = progress();
      expect(map.length, 1);
    });

    test('valid JSON round-trips through encode', () {
      final source = {'js:src1:m1': progress()};
      final decoded = MangaLibraryCodec.decodeProgress(
        MangaLibraryCodec.encodeProgress(source),
      );
      expect(decoded.keys, ['js:src1:m1']);
      expect(decoded['js:src1:m1']!.chapterLabel, '第 3 话');
      decoded['js:src1:m2'] = progress(id: 'm2');
      expect(decoded.length, 2);
    });
  });

  group('MangaLibraryStore on fresh storage', () {
    late Directory directory;
    late PathProviderPlatform originalPathProvider;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('anikumo_b82_');
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

    test('first-ever recordProgress persists and lists', () async {
      await MangaLibraryStore.clearProgress();
      await MangaLibraryStore.recordProgress(progress());
      final list = MangaLibraryStore.loadProgressList();
      expect(list, hasLength(1));
      expect(list.single.mangaId, 'm1');
      // The detail page's lookup, keyed exactly as the UI does.
      final byKey = MangaLibraryStore.loadProgressMap()['js:src1:m1'];
      expect(byKey, isNotNull);
      expect(byKey!.chapterLabel, '第 3 话');
    });

    test('recording still works after a clear (the reported trap)',
        () async {
      await MangaLibraryStore.clearProgress();
      await MangaLibraryStore.recordProgress(progress(id: 'm2'));
      final list = MangaLibraryStore.loadProgressList();
      expect(list, hasLength(1));
      expect(list.single.mangaId, 'm2');
    });

    test('records accumulate and sort newest first', () async {
      await MangaLibraryStore.clearProgress();
      await MangaLibraryStore.recordProgress(
        progress(id: 'old', updatedAtMs: 100),
      );
      await MangaLibraryStore.recordProgress(
        progress(id: 'new', updatedAtMs: 200),
      );
      final list = MangaLibraryStore.loadProgressList();
      expect(list.map((p) => p.mangaId), ['new', 'old']);
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
