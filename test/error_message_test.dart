import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/utils/error_message.dart';

// Batch 41: home sections must show short human messages,
// not raw exception dumps (v12 device screenshots showed
// full DioException strings in red across the novel home).
void main() {
  group('friendlyError', () {
    test('DNS failure (dead source domain)', () {
      expect(
        friendlyError(Exception(
            "DioException [connection error]: The connection errored: "
            "Failed host lookup: 'www.deqixs.com'")),
        contains('域名解析失败'),
      );
    });

    test('TLS handshake failure', () {
      expect(
        friendlyError(Exception(
            'DioException [unknown]: null\n'
            'Error: HandshakeException: Handshake error in client')),
        contains('安全握手错误'),
      );
    });

    test('timeouts', () {
      expect(friendlyError(Exception('TimeoutException after 0:00:30')),
          contains('超时'));
      expect(
        friendlyError(Exception('DioException [receive timeout]')),
        contains('超时'),
      );
    });

    test('StateError prefix is stripped, message kept', () {
      expect(friendlyError(StateError('源站返回 403')), '源站返回 403');
      expect(friendlyError(StateError('源站返回 502')), '源站返回 502');
    });

    test('nested JS dispatcher prefix collapses', () {
      expect(
        friendlyError(StateError('JS 源调用失败：Error: 解析失败，状态码：403')),
        'JS 源调用失败：解析失败，状态码：403',
      );
    });

    test('unknown errors pass through untouched', () {
      expect(friendlyError(Exception('自定义错误')), contains('自定义错误'));
    });
  });
}
