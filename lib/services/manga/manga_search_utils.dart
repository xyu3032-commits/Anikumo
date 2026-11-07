import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_api.dart';

/// Normalizes a title or query for relevance comparison:
/// lowercase, with spaces and common punctuation removed.
String normalizeMangaTitle(String value) {
  final stripped = value.toLowerCase().replaceAll(
        RegExp('[\\s·・、,，.。!！?？:：;；"“”' "'" '「」『』()（）\\[\\]【】\\-—~～]'),
        '',
      );
  return stripped.trim();
}

/// Relevance bucket of a title for a query: 0 exact, 1 prefix,
/// 2 contains, 3 unrelated.
int mangaTitleScore(String title, String query) {
final t = normalizeMangaTitle(title);
final q = normalizeMangaTitle(query);
if (q.isEmpty || t.isEmpty) return 3;
if (t == q) return 0;
if (t.startsWith(q)) return 1;
if (t.contains(q)) return 2;
return 3;
}

/// Stable relevance sort (exact matches first), preserving the
/// source's own order inside each bucket.
List<MangaItem> rankMangaResults(List<MangaItem> items, String query) {
final decorated = [
for (var i = 0; i < items.length; i++)
(index: i, score: mangaTitleScore(items[i].title, query), item: items[i]),
]..sort((a, b) {
final byScore = a.score.compareTo(b.score);
return byScore!= 0? byScore: a.index.compareTo(b.index);
});
return [for (final entry in decorated) entry.item];
}

/// Batch 26: drops the unrelated tail. rankMangaResults only
/// SORTS score-3 (title shares nothing with the query) items
/// last — loose sources (fuzzy site search, broad JS-source
/// APIs) return pages of them, and both search pages then
/// displayed manga that have nothing to do with the query
/// (device-reported: “出现不相干漫画”). Keeps relevant items
/// (score <= 2); when NOTHING is relevant, non-strict mode
/// keeps the ranked list (a dedicated search page shows the
/// source's loose matches rather than a blank page), while
/// strict mode (companion sections, where precision matters
/// and empty is a fine answer) returns only relevant items.
List<MangaItem> filterRelevantMangaResults(
  List<MangaItem> ranked,
  String query, {
  bool strict = false,
}) {
  final relevant = [
    for (final item in ranked)
      if (mangaTitleScore(item.title, query) <= 2) item,
  ];
  if (relevant.isNotEmpty) return relevant;
  return strict ? const [] : ranked;
}

/// Batch 26: in all-source searches the SAME manga arrives
/// once per source; the source+id dedupe keeps them all and
/// the grid reads as duplicates. Collapses entries whose
/// normalized titles match, keeping the first (call after
/// ranking so the best-ranked copy wins).
List<MangaItem> dedupeMangaByTitle(List<MangaItem> items) {
  final seen = <String>{};
  return [
    for (final item in items)
      if (seen.add(normalizeMangaTitle(item.title))) item,
  ];
}

/// Drops duplicate entries (same source + id) keeping the first.
List<MangaItem> dedupeMangaItems(List<MangaItem> items) {
final seen = <String>{};
return [
for (final item in items)
if (seen.add(item.storageKey)) item,
];
}

/// Whether an entry carries the minimum information to be worth
/// showing at all.
bool mangaHasInfo(MangaItem item) =>
item.id.isNotEmpty && item.title.trim().isNotEmpty;

/// Verifies that a manga can actually be read from its source
/// (it has at least one readable chapter). Results are cached
/// per session; the check powers the search pages' auto-hide of
/// entries a source lists but cannot serve.
class MangaAvailabilityChecker {
MangaAvailabilityChecker._();

static final Map<String, bool> _cache = {};

static Future<bool> isReadable(MangaItem item) async {
final cached = _cache[item.storageKey];
if (cached!= null) return cached;
var readable = false;
try {
final chapters = await MangaApi.fetchChapters(item);
readable = chapters.isNotEmpty;
} catch (_) {
// Batch 26: a FAILED check (network error, a source's
// 403) is not proof of "no chapters" — treating it as
// unreadable hid perfectly good manga while junk with a
// lucky check stayed (device-reported wrong results).
// Keep the entry visible and do not cache the verdict.
return true;
}
_cache[item.storageKey] = readable;
return readable;
}

/// Checks a batch with limited concurrency, reporting each
/// verdict as it lands.
static Future<void> checkAll(
List<MangaItem> items, {
required void Function(MangaItem item, bool readable) onResult,
int concurrency = 4,
}) async {
final queue = [...items];
Future<void> worker() async {
while (queue.isNotEmpty) {
final item = queue.removeAt(0);
final readable = await isReadable(item);
onResult(item, readable);
}
}

await Future.wait([
for (var i = 0; i < concurrency && i < items.length; i++) worker(),
]);
}
}
