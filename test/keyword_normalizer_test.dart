import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/utils/keyword_normalizer.dart';

void main() {
  group('KeywordNormalizer.normalize', () {
    test('strips Chinese season suffix', () {
      expect(KeywordNormalizer.normalize('葬送的芙莉莲 第二季'), '葬送的芙莉莲');
      expect(KeywordNormalizer.normalize('进击的巨人 第4期'), '进击的巨人');
    });

    test('strips English season suffix', () {
      expect(KeywordNormalizer.normalize('Frieren Season 2'), 'Frieren');
      expect(KeywordNormalizer.normalize('Some Show S3'), 'Some Show');
    });

    test('strips trailing year brackets', () {
      expect(KeywordNormalizer.normalize('某番（2025）'), '某番');
    });

    test('strips stacked decorations', () {
      expect(KeywordNormalizer.normalize('某番 第二季（2025）'), '某番');
    });

    test('leaves clean titles untouched', () {
      expect(KeywordNormalizer.normalize('葬送的芙莉莲'), '葬送的芙莉莲');
    });
  });

  group('KeywordNormalizer.fallbackKeyword', () {
    test('returns cleaned keyword when it differs', () {
      expect(
        KeywordNormalizer.fallbackKeyword('葬送的芙莉莲 第二季'),
        '葬送的芙莉莲',
      );
    });

    test('returns null when nothing would change', () {
      expect(KeywordNormalizer.fallbackKeyword('葬送的芙莉莲'), isNull);
      expect(KeywordNormalizer.fallbackKeyword('  葬送的芙莉莲  '), isNull);
    });

    test('returns null when cleaning would erase the keyword', () {
      expect(KeywordNormalizer.fallbackKeyword('第二季'), isNull);
    });
  });
}
