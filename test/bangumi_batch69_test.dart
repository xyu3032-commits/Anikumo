// Batch 69: anime tag-search resilience — the retry
// loop's behavior and which Bangumi search errors count
// as retryable (timeouts/429/5xx yes; 4xx/cert/cancel no;
// Bangumi's data-less error payload yes).
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/request/apis/bangumi_api.dart';
import 'package:anikumo/request/core/network_exception.dart';
import 'package:anikumo/utils/transient_retry.dart';

void main() {
  group('retryWithBackoff', () {
    test('succeeds after transient failures', () async {
      var calls = 0;
      final value = await retryWithBackoff<int>(
        () async {
          calls++;
          if (calls < 3) {
            throw const NetworkException(
              type: NetworkExceptionType.receiveTimeout,
              message: 'timeout',
            );
          }
          return 7;
        },
        shouldRetry: BangumiApi.isRetryableSearchError,
        delays: const [Duration(milliseconds: 1), Duration(milliseconds: 1)],
      );
      expect(value, 7);
      expect(calls, 3);
    });

    test('gives up after maxAttempts and propagates', () async {
      var calls = 0;
      await expectLater(
        retryWithBackoff<int>(
          () async {
            calls++;
            throw const NetworkException(
              type: NetworkExceptionType.connectionError,
              message: 'reset',
            );
          },
          shouldRetry: BangumiApi.isRetryableSearchError,
          delays: const [Duration(milliseconds: 1), Duration(milliseconds: 1)],
        ),
        throwsA(isA<NetworkException>()),
      );
      expect(calls, 3);
    });

    test('non-retryable errors short-circuit immediately', () async {
      var calls = 0;
      await expectLater(
        retryWithBackoff<int>(
          () async {
            calls++;
            throw const NetworkException(
              type: NetworkExceptionType.badResponse,
              message: 'not found',
              statusCode: 404,
            );
          },
          shouldRetry: BangumiApi.isRetryableSearchError,
          delays: const [Duration(milliseconds: 1), Duration(milliseconds: 1)],
        ),
        throwsA(isA<NetworkException>()),
      );
      expect(calls, 1);
    });
  });

  group('isRetryableSearchError', () {
    NetworkException ne(NetworkExceptionType type, [int? code]) =>
        NetworkException(type: type, message: 'x', statusCode: code);

    test('timeouts and connection flakes retry', () {
      expect(
          BangumiApi.isRetryableSearchError(
              ne(NetworkExceptionType.receiveTimeout)),
          isTrue);
      expect(
          BangumiApi.isRetryableSearchError(
              ne(NetworkExceptionType.connectionTimeout)),
          isTrue);
      expect(
          BangumiApi.isRetryableSearchError(
              ne(NetworkExceptionType.connectionError)),
          isTrue);
      expect(
          BangumiApi.isRetryableSearchError(ne(NetworkExceptionType.unknown)),
          isTrue);
    });

    test('429 and 5xx retry, other statuses do not', () {
      expect(
          BangumiApi.isRetryableSearchError(
              ne(NetworkExceptionType.badResponse, 429)),
          isTrue);
      expect(
          BangumiApi.isRetryableSearchError(
              ne(NetworkExceptionType.badResponse, 503)),
          isTrue);
      expect(
          BangumiApi.isRetryableSearchError(
              ne(NetworkExceptionType.badResponse, 404)),
          isFalse);
      expect(
          BangumiApi.isRetryableSearchError(
              ne(NetworkExceptionType.badResponse, 400)),
          isFalse);
    });

    test('certificate and cancel never retry', () {
      expect(
          BangumiApi.isRetryableSearchError(
              ne(NetworkExceptionType.badCertificate)),
          isFalse);
      expect(
          BangumiApi.isRetryableSearchError(ne(NetworkExceptionType.cancel)),
          isFalse);
    });

    test('data-less Bangumi payload retries, other StateErrors do not',
        () {
      expect(
          BangumiApi.isRetryableSearchError(
              StateError('Bangumi 搜索返回异常：响应缺少 data 列表')),
          isTrue);
      expect(BangumiApi.isRetryableSearchError(StateError('unrelated')),
          isFalse);
    });
  });
}
