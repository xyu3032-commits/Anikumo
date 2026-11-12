import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:liuguang_storage/liuguang_storage.dart';
import 'm3u8.dart';

enum DownloadStatus { queued, downloading, paused, completed, failed, canceled }

class DownloadException implements Exception {
  final String message;
  DownloadException(this.message);
  @override String toString() => 'DownloadException: $message';
}

class DownloadTask {
  final String id;
  final String url;
  final String targetPath;
  final Map<String, String> headers;
  final int totalBytes; // -1 = unknown
  final int downloadedBytes;
  final DownloadStatus status;
  final String? error;
  final DateTime createdAt;
  final bool isHls;
  final bool rangeFallback;
  const DownloadTask({required this.id, required this.url, required this.targetPath, this.headers = const {},
      this.totalBytes = -1, this.downloadedBytes = 0, this.status = DownloadStatus.queued, this.error,
      required this.createdAt, this.isHls = false, this.rangeFallback = false});
  double get progress => totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0, 1).toDouble() : -1;
  DownloadTask copyWith({int? totalBytes, int? downloadedBytes, DownloadStatus? status, String? error, bool? rangeFallback}) => DownloadTask(
      id: id, url: url, targetPath: targetPath, headers: headers, totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes, status: status ?? this.status,
      error: error, createdAt: createdAt, isHls: isHls, rangeFallback: rangeFallback ?? this.rangeFallback);
  Map<String, dynamic> toJson() => {'id': id, 'url': url, 'targetPath': targetPath, 'headers': headers,
      'totalBytes': totalBytes, 'downloadedBytes': downloadedBytes, 'status': status.name, 'error': error,
      'createdAt': createdAt.toIso8601String(), 'isHls': isHls, 'rangeFallback': rangeFallback};
  factory DownloadTask.fromJson(Map<String, dynamic> j) => DownloadTask(
      id: j['id']?.toString() ?? '', url: j['url']?.toString() ?? '', targetPath: j['targetPath']?.toString() ?? '',
      headers: j['headers'] is Map ? (j['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())) : const {},
      totalBytes: j['totalBytes'] is num ? (j['totalBytes'] as num).toInt() : -1,
      downloadedBytes: j['downloadedBytes'] is num ? (j['downloadedBytes'] as num).toInt() : 0,
      status: DownloadStatus.values.firstWhere((e) => e.name == j['status'], orElse: () => DownloadStatus.queued),
      error: j['error']?.toString(),
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      isHls: j['isHls'] == true, rangeFallback: j['rangeFallback'] == true);
}

class DownloadResponse {
  final int statusCode;
  final int? contentLength; // length of THIS response body
  final bool acceptsRanges;
  final Stream<List<int>> body;
  const DownloadResponse({required this.statusCode, this.contentLength, this.acceptsRanges = false, required this.body});
}

/// Injectable byte transport. The default implementation is dart:io
/// based; tests substitute an in-memory one. (liuguang_network's client is
/// body-string oriented, so downloads stream bytes through this seam.)
abstract interface class DownloadTransport {
  Future<DownloadResponse> open(Uri uri, {Map<String, String> headers = const {}, int? rangeStart});
}

class IoDownloadTransport implements DownloadTransport {
  final HttpClient _client;
  IoDownloadTransport([HttpClient? client]) : _client = client ?? HttpClient();
  @override Future<DownloadResponse> open(Uri uri, {Map<String, String> headers = const {}, int? rangeStart}) async {
    final req = await _client.getUrl(uri);
    headers.forEach((k, v) => req.headers.set(k, v));
    if (rangeStart != null && rangeStart > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$rangeStart-');
    final resp = await req.close();
    final acceptRanges = resp.headers.value(HttpHeaders.acceptRangesHeader);
    return DownloadResponse(statusCode: resp.statusCode, contentLength: resp.contentLength < 0 ? null : resp.contentLength,
        acceptsRanges: resp.statusCode == 206 || (acceptRanges?.contains('bytes') ?? false), body: resp);
  }
}

/// Download manager: bounded-concurrency queue, HTTP Range resume,
/// pause/resume/cancel, bounded auto-retry, progress stream, and task
/// persistence via [StorageAdapter] (unfinished tasks survive restarts;
/// a task found in `downloading` state after restore is parked as
/// paused). HLS media playlists are downloaded segment by segment and
/// concatenated into a single output file with segment-level resume.
/// Encrypted (AES-128) and live playlists fail with an explicit error.
class DownloadManager {
  final StorageAdapter storage;
  final DownloadTransport transport;
  final int maxConcurrent;
  final int maxRetries;
  final Future<void> Function(Duration) _sleep;
  static const tasksTable = 'downloads';
  static const segmentsTable = 'download_segments';

  final Map<String, DownloadTask> _tasks = {};
  final List<String> _waiting = [];
  final Set<String> _running = {};
  final Set<String> _pauseFlags = {};
  final Set<String> _cancelFlags = {};
  final _updates = StreamController<DownloadTask>.broadcast();

  DownloadManager({required this.storage, DownloadTransport? transport, this.maxConcurrent = 2, this.maxRetries = 2,
      Future<void> Function(Duration)? sleeper})
      : transport = transport ?? IoDownloadTransport(), _sleep = sleeper ?? ((d) => Future.delayed(d));

  Stream<DownloadTask> get updates => _updates.stream;
  List<DownloadTask> get tasks => _tasks.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  DownloadTask? task(String id) => _tasks[id];

  Future<void> restore() async {
    _tasks.clear();
    for (final row in await storage.all(tasksTable)) {
      var t = DownloadTask.fromJson(row);
      if (t.status == DownloadStatus.downloading) {
        t = t.copyWith(status: DownloadStatus.paused, error: 'interrupted by restart');
        await _persist(t);
      }
      _tasks[t.id] = t;
    }
  }

  Future<DownloadTask> enqueue({required String url, required String targetPath, Map<String, String> headers = const {}, String? id}) async {
    final task = DownloadTask(id: id ?? 'dl-${DateTime.now().microsecondsSinceEpoch}', url: url, targetPath: targetPath,
        headers: headers, createdAt: DateTime.now(), isHls: Uri.parse(url).path.toLowerCase().endsWith('.m3u8'));
    _tasks[task.id] = task;
    await _persist(task);
    _updates.add(task);
    return task;
  }

  Future<void> _persist(DownloadTask t) => storage.put(tasksTable, t.id, t.toJson());
  void _set(DownloadTask t, {bool persist = true}) {
    _tasks[t.id] = t;
    _updates.add(t);
    if (persist) unawaited(_persist(t));
  }

  Future<void> start(String id) async {
    final t = _tasks[id];
    if (t == null) throw DownloadException('unknown task $id');
    if (t.status == DownloadStatus.completed || t.status == DownloadStatus.canceled || _running.contains(id)) return;
    if (_running.length >= maxConcurrent) {
      if (!_waiting.contains(id)) _waiting.add(id);
      _set(t.copyWith(status: DownloadStatus.queued));
      return;
    }
    _launch(id);
  }

  void _launch(String id) {
    _running.add(id);
    unawaited(_run(id).whenComplete(() {
      _running.remove(id);
      _pauseFlags.remove(id);
      _cancelFlags.remove(id);
      _pump();
    }));
  }

  void _pump() {
    while (_running.length < maxConcurrent && _waiting.isNotEmpty) {
      final id = _waiting.removeAt(0);
      final t = _tasks[id];
      if (t != null && t.status != DownloadStatus.canceled && t.status != DownloadStatus.completed) _launch(id);
    }
  }

  Future<void> _awaitParked(String id) async {
    var guard = 0;
    while (_running.contains(id) && guard++ < 1000) { await Future<void>.delayed(const Duration(milliseconds: 2)); }
  }

  Future<void> pause(String id) async {
    final t = _tasks[id];
    if (t == null) throw DownloadException('unknown task $id');
    if (_running.contains(id)) {
      _pauseFlags.add(id);
      await _awaitParked(id);
    } else {
      _waiting.remove(id);
      if (t.status == DownloadStatus.queued) _set(t.copyWith(status: DownloadStatus.paused));
    }
  }

  Future<void> resume(String id) async {
    final t = _tasks[id];
    if (t == null) throw DownloadException('unknown task $id');
    if (t.status == DownloadStatus.completed || t.status == DownloadStatus.canceled) return;
    _set(t.copyWith(status: DownloadStatus.queued, error: null));
    await start(id);
  }

  Future<void> cancel(String id) async {
    final t = _tasks[id];
    if (t == null) throw DownloadException('unknown task $id');
    if (_running.contains(id)) {
      _cancelFlags.add(id);
      await _awaitParked(id);
    } else {
      _waiting.remove(id);
      _set(t.copyWith(status: DownloadStatus.canceled));
      await _deletePart(t);
    }
  }

  Future<void> _deletePart(DownloadTask t) async {
    final part = File('${t.targetPath}.part');
    if (await part.exists()) await part.delete();
  }

  Future<void> _run(String id) async {
    var t = _tasks[id]!;
    var attempt = 0;
    while (true) {
      try {
        if (t.isHls) { await _runHls(id); } else { await _runPlain(id); }
        return;
      } catch (e) {
        t = _tasks[id]!;
        if (t.status == DownloadStatus.paused || t.status == DownloadStatus.canceled || _cancelFlags.contains(id)) return;
        if (attempt >= maxRetries) {
          _set(t.copyWith(status: DownloadStatus.failed, error: e.toString()));
          return;
        }
        attempt++;
        _set(t.copyWith(error: 'retry $attempt after: $e'));
        await _sleep(Duration(milliseconds: 50 * attempt));
        t = _tasks[id]!;
        if (t.status == DownloadStatus.canceled) return;
      }
    }
  }

  /// Returns true when the task was parked (paused/canceled) mid-stream.
  Future<bool> _runPlain(String id) async {
    var t = _tasks[id]!;
    final part = File('${t.targetPath}.part');
    await part.parent.create(recursive: true);
    var existing = await part.exists() ? await part.length() : 0;
    final resp = await transport.open(Uri.parse(t.url), headers: t.headers, rangeStart: existing > 0 ? existing : null);
    if (resp.statusCode >= 400) throw DownloadException('HTTP ${resp.statusCode} for ${t.url}');
    var append = existing > 0 && resp.statusCode == 206;
    var rangeFallback = t.rangeFallback;
    if (existing > 0 && !append) { rangeFallback = true; existing = 0; } // server ignored Range: restart cleanly, never duplicate bytes
    final total = resp.contentLength == null ? t.totalBytes : (append ? existing + resp.contentLength! : resp.contentLength!);
    t = t.copyWith(status: DownloadStatus.downloading, totalBytes: total, downloadedBytes: existing, rangeFallback: rangeFallback, error: null);
    _set(t);
    final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
    var downloaded = existing;
    try {
      await for (final chunk in resp.body) {
        if (_cancelFlags.contains(id)) { await sink.close(); await _deletePart(t); _set(t.copyWith(status: DownloadStatus.canceled)); return true; }
        if (_pauseFlags.contains(id)) { await sink.flush(); await sink.close(); _set(t.copyWith(status: DownloadStatus.paused, downloadedBytes: downloaded)); return true; }
        sink.add(chunk);
        downloaded += chunk.length;
        t = t.copyWith(downloadedBytes: downloaded);
        _set(t, persist: false);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try { await sink.close(); } catch (_) {}
      rethrow;
    }
    final len = await part.length();
    if (total > 0 && len != total) throw DownloadException('size mismatch: got $len of $total bytes');
    await part.rename(t.targetPath);
    _set(t.copyWith(status: DownloadStatus.completed, downloadedBytes: len, totalBytes: total > 0 ? total : len));
    return false;
  }

  Future<String> _fetchText(Uri uri, Map<String, String> headers) async {
    final resp = await transport.open(uri, headers: headers);
    if (resp.statusCode >= 400) throw DownloadException('HTTP ${resp.statusCode} for $uri');
    final bytes = <int>[];
    await for (final c in resp.body) { bytes.addAll(c); }
    return utf8.decode(bytes);
  }

  Future<bool> _runHls(String id) async {
    var t = _tasks[id]!;
    final part = File('${t.targetPath}.part');
    await part.parent.create(recursive: true);
    // ---- segment plan (persisted for segment-level resume)
    Map<String, dynamic>? segRow = await storage.get(segmentsTable, id);
    List<String> urls; List<int> lengths; var done = 0;
    if (segRow == null) {
      final text = await _fetchText(Uri.parse(t.url), t.headers);
      final pl = parseM3u8(text, base: Uri.parse(t.url));
      if (pl.isMaster) throw DownloadException('master playlists are not supported for download; enqueue a media playlist instead');
      if (pl.isEncrypted) throw DownloadException('encrypted HLS segments are not supported (EXT-X-KEY METHOD=${pl.keyMethod}, e.g. AES-128)');
      if (pl.isLive) throw DownloadException('live HLS playlists (no EXT-X-ENDLIST) are not supported for download');
      if (pl.segmentUris.isEmpty) throw DownloadException('HLS playlist contains no segments');
      urls = pl.segmentUris;
      lengths = List<int>.filled(urls.length, -1);
      await storage.put(segmentsTable, id, {'urls': urls, 'lengths': lengths, 'done': 0});
    } else {
      urls = (segRow['urls'] as List).map((e) => e.toString()).toList();
      lengths = (segRow['lengths'] as List).map((e) => (e as num).toInt()).toList();
      done = (segRow['done'] as num).toInt();
    }
    var expected = 0;
    for (var i = 0; i < done; i++) { if (lengths[i] < 0) { done = i; break; } expected += lengths[i]; }
    var partLen = await part.exists() ? await part.length() : 0;
    if (partLen != expected) {
      // Part file disagrees with the segment ledger: trust the ledger.
      if (partLen > expected) {
        final raf = await part.open(mode: FileMode.append);
        await raf.truncate(expected);
        await raf.close();
      } else {
        done = 0; expected = 0;
        lengths = List<int>.filled(urls.length, -1);
        if (await part.exists()) await part.delete();
        await storage.put(segmentsTable, id, {'urls': urls, 'lengths': lengths, 'done': 0});
      }
      partLen = expected;
    }
    t = t.copyWith(status: DownloadStatus.downloading, downloadedBytes: partLen, error: null);
    _set(t);
    final sink = part.openWrite(mode: FileMode.append);
    var downloaded = partLen;
    try {
      for (var i = done; i < urls.length; i++) {
        if (_cancelFlags.contains(id)) { await sink.close(); await _deletePart(t); await storage.delete(segmentsTable, id); _set(t.copyWith(status: DownloadStatus.canceled)); return true; }
        if (_pauseFlags.contains(id)) { await sink.flush(); await sink.close(); _set(t.copyWith(status: DownloadStatus.paused, downloadedBytes: downloaded)); return true; }
        final resp = await transport.open(Uri.parse(urls[i]), headers: t.headers);
        if (resp.statusCode >= 400) throw DownloadException('HTTP ${resp.statusCode} for segment $i');
        var segLen = 0;
        await for (final chunk in resp.body) {
          if (_cancelFlags.contains(id) || _pauseFlags.contains(id)) break;
          sink.add(chunk);
          segLen += chunk.length;
          downloaded += chunk.length;
        }
        if (_cancelFlags.contains(id) || _pauseFlags.contains(id)) { i--; downloaded -= segLen; continue; }
        lengths[i] = segLen;
        await sink.flush();
        await storage.put(segmentsTable, id, {'urls': urls, 'lengths': lengths, 'done': i + 1});
        t = t.copyWith(downloadedBytes: downloaded);
        _set(t, persist: false);
      }
    } catch (e) {
      try { await sink.close(); } catch (_) {}
      rethrow;
    }
    await sink.flush();
    await sink.close();
    if (_cancelFlags.contains(id) || _pauseFlags.contains(id)) {
      // Parked while finishing the last segment boundary.
      _set(t.copyWith(status: _cancelFlags.contains(id) ? DownloadStatus.canceled : DownloadStatus.paused, downloadedBytes: downloaded));
      if (_cancelFlags.contains(id)) { await _deletePart(t); await storage.delete(segmentsTable, id); }
      return true;
    }
    final len = await part.length();
    await part.rename(t.targetPath);
    await storage.delete(segmentsTable, id);
    _set(t.copyWith(status: DownloadStatus.completed, downloadedBytes: len, totalBytes: len));
    return false;
  }

  Future<void> dispose() async { await _updates.close(); }
}
