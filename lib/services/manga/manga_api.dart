import 'package:anikumo/modules/manga/manga_item.dart';
import 'dart:convert';

import 'package:anikumo/services/cross_search_trio.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/manga/cross_media.dart';
import 'package:anikumo/utils/transient_retry.dart';

/// The facade every manga page talks to. Browsing calls go to the
/// ACTIVE source; calls about a specific manga (chapters, pages,
/// detail enrichment) always go to that manga's OWN source, so a
/// favorite from another source still opens and reads correctly.
///
/// Batch 16: the facade now memoizes the expensive, repeat-heavy
/// calls for ALL sources (previously only MangaDex cached its
/// chapter feed internally): chapter lists and detail enrichment
/// for 10 minutes, tag lists for 30, and search results for the
/// session. Favorites' new-chapter checks and back-navigation
/// stop re-hitting the network (or re-spinning a JS runtime).
class MangaApi {
  MangaApi._();

  static MangaSource get active => MangaSources.active();

  /// Batch 62: null-safe twin for UI that renders even when
  /// no source is installed yet (build() must never throw —
  /// in release mode that is a pure-grey screen).
  static MangaSource? get activeOrNull => MangaSources.activeOrNull();

  static final _chaptersCache = _TtlCache<List<MangaChapter>>(
    ttl: const Duration(minutes: 10),
    capacity: 50,
  );
  static final _detailsCache = _TtlCache<MangaItem>(
    ttl: const Duration(minutes: 10),
    capacity: 50,
  );
  static final _tagsCache = _TtlCache<List<MangaTag>>(
    ttl: const Duration(minutes: 30),
    capacity: 16,
  );
  static final _searchCache = _TtlCache<List<MangaItem>>(
    ttl: const Duration(minutes: 30),
    capacity: 40,
  );
  static final _pagesCache = _TtlCache<List<MangaPage>>(
    ttl: const Duration(minutes: 10),
    capacity: 30,
  );
  // Batch 22: popular/updated lists had NO cache at all —
  // every entry into the manga zone re-ran every source's
  // tags + popular (full JS bridge calls for JS sources).
  static final _popularCache = _TtlCache<List<MangaItem>>(
    ttl: const Duration(minutes: 10),
    capacity: 24,
  );
  static final _updatedCache = _TtlCache<List<MangaItem>>(
    ttl: const Duration(minutes: 10),
    capacity: 24,
  );

  /// Drops every memoized entry (source switches, manual
  /// refreshes). Visible for tests.
  static void clearCaches() {
    _chaptersCache.clear();
    _detailsCache.clear();
    _tagsCache.clear();
    _searchCache.clear();
    _pagesCache.clear();
    _popularCache.clear();
    _updatedCache.clear();
  }

  static Future<List<MangaItem>> searchManga(
    String keyword, {
    int limit = 30,
    int page = 1,
  }) =>
      searchMangaFor(active, keyword, limit: limit, page: page);

  /// Batch 97: search ONE chosen source (the search page's
  /// free source switching). Same memo and hard cap as the
  /// active-source variant — the cap used to live only on
  /// the active path (batch 95).
  static Future<List<MangaItem>> searchMangaFor(
    MangaSource source,
    String keyword, {
    int limit = 30,
    int page = 1,
  }) async {
    final key = '${source.id}|$keyword|$limit|$page';
    final cached = _searchCache.get(key);
    if (cached != null) return cached;
    // Batch 95: hard cap. This await used to be unbounded:
    // a JS source serializes its engine calls, and the
    // engine's own timeout only starts when a call reaches
    // the head of the queue — a call queued behind a wedged
    // one (a source whose search/category code loops
    // internally on an unusual keyword, some tag names
    // among them) waited forever, and the search page's
    // spinner with it.
    final result = await source
        .search(keyword, limit: limit, page: page)
        .timeout(const Duration(seconds: 30));
    if (result.isNotEmpty) _searchCache.put(key, result);
    return result;
  }

  /// The sources a cross-zone manga search uses by default
  /// (batch 75): the user's pinned trio when set (see
  /// SettingsKeys.mangaCrossSearchSourceIds), otherwise the
  /// active source first, then the rest in display order —
  /// at most [maxCrossSearchSources] either way.
  static List<MangaSource> crossSearchSources() {
    final all = MangaSources.all();
    if (all.isEmpty) return const [];
    final ordered = MangaSources.sortForDisplay(all);
    final head = activeOrNull;
    final arranged = [
      if (head != null) head,
      for (final source in ordered)
        if (source.id != head?.id) source,
    ];
    return resolveCrossSearchTrio(
      arranged,
      idOf: (source) => source.id,
      pinnedIds: decodeCrossSearchIds(
        GStorage.getSetting(SettingsKeys.mangaCrossSearchSourceIds),
      ),
    );
  }

