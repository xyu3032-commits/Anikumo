import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:anikumo/services/network/bangumi_acceleration.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Batch 26: (1) anime search found nothing because the
// default Bangumi route is the signed mirror and source
// builds carry no mirror credentials — acceleration must
// fall back to direct; (2) loose manga search results kept
// their unrelated tail on both search pages.
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

MangaItem _item(String id, String title, {String source = 's1'}) =>
    MangaItem(
      id: id,
      title: title,
      description: '',
      coverUrl: '',
      author: '',
      status: '',
      year: 0,
      tags: const [],
      source: source,
    );

void main() {
  group('BangumiAcceleration without mirror credentials', () {
    late Directory directory;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('anikumo_b26_');
      PathProviderPlatform.instance = _TestPaths(directory.path);
      Hive.init(directory.path);
      await GStorage.init();
    });

    tearDownAll(() async {
      await Hive.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('test builds carry no mirror credentials', () {
      expect(BangumiAcceleration.hasMirrorCredentials, isFalse);
    });

    test('default (proxy on, mode unset) resolves to direct, not mirror',
        () async {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, '');
      await GStorage.putSetting(SettingsKeys.enableBangumiProxy, true);
      expect(BangumiAcceleration.current, BangumiAcceleration.direct);
    });

    test('explicit mirror also falls back to direct', () async {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'mirror');
      expect(BangumiAcceleration.current, BangumiAcceleration.direct);
    });

    test('explicit ech and direct are honored', () async {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'ech');
      expect(BangumiAcceleration.current, BangumiAcceleration.ech);
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'direct');
      expect(BangumiAcceleration.current, BangumiAcceleration.direct);
    });

    test('proxy off and mode unset is direct as before', () async {
      await GStorage.putSetting(SettingsKeys.bangumiAcceleration, '');
      await GStorage.putSetting(SettingsKeys.enableBangumiProxy, false);
      expect(BangumiAcceleration.current, BangumiAcceleration.direct);
    });
  });

  group('filterRelevantMangaResults', () {
    final ranked = [
      _item('1', '海贼王'), // exact-ish (contains query below)
      _item('2', '海贼王 剧场版'),
      _item('3', '火影忍者'),
      _item('4', '完全不相干的作品'),
    ];

    test('drops the unrelated tail when relevant items exist', () {
      final out = filterRelevantMangaResults(
        rankMangaResults(ranked, '海贼王'),
        '海贼王',
      );
      expect(out.map((e) => e.id), ['1', '2']);
    });

    test('strict mode returns empty when nothing is relevant', () {
      final out = filterRelevantMangaResults(
        [_item('9', '毫不相关')],
        '海贼王',
        strict: true,
      );
      expect(out, isEmpty);
    });

    test('non-strict keeps loose results when nothing is relevant', () {
      final loose = [_item('9', '毫不相关')];
      final out = filterRelevantMangaResults(loose, '海贼王');
      expect(out.map((e) => e.id), ['9']);
    });
  });

  group('dedupeMangaByTitle', () {
    test('same manga from several sources collapses to the first', () {
      final items = [
        _item('a', '海贼王', source: 's1'),
        _item('b', '海贼王', source: 's2'),
        _item('c', '火影忍者', source: 's2'),
      ];
      final out = dedupeMangaByTitle(items);
      expect(out.map((e) => e.id), ['a', 'c']);
    });

    test('punctuation/spacing variants count as the same title', () {
      final items = [
        _item('a', '海贼王', source: 's1'),
        _item('b', '海贼王 ', source: 's2'),
      ];
      expect(dedupeMangaByTitle(items), hasLength(1));
    });
  });
}
