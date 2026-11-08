import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Batch 88: Venera source-index detection and the
/// onImageLoad / onThumbnailLoad config mapping. The engine
/// side (dispatcher kinds imageConfigs / thumbnailConfigs)
/// is covered by the desktop probe
/// (tool/manga_hooks_probe_test.dart), which needs the real
/// QuickJS library.
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

MangaItem _item({
  String coverUrl = 'https://img.example.com/cover.jpg',
  Map<String, String> headers = const {},
}) {
  return MangaItem(
    id: 'c1',
    title: '示例漫画',
    description: '',
    coverUrl: coverUrl,
    author: '',
    status: '',
    year: null,
    tags: const [],
    source: 'probe',
    headers: headers,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b88');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  group('parseVeneraIndex', () {
    test('accepts the community index shape', () {
      const payload = '''
[
  {"name": "源甲", "fileName": "src_a.js", "key": "src_a",
   "version": "1.4.1", "description": "示例说明"},
  {"name": "源乙", "fileName": "src_b.js", "key": "src_b",
   "version": "2.0.0"}
]
''';
      final entries = MangaSources.parseVeneraIndex(payload);
      expect(entries, isNotNull);
      expect(entries, hasLength(2));
      expect(entries![0].fileName, 'src_a.js');
      expect(entries[0].name, '源甲');
      expect(entries[0].key, 'src_a');
      expect(entries[0].version, '1.4.1');
      expect(entries[1].name, '源乙');
    });

    test('name falls back to key, then to fileName', () {
      final entries = MangaSources.parseVeneraIndex(
        '[{"fileName": "only.js", "key": "k1"},'
        ' {"fileName": "bare.js"}]',
      );
      expect(entries, isNotNull);
      expect(entries![0].name, 'k1');
      expect(entries[1].name, 'bare.js');
    });

    test('rejects a Legado book-source pack', () {
      const legado = '''
[{"bookSourceName": "示例书源", "bookSourceUrl": "https://example.com",
  "bookSourceType": 2, "searchUrl": "https://example.com/s"}]
''';
      expect(MangaSources.parseVeneraIndex(legado), isNull);
    });

    test('rejects a single JS source and other payloads', () {
      expect(
        MangaSources.parseVeneraIndex(
          'class Foo extends ComicSource {}',
        ),
        isNull,
      );
      expect(MangaSources.parseVeneraIndex('{"a": 1}'), isNull);
      expect(MangaSources.parseVeneraIndex('[]'), isNull);
      expect(MangaSources.parseVeneraIndex('not json'), isNull);
      expect(MangaSources.parseVeneraIndex(''), isNull);
    });

    test('rejects a mixed array (one entry without a .js file)', () {
      expect(
        MangaSources.parseVeneraIndex(
          '[{"fileName": "ok.js"}, {"fileName": "notes.txt"}]',
        ),
        isNull,
      );
      expect(
        MangaSources.parseVeneraIndex('[{"fileName": "ok.js"}, 42]'),
        isNull,
      );
    });
  });

  group('applyImageConfigs', () {
    final pages = [
      const MangaPage(
        'https://img.example.com/p1.jpg',
        headers: {'A': '1', 'Keep': 'yes'},
      ),
      const MangaPage('https://img.example.com/p2.jpg'),
      const MangaPage('file:///data/p3.jpg'),
    ];

    test('null / non-list configs pass pages through untouched', () {
      expect(applyImageConfigs(pages, null), same(pages));
      expect(applyImageConfigs(pages, 'junk'), same(pages));
    });

    test('url replaced, headers merged with config winning', () {
      final out = applyImageConfigs(pages, [
        {
          'url': 'https://cdn.example.com/p1.jpg',
          'headers': {'A': '9', 'Referer': 'https://ref.example.com/'},
        },
        null,
        {'url': 'https://cdn.example.com/p3.jpg'},
      ]);
      expect(out[0].url, 'https://cdn.example.com/p1.jpg');
      expect(out[0].headers, {
        'A': '9',
        'Keep': 'yes',
        'Referer': 'https://ref.example.com/',
      });
      expect(out[1].url, 'https://img.example.com/p2.jpg');
      // Local (downloaded) pages are never rewritten.
      expect(out[2].url, 'file:///data/p3.jpg');
    });

    test('non-GET configs are not honored', () {
      final out = applyImageConfigs(pages, [
        {'url': 'https://cdn.example.com/x.jpg', 'method': 'POST'},
        {'url': 'https://cdn.example.com/y.jpg', 'method': 'get'},
        null,
      ]);
      expect(out[0].url, 'https://img.example.com/p1.jpg');
      expect(out[1].url, 'https://cdn.example.com/y.jpg');
    });

    test('short config list leaves the tail untouched', () {
      final out = applyImageConfigs(pages, [
        {'headers': {'Referer': 'https://ref.example.com/'}},
      ]);
      expect(out[0].url, 'https://img.example.com/p1.jpg');
      expect(out[0].headers['Referer'], 'https://ref.example.com/');
      expect(out[1].url, 'https://img.example.com/p2.jpg');
    });
  });

  group('applyThumbnailConfigs', () {
    test('cover replaced and headers stored on the item', () {
      final out = applyThumbnailConfigs([_item()], [
        {
          'url': 'https://img.example.com/thumb.jpg',
          'method': 'GET',
          'headers': {'Referer': 'https://ref.example.com/'},
        },
      ]);
      expect(out[0].coverUrl, 'https://img.example.com/thumb.jpg');
      expect(out[0].coverHeaders, {'Referer': 'https://ref.example.com/'});
    });

    test('null configs and empty covers pass through', () {
      final items = [_item(), _item(coverUrl: '')];
      expect(applyThumbnailConfigs(items, null), same(items));
      final out = applyThumbnailConfigs(items, [
        null,
        {'url': 'https://img.example.com/other.jpg'},
      ]);
      expect(out[0].coverUrl, 'https://img.example.com/cover.jpg');
      expect(out[1].coverUrl, '');
    });

    test('headers-only config merges over existing headers', () {
      final out = applyThumbnailConfigs(
        [_item(headers: const {'X-Old': '1'})],
        [
          {'headers': {'Referer': 'https://ref.example.com/'}},
        ],
      );
      expect(out[0].coverUrl, 'https://img.example.com/cover.jpg');
      expect(out[0].headers, {
        'X-Old': '1',
        'Referer': 'https://ref.example.com/',
      });
    });
  });
}
