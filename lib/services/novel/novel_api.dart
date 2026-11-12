import 'dart:async';

import '../../models/novel_item.dart';
import 'novel_source.dart';
import 'package:anikumo/services/cross_search_trio.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/transient_retry.dart';
import 'novel_sources.dart';
import 'legado_http.dart';
import 'moyuan_host.dart';

/// Facade over the novel sources, mirroring MangaApi:
/// browsing goes through the picked source; detail calls
/// route back to each book's own source.
class NovelApi {
  NovelApi._();

  static Future<List<NovelItem>> searchOn(
    NovelSource source,
    String key, {
    int page = 1,
  }) => source.search(key, page: page);

  static Future<List<NovelItem>> searchActive(
    String key, {
    int page = 1,
  }) async {
    // Batch 62: no source installed -> an empty result, not
    // a StateError out of active().
    final source = NovelSources.activeOrNull();
    if (source == null) return const [];
    return source.search(key, page: page);
  }

  /// Fan out to every source; a failing source contributes
  /// nothing instead of failing the whole search.
  static Future<List<NovelItem>> searchAll(String key) =>
      _searchSources(NovelSources.sortForDisplay(NovelSources.all()), key);

  /// The sources a cross-zone novel search uses by default
  /// (batch 75): the user's pinned trio when set (see
  /// SettingsKeys.novelCrossSearchSourceIds), otherwise the
  /// display order with live sources ahead of hard-dead ones —
  /// at most [maxCrossSearchSources] either way.
  static List<NovelSource> crossSearchSources() {
    final ordered = NovelSources.sortForDisplay(NovelSources.all());
    final arranged = [
      for (final s in ordered)
        if (!NovelSources.isDead(s.id)) s,
      for (final s in ordered)
        if (NovelSources.isDead(s.id)) s,
    ];
    return resolveCrossSearchTrio(
      arranged,
      idOf: (source) => source.id,
      pinnedIds: decodeCrossSearchIds(
        GStorage.getSetting(SettingsKeys.novelCrossSearchSourceIds),
      ),
    );
  }

  /// Cross-zone default search (batch 75): just the trio from
  /// [crossSearchSources], same wave rules as [searchAll].
  static Future<List<NovelItem>> searchCross(String key) =>
      _searchSources(crossSearchSources(), key);

  /// The 「更多搜索」 widening (batch 75): every installed
  /// source NOT in [excludeIds], no trio cap. The caller
  /// merges the result with what it already shows.
  static Future<List<NovelItem>> searchCrossRest(
    String key, {
    required Set<String> excludeIds,
  }) {
    final rest = [
      for (final s in NovelSources.sortForDisplay(NovelSources.all()))
        if (!excludeIds.contains(s.id)) s,
    ];
    return _searchSources(rest, key);
  }

  /// Batch 51 core, shared by searchAll / searchCross /
  /// searchCrossRest: pinned-first order (the caller's),
  /// hard-dead sources skipped (batch 46 registry) unless
  /// every live source returns nothing, at most 6 searches in
  /// flight, and a 15s per-source ceiling — the fix for
  /// "too many novel sources lag the other zones".
  static Future<List<NovelItem>> _searchSources(
    List<NovelSource> ordered,
    String key,
  ) async {
    final alive = [
      for (final s in ordered)
        if (!NovelSources.isDead(s.id)) s,
    ];
    final dead = [
      for (final s in ordered)
        if (NovelSources.isDead(s.id)) s,
    ];
    var results = await _searchWave(alive, key);
    if (results.isEmpty && dead.isNotEmpty) {
      results = await _searchWave(dead, key);
    }
    final seen = <String>{};
    return [
      for (final list in results)
        for (final item in list)
          if (seen.add(item.storageKey)) item,
    ];
  }

  /// One wave of a pooled multi-source search: at most six
  /// sources in flight, each capped at 15 seconds, result
  /// lists kept in source order.
  static Future<List<List<NovelItem>>> _searchWave(
    List<NovelSource> sources,
    String key,
  ) async {
    if (sources.isEmpty) return const [];
    final out = List<List<NovelItem>>.filled(sources.length, const []);
    var next = 0;
    Future<void> worker() async {
      while (next < sources.length) {
        final i = next++;
        try {
          out[i] = await sources[i]
              .search(key)
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () => const <NovelItem>[],
              );
        } catch (_) {
          out[i] = const [];
        }
      }
    }

