import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/novel_source.dart';
import 'package:anikumo/services/novel/novel_sources.dart';

// Batch 42: only a dead domain may mark a source dead.
// Batch 46 (user override after the v13 device report —
// 铅笔 403 / 艾途 502 / 快书 握手失败 were never badged or
// auto-deleted): site-refusal failures count as dead too;
// timeouts still do not, and auto-delete needs two strikes
// (recordDead), so one bad evening deletes nothing.
void main() {
  group('NovelSources.isHardDeadError', () {
    test('host lookup failure is hard-dead', () {
      expect(
        NovelSources.isHardDeadError(
          "DioException [connection error]: The connection errored: "
          "Failed host lookup: 'www.deqixs.com'",
        ),
        isTrue,
      );
    });

    test('site refusal / outage failures are hard-dead (batch 46)', () {
      expect(NovelSources.isHardDeadError('Bad state: 源站返回 403'), isTrue);
      expect(NovelSources.isHardDeadError('Bad state: 源站返回 502'), isTrue);
      expect(NovelSources.isHardDeadError('Bad state: 源站返回 404'), isTrue);
      expect(
        NovelSources.isHardDeadError(
          'DioException [unknown]: HandshakeException: Handshake error',
        ),
        isTrue,
      );
      expect(
        NovelSources.isHardDeadError(
          'DioException [connection error]: SocketException: '
          'Connection refused',
        ),
        isTrue,
      );
    });

    test('timeouts and odd statuses are not hard-dead', () {
      expect(
        NovelSources.isHardDeadError('TimeoutException after 0:00:30'),
        isFalse,
      );
      expect(NovelSources.isHardDeadError('Bad state: 源站返回 200'), isFalse);
      expect(NovelSources.isHardDeadError('Bad state: 源站返回 301'), isFalse);
      expect(NovelSources.isHardDeadError('some unrelated error'), isFalse);
    });
  });

  group('NovelSources.sortForDisplay', () {
    test('pinned sources lead in pin order, rest keep order', () {
      final a = _FakeSource('a');
      final b = _FakeSource('b');
      final c = _FakeSource('c');
      final sorted = NovelSources.sortForDisplay(
        [a, b, c],
        pinned: const ['c', 'a'],
      );
      expect(sorted.map((s) => s.id).toList(), ['c', 'a', 'b']);
    });

    test('unknown pinned ids are skipped; no pins = unchanged', () {
      final a = _FakeSource('a');
      final b = _FakeSource('b');
      expect(
        NovelSources.sortForDisplay([a, b], pinned: const ['zzz'])
            .map((s) => s.id)
            .toList(),
        ['a', 'b'],
      );
      expect(
        NovelSources.sortForDisplay([a, b], pinned: const [])
            .map((s) => s.id)
            .toList(),
        ['a', 'b'],
      );
    });
  });
}

class _FakeSource implements NovelSource {
  _FakeSource(this._id);

  final String _id;

  @override
  String get id => _id;

  @override
  String get name => _id;

  @override
  bool get builtin => false;

  @override
  String get loginUrl => '';

  @override
  int get type => 0;

  @override
  Map<String, String> get headers => const {};

  @override
  List<NovelExploreCategory> get exploreCategories => const [];

  @override
  Future<List<NovelItem>> search(String key, {int page = 1}) =>
      throw UnimplementedError();

  @override
  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  }) =>
      throw UnimplementedError();

  @override
  Future<NovelItem> bookInfo(NovelItem item) => throw UnimplementedError();

  @override
  Future<List<NovelChapter>> chapters(NovelItem item) =>
      throw UnimplementedError();

  @override
  Future<List<NovelBlock>> content(NovelItem item, NovelChapter chapter) =>
      throw UnimplementedError();
}
