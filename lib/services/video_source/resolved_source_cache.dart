import 'package:anikumo/services/video_source/video_source_format.dart';

/// TTL cache for already-resolved video stream URLs.
///
/// Baseline problem: every `WebViewVideoSourceService.resolve` paid a full
/// headless-WebView page load plus sniffing round (up to the 15s resolve
/// timeout), even when the user re-entered the episode they were just
/// watching, or switched away and back. Stream URLs are signed/short-lived
/// on many sources, so entries expire after [ttl] and the cache is capped
/// with simple LRU eviction; a stale entry only ever costs one fresh
/// resolve, never a wrong video — the episode page URL is the key.
///
/// Only the stream URL and its confirmed format are stored. The playback
/// offset is *not* part of an entry: it is an echo of the offset requested
/// at resolve time, so callers rebuild the result with their own offset.
class ResolvedSourceEntry {
  const ResolvedSourceEntry({required this.url, required this.format});

  final String url;
  final VideoSourceFormat format;
}

class _CachedEntry {
  _CachedEntry(this.entry, this.storedAt);

  final ResolvedSourceEntry entry;
  final DateTime storedAt;
}

class ResolvedSourceCache {
  ResolvedSourceCache({
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 32,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Shared instance used by the playback and download resolve paths, so a
  /// URL resolved by prefetching is visible to the player and vice versa.
  static final ResolvedSourceCache instance = ResolvedSourceCache();

  /// How long a resolved stream URL is trusted before it is re-resolved.
  final Duration ttl;

  /// Maximum number of episode entries kept; least recently used entries
  /// are evicted first.
  final int maxEntries;

  final DateTime Function() _clock;

  // Insertion-ordered (Dart maps preserve insertion order); lookups
  // re-insert their key so the first key is always the LRU one.
  final Map<String, _CachedEntry> _entries = {};

  int get size => _entries.length;

  String _key(String episodeUrl, bool useLegacyParser) =>
      '$episodeUrl\nlegacy=$useLegacyParser';

  /// Returns the cached stream for [episodeUrl], or null on miss/expiry.
  ResolvedSourceEntry? lookup(String episodeUrl, bool useLegacyParser) {
    final key = _key(episodeUrl, useLegacyParser);
    final cached = _entries[key];
    if (cached == null) return null;
    if (!_clock().isBefore(cached.storedAt.add(ttl))) {
      _entries.remove(key);
      return null;
    }
    // Refresh recency.
    _entries.remove(key);
    _entries[key] = cached;
    return cached.entry;
  }

  void store(
    String episodeUrl,
    bool useLegacyParser,
    ResolvedSourceEntry entry,
  ) {
    final key = _key(episodeUrl, useLegacyParser);
    _entries.remove(key);
    _entries[key] = _CachedEntry(entry, _clock());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void invalidate(String episodeUrl, bool useLegacyParser) {
    _entries.remove(_key(episodeUrl, useLegacyParser));
  }

  void clear() {
    _entries.clear();
  }
}
