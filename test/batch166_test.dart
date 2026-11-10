// Batch 166: the diagnostics report carries each source's own
// rule definition, and JS error snippets carry whole scripts.

import 'package:flutter_test/flutter_test.dart';

import 'package:anikumo/pages/novel/novel_diagnostics_page.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/novel_source.dart';

void main() {
  group('definition digest', () {
    test('keeps the rule keys, drops bookkeeping keys', () {
      final trimmed = trimDefForReport({
        'bookSourceUrl': 'https://example.com',
        'searchUrl': 'https://example.com/s,{"charset":"gbk"}',
        'ruleSearch': {'bookList': '.row', 'name': 'h3'},
        'ruleContent': {'content': '#text'},
        'lastUpdateTime': 123456,
        'customOrder': 7,
        'respondTime': 180000,
      });
      expect(trimmed.keys,
          containsAll(['bookSourceUrl', 'searchUrl', 'ruleSearch', 'ruleContent']));
      expect(trimmed.containsKey('lastUpdateTime'), isFalse);
      expect(trimmed.containsKey('customOrder'), isFalse);
      expect(trimmed.containsKey('respondTime'), isFalse);
    });

    test('digest renders a Legado source definition as JSON', () {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '示例源',
        'bookSourceUrl': 'https://example.com',
        'searchUrl': 'https://example.com/search?key={{key}}',
        'ruleToc': {'chapterList': 'ul li a'},
      });
      final digest = novelSourceDefDigest(LegadoNovelSource(def!));
      expect(digest, contains('searchUrl'));
      expect(digest, contains('chapterList'));
    });

    test('digest caps very long definitions', () {
      final def = LegadoSourceDef.fromJson({
        'bookSourceName': '长源',
        'bookSourceUrl': 'https://example.com',
        'searchUrl': 'x' * 9000,
      });
      final digest = novelSourceDefDigest(LegadoNovelSource(def!));
      expect(digest.length, lessThan(6100));
      expect(digest.endsWith('…'), isTrue);
    });
  });
}