  /// Merges per-source legs for the cross-zone search
  /// (batch 75). Legs are in priority order, leg 0 being the
  /// primary (the active / first pinned source). When the
  /// primary came back empty-handed the rest simply lead;
  /// when it answered with nothing relevant to the keyword
  /// ("不对") while a fallback leg DID answer, the fallback
  /// legs are promoted ahead — the auto-switch — and the
  /// primary's results are KEPT behind them with a reserved
  /// tail slice instead of being dropped. When nothing is
  /// relevant anywhere, plain priority order is kept (the
  /// caller's loose-match display decides). Pure and static
  /// so the rule is unit-testable.
  static List<MangaItem> mergeSearchLegs(
    List<List<MangaItem>> legs,
    String keyword, {
    int limit = 24,
  }) {
    if (legs.isEmpty) return const [];
    final primary = legs.first;
    bool legUseful(List<MangaItem> leg) =>
        leg.any((item) => _titleMatchesQuery(item.title, keyword));
    final switchNeeded = primary.isNotEmpty &&
        keyword.trim().isNotEmpty &&
        !legUseful(primary) &&
        legs.skip(1).any(legUseful);
    final seen = <String>{};
    List<MangaItem> dedupe(Iterable<MangaItem> items) => [
          for (final item in items)
            if (seen.add(item.storageKey)) item,
        ];
    if (!switchNeeded) {
      return dedupe([
        for (final leg in legs) ...leg,
      ]).take(limit).toList();
    }
    final head = dedupe([
      for (final leg in legs.skip(1)) ...leg,
    ]);
    final tail = dedupe(primary).take(6).toList();
    final headBudget = limit - tail.length;
    return [
      ...head.take(headBudget < 0 ? 0 : headBudget),
      ...tail,
    ];
  }

