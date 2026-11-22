import 'package:anikumo/services/video_source/video_source_format.dart';

/// Batch 277 (#3): in-memory index of already-resolved
/// episode streams, keyed semantically by
/// (adapterName, src, road, episode) instead of by page
/// URL like the service-level `ResolvedSourceCache`.
///
/// Why a second layer: the URL-keyed cache only hits when
/// the caller reproduces the exact page URL string. The
/// player thinks in (source, work, road, episode) terms,
/// so this index lets an episode switch answer "have we
/// resolved this episode on this road?" directly — most
/// importantly for the episode the 80%-playback prefetch
/// just resolved.
///
/// Only the stream URL and its confirmed format are
/// stored. Playback headers are not part of a resolve
/// result in this player: they are derived from the
/// plugin at play time and are identical on the hit and
/// miss paths. Stream URLs are signed/short-lived on
/// many sources, so entries expire after [ttl] and the
/// index is capped with LRU eviction; a stale entry only
/// ever costs one fresh resolve.
class EpisodeResolveEntry {
  const EpisodeResolveEntry({required this.url, required this.format});

  final String url;
  final VideoSourceFormat format;
}

class _IndexedEntry {
  _IndexedEntry(this.entry, this.storedAt);

  final EpisodeResolveEntry entry;
  final DateTime storedAt;
}

class EpisodeResolveIndex {
  EpisodeResolveIndex({
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 32,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Shared instance: the prefetch path stores, the
  /// episode-switch path looks up.
  static final EpisodeResolveIndex instance = EpisodeResolveIndex();

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _clock;

  // Insertion-ordered; lookups re-insert their key so the
  // first key is always the least recently used one.
  final Map<String, _IndexedEntry> _entries = {};

  int get size => _entries.length;

  static String key({
    required String adapterName,
    required String src,
    required int road,
    required int episode,
  }) =>
      '$adapterName\n$src\n$road\n$episode';

  /// Returns the indexed stream for [key], or null on
  /// miss/expiry.
  EpisodeResolveEntry? lookup(String key) {
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

  void store(String key, EpisodeResolveEntry entry) {
    _entries.remove(key);
    _entries[key] = _IndexedEntry(entry, _clock());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void invalidate(String key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }
}
