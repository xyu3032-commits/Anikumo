import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/video_source/resolved_source_cache.dart';
import 'package:anikumo/services/video_source/video_source_format.dart';

void main() {
  group('ResolvedSourceCache', () {
    late DateTime now;
    late ResolvedSourceCache cache;

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      cache = ResolvedSourceCache(
        ttl: const Duration(minutes: 10),
        maxEntries: 3,
        clock: () => now,
      );
    });

    const entry = ResolvedSourceEntry(
      url: 'https://cdn.example/v.m3u8',
      format: VideoSourceFormat.hls,
    );

    test('miss returns null, store then lookup hits', () {
      expect(cache.lookup('https://site/ep1', false), isNull);
      cache.store('https://site/ep1', false, entry);
      final hit = cache.lookup('https://site/ep1', false);
      expect(hit, isNotNull);
      expect(hit!.url, entry.url);
      expect(hit.format, VideoSourceFormat.hls);
    });

    test('legacy parser flag is part of the key', () {
      cache.store('https://site/ep1', false, entry);
      expect(cache.lookup('https://site/ep1', true), isNull);
      expect(cache.lookup('https://site/ep1', false), isNotNull);
    });

    test('entries expire after ttl and are dropped', () {
      cache.store('https://site/ep1', false, entry);
      now = now.add(const Duration(minutes: 9, seconds: 59));
      expect(cache.lookup('https://site/ep1', false), isNotNull);
      now = now.add(const Duration(seconds: 1));
      expect(cache.lookup('https://site/ep1', false), isNull);
      expect(cache.size, 0);
    });

    test('invalidate and clear remove entries', () {
      cache.store('https://site/ep1', false, entry);
      cache.invalidate('https://site/ep1', false);
      expect(cache.lookup('https://site/ep1', false), isNull);
      cache.store('https://site/ep1', false, entry);
      cache.clear();
      expect(cache.size, 0);
    });

    test('evicts least recently used entry beyond capacity', () {
      cache.store('e1', false, entry);
      cache.store('e2', false, entry);
      cache.store('e3', false, entry);
      // Touch e1 so e2 becomes the LRU entry.
      expect(cache.lookup('e1', false), isNotNull);
      cache.store('e4', false, entry);
      expect(cache.size, 3);
      expect(cache.lookup('e2', false), isNull);
      expect(cache.lookup('e1', false), isNotNull);
      expect(cache.lookup('e3', false), isNotNull);
      expect(cache.lookup('e4', false), isNotNull);
    });

    test('re-storing an episode refreshes its timestamp', () {
      cache.store('e1', false, entry);
      now = now.add(const Duration(minutes: 9));
      cache.store('e1', false, entry);
      now = now.add(const Duration(minutes: 9));
      expect(cache.lookup('e1', false), isNotNull);
    });
  });
}
