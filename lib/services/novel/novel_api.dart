import '../../models/novel_item.dart';
import 'novel_source.dart';
import 'package:anikumo/services/cross_search_trio.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/transient_retry.dart';
import 'novel_sources.dart';

/// Facade over the novel sources, mirroring MangaApi:
/// browsing goes through the picked source; detail calls
/// route back to each book's own source.
class NovelApi {
NovelApi._();

static Future<List<NovelItem>> searchOn(
NovelSource source,
String key, {
int page = 1,
}) =>
source.search(key, page: page);

static Future<List<NovelItem>> searchActive(String key, {int page = 1}) async {
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
            .timeout(const Duration(seconds: 15),
                onTimeout: () => const <NovelItem>[]);
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
final toc = await chapters(candidate)
    .timeout(const Duration(seconds: 25), onTimeout: () => []);
if (toc.isNotEmpty) return candidate;
} catch (_) {
// Not readable on this source — try the next.
}
}
return null;
}

static NovelSource sourceFor(NovelItem item) =>
NovelSources.byId(item.source)?? NovelSources.active();

static Future<NovelItem> bookInfo(NovelItem item) =>
    retryTransient(() => sourceFor(item).bookInfo(item));

// Batch 40: aggregate timeout — resolving the TOC URL plus
// fetching the TOC page is two round trips; bound the pair
// so the detail page lands in its error state instead of
// spinning forever on a wedged site.
static Future<List<NovelChapter>> chapters(NovelItem item) =>
    // Batch 43: one automatic retry on transient flakes
    // (LegadoHttp already retries bare timeouts internally;
    // this layer covers connection resets and friends).
    retryTransient(
      () => sourceFor(item)
          .chapters(item)
          .timeout(const Duration(seconds: 60)),
    );

static Future<List<NovelBlock>> content(
NovelItem item,
NovelChapter chapter,
) =>
sourceFor(item).content(item, chapter);

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
t = t.replaceAll(
RegExp(r'[（(\]]'),
'',
);
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
(score: novelRelevanceScore(query, items[i].title), index: i, item: items[i]),
];
scored.sort((a, b) {
final byScore = a.score.compareTo(b.score);
return byScore!= 0? byScore: a.index.compareTo(b.index);
});
return [
for (final s in scored)
if (!strict || s.score < 3) s.item,
];
}