  /// Title-vs-query relevance for the auto-switch decision:
  /// normalized containment (exact / prefix / contains all
  /// count). Mirrors mangaTitleScore's <= 2 buckets in
  /// manga_search_utils.dart; duplicated here in miniature
  /// because that file imports this one (for the
  /// availability checker), and the pair must not cycle.
  static bool _titleMatchesQuery(String title, String query) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(
          RegExp(
            '[\\s·・、,，.。!！?？:：;；"“”\'「」『』()（）\\[\\]【】\\-—~～]',
          ),
          '',
        )
        .trim();
    final t = normalize(title);
    final q = normalize(query);
    return q.isNotEmpty && t.isNotEmpty && t.contains(q);
  }

  /// Search for the cross-zone search pages. Batch 48
  /// introduced it as "active source first, others only when
  /// it comes back empty or broken"; batch 72 made the legs
  /// parallel with partial merges; batch 75 caps the fan-out
  /// at the cross-search trio (see [crossSearchSources]) and
  /// merges through [mergeSearchLegs].
  static Future<List<MangaItem>> searchMangaMulti(
    String keyword, {
    int limit = 24,
    void Function(List<MangaItem> merged)? onPartial,
  }) =>
      _searchMangaLegs(
        crossSearchSources(),
        keyword,
        limit: limit,
        onPartial: onPartial,
      );

  /// The 「更多搜索」 widening (batch 75): every installed
  /// source NOT in [excludeIds], in parallel, no trio cap.
  /// The caller merges the result with what it already shows
  /// (the original results stay).
  static Future<List<MangaItem>> searchMangaRest(
    String keyword, {
    required Set<String> excludeIds,
    int limit = 96,
    void Function(List<MangaItem> merged)? onPartial,
  }) {
    final rest = [
      for (final source in MangaSources.sortForDisplay(MangaSources.all()))
        if (!excludeIds.contains(source.id)) source,
    ];
    return _searchMangaLegs(rest, keyword, limit: limit, onPartial: onPartial);
  }

  /// Parallel legs over [sources], each bounded at 8s,
  /// merged (source-priority order, deduped) into partial
  /// emissions as they land, so the caller shows the fastest
  /// source's results first and fills in as the rest arrive.
  /// The returned future completes with the final merge.
  static Future<List<MangaItem>> _searchMangaLegs(
    List<MangaSource> sources,
    String keyword, {
    required int limit,
    void Function(List<MangaItem> merged)? onPartial,
  }) async {
    if (sources.isEmpty) return const [];
    final activeId = activeOrNull?.id;
    final legs = <Future<List<MangaItem>>>[
      for (final source in sources)
        // The active leg goes through searchManga to reuse
        // its result cache; a repeat cross search is free.
        (source.id == activeId
                ? searchManga(keyword, limit: limit)
                : source.search(keyword, limit: limit))
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () => const <MangaItem>[],
            )
            .catchError((_) => const <MangaItem>[]),
    ];
    final perLeg = List<List<MangaItem>>.filled(legs.length, const []);
    List<MangaItem> merge() => mergeSearchLegs(perLeg, keyword, limit: limit);

    var settled = 0;
    await Future.wait([
      for (var i = 0; i < legs.length; i++)
        legs[i].then((items) {
          perLeg[i] = items;
          settled++;
          if (onPartial != null && settled < legs.length) {
            onPartial(merge());
          }
        }),
    ]);
    return merge();
  }

  static Future<List<MangaItem>> fetchPopular({int limit = 20, int page = 1}) =>
      fetchPopularFor(active, limit: limit, page: page);

  /// Batch 22: per-source cached popular list — the home
  /// page's per-source sections use this instead of calling
  /// the source directly (which bypassed every cache).
  static Future<List<MangaItem>> fetchPopularFor(
    MangaSource source, {
    int limit = 20,
    int page = 1,
    bool fresh = false,
  }) async {
    // Batch 96: the cache/snapshot key no longer contains
    // [limit]. No current source type honours it (JS sources
    // return their whole feed; the Legado adapter returns
    // the site's own page) — it only fragmented the caches:
    // the home section (limit 20) and the explore grid
    // (limit 24) fetched the SAME list twice through the
    // serialized engine, and the grid's disk-snapshot lookup
    // missed the snapshot the home section had just written.
    // One fetch now serves every caller. (Old limit-keyed
    // snapshots simply age out of the store.)
    final key = '${source.id}|P|$page';
    // Batch 90: [fresh] (manual pull-refresh) bypasses the
    // memo — a refresh that silently returns the 10-minute
    // cache reads as "refresh does nothing / is broken".
    if (!fresh) {
      final cached = _popularCache.get(key);
      if (cached != null) return cached;
    }
    // Batch 40: aggregate timeout — a source that chains
    // several slow requests (or a JS source whose engine is
    // wedged) previously kept grids and home sections on
    // skeletons forever. Individual requests already time
    // out per-source; this bounds the whole call so callers
    // land in their error states.
    // Batch 43: one automatic retry on transient flakes.
    // Batch 96: the 30 s cap now wraps the RETRY as a whole.
    // It used to sit inside, and TimeoutException counts as
    // transient — a slow source burned 30 s, retried from
    // scratch, and burned another 30 s before the grid saw
    // anything. The total budget is 30 s, retry included.
    final result = await retryTransient(
      () => source.popular(limit: limit, page: page),
    ).timeout(const Duration(seconds: 30));
    if (result.isNotEmpty) {
      _popularCache.put(key, result);
      _writePopularSnapshot(key, result);
    }
    return result;
  }

  // ---- Batch 25: disk snapshots (stale-while-revalidate) --
  //
  // The in-memory caches die with the process, so a cold
  // start still paid every source's full load (JS sources:
  // a whole bridge round) before painting anything. Popular
  // lists now persist to disk; the home section paints the
  // snapshot instantly and refreshes in the background when
  // it is older than the memory TTL.

  static Map<String, dynamic>? _snapshotStoreCache;

  /// Drops the parsed snapshot store so the next read goes
  /// back to disk. Visible for tests that rewrite the
  /// persisted JSON directly.
  static void resetSnapshotStoreForTesting() {
    _snapshotStoreCache = null;
  }

  static Map<String, dynamic> _snapshotStore() {
    if (_snapshotStoreCache != null) return _snapshotStoreCache!;
    var store = <String, dynamic>{};
    final raw = GStorage.getSetting(SettingsKeys.mangaPopularSnapshotsJson);
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) store = decoded.cast<String, dynamic>();
      } catch (_) {
        store = <String, dynamic>{};
      }
    }
    return _snapshotStoreCache = store;
  }

  static void _writePopularSnapshot(String key, List<MangaItem> items) {
    try {
      final store = _snapshotStore();
      store[key] = {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((e) => e.toSnapshot()).toList(),
      };
      // Keep the newest 24 sections, mirroring the memory
      // cache's capacity.
      if (store.length > 24) {
        final sorted = store.entries.toList()
          ..sort(
            (a, b) => ((a.value as Map)['ts'] as int? ?? 0).compareTo(
              (b.value as Map)['ts'] as int? ?? 0,
            ),
          );
        for (final e in sorted.take(store.length - 24)) {
          store.remove(e.key);
        }
      }
      GStorage.putSetting(
        SettingsKeys.mangaPopularSnapshotsJson,
        jsonEncode(store),
      );
    } catch (_) {
      // Snapshots are an optimization; never fail a load
      // because persisting one failed.
    }
  }

  /// The disk snapshot for a popular list, or null when none
  /// (or older than a week — beyond that, a spinner is more
  /// honest than ancient data). [fresh] mirrors the memory
  /// TTL: a fresh snapshot needs no background refresh.
  static ({List<MangaItem> items, bool fresh})? popularSnapshot(
    MangaSource source, {
    int limit = 20,
    int page = 1,
  }) {
    try {
      // Batch 96: same unified key as fetchPopularFor —
      // [limit] is accepted for call-site compatibility but
      // no longer fragments the store.
      final entry = _snapshotStore()['${source.id}|P|$page'];
      if (entry is! Map) return null;
      final ts = entry['ts'] as int? ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > const Duration(days: 7).inMilliseconds) return null;
      final rawItems = entry['items'];
      if (rawItems is! List || rawItems.isEmpty) return null;
      final items = rawItems
          .whereType<Map>()
          .map((e) => MangaItem.fromSnapshot(e.cast<String, dynamic>()))
          .where((e) => e.id.isNotEmpty)
          .toList();
      if (items.isEmpty) return null;
      return (
        items: items,
        fresh: age <= const Duration(minutes: 10).inMilliseconds,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<MangaItem>> fetchRecentlyUpdated({
    int limit = 20,
    int page = 1,
    bool fresh = false,
  }) async {
    final source = MangaSources.activeOrNull();
    if (source == null) return const [];
    return fetchUpdatedFor(source, limit: limit, page: page, fresh: fresh);
  }

  static Future<List<MangaItem>> fetchUpdatedFor(
    MangaSource source, {
    int limit = 20,
    int page = 1,
    bool fresh = false,
  }) async {
    // Batch 96: own key space (U) — for the Legado adapter
    // "updated" is a different feed than "popular", so the
    // two must not share entries — but [limit] no longer
    // fragments this cache either (see fetchPopularFor).
    final key = '${source.id}|U|$page';
    if (!fresh) {
      final cached = _updatedCache.get(key);
      if (cached != null) return cached;
    }
    // Batch 96: this call had NO timeout and NO retry at
    // all — a wedged updated() held the home page's
    // latest-updates rail on its skeleton indefinitely. It
    // now gets the same treatment as popular: one transient
    // retry inside a 30 s total budget.
    final result = await retryTransient(
      () => source.updated(limit: limit, page: page),
    ).timeout(const Duration(seconds: 30));
    if (result.isNotEmpty) _updatedCache.put(key, result);
    return result;
  }

  static Future<List<MangaTag>> fetchTags() => fetchTagsFor(active);

  /// Batch 22: per-source cached tag list (30 min).
  static Future<List<MangaTag>> fetchTagsFor(MangaSource source) async {
    final key = source.id;
    final cached = _tagsCache.get(key);
    if (cached != null) return cached;
    final result = await source.tags();
    if (result.isNotEmpty) _tagsCache.put(key, result);
    return result;
  }

  static Future<List<MangaItem>> fetchByTag(
    String tagId, {
    int limit = 30,
    int page = 1,
  }) => active.byTag(tagId, limit: limit, page: page);

  /// [fresh] bypasses (and refreshes) the memo — the favorites
  /// new-chapter check uses it so badges never lag the cache.
  static Future<List<MangaChapter>> fetchChapters(
    MangaItem manga, {
    bool fresh = false,
  }) async {
    final source = MangaSources.byId(manga.source);
    if (source == null) return const [];
    final key = '${manga.source}|${manga.id}';
    if (!fresh) {
      final cached = _chaptersCache.get(key);
      if (cached != null) return cached;
    }
    // Batch 40: aggregate timeout, same reasoning as
    // fetchPopularFor — chapter fetches that chain paged
    // requests get 60 s for long series, then the detail
    // page's error state (with retry) takes over.
    final result = await retryTransient(
      () => source.chapters(manga).timeout(const Duration(seconds: 60)),
    );
    if (result.isNotEmpty) _chaptersCache.put(key, result);
    return result;
  }

  // ---- Batch 42: readable-edition fallback ----------------
  //
  // When a comic's own source has no readable chapters (or
  // errors out), find the same title on another installed
  // source and VERIFY it really has chapters before handing
  // it back. The global active source is never touched: the
  // switch is local to the one comic, exactly like picking
  // another source's result by hand.

  /// True when [candidate] actually serves chapters
  /// (bounded; failures count as not readable).
  static Future<bool> _hasChapters(MangaItem candidate) async {
    try {
      final chapters = await fetchChapters(
        candidate,
      ).timeout(const Duration(seconds: 25), onTimeout: () => []);
      return chapters.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// The same comic on another source, with chapters —
  /// or null when no installed source can serve it.
  static Future<MangaItem?> findReadableEdition(
    MangaItem manga, {
    int maxSources = 4,
  }) async {
    final title = manga.title.trim();
    if (title.isEmpty) return null;
    var tried = 0;
    for (final source in MangaSources.all()) {
      if (source.id == manga.source) continue;
      if (tried >= maxSources) break;
      tried++;
      try {
        final results = await source
            .search(title, limit: 10, page: 1)
            .timeout(const Duration(seconds: 15), onTimeout: () => []);
        final ranked = rankCrossManga(results, title);
        for (final candidate in ranked.take(2)) {
          if (await _hasChapters(candidate)) return candidate;
        }
      } catch (_) {
        // A broken source must not stop the fallback.
      }
    }
    return null;
  }

  /// Companion-rail search: the active source first, then
  /// the other installed sources, returning the first
  /// source's ranked matches that include at least one
  /// readable comic. Empty when nothing readable exists.
  static Future<List<MangaItem>> searchReadableCompanions(
    String title, {
    int limit = 8,
  }) async {
    final activeSource = MangaSources.activeOrNull();
    final ordered = [
      if (activeSource != null) activeSource,
      for (final s in MangaSources.all())
        if (s.id != activeSource?.id) s,
    ];
    for (final source in ordered) {
      try {
        final results = await source
            .search(title, limit: 12, page: 1)
            .timeout(const Duration(seconds: 15), onTimeout: () => []);
        final ranked = rankCrossManga(results, title);
        if (ranked.isEmpty) continue;
        // Verify the best match is readable; a source whose
        // top hit is a dead entry falls through to the next.
        if (await _hasChapters(ranked.first)) {
          return ranked.take(limit).toList();
        }
      } catch (_) {
        // Try the next source.
      }
    }
    return const [];
  }

  /// Page lists are memoized briefly: reopening a chapter (or
  /// flipping back and forth) used to re-run the source call —
  /// for JS sources that means re-executing loadEp in the
  /// runtime. Ten minutes stays well inside the signed-URL
  /// lifetime of the CDNs that expire links.
  static Future<List<MangaPage>> fetchChapterPages(
    MangaItem manga,
    MangaChapter chapter,
  ) async {
    final source = MangaSources.byId(manga.source);
    if (source == null) return const [];
    final key = '${manga.source}|${manga.id}|${chapter.id}';
    final cached = _pagesCache.get(key);
    if (cached != null) return cached;
    // Batch 40: same aggregate timeout as chapters — a
    // wedged loadEp previously spun the reader forever.
    final result = await retryTransient(
      () => source.pages(manga, chapter).timeout(const Duration(seconds: 60)),
    );
    if (result.isNotEmpty) _pagesCache.put(key, result);
    return result;
  }

  static Future<MangaItem?> fetchDetails(MangaItem manga) async {
    final source = MangaSources.byId(manga.source);
    if (source == null) return null;
    final key = '${manga.source}|${manga.id}';
    final cached = _detailsCache.get(key);
    if (cached != null) return cached;
    final result = await retryTransient(() => source.details(manga));
    if (result != null) _detailsCache.put(key, result);
    return result;
  }
}

/// A tiny TTL + LRU memo for facade results. Insertion order is
/// the eviction order; expired entries read as misses.
class _TtlCache<T> {
  _TtlCache({required this.ttl, required this.capacity});

  final Duration ttl;
  final int capacity;
  final _entries = <String, (DateTime, T)>{};

  T? get(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.$1) > ttl) {
      _entries.remove(key);
      return null;
    }
    return entry.$2;
  }

  void put(String key, T value) {
    _entries.remove(key);
    _entries[key] = (DateTime.now(), value);
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}
