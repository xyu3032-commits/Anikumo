// Batch 62: rule repository address normalization and
// catalog parsing. The repository is user-supplied (the
// built-in one was removed in batch 59); GitHub *web*
// addresses must resolve to their raw form because that
// is what users paste.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/plugin/rule_repository.dart';

void main() {
  group('normalizeBase — github web addresses', () {
    test('plain repo page resolves to raw main branch', () {
      expect(
        RuleRepository.normalizeBase('https://github.com/Predidit/KazumiRules'),
        'https://raw.githubusercontent.com/Predidit/KazumiRules/main/',
      );
    });

    test('trailing slash and .git suffix are tolerated', () {
      expect(
        RuleRepository.normalizeBase(
            'https://github.com/Predidit/KazumiRules/'),
        'https://raw.githubusercontent.com/Predidit/KazumiRules/main/',
      );
      expect(
        RuleRepository.normalizeBase(
            'https://github.com/Predidit/KazumiRules.git'),
        'https://raw.githubusercontent.com/Predidit/KazumiRules/main/',
      );
    });

    test('tree URLs carry branch and subpath', () {
      expect(
        RuleRepository.normalizeBase(
            'https://github.com/someone/repo/tree/dev'),
        'https://raw.githubusercontent.com/someone/repo/dev/',
      );
      expect(
        RuleRepository.normalizeBase(
            'https://github.com/someone/repo/tree/main/rules'),
        'https://raw.githubusercontent.com/someone/repo/main/rules/',
      );
    });

    test('non-repo github pages are refused', () {
      expect(RuleRepository.normalizeBase('https://github.com/onlyowner'),
          isNull);
      expect(
        RuleRepository.normalizeBase('https://github.com/a/b/issues'),
        isNull,
      );
    });
  });

  group('normalizeBase — raw / directory addresses', () {
    test('raw directory passes through', () {
      expect(
        RuleRepository.normalizeBase(
            'https://raw.githubusercontent.com/Predidit/KazumiRules/main/'),
        'https://raw.githubusercontent.com/Predidit/KazumiRules/main/',
      );
    });

    test('an index.json address resolves to its directory', () {
      expect(
        RuleRepository.normalizeBase('https://example.com/rules/index.json'),
        'https://example.com/rules/',
      );
    });

    test('a single rule file is NOT a repository', () {
      expect(
        RuleRepository.normalizeBase('https://example.com/rules/foo.json'),
        isNull,
      );
      expect(
        RuleRepository.normalizeBase('https://example.com/rule.json'),
        isNull,
      );
    });

    test('non-URLs and share links are refused', () {
      expect(RuleRepository.normalizeBase('hello'), isNull);
      expect(RuleRepository.normalizeBase('anikumo://plugin/abc'), isNull);
      expect(RuleRepository.normalizeBase(''), isNull);
    });
  });

  group('catalog / rule URIs', () {
    const base = 'https://raw.githubusercontent.com/Predidit/KazumiRules/main/';

    test('catalog is index.json under the base', () {
      expect(
        RuleRepository.catalogUri(base).toString(),
        '${base}index.json',
      );
    });

    test('rule files append .json and encode the name', () {
      expect(
        RuleRepository.ruleUri(base, 'AGE动漫').toString(),
        '${base}AGE%E5%8A%A8%E6%BC%AB.json',
      );
    });
  });

  group('parseCatalog', () {
    test('valid entries parse, invalid ones are skipped', () {
      final catalog = RuleRepository.parseCatalog(
        '[{"name":"a","version":"1.0","author":"x","lastUpdate":7},'
        '{"version":"2.0"},42]',
      );
      expect(catalog.items, hasLength(1));
      expect(catalog.items.single.name, 'a');
      expect(catalog.items.single.lastUpdate, 7);
      expect(catalog.skipped, 2);
    });

    test('a non-array root throws', () {
      expect(() => RuleRepository.parseCatalog('{"name":"a"}'),
          throwsFormatException);
    });

    test('an all-invalid array throws', () {
      expect(() => RuleRepository.parseCatalog('[1,2]'),
          throwsFormatException);
    });
  });
}
