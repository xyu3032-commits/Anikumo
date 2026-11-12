import 'dart:async';
import 'dart:convert';

import 'package:liuguang_network/liuguang_network.dart';

import 'package:anikumo/services/storage/storage.dart';

/// Batch 211: series covers from TVmaze, for the 影视 zone
/// only — the user designated TVmaze as the cover source
/// for 电视剧 and was explicit that these covers must never
/// leak into the anime zone (whose covers come from its own
/// metadata). This service lives under services/liuguang
/// and is only ever called from film-zone code.
///
/// Endpoint facts (verified live 2026-11-11 against the
/// public API): GET https://api.tvmaze.com/search/shows?q=
/// needs NO key and returns scored matches with inline
/// images. The key the user provided belongs to TVmaze's
/// *user* API (premium, HTTP-Basic, per-account follows /
/// watched marks — see the manual at static.tvmaze.com/
/// apidoc), which serves personal data, not covers; it is
/// kept in the secure vault and deliberately unused here.
///
/// Matching is conservative — a wrong cover is worse than
/// a missing one: a result is accepted only on an exact
/// normalized title match (year must agree when both sides
/// know it), or a containment match with equal years.
/// Lookups are cached persistently (including confirmed
/// misses), de-duplicated in flight, and capped at three
/// concurrent requests.

/// Removes season / variant suffixes catalogue titles
/// commonly carry, for use as the search query.
String tvmazeSearchTitle(String title) {
  var t = title.trim();
  t = t.replaceAll(RegExp(r'（[^）]*）'), ' ');
  t = t.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  t = t.replaceAll(RegExp(r'【[^】]*】'), ' ');
  t = t.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  t = t.replaceAll(
    RegExp(
      r'(第\s*[0-9一二三四五六七八九十]+\s*[季部]|season\s*\d+|s\d{1,2})\s*$',
      caseSensitive: false,
    ),
    '',
  );
  t = t.replaceAll(RegExp(r'(国语版|粤语版|未删减版?|完整版|高清版|台版|港版)\s*$'), '');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Comparison form: lowercase, no whitespace or
/// punctuation — CJK titles compare by their characters,
/// latin titles by their letters/digits.
String normalizeTvmazeTitle(String title) {
  return tvmazeSearchTitle(
    title,
  ).toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');
}

/// Picks a poster URL out of a decoded TVmaze search
/// response (a list of {score, show} maps), or null when no
/// result matches confidently. See the class doc for the
/// acceptance rules.
String? pickTvmazePoster(Object? decoded, {required String title, int? year}) {
  if (decoded is! List) return null;
  final query = normalizeTvmazeTitle(title);
  if (query.isEmpty) return null;
  ({String url, bool exact})? containmentHit;
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final show = entry['show'];
    if (show is! Map) continue;
    final image = show['image'];
    if (image is! Map) continue;
    final url = (image['original'] ?? image['medium'])?.toString() ?? '';
    if (url.isEmpty) continue;
    final name = normalizeTvmazeTitle(show['name']?.toString() ?? '');
    if (name.isEmpty) continue;
    final premiered = show['premiered']?.toString() ?? '';
    final showYear = premiered.length >= 4
        ? int.tryParse(premiered.substring(0, 4))
        : null;
    if (name == query) {
      final yearOk =
          year == null || showYear == null || (year - showYear).abs() <= 1;
      if (yearOk) return url;
      continue;
    }
    if (containmentHit == null &&
        year != null &&
        showYear == year &&
        (name.contains(query) || query.contains(name))) {
      containmentHit = (url: url, exact: false);
    }
  }
  return containmentHit?.url;
}

class TvMazeCoverService {
  TvMazeCoverService._();

  static final TvMazeCoverService instance = TvMazeCoverService._();

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      'Chrome/120.0 Mobile Safari/537.36';
  static const _maxCacheEntries = 600;
  static const _maxConcurrent = 3;

  final LiuGuangHttpClient _client = LiuGuangHttpClient();
  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};
  bool _cacheLoaded = false;
  int _active = 0;
  final List<Completer<void>> _waiters = [];

  /// Batch 217: cache writes are coalesced — persisting the
  /// whole JSON map on every single resolution (one per
  /// poster card!) made grid scrolling a write storm on the
  /// shared settings box.
  DateTime? _lastPersistAt;
  Timer? _persistTimer;
  bool _persistDirty = false;

  /// Persists now when the last write is not recent
  /// (awaited by the caller), coalesces bursts into one
  /// trailing write.
  Future<void> _schedulePersist() {
    _persistDirty = true;
    final last = _lastPersistAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 2)) {
      _persistTimer ??= Timer(const Duration(seconds: 2), () {
        _persistTimer = null;
        if (_persistDirty) _persistCache();
      });
      return Future.value();
    }
    return _persistCache();
  }

  String _key(String title, int? year) =>
      '${normalizeTvmazeTitle(title)}|${year ?? ''}';

  void _loadCache() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final raw = GStorage.getSetting(SettingsKeys.videoTvmazeCoverCacheJson);
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) => _cache['$k'] = '$v');
      }
    } catch (_) {
      // A corrupt cover cache just re-resolves on demand.
    }
  }

  Future<void> _persistCache() async {
    _persistDirty = false;
    _lastPersistAt = DateTime.now();
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    await GStorage.putSetting(
      SettingsKeys.videoTvmazeCoverCacheJson,
      jsonEncode(_cache),
    );
  }

  /// The already-known poster for a title (no network), or
  /// null when unknown / a confirmed miss.
  String? cachedPosterFor({required String title, int? year}) {
    _loadCache();
    final hit = _cache[_key(title, year)];
    return (hit == null || hit.isEmpty) ? null : hit;
  }

  /// Resolves the TVmaze poster for a series title, using
  /// the persistent cache first. Returns null when TVmaze
  /// has no confident match — the caller keeps the source's
  /// own poster in that case.
  Future<String?> posterFor({required String title, int? year}) {
    _loadCache();
    final key = _key(title, year);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit.isEmpty ? null : hit);
    return _inFlight.putIfAbsent(key, () => _resolve(key, title, year));
  }

  Future<String?> _resolve(String key, String title, int? year) async {
    await _acquire();
    try {
      final query = Uri.encodeQueryComponent(tvmazeSearchTitle(title));
      final decoded = await _client.getJson(
        'https://api.tvmaze.com/search/shows?q=$query',
        headers: const {'User-Agent': _ua},
      );
      final url = pickTvmazePoster(decoded, title: title, year: year);
      _cache[key] = url ?? '';
      await _schedulePersist();
      return url;
    } catch (_) {
      // Network failures are NOT persisted as misses — a
      // later launch may have better luck.
      return null;
    } finally {
      _release();
      _inFlight.remove(key);
    }
  }

  Future<void> _acquire() {
    if (_active < _maxConcurrent) {
      _active++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}