    final lanes = sources.length < 6 ? sources.length : 6;
    await Future.wait([for (var w = 0; w < lanes; w++) worker()]);
    return out;
  }

  /// Batch 42: the same book on another source, VERIFIED to
  /// have chapters — the novel counterpart of the manga
  /// readable-edition fallback. Used when a book's own source
  /// returns no chapters or errors, and by the anime detail's
  /// companion rail. Verification is bounded per candidate;
  /// the first candidate whose chapter list really loads
  /// wins. Null when nothing readable exists anywhere.
  static Future<NovelItem?> findReadableEdition(
    NovelItem item, {
    int verifyCount = 3,
  }) async {
    final title = item.title.trim();
    if (title.isEmpty) return null;
    final results = await searchAll(title);
    final ranked = rankNovels(title, results, strict: true);
    var checked = 0;
    for (final candidate in ranked) {
      if (candidate.storageKey == item.storageKey) continue;
      if (checked >= verifyCount) break;
      checked++;
      try {
        final toc = await chapters(
          candidate,
        ).timeout(const Duration(seconds: 25), onTimeout: () => []);
        if (toc.isNotEmpty) return candidate;
      } catch (_) {
        // Not readable on this source — try the next.
      }
    }
    return null;
  }

  /// Test seam (null in production): overrides source
  /// resolution so the session caches can be exercised
  /// without the JS engine.
  static NovelSource Function(NovelItem item)? debugSourceResolver;

  static NovelSource sourceFor(NovelItem item) =>
      debugSourceResolver?.call(item) ??
      NovelSources.byId(item.source) ??
      NovelSources.active();

  static Future<NovelItem> bookInfo(NovelItem item) =>
      retryTransient(() => sourceFor(item).bookInfo(item));

  // Batch 40: aggregate timeout — resolving the TOC URL plus
  // fetching the TOC page is two round trips; bound the pair
  // so the detail page lands in its error state instead of
  // spinning forever on a wedged site.
  // ---- Batch 192: session caches -------------------------
  // Chapter lists and chapter contents are re-asked
  // constantly (detail -> reader, chapter back-and-forth)
  // and every ask re-ran the whole engine + network path
  // on the UI isolate — the main novel-side jank source.
  // Cache both for the session; any source install /
  // remove / update bumps NovelSources.revision and
  // empties the caches.
  static int _cacheRevision = -1;
  static final Map<String, List<NovelChapter>> _chaptersCache = {};
  static final Map<String, Future<NovelContentResult>> _contentCache = {};

  static void _syncCaches() {
    final revision = NovelSources.revision.value;
    if (revision != _cacheRevision) {
      _cacheRevision = revision;
      _chaptersCache.clear();
      _contentCache.clear();
    }
  }

  /// Warm a chapter's content in the session cache (the
  /// reader calls this for the next chapter after a
  /// successful load). Errors are swallowed; failed
  /// futures evict themselves, so a later real load of
  /// the same chapter retries the source.
  static void prefetchContent(NovelItem item, NovelChapter chapter) {
    unawaited(contentDetailed(item, chapter).then((_) {}, onError: (_) {}));
  }

  static Future<List<NovelChapter>> chapters(
    NovelItem item, {
    bool fresh = false,
  }) async {
    _syncCaches();
    final key = item.storageKey;
    if (!fresh) {
      final cached = _chaptersCache[key];
      if (cached != null) return cached;
    }
    final chapters = await retryTransient(
      () => sourceFor(item).chapters(item).timeout(const Duration(seconds: 60)),
    );
    // An empty list usually marks a transient source
    // state; do not pin it for the session.
    if (chapters.isNotEmpty) {
      if (_chaptersCache.length >= 32) {
        _chaptersCache.remove(_chaptersCache.keys.first);
      }
      _chaptersCache[key] = chapters;
    }
    return chapters;
  }

  static Future<List<NovelBlock>> content(
    NovelItem item,
    NovelChapter chapter,
  ) => sourceFor(item).content(item, chapter);

  /// Batch 184: content with the completeness signal, for
  /// the reader's chapter-end state. Only definition-backed
  /// sources can know about truncation; every other source
  /// returns its blocks unflagged.
  static Future<NovelContentResult> contentDetailed(
    NovelItem item,
    NovelChapter chapter,
  ) {
    // Batch 192: session-cached and single-flight — the
    // reader's next-chapter prefetch and a real load of
    // the same chapter share one engine + network pass.
    _syncCaches();
    final key = '${item.storageKey}::${chapter.url}';
    final cached = _contentCache[key];
    if (cached != null) return cached;
    final future = _fetchContentDetailed(item, chapter);
    if (_contentCache.length >= 16) {
      _contentCache.remove(_contentCache.keys.first);
    }
    _contentCache[key] = future;
    // Only successful, readable results stay cached; a
    // failure or an empty chapter evicts itself so the
    // next attempt retries the source.
    // Batch 195: flagged results (pagination cut short, or a
    // verification wall's preview) evict themselves too —
    // pinning a preview would keep serving it after the
    // reader passes the site's check in the web view.
    future.then(
      (result) {
        if ((!novelBlocksHaveContent(result.blocks) ||
                result.possiblyTruncated ||
                result.verificationRequired) &&
            identical(_contentCache[key], future)) {
          _contentCache.remove(key);
        }
      },
      onError: (_) {
        if (identical(_contentCache[key], future)) {
          _contentCache.remove(key);
        }
      },
    );
    return future;
  }

  static Future<NovelContentResult> _fetchContentDetailed(
    NovelItem item,
    NovelChapter chapter,
  ) async {
    final source = sourceFor(item);
    if (source is LegadoNovelSource) {
      return source.contentDetailed(item, chapter);
    }
    return NovelContentResult(await source.content(item, chapter));
  }

  /// The item's source headers (User-Agent etc.) for the
  /// reader's WebView mode.
  static Map<String, String> headersFor(NovelItem item) =>
      sourceFor(item).headers;
}

