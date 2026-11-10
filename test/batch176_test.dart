import 'package:anikumo/pages/novel/novel_diagnostics_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Batch 176: the diagnostics verdict line classifies a
/// source run from what it actually observed — step error
/// texts, result counts and the search response body — so
/// "0 results" no longer lumps DNS failures, rule rot and
/// genuinely empty results together.
void main() {
  group('novelDiagVerdict (batch 176)', () {
    test('DNS failure in the search error text', () {
      final v = novelDiagVerdict(
        searchError: 'Bad state: MoYuan call failed: Request failed: '
            'http://www.ijjxs.org — DioException [connection error]: '
            "Failed host lookup: 'www.ijjxs.org'",
        searchCount: 0,
      );
      expect(v, contains('DNS 解析失败'));
    });

    test('HTTP status is read out of the error text', () {
      final v = novelDiagVerdict(
        searchError: 'Bad state: MoYuan call failed: HTTP 404 for '
            'https://novel.snssdk.com/api/search/v1/[object Object]',
        searchCount: 0,
      );
      expect(v, contains('HTTP 404'));
    });

    test('template residue error is called out as an engine issue', () {
      final v = novelDiagVerdict(
        searchError: 'Bad state: MoYuan call failed: URL template was '
            'not fully evaluated: http://x/{{key}}',
        searchCount: 0,
      );
      expect(v, contains('网址模板未执行'));
    });

    test('timeout in the chapters step', () {
      final v = novelDiagVerdict(
        searchCount: 3,
        chaptersError: 'TimeoutException: MoYuan call timed out',
      );
      expect(v, startsWith('目录失败'));
      expect(v, contains('请求超时'));
    });

    test('zero results with an empty body', () {
      final v = novelDiagVerdict(searchCount: 0, searchBody: '  ');
      expect(v, contains('网站响应为空'));
    });

    test('zero results behind a verification page', () {
      final v = novelDiagVerdict(
        searchCount: 0,
        searchBody: '<html><body>请完成滑动验证后继续访问</body></html>',
      );
      expect(v, contains('验证/拦截页'));
    });

    test('zero results with a full page means the list rule matched nothing',
        () {
      final body = '<html><body>${'x' * 500}</body></html>';
      final v = novelDiagVerdict(searchCount: 0, searchBody: body);
      expect(v, contains('列表规则 0 匹配'));
    });

    test('empty chapter list', () {
      final v = novelDiagVerdict(searchCount: 5, chaptersCount: 0);
      expect(v, contains('目录为空'));
    });

    test('content extracted nothing', () {
      final v = novelDiagVerdict(
        searchCount: 5,
        chaptersCount: 100,
        contentBlocks: 0,
      );
      expect(v, contains('正文为空'));
    });

    test('full chain ok', () {
      final v = novelDiagVerdict(
        searchCount: 10,
        chaptersCount: 1794,
        contentBlocks: 42,
      );
      expect(v, contains('全链通过'));
    });
  });
}
