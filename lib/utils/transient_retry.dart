import 'dart:async';

/// Batch 43: transient-failure classification + one-shot
/// retry — the "self-repair" layer for source invocations.
///
/// A phone's network flakes constantly: connections reset
/// mid-flight, DNS hiccups on network switches, a CDN drops
/// one request in twenty. Before this batch every such flake
/// surfaced as a hard error state and the user had to tap
/// retry by hand. Now the API facades retry a transient
/// failure exactly once, automatically.
///
/// Deliberately NOT transient (retrying cannot help, and
/// would only double the wait or mask real state):
/// - Failed host lookup — the domain is dead; the novel
///   zone's dead-source registry owns that case.
/// - HTTP 4xx/5xx surfaced by sources （源站返回 403/502…) —
///   site-side answers, already final.
/// - Parse/rule failures （目录页没有匹配到章节…) — the site
///   answered; the answer was unusable.
/// - Handshake errors — almost always persistent (bad cert,
///   clock skew), not one-request flakes.
bool isTransientError(Object error) {
  if (error is TimeoutException) return true;
  final t = error.toString();
  if (t.contains('Failed host lookup')) return false;
  if (t.contains('HandshakeException')) return false;
  if (t.contains('源站返回')) return false;
  return t.contains('connection error') ||
      t.contains('Connection reset') ||
      t.contains('Connection closed') ||
      t.contains('connectionTimeout') ||
      t.contains('receiveTimeout') ||
      t.contains('sendTimeout') ||
      t.contains('SocketException') ||
      t.contains('网络请求失败') ||
      t.contains('JS 引擎已重置') ||
      t.contains('JS 引擎故障') ||
      t.contains('JS 引擎未就绪') ||
      t.contains('引擎启动超时');
}

/// Runs [run]; on a transient failure waits briefly and
/// runs it once more. The second failure (transient or not)
/// propagates untouched.
Future<T> retryTransient<T>(
  Future<T> Function() run, {
  Duration delay = const Duration(milliseconds: 600),
}) async {
  try {
    return await run();
  } catch (e) {
    if (!isTransientError(e)) rethrow;
    await Future<void>.delayed(delay);
    return run();
  }
}

/// Batch 69: bounded multi-attempt retry with backoff for
/// callers whose error types carry their own retryability
/// (e.g. the anime zone's typed NetworkException, where a
/// 429/5xx or a timeout deserves another attempt but a 4xx
/// or a bad certificate does not). [shouldRetry] decides
/// per failure; the last failure propagates.
Future<T> retryWithBackoff<T>(
  Future<T> Function() run, {
  required bool Function(Object error) shouldRetry,
  int maxAttempts = 3,
  List<Duration> delays = const [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ],
}) async {
  var attempt = 0;
  while (true) {
    try {
      return await run();
    } catch (e) {
      attempt++;
      if (attempt >= maxAttempts || !shouldRetry(e)) rethrow;
      final i = attempt - 1;
      await Future<void>.delayed(
          i < delays.length ? delays[i] : delays.last);
    }
  }
}
