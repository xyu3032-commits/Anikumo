import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:liuguang_core/liuguang_core.dart';

import 'film_features.dart';
import 'film_prefs.dart';
import 'video_engine.dart';

/// Batch 232: network probes behind the 线路测速优选 and
/// 下载省空间 feature packs. Every probe is best-effort —
/// a failure reads as "unknown" and the caller keeps its
/// default behaviour.

/// Time to first byte for [url] in milliseconds, or null
/// when the probe failed or timed out.
Future<int?> probeFirstByteMs(
  Uri url, {
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 6),
}) async {
  final client = HttpClient();
  client.connectionTimeout = timeout;
  final watch = Stopwatch()..start();
  try {
    final request = await client.getUrl(url).timeout(timeout);
    headers.forEach((k, v) => request.headers.set(k, v));
    final response = await request.close().timeout(timeout);
    await response.first.timeout(timeout);
    watch.stop();
    return watch.elapsedMilliseconds;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// A comparable "how heavy is this source" hint for one
/// playback source: a direct file's content length, or a
/// master playlist's lowest variant bandwidth (with the
/// variant's URL as the override to actually download).
/// Null hint = unknown weight.
Future<({int? hint, String? urlOverride})> probeSizeHint(
  VideoSource source,
) async {
  final uri = Uri.tryParse(source.url);
  if (uri == null) return (hint: null, urlOverride: null);
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 8);
  try {
    if (source.url.contains('.m3u8')) {
      final request = await client.getUrl(uri);
      source.headers.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();
      if (response.statusCode >= 400) return (hint: null, urlOverride: null);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));
      final variant = parseMasterMinVariant(body, uri);
      if (variant == null) return (hint: null, urlOverride: null);
      return (hint: variant.bandwidth, urlOverride: variant.uri.toString());
    }
    final request = await client.headUrl(uri);
    source.headers.forEach((k, v) => request.headers.set(k, v));
    final response = await request.close();
    final length = response.contentLength;
    return (hint: length > 0 ? length : null, urlOverride: null);
  } catch (_) {
    return (hint: null, urlOverride: null);
  } finally {
    client.close(force: true);
  }
}

/// Batch 237 (speed half): the 测速 probe for one film
/// source — time to first byte of its list endpoint, the
/// exact call the home and discover pages pay first.
/// Records the outcome into the shared speed table and
/// returns the measured ms (null when the probe failed).
Future<int?> probeFilmSourceSpeed(VideoSourceEntry entry) async {
  final base = entry.api;
  final sep = base.contains('?') ? '&' : '?';
  final uri = Uri.tryParse('$base${sep}ac=list&pg=1');
  if (uri == null) {
    await FilmSourceSpeeds.record(entry.id, null);
    return null;
  }
  final ms = await probeFirstByteMs(
    uri,
    headers: const {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          'Chrome/120.0 Mobile Safari/537.36',
    },
  );
  await FilmSourceSpeeds.record(entry.id, ms);
  return ms;
}

/// Batch 249: zone-entry auto-probe. Fresh records
/// (24 h, FilmSourceSpeeds.freshFor) are left alone —
/// only stale or never-measured enabled sources are
/// swept, in the background: the caller fires and
/// forgets and first paint never waits for a probe.
/// The sweep feeds the SAME speeds table the manual
/// probe and every ordering consumer already read, so
/// the refreshed order applies silently at the next
/// load. A sweep already running is not duplicated.
abstract final class FilmSpeedAutoProbe {
  static bool _running = false;

  static bool get running => _running;

  /// The entries a sweep would probe right now: enabled
  /// and (never measured or past the freshness window).
  static List<VideoSourceEntry> staleEntries(
    List<VideoSourceEntry> entries,
    DateTime now,
  ) {
    return [
      for (final e in entries)
        if (e.enabled && _isStale(e.id, now)) e,
    ];
  }

  static bool _isStale(String id, DateTime now) {
    final record = FilmSourceSpeeds.recordOf(id);
    return record == null || !FilmSourceSpeeds.isFresh(record, now);
  }

  static Future<void> maybeProbe() async {
    if (_running) return;
    final targets = staleEntries(
      VideoEngineService.instance.sources,
      DateTime.now(),
    );
    if (targets.isEmpty) return;
    _running = true;
    try {
      await probeAllFilmSourceSpeeds(targets);
    } finally {
      _running = false;
    }
  }
}

/// Batch 237 (speed half): sweeps every entry with three
/// probes in flight, reporting progress as (done, total).
Future<void> probeAllFilmSourceSpeeds(
  List<VideoSourceEntry> entries, {
  void Function(int done, int total)? onProgress,
}) async {
  var cursor = 0;
  var done = 0;
  Future<void> worker() async {
    while (cursor < entries.length) {
      final entry = entries[cursor++];
      await probeFilmSourceSpeed(entry);
      done++;
      onProgress?.call(done, entries.length);
    }
  }

  await Future.wait([worker(), worker(), worker()]);
}
