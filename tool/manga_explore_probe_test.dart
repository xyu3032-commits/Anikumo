// Explore-shape probe (bug hunt, 2026-11-08): the user
// reports manga that SEARCH finds fine but whose explore /
// source pages show nothing. Drive the real QuickJS engine
// with synthetic sources that copy the dominant real-world
// explore shapes (singlePageWithMultiPart parts-map,
// multiPageComicList array / {comics} envelope, and a
// section carrying an optionList) and see what
// JsMangaSource.popular() actually returns for each.
//
// Run with:
//   LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/manga_explore_probe_test.dart
//
// No network: every load below returns canned data.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
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

/// Shape A: one section, type singlePageWithMultiPart,
/// load() takes no arguments and returns a parts map
/// {sectionTitle: [comic, ...]} of plain objects.
const _partsSource = r'''
class ProbeParts extends ComicSource {
  name = "probe-parts";
  key = "probe_parts";
  version = "1.0.0";
  explore = [
    {
      title: "首页",
      type: "singlePageWithMultiPart",
      load: async () => {
        return {
          "推荐": [
            { id: 'a1', title: '甲漫画', cover: 'https://img.example.com/a1.jpg', author: '作者甲', tags: ['热血'] },
            { id: 'a2', title: '乙漫画', cover: 'https://img.example.com/a2.jpg' },
          ],
          "热门": [
            { id: 'a3', title: '丙漫画', cover: 'https://img.example.com/a3.jpg' },
          ],
        };
      },
    },
  ];
  search = {
    load: async (kw, opts, page) => ({
      comics: [
        { id: 'a1', title: '甲漫画', cover: 'https://img.example.com/a1.jpg' },
      ],
      maxPage: 1,
    }),
  };
}
''';

/// Shape B1: multiPageComicList whose load returns a bare
/// array.
const _arraySource = r'''
class ProbeArray extends ComicSource {
  name = "probe-array";
  key = "probe_array";
  version = "1.0.0";
  explore = [
    {
      title: "最新",
      type: "multiPageComicList",
      load: async (page) => {
        if (page > 1) return [];
        return [
          { id: 'b1', title: '丁漫画', cover: 'https://img.example.com/b1.jpg' },
          { id: 'b2', title: '戊漫画', cover: 'https://img.example.com/b2.jpg' },
        ];
      },
    },
  ];
  search = {
    load: async (kw, opts, page) => ({
      comics: [
        { id: 'b1', title: '丁漫画', cover: 'https://img.example.com/b1.jpg' },
      ],
      maxPage: 1,
    }),
  };
}
''';

/// Shape B2: multiPageComicList whose load returns a
/// {comics, maxPage} envelope.
const _envelopeSource = r'''
class ProbeEnvelope extends ComicSource {
  name = "probe-envelope";
  key = "probe_envelope";
  version = "1.0.0";
  explore = [
    {
      title: "排行",
      type: "multiPageComicList",
      load: async (page) => ({
        comics: [
          { id: 'e1', title: '己漫画', cover: 'https://img.example.com/e1.jpg' },
        ],
        maxPage: 4,
      }),
    },
  ];
  search = {
    load: async (kw, opts, page) => ({
      comics: [
        { id: 'e1', title: '己漫画', cover: 'https://img.example.com/e1.jpg' },
      ],
      maxPage: 1,
    }),
  };
}
''';

/// Shape C: the section carries an optionList; its load
/// signature is load(option, page) and it only returns
/// comics for the expected default option value.
const _optionSource = r'''
class ProbeOption extends ComicSource {
  name = "probe-option";
  key = "probe_option";
  version = "1.0.0";
  explore = [
    {
      title: "分类浏览",
      type: "multiPageComicList",
      optionList: [
        {
          options: ["day-日榜", "week-周榜"],
          default: "week",
        },
      ],
      load: async (option, page) => {
        if (option !== "week" && option !== "day") {
          return [];
        }
        return [
          { id: 'o1', title: '庚漫画', cover: 'https://img.example.com/o1.jpg' },
        ];
      },
    },
  ];
  search = {
    load: async (kw, opts, page) => ({
      comics: [
        { id: 'o1', title: '庚漫画', cover: 'https://img.example.com/o1.jpg' },
      ],
      maxPage: 1,
    }),
  };
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
    final dir = await Directory.systemTemp.createTemp('qjs_explore_probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('shape A: singlePageWithMultiPart parts map', () async {
    final source = _src('probe_parts', 'probe-parts', _partsSource);
    final items = await source.popular(page: 1);
    print('A popular: ${items.map((i) => i.title).toList()}');
    expect(items.map((i) => i.id), ['a1', 'a2', 'a3']);
  });

  test('shape B1: multiPageComicList bare array', () async {
    final source = _src('probe_array', 'probe-array', _arraySource);
    final items = await source.popular(page: 1);
    print('B1 popular: ${items.map((i) => i.title).toList()}');
    expect(items.map((i) => i.id), ['b1', 'b2']);
  });

  test('shape B2: multiPageComicList envelope', () async {
    final source = _src('probe_envelope', 'probe-envelope', _envelopeSource);
    final items = await source.popular(page: 1);
    print('B2 popular: ${items.map((i) => i.title).toList()}');
    expect(items.map((i) => i.id), ['e1']);
  });

  test('shape C: section with optionList', () async {
    final source = _src('probe_option', 'probe-option', _optionSource);
    final items = await source.popular(page: 1);
    print('C popular: ${items.map((i) => i.title).toList()}');
    expect(items.map((i) => i.id), ['o1']);
  });
}
