// Batch 62 optimization: the shared paste-import pipeline.
// Multi-URL pastes download every standalone URL line
// (bounded concurrency, merged, deduped); local content
// still wins without touching the network; repository
// addresses are guidance, never downloads.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/plugin/plugin_import_parser.dart';

String ruleJson(String name) => '{"name":"$name","version":"1.0"}';

void main() {
  group('extractBareRuleUrls', () {
    test('collects standalone URL lines in order, deduped', () {
      final urls = extractBareRuleUrls(
        '看看这个\n'
        'https://example.com/a.json\n'
        'https://example.com/b.json 不是直链\n'
        '  https://example.com/b.json  \n'
        'https://example.com/a.json\n',
      );
      expect(urls, [
        'https://example.com/a.json',
        'https://example.com/b.json',
      ]);
    });

    test('plain text yields nothing', () {
      expect(extractBareRuleUrls('随便写点什么'), isEmpty);
    });
  });

  group('mergeImportResults', () {
    test('later file wins on a duplicate name', () {
      final first = PluginImportParser.parse(ruleJson('dup'));
      final second = PluginImportParser.parse(
          '[{"name":"dup","version":"2.0"},{"name":"other"}]');
      final merged = mergeImportResults([first, second]);
      expect(merged.plugins, hasLength(2));
      expect(
        merged.plugins.firstWhere((p) => p.name == 'dup').version,
        '2.0',
      );
      expect(merged.duplicateCount, 1);
    });
  });

  group('importFromPastedText', () {
    test('local JSON never touches the network', () async {
      var calls = 0;
      final result = await importFromPastedText(
        ruleJson('local'),
        fetcher: (url) async {
          calls++;
          return ruleJson('remote');
        },
      );
      expect(result.plugins.single.name, 'local');
      expect(calls, 0);
    });

    test('every pasted URL line is downloaded and merged', () async {
      final bodies = {
        'https://example.com/a.json': ruleJson('a'),
        'https://example.com/b.json': ruleJson('b'),
      };
      final result = await importFromPastedText(
        'https://example.com/a.json\nhttps://example.com/b.json',
        fetcher: (url) async => bodies[url]!,
      );
      expect(result.plugins.map((p) => p.name), ['a', 'b']);
      expect(result.failures, isEmpty);
    });

    test('one dead URL does not sink the others', () async {
      final result = await importFromPastedText(
        'https://example.com/good.json\nhttps://example.com/dead.json',
        fetcher: (url) async {
          if (url.contains('dead')) {
            throw Exception('connection error');
          }
          return ruleJson('good');
        },
      );
      expect(result.plugins.single.name, 'good');
      expect(result.failures, hasLength(1));
      expect(result.failures.single, contains('dead.json'));
    });

    test('a repository address is guidance, not a download', () async {
      var calls = 0;
      final result = await importFromPastedText(
        'https://github.com/Predidit/KazumiRules',
        fetcher: (url) async {
          calls++;
          return '<html></html>';
        },
      );
      expect(result.plugins, isEmpty);
      expect(calls, 0);
      expect(result.failures.single, contains('规则仓库'));
    });

    test('repo line plus file URL: file imports, repo is noted', () async {
      final result = await importFromPastedText(
        'https://github.com/Predidit/KazumiRules\n'
        'https://example.com/a.json',
        fetcher: (url) async => ruleJson('a'),
      );
      expect(result.plugins.single.name, 'a');
      expect(result.failures.single, contains('规则仓库'));
    });
  });
}
