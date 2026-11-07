import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/utils/transient_retry.dart';

// Batch 43: the self-repair classifier — transient flakes
// retry once, final answers never do.
void main() {
  group('isTransientError', () {
    test('timeouts and connection flakes are transient', () {
      expect(isTransientError(TimeoutException('slow')), isTrue);
      expect(
        isTransientError(Exception(
            'DioException [connection error]: The connection errored')),
        isTrue,
      );
      expect(
        isTransientError(const SocketException('Connection reset by peer')),
        isTrue,
      );
      expect(isTransientError(StateError('JS 引擎已重置')), isTrue);
      expect(isTransientError(Exception('网络请求失败: broken')), isTrue);
    });

    test('dead domains, site answers and parse failures are final', () {
      expect(
        isTransientError(Exception("Failed host lookup: 'www.deqixs.com'")),
        isFalse,
      );
      expect(isTransientError(StateError('源站返回 403')), isFalse);
      expect(isTransientError(StateError('源站返回 502')), isFalse);
      expect(
        isTransientError(StateError('目录页没有匹配到章节（速读谷）')),
        isFalse,
      );
      expect(
        isTransientError(Exception('HandshakeException: Handshake error')),
        isFalse,
      );
      expect(isTransientError(StateError('拷贝漫画接口返回异常')), isFalse);
    });
  });

  group('retryTransient', () {
    test('a transient first failure is retried and succeeds', () async {
      var attempts = 0;
      final value = await retryTransient(() async {
        attempts++;
        if (attempts == 1) {
          throw const SocketException('Connection reset by peer');
        }
        return 42;
      }, delay: Duration.zero);
      expect(value, 42);
      expect(attempts, 2);
    });

    test('a final failure is never retried', () async {
      var attempts = 0;
      await expectLater(
        retryTransient(() async {
          attempts++;
          throw StateError('源站返回 403');
        }, delay: Duration.zero),
        throwsStateError,
      );
      expect(attempts, 1);
    });

    test('a second transient failure propagates', () async {
      var attempts = 0;
      await expectLater(
        retryTransient(() async {
          attempts++;
          throw TimeoutException('still slow');
        }, delay: Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      expect(attempts, 2);
    });
  });
}
