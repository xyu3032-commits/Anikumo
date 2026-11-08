// Batch 106: history displays went stale after deletions
// made on other pages — the manga home rail and the
// combined history page now rebuild off the library
// stores' revision ticks. The novel store had no tick at
// all; these tests pin its contract: progress mutations
// bump it, a no-op removal does not.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('batch106_novel');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('novel progress mutations bump the revision tick', () async {
    const item = NovelItem(bookUrl: 'http://x/1', title: '书一', source: 's1');
    final progress = NovelProgress(
      item: item,
      chapterIndex: 0,
      chapterTitle: '第一章',
      updatedAt: 1,
    );
    final start = NovelLibraryStore.revision.value;

    await NovelLibraryStore.recordProgress(progress);
    expect(NovelLibraryStore.revision.value, start + 1);

    await NovelLibraryStore.removeProgress(item.storageKey);
    expect(NovelLibraryStore.revision.value, start + 2);
    expect(NovelLibraryStore.loadProgressList(), isEmpty);

    // Removing an already-gone record changes nothing and
    // must not tick (no pointless rebuilds).
    await NovelLibraryStore.removeProgress(item.storageKey);
    expect(NovelLibraryStore.revision.value, start + 2);

    await NovelLibraryStore.recordProgress(progress);
    await NovelLibraryStore.clearProgress();
    expect(NovelLibraryStore.revision.value, start + 4);
    expect(NovelLibraryStore.loadProgressList(), isEmpty);
  });
}
