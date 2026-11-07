import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/js/gbk_table.dart';

/// Batch 76: GBK codec — the decode table's integrity. The
/// codec behavior itself (encode/decode over real bytes) is
/// covered by the desktop probe (tool/gbk_probe_test.dart),
/// which runs the real QuickJS engine.
void main() {
  group('kGbkDecodeTable', () {
    test('covers every GBK pair: 126 leads x 190 trails', () {
      expect(kGbkDecodeTable.length, 23940);
    });

    test('spot checks match the standard GBK mapping', () {
      // index = (lead - 0x81) * 190 + trailIndex
      String at(int lead, int trail) {
        final ti = trail <= 0x7e ? trail - 0x40 : trail - 0x41;
        return kGbkDecodeTable[(lead - 0x81) * 190 + ti];
      }

      expect(at(0xd6, 0xd0), '中');
      expect(at(0xce, 0xc4), '文');
      expect(at(0xc2, 0xfe), '漫');
      expect(at(0xbb, 0xad), '画');
      expect(at(0xb2, 0xe2), '测');
      expect(at(0xca, 0xd4), '试');
    });

    test('undefined pairs hold the replacement character', () {
      // A1 40 is not assigned in GBK.
      final ti = 0x40 - 0x40;
      expect(kGbkDecodeTable[(0xa1 - 0x81) * 190 + ti], '�');
    });

    test('safe to embed in a JS double-quoted string', () {
      for (var i = 0; i < kGbkDecodeTable.length; i++) {
        final unit = kGbkDecodeTable.codeUnitAt(i);
        expect(unit, greaterThanOrEqualTo(0x20));
        expect(unit, isNot(0x22)); // "
        expect(unit, isNot(0x5c)); // backslash
        expect(unit, isNot(0x2028));
        expect(unit, isNot(0x2029));
        expect(unit < 0xd800 || unit > 0xdfff, isTrue);
      }
    });
  });

  group('veneraGbkScript', () {
    test('embeds the table and binds both Convert functions', () {
      expect(veneraGbkScript.contains(kGbkDecodeTable), isTrue);
      expect(veneraGbkScript.contains('Convert.encodeGbk'), isTrue);
      expect(veneraGbkScript.contains('Convert.decodeGbk'), isTrue);
      expect(veneraGbkScript.contains('__anikumoGbkDecode'), isTrue);
      expect(veneraGbkScript.contains('__anikumoGbkEncode'), isTrue);
    });
  });
}
