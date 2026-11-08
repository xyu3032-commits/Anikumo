// Batch 104 unit tests:
//  1. friendlyError collapses raw JS engine dumps (the
//     「点击更多显示 JS」 report) into one human line and
//     keeps its older network mappings.
//  2. The downloads index never hands back an unmodifiable
//     list (the first-ever-download failure), and deleting
//     from an empty index is a no-op, not a throw.
//  3. (The source-priority ordering item was removed in
//     batch 105 — the user corrected the rule: a tag
//     search runs on the tagged manga's own source alone.
//     Its tests live in batch105_test.dart.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/error_message.dart';
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
  group('friendlyError vs JS dumps (batch 104)', () {
    test('a QuickJS TypeError with a stack collapses to one line', () {
      final raw = StateError(
        "JS 源调用失败：Error: TypeError: cannot read property 'map' of undefined\n"
        '    at load (comic.js:128)\n'
        '    at __anikumoCall (dispatcher.js:1617)',
      );
      expect(friendlyError(raw), '源脚本运行出错，请重试或换一个源');
    });

    test('a ReferenceError collapses too', () {
      expect(
        friendlyError(Exception('ReferenceError: load is not defined')),
        '源脚本运行出错，请重试或换一个源',
      );
    });

    test('multi-line non-JS errors keep only the first line', () {
      expect(
        friendlyError(Exception('源返回了异常数据\nsecond line\nthird line')),
        '源返回了异常数据',
      );
    });

    test('older network mappings still win', () {
      expect(
        friendlyError(Exception("Failed host lookup: 'example.com'")),
        contains('域名解析失败'),
      );
      expect(
        friendlyError(Exception('TimeoutException after 0:00:30')),
        '加载超时，请重试',
      );
    });

    test('very long single-line messages are bounded', () {
      final out = friendlyError(Exception('x' * 300));
      expect(out.length, lessThanOrEqualTo(121));
      expect(out.endsWith('…'), isTrue);
    });
  });

  group('downloads index mutability (batch 104)', () {
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('batch104_dl');
      PathProviderPlatform.instance = _TestPaths(dir.path);
      Hive.init(dir.path);
      await GStorage.init();
    });

    test('a fresh (missing) index loads as a writable list', () async {
      final entries = await MangaDownloadStore.loadIndex();
      expect(entries, isEmpty);
      // The regression: this threw UnsupportedError on the
      // const [] the loader used to return, which is what
      // made every first download fail after the pages had
      // already been fetched.
      entries.add(
        const MangaDownloadEntry(
          source: 's',
          mangaId: 'm',
          mangaTitle: 't',
          coverUrl: '',
          chapterId: 'c',
          chapterLabel: '1',
          pageCount: 1,
          downloadedAtMs: 0,
        ),
      );
      entries.removeWhere((e) => e.key == 's:m:c');
      expect(entries, isEmpty);
    });

    test('deleteEntry on an empty index completes quietly', () async {
      await MangaDownloadStore.deleteEntry(
        const MangaDownloadEntry(
          source: 'ghost',
          mangaId: 'none',
          mangaTitle: '',
          coverUrl: '',
          chapterId: 'none',
          chapterLabel: '',
          pageCount: 0,
          downloadedAtMs: 0,
        ),
      );
    });
  });

}