/// Normalize a title for cross-media matching: lowercase,
/// strip brackets, season/part markers and punctuation —
/// the same treatment the manga ranker gives anime titles.
String normalizeNovelTitle(String title) {
  var t = title.toLowerCase().trim();
  t = t.replaceAll(RegExp(r'[（(\]]'), '');
  t = t.replaceAll(
    RegExp(r'第[一二三四五六七八九十\d]+[季部卷册]|[sS]eason\s*\d+|season\s*\d+'),
    '',
  );
  t = t.replaceAll(RegExp(r'[\s·・:：、，,。.\-—_~!！?？]'), '');
  return t;
}

/// 0 exact, 1 prefix, 2 contains, 3 unrelated.
int novelRelevanceScore(String query, String title) {
  final q = normalizeNovelTitle(query);
  final t = normalizeNovelTitle(title);
  if (q.isEmpty || t.isEmpty) return 3;
  if (t == q) return 0;
  if (t.startsWith(q) || q.startsWith(t)) return 1;
  if (t.contains(q) || q.contains(t)) return 2;
  return 3;
}

/// Sort by relevance (stable within a tier). With [strict],
/// unrelated (score 3) results are dropped — the mode the
/// anime/manga companion rails use.
List<NovelItem> rankNovels(
  String query,
  List<NovelItem> items, {
  bool strict = false,
}) {
  final scored = [
    for (var i = 0; i < items.length; i++)
      (
        score: novelRelevanceScore(query, items[i].title),
        index: i,
        item: items[i],
      ),
  ];
  scored.sort((a, b) {
    final byScore = a.score.compareTo(b.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return [
    for (final s in scored)
      if (!strict || s.score < 3) s.item,
  ];
}

/// Batch 252: the cookie header for [url] from whichever
/// jar the live engines keep — the MoYuan engine's own
/// jar first (its fetches maintain it), the Dart jar
/// second (WebView flows plant there). Guarded: a jar
/// that is not up yet simply contributes nothing.
String novelCookieHeaderFor(String url) {
  try {
    final fromEngine = MoyuanHost.instance.cookieHeaderFor(url);
    if (fromEngine.isNotEmpty) return fromEngine;
  } catch (_) {}
  try {
    return LegadoHttp.cookieHeaderFor(url);
  } catch (_) {
    return '';
  }
}

/// Batch 252: complete a chapter image's request
/// headers. Content rules attach only what they declare;
/// for sources that declare nothing, image requests
/// used to go out with no User-Agent, no Referer and no
/// cookies while the chapter pages themselves ride the
/// engine's full stack — image CDNs with anti-hotlink
/// or UA gates rejected exactly those requests (the
/// chapter rendered, every image broken). Completion
/// mirrors the engine's own fetches: the source's
/// declared UA (else the shared browser UA), the
/// chapter page as Referer, the jars' cookies for the
/// image host. Anything the block already carries wins.
Map<String, String> novelImageRequestHeaders({
  required Map<String, String> blockHeaders,
  required Map<String, String> sourceHeaders,
  required String chapterUrl,
  required String imageUrl,
  required String cookieHeader,
}) {
  final out = <String, String>{};
  final present = <String>{};
  void put(String key, String value) {
    if (value.isEmpty) return;
    final lower = key.toLowerCase();
    if (present.contains(lower)) return;
    present.add(lower);
    out[key] = value;
  }

  blockHeaders.forEach(put);
  String? declaredUa;
  for (final e in sourceHeaders.entries) {
    if (e.key.toLowerCase() == 'user-agent') declaredUa = e.value;
  }
  put('User-Agent', declaredUa ?? LegadoHttp.defaultUa);
  if (chapterUrl.isNotEmpty) put('Referer', chapterUrl);
  if (cookieHeader.isNotEmpty) put('Cookie', cookieHeader);
  return out;
}
