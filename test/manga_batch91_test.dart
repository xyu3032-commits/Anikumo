import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Batch 91: the availability probe's cooperative stop.
/// With no sources installed every check resolves
/// "unreadable" immediately (fetchChapters short-circuits),
/// which makes the worker behavior deterministic: without
/// a stop signal every item reports; with one, none do.
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

MangaItem _item(String id) {
  return MangaItem(
    id: id,
    title: '漫画$id',
    description: '',
    coverUrl: '',
    author: '',
    status: '',
    year: null,
    tags: const [],
    source: 'b91-no-such-source',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b91');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('checkAll reports every item when allowed to run', () async {
    final reported = <String>[];
    await MangaAvailabilityChecker.checkAll(
      [_item('run-1'), _item('run-2'), _item('run-3')],
      onResult: (item, readable) {
        expect(readable, isFalse);
        reported.add(item.id);
      },
    );
    expect(reported, ['run-1', 'run-2', 'run-3']);
  });

  test('checkAll launches nothing once shouldContinue is false',
      () async {
    final reported = <String>[];
    await MangaAvailabilityChecker.checkAll(
      [_item('stop-1'), _item('stop-2'), _item('stop-3')],
      shouldContinue: () => false,
      onResult: (item, readable) => reported.add(item.id),
    );
    expect(reported, isEmpty);
  });

  test('checkAll stops launching new checks when the signal flips',
      () async {
    var budget = 2;
    final reported = <String>[];
    await MangaAvailabilityChecker.checkAll(
      [
        _item('flip-1'),
        _item('flip-2'),
        _item('flip-3'),
        _item('flip-4'),
        _item('flip-5'),
        _item('flip-6'),
      ],
      concurrency: 1,
      shouldContinue: () => budget-- > 0,
      onResult: (item, readable) => reported.add(item.id),
    );
    // Exactly the checks launched while the signal held:
    // two launches, then the workers stop.
    expect(reported, ['flip-1', 'flip-2']);
  });
}
