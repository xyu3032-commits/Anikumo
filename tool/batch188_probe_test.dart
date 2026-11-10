// Batch 188 regression probe: drive the REAL QuickJS
// runtime with loadNext (token-paged) sources after the
// __anikumoPaged hardening — a device report says v56
// throws JS call errors immediately, worse than v55.
// If registration, the dispatcher, or the paged walk is
// broken in the real runtime, it fails here.
//
// Run with:
//   LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/batch188_probe_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
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

const _pagedSource = r'''
class ProbePaged extends ComicSource {
  name = "probe-paged";
  key = "probe_paged";
  version = "1.0.0";
  explore = [
    {
      title: "首页",
      type: "multiPageComicList",
      loadNext: async (tok) => {
        if (tok === null || tok === undefined) {
          return { comics: [{ id: 'p1', title: '一页', cover: 'https://img.example.com/p1.jpg' }], next: 't2' };
        }
        if (tok === 't2') {
          return { comics: [{ id: 'p2', title: '二页', cover: 'https://img.example.com/p2.jpg' }], next: 't3' };
        }
        return { comics: [{ id: 'p3', title: '三页', cover: 'https://img.example.com/p3.jpg' }] };
      },
    },
  ];
  search = {
    loadNext: async (kw, opts, tok) => {
      if (tok === null || tok === undefined) {
        return { comics: [{ id: 's1', title: '搜一', cover: 'https://img.example.com/s1.jpg' }], next: 'u2' };
      }
      return { comics: [{ id: 's2', title: '搜二', cover: 'https://img.example.com/s2.jpg' }] };
    },
  };
  comic = {
    loadInfo: async (id) => ({
      title: '详情' + id,
      cover: 'https://img.example.com/d.jpg',
      chapters: { '1': '第一话', '2': '第二话' },
    }),
  };
}
''';

const _flakySource = r'''
class ProbeFlaky extends ComicSource {
  name = "probe-flaky";
  key = "probe_flaky";
  version = "1.0.0";
  flaked = false;
  explore = [
    {
      title: "首页",
      type: "multiPageComicList",
      loadNext: async (tok) => {
        if (tok === null || tok === undefined) {
          return { comics: [{ id: 'f1', title: '壹页', cover: 'https://img.example.com/f1.jpg' }], next: 't2' };
        }
        if (!this.flaked) {
          this.flaked = true;
          return { comics: [] };
        }
        return { comics: [{ id: 'f2', title: '贰页', cover: 'https://img.example.com/f2.jpg' }] };
      },
    },
  ];
}
''';

JsMangaSource _src(String key, String name, String code) => JsMangaSource(
      jsKey: key,
      displayName: name,
      version: '1.0.0',
      fileName: '$key.js',
      code: code,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('qjs_b188_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('loadNext explore pages 1-3 walk, page 4 is empty', () async {
    final source = _src('probe_paged', 'probe-paged', _pagedSource);
    expect((await source.popular(page: 1)).map((i) => i.id), ['p1']);
    expect((await source.popular(page: 2)).map((i) => i.id), ['p2']);
    expect((await source.popular(page: 3)).map((i) => i.id), ['p3']);
    expect(await source.popular(page: 4), isEmpty);
  });

  test('loadNext search pages walk', () async {
    final source = _src('probe_paged', 'probe-paged', _pagedSource);
    expect((await source.search('x', page: 1)).map((i) => i.id), ['s1']);
    expect((await source.search('x', page: 2)).map((i) => i.id), ['s2']);
  });

  test('loadInfo still works after the paged changes', () async {
    final source = _src('probe_paged', 'probe-paged', _pagedSource);
    const item = MangaItem(
      id: 'p1',
      title: '一页',
      description: '',
      coverUrl: '',
      author: '',
      status: '',
      year: null,
      tags: [],
    );
    final chapters = await source.chapters(item);
    expect(chapters.map((c) => c.title), ['第一话', '第二话']);
  });

  test('flaky mid-chain page throws once, then recovers', () async {
    final source = _src('probe_flaky', 'probe-flaky', _flakySource);
    expect((await source.popular(page: 1)).map((i) => i.id), ['f1']);
    await expectLater(source.popular(page: 2), throwsA(anything));
    expect((await source.popular(page: 2)).map((i) => i.id), ['f2']);
  });
}
