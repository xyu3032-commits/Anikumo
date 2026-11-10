// Batch 191: the settings-schema model the source-row
// expansion panel renders. (The live engine round trip —
// schema from a real source, write → re-register →
// runtime observes, callback execution — is covered by
// tool/batch191_probe_test.dart, which needs the desktop
// QuickJS probe bench and stays out of the default suite.)
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';

void main() {
  group('MangaSettingDef.fromJson (B191)', () {
    test('select keeps option value/text pairs in order', () {
      final def = MangaSettingDef.fromJson('region', {
        'title': 'CDN线路',
        'type': 'select',
        'options': [
          {'value': '1', 'text': '大陆线路'},
          {'value': '0', 'text': '海外线路'},
        ],
        'defaultValue': '0',
        'hasCallback': false,
      });
      expect(def.title, 'CDN线路');
      expect(def.options.map((o) => o.value), ['1', '0']);
      expect(def.options.last.text, '海外线路');
      expect(def.defaultValue, '0');
    });

    test('bare string options fall back to value == text', () {
      final def = MangaSettingDef.fromJson('quality', {
        'type': 'select',
        'options': ['原图', '高清'],
      });
      expect(def.options.map((o) => o.text), ['原图', '高清']);
      expect(def.title, 'quality');
      expect(def.type, 'select');
    });

    test('callback def carries the flag and button text', () {
      final def = MangaSettingDef.fromJson('wipe', {
        'title': '清除设备信息',
        'type': 'callback',
        'buttonText': '清除',
        'hasCallback': true,
      });
      expect(def.hasCallback, isTrue);
      expect(def.buttonText, '清除');
      expect(def.options, isEmpty);
    });

    test('missing fields degrade to an input def', () {
      final def = MangaSettingDef.fromJson('base_url', const {});
      expect(def.type, 'input');
      expect(def.title, 'base_url');
      expect(def.defaultValue, isNull);
      expect(def.validator, isNull);
    });
  });
}
