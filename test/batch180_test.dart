import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/pages/novel/novel_diagnostics_page.dart';
import 'package:anikumo/services/novel/moyuan_host.dart';

// Batch 180: (a) a bare "Stack Overflow" is Dart's own
// StackOverflowError — JS engine failures always arrive
// prefixed — so Dart layer boundaries tag it with context;
// (b) the source diagnosis quotes the raw search response
// when a search comes back empty ([搜索原文]).
int _boom() => _boom() + 1;

void main() {
  group('guardDartStack (batch 180)', () {
    test('provenance pin: StackOverflowError prints bare', () {
      expect(StackOverflowError().toString(), 'Stack Overflow');
    });

    test('values pass through untouched', () async {
      expect(await guardDartStack(() async => 42, '层', 'ctx'), 42);
    });

    test('non-stack errors pass through untouched', () async {
      await expectLater(
        guardDartStack(() async => throw ArgumentError('nope'), '层', 'ctx'),
        throwsArgumentError,
      );
    });

    test('a real stack overflow is rethrown with layer and context',
        () async {
      await expectLater(
        guardDartStack(() async => _boom(), 'Dart 正文层',
            'source: 测试源, chapter: https://x.example/read/1'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Stack Overflow (Dart 正文层)'),
            contains('测试源'),
            contains('https://x.example/read/1'),
          ),
        )),
      );
    });
  });

  group('debugSearchExcerpt (batch 180)', () {
    test('empty bodies quote nothing', () {
      expect(debugSearchExcerpt(const {}), '');
    });

    test('short body is whitespace-compacted verbatim', () {
      expect(debugSearchExcerpt({'u': '<ul>\n  <li>甲</li>\n</ul>'}),
          '<ul> <li>甲</li> </ul>');
    });

    test('long body without the keyword quotes the head', () {
      final body = 'x' * 4000;
      final out = debugSearchExcerpt({'u': body});
      expect(out.length, 1501);
      expect(out.startsWith('xxx'), isTrue);
      expect(out.endsWith('…'), isTrue);
    });

    test('long body centers on the keyword (result lists live mid-page)',
        () {
      final body = '${'h' * 3000}斗罗大陆${'t' * 3000}';
      final out = debugSearchExcerpt({'u': body});
      expect(out.startsWith('…'), isTrue);
      expect(out.contains('斗罗大陆'), isTrue);
      expect(out.length, lessThan(1600));
    });
  });

  group('verdict stack classification (batch 180)', () {
    test('Dart-side stack overflow is called out as not a rule problem',
        () {
      final v = novelDiagVerdict(
        searchCount: 1,
        chaptersCount: 10,
        contentError:
            'Bad state: Stack Overflow (Dart 正文层) — source: 某源, chapter: https://x.example/1',
      );
      expect(v, contains('Dart 代码栈溢出'));
    });

    test('engine-side stack overflow points at the content rule', () {
      final v = novelDiagVerdict(
        searchCount: 1,
        chaptersCount: 10,
        contentError:
            'Bad state: MoYuan call failed: Stack overflow while loading chapter content — source: 某源',
      );
      expect(v, contains('正文规则处栈溢出'));
    });
  });
}
