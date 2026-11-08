// Batch 88 desktop probe: drive the real QuickJS engine
// with stub sources to verify the image/thumbnail hook
// chain end to end — dispatcher kinds imageConfigs /
// thumbnailConfigs, the async onImageLoad semantics
// (per-image failure isolation, onResponse rejection),
// and their application inside JsMangaSource.pages /
// search / details. A hook-less source must pass through
// completely untouched.
//
// Run with:
//   LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/manga_hooks_probe_test.dart
//
// No network: every hook below is local computation.
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

const _hookedSource = r'''
class ProbeHooks extends ComicSource {
  name = "probe-hooks";
  key = "probe_hooks";
  version = "1.0.0";
  comic = {
    loadInfo: async (id) => ({
      title: '探针漫画',
      cover: 'https://img.example.com/cover.jpg',
    }),
    loadEp: async (id, ep) => ({ images: [
      'https://img.example.com/p1.jpg',
      'https://img.example.com/p2.jpg',
      'https://img.example.com/p3.jpg',
      'https://img.example.com/p4.jpg',
    ]}),
    onImageLoad: async (url, comicId, epId) => {
      await Promise.resolve();
      if (url.includes('p2')) throw new Error('hook boom');
      if (url.includes('p3')) {
        return {
          url: url + '?sig=' + comicId + '-' + epId,
          headers: { 'X-Auth': 'tok' },
        };
      }
      if (url.includes('p4')) {
        // Encrypted-image shape: needs a byte transform the
        // host cannot run yet — must NOT be applied.
        return { url: 'https://enc.example.com/p4', onResponse: (b) => b };
      }
      return { url: url, headers: { 'Referer': 'https://ref.example.com/' } };
    },
    onThumbnailLoad: (url) => ({
      url: url.replace('cover', 'thumb'),
      method: 'GET',
      headers: { 'Referer': 'https://ref.example.com/' },
    }),
  };
  search = {
    load: async (kw, opts, page) => ({
      comics: [
        { id: 'c1', title: '探针漫画', cover: 'https://img.example.com/cover.jpg' },
      ],
      maxPage: 1,
    }),
  };
}
''';

const _plainSource = r'''
class ProbePlain extends ComicSource {
  name = "probe-plain";
  key = "probe_plain";
  version = "1.0.0";
  comic = {
    loadEp: async (id, ep) => ({ images: ['https://img.example.com/q1.jpg'] }),
  };
  search = {
    load: async (kw, opts, page) => ({
      comics: [
        { id: 'c9', title: '素源漫画', cover: 'https://img.example.com/c9.jpg' },
      ],
      maxPage: 1,
    }),
  };
}
''';

const _baseItem = MangaItem(
  id: 'c1',
  title: '探针漫画',
  description: '',
  coverUrl: 'https://img.example.com/cover.jpg',
  author: '',
  status: '',
  year: null,
  tags: [],
  source: 'probe_hooks',
);

const _chapter = MangaChapter(
  id: 'ep1',
  volume: null,
  chapter: null,
  title: '第一话',
  language: '',
  pages: 0,
  publishedAt: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('qjs_hooks_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('pages(): onImageLoad applied per image, failures isolated',
      () async {
    final source = JsMangaSource(
      jsKey: 'probe_hooks',
      displayName: 'probe-hooks',
      version: '1.0.0',
      fileName: 'probe_hooks.js',
      code: _hookedSource,
    );
    final pages = await source.pages(_baseItem, _chapter);
    print('pages: ${[for (final p in pages) (p.url, p.headers)]}');
    expect(pages, hasLength(4));
    // p1: URL unchanged, Referer attached.
    expect(pages[0].url, 'https://img.example.com/p1.jpg');
    expect(pages[0].headers, {'Referer': 'https://ref.example.com/'});
    // p2: the hook threw — original page survives untouched.
    expect(pages[1].url, 'https://img.example.com/p2.jpg');
    expect(pages[1].headers, isEmpty);
    // p3: signed URL + auth header, built from comic/ep ids.
    expect(pages[2].url, 'https://img.example.com/p3.jpg?sig=c1-ep1');
    expect(pages[2].headers, {'X-Auth': 'tok'});
    // p4: onResponse config rejected — original URL kept.
    expect(pages[3].url, 'https://img.example.com/p4.jpg');
    expect(pages[3].headers, isEmpty);
  });

  test('search()/details(): onThumbnailLoad rewrites covers', () async {
    final source = JsMangaSource(
      jsKey: 'probe_hooks',
      displayName: 'probe-hooks',
      version: '1.0.0',
      fileName: 'probe_hooks.js',
      code: _hookedSource,
    );
    final results = await source.search('探针');
    expect(results, hasLength(1));
    expect(results[0].coverUrl, 'https://img.example.com/thumb.jpg');
    expect(results[0].coverHeaders, {'Referer': 'https://ref.example.com/'});

    final detail = await source.details(_baseItem);
    expect(detail, isNotNull);
    expect(detail!.coverUrl, 'https://img.example.com/thumb.jpg');
    expect(detail.coverHeaders, {'Referer': 'https://ref.example.com/'});
  });

  test('hook-less source passes through untouched', () async {
    final source = JsMangaSource(
      jsKey: 'probe_plain',
      displayName: 'probe-plain',
      version: '1.0.0',
      fileName: 'probe_plain.js',
      code: _plainSource,
    );
    final pages = await source.pages(_baseItem, _chapter);
    expect(pages, hasLength(1));
    expect(pages[0].url, 'https://img.example.com/q1.jpg');
    expect(pages[0].headers, isEmpty);

    final results = await source.search('素源');
    expect(results, hasLength(1));
    expect(results[0].coverUrl, 'https://img.example.com/c9.jpg');
    expect(results[0].headers, isEmpty);
  });
}
