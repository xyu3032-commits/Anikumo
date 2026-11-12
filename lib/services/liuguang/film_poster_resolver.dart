import 'dart:async';
import 'dart:convert';

import 'package:liuguang_core/liuguang_core.dart';

import 'package:anikumo/services/liuguang/cms_api_source.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 212: source-poster backfill for poster cards.
///
/// Some interface stations ship slim list payloads with no
/// poster field at all (verified live: their ac=list rows
/// carry only id/name/type/remarks), so cards rendered
/// straight from browse/search results have nothing to
/// show — the poster only appears after opening the detail
/// page, whose payload does include it. This resolver
/// closes that gap: ids are queued per source, flushed in
/// ONE batched detail call per source (the interface
/// accepts comma-separated ids), and the results are
/// cached persistently (including confirmed "no poster").
class FilmPosterResolver {
  FilmPosterResolver._();

  static final FilmPosterResolver instance = FilmPosterResolver._();

  static const _maxCacheEntries = 800;
  static const _flushDelay = Duration(milliseconds: 200);
  static const _batchSize = 20;

  final Map<String, String> _cache = {};
  final Map<String, Completer<String?>> _pending = {};
  final Map<String, Set<String>> _queues = {};
  bool _cacheLoaded = false;
  Timer? _flushTimer;

  /// Batch 217: cache writes are coalesced (see
  /// TvMazeCoverService) — one whole-map write per batch
  /// flush was a write storm while scrolling.
  DateTime? _lastPersistAt;
  Timer? _persistTimer;
  bool _persistDirty = false;

  /// Persists now when the last write is not recent
  /// (awaited by the caller, so ordering stays observable),
  /// and coalesces bursts into one trailing write.
  Future<void> _schedulePersist() {
    _persistDirty = true;
    final last = _lastPersistAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 2)) {
      _persistTimer ??= Timer(const Duration(seconds: 2), () {
        _persistTimer = null;
        if (_persistDirty) unawaited(_persistCache());
      });
      return Future.value();
    }
    return _persistCache();
  }

  void _loadCache() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final raw = GStorage.getSetting(SettingsKeys.videoSourcePosterCacheJson);
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) => _cache['$k'] = '$v');
      }
    } catch (_) {
      // A corrupt poster cache just re-resolves on demand.
    }
  }

  Future<void> _persistCache() async {
    _persistDirty = false;
    _lastPersistAt = DateTime.now();
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    await GStorage.putSetting(
      SettingsKeys.videoSourcePosterCacheJson,
      jsonEncode(_cache),
    );
  }

  /// The poster to show for [item]: its own when it has
  /// one, the cached backfill when known, otherwise a
  /// batched lookup (null when the source has none either).
  Future<String?> posterFor(MediaItem item) {
    final own = item.artwork.poster;
    if (own != null && own.isNotEmpty) return Future.value(own);
    _loadCache();
    final hit = _cache[item.id];
    if (hit != null) return Future.value(hit.isEmpty ? null : hit);
    final running = _pending[item.id];
    if (running != null) return running.future;
    // Feasibility first: an item whose source is gone (or
    // storage is not up yet, as in widget tests) resolves
    // to null immediately — no debounce timer is armed for
    // a lookup that cannot succeed anyway.
    try {
      final service = VideoEngineService.instance;
      service.loadRegistry();
      final known = service.sources.any((s) => s.id == item.sourceId);
      if (!known) return Future.value(null);
    } catch (_) {
      return Future.value(null);
    }
    final completer = Completer<String?>();
    _pending[item.id] = completer;
    (_queues[item.sourceId] ??= {}).add(item.id);
    _flushTimer ??= Timer(_flushDelay, _flush);
    if ((_queues[item.sourceId]?.length ?? 0) >= _batchSize) {
      _flush();
    }
    return completer.future;
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final queues = Map<String, Set<String>>.of(_queues);
    _queues.clear();
    for (final entry in queues.entries) {
      unawaited(_resolveSource(entry.key, entry.value.toList()));
    }
  }

  Future<void> _resolveSource(String sourceId, List<String> mediaIds) async {
    Map<String, String> found = const {};
    try {
      final service = VideoEngineService.instance;
      service.loadRegistry();
      VideoSourceEntry? entry;
      for (final s in service.sources) {
        if (s.id == sourceId) {
          entry = s;
          break;
        }
      }
      if (entry != null) {
        final provider = service.providerFor(entry);
        if (provider is CmsApiSource) {
          found = await provider.fetchPosterUrls(mediaIds);
        }
      }
      for (final id in mediaIds) {
        _cache[id] = found[id] ?? '';
      }
      await _schedulePersist();
    } catch (_) {
      // A failed batch is not cached — the next appearance
      // of the card tries again.
    } finally {
      for (final id in mediaIds) {
        final completer = _pending.remove(id);
        final url = found[id];
        completer?.complete((url == null || url.isEmpty) ? null : url);
      }
    }
  }
}
