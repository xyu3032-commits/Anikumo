// Batch 157: the split of labour behind JS template
// support — LegadoParse.fillTemplate resolves only the
// deterministic shapes and leaves JS expressions for the
// engine's JS evaluation untouched; the cookie jar exposes
// the snapshot the JS bridge mirrors into scripts.
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/novel/legado_http.dart';
import 'package:anikumo/services/novel/legado_parse.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'dart:io';

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
  group('fillTemplate contract (batch 157)', () {
    test('JS expressions pass through for the JS bridge', () {
      expect(
        LegadoParse.fillTemplate(
          '{{cookie.removeCookie("https://x")}} https://x/s?k={{key}}',
          key: '斗罗',
          page: 1,
        ),
        '{{cookie.removeCookie("https://x")}} '
        'https://x/s?k=%E6%96%97%E7%BD%97',
      );
      expect(
        LegadoParse.fillTemplate(
          "{{bhost()}}/s{{page==1?'':'_'+page}}",
          key: '',
          page: 2,
        ),
        "{{bhost()}}/s{{page==1?'':'_'+page}}",
      );
    });
  });

  group('cookie jar snapshot (batch 157)', () {
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('batch157');
      PathProviderPlatform.instance = _TestPaths(dir.path);
      Hive.init(dir.path);
      await GStorage.init();
    });

    test('snapshot mirrors stored cookies per domain', () async {
      await LegadoHttp.storeCookies('https://example.com/a', [
        'sess=abc; Path=/',
        'theme=dark; Path=/',
      ]);
      final snap = LegadoHttp.jarSnapshot();
      expect(snap['example.com'], {'sess': 'abc', 'theme': 'dark'});
      // The snapshot is a copy: mutating it must not leak
      // back into the jar the HTTP layer sends.
      snap['example.com']!['sess'] = 'forged';
      expect(
        LegadoHttp.cookieHeaderFor('https://example.com/a'),
        contains('sess=abc'),
      );
    });
  });
}
