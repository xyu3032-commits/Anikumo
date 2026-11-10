// Batch 192: NovelApi's session caches — chapter lists
// and chapter contents are cached per book/chapter,
// single-flighted, evicted on failure/empty, and wiped
// when the source registry revision moves. Exercised
// through the debugSourceResolver seam with a counting
// fake source (no JS engine involved).
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/novel_api.dart';
import 'package:anikumo/services/novel/novel_source.dart';
import 'package:anikumo/services/novel/novel_sources.dart';

class _CountingSource implements NovelSource {
  int chapterCalls = 0;
  int contentCalls = 0;
  bool failContentOnce = false;
  bool emptyChapters = false;
  bool emptyContent = false;

  @override
  String get id => 'counting';
  @override
  String get name => 'Counting';
  @override
  bool get builtin => false;
  @override
  int get type => 0;
  @override
  Map<String, String> get headers => const {};
  @override
  String get loginUrl => '';
  @override
  List<NovelExploreCategory> get exploreCategories => const [];
  @override
  bool get hasDynamicExplore => false;
  @override
  bool get exploreKindsResolved => true;
  @override
  Future<void> ensureExploreKinds() async {}

  @override
  Future<List<NovelItem>> search(String key, {int page = 1}) async =>
      const [];

  @override
  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  }) async =>
      const [];

  @override
  Future<NovelItem> bookInfo(NovelItem item) async => item;

  @override
  Future<List<NovelChapter>> chapters(NovelItem item) async {
    chapterCalls++;
    if (emptyChapters) return const [];
    return const [
      NovelChapter(title: '第一章', url: 'https://x/1'),
      NovelChapter(title: '第二章', url: 'https://x/2'),
    ];
  }

  @override
  Future<List<NovelBlock>> content(
    NovelItem item,
    NovelChapter chapter,
  ) async {
    contentCalls++;
    if (failContentOnce) {
      failContentOnce = false;
      throw StateError('boom');
    }
    if (emptyContent) return const [];
    return const [NovelTextBlock('正文内容')];
  }
}

void main() {
  const item = NovelItem(
    bookUrl: 'https://x/book',
    title: '测试书',
    source: 'counting',
  );
  const chapter = NovelChapter(title: '第一章', url: 'https://x/1');
  late _CountingSource source;

  setUp(() {
    source = _CountingSource();
    NovelApi.debugSourceResolver = (_) => source;
    // A fresh cache landscape for each test.
    NovelSources.revision.value++;
  });

  tearDown(() {
    NovelApi.debugSourceResolver = null;
  });

  test('chapters are cached per book; fresh bypasses', () async {
    await NovelApi.chapters(item);
    await NovelApi.chapters(item);
    expect(source.chapterCalls, 1);
    await NovelApi.chapters(item, fresh: true);
    expect(source.chapterCalls, 2);
  });

  test('empty chapter lists are not pinned', () async {
    source.emptyChapters = true;
    await NovelApi.chapters(item);
    await NovelApi.chapters(item);
    expect(source.chapterCalls, 2);
  });

  test('content is cached and single-flighted', () async {
    final results = await Future.wait([
      NovelApi.contentDetailed(item, chapter),
      NovelApi.contentDetailed(item, chapter),
      NovelApi.contentDetailed(item, chapter),
    ]);
    expect(source.contentCalls, 1);
    expect(results.first.blocks.single, isA<NovelTextBlock>());
    await NovelApi.contentDetailed(item, chapter);
    expect(source.contentCalls, 1);
  });

  test('failed content evicts itself and retries next time', () async {
    source.failContentOnce = true;
    await expectLater(
      NovelApi.contentDetailed(item, chapter),
      throwsStateError,
    );
    final ok = await NovelApi.contentDetailed(item, chapter);
    expect(ok.blocks, isNotEmpty);
    expect(source.contentCalls, 2);
  });

  test('empty content evicts itself', () async {
    source.emptyContent = true;
    await NovelApi.contentDetailed(item, chapter);
    await NovelApi.contentDetailed(item, chapter);
    expect(source.contentCalls, 2);
  });

  test('a registry revision bump wipes both caches', () async {
    await NovelApi.chapters(item);
    await NovelApi.contentDetailed(item, chapter);
    NovelSources.revision.value++;
    await NovelApi.chapters(item);
    await NovelApi.contentDetailed(item, chapter);
    expect(source.chapterCalls, 2);
    expect(source.contentCalls, 2);
  });
}
