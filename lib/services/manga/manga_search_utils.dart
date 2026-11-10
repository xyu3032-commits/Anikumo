import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_source.dart';
import 'package:anikumo/services/manga/manga_sources.dart';

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

/// Batch 89: matches a manga's display tag names against a
/// source's tag catalogue, returning the catalogue entries
/// (which carry the ids `byTag` needs) in the manga's own
/// tag order. Names compare trimmed and case-insensitively;
/// unmatched names are skipped.
List<MangaTag> matchTagsByName(List<String> names, List<MangaTag> catalogue) {
  final byName = <String, MangaTag>{};
  for (final tag in catalogue) {
    byName.putIfAbsent(tag.name.trim().toLowerCase(), () => tag);
  }
  final matched = <MangaTag>[];
  final seenIds = <String>{};
  for (final name in names) {
    final tag = byName[name.trim().toLowerCase()];
    if (tag != null && seenIds.add(tag.id)) matched.add(tag);
  }
  return matched;
}

/// Batch 89: ranks tag-recommendation candidates for the
/// detail page's “你可能还喜欢” rail. The current manga is
/// dropped, duplicates collapse by storage key, and the
/// rest order by how many tags they share with the current
/// manga (descending), keeping the source's own order
/// inside a tie. Zero-shared candidates are KEPT at the
/// tail: they arrived from a tag listing, so they are
/// related by construction even when their list payload
/// carries no tag field to count.
List<MangaItem> rankTagRecommendations(
  MangaItem current,
  List<MangaItem> candidates, {
  int limit = 12,
}) {
  final wanted = {
    for (final tag in current.tags) tag.trim().toLowerCase(),
  }..remove('');
  final seen = <String>{current.storageKey};
  final decorated = <({int index, int shared, MangaItem item})>[];
  for (var i = 0; i < candidates.length; i++) {
    final item = candidates[i];
    if (!seen.add(item.storageKey)) continue;
    final shared = item.tags
        .where((tag) => wanted.contains(tag.trim().toLowerCase()))
        .length;
    decorated.add((index: i, shared: shared, item: item));
  }
  decorated.sort((a, b) {
    final byShared = b.shared.compareTo(a.shared);
    return byShared != 0 ? byShared : a.index.compareTo(b.index);
  });
  return [for (final entry in decorated.take(limit)) entry.item];
}

/// Batch 97: tags that describe a manga's FORMAT or STATUS
/// rather than its taste — they match thousands of unrelated
/// titles, so they must never DRIVE a recommendation (the
/// old 猜你喜欢 rail took the seed's first catalogue tag,
/// which was often one of these, and filled with whatever
/// the source's browse order served). Deliberately
/// conservative: only obvious non-genre labels.
const Set<String> _genericMangaTags = {
  '全彩', '彩色', '黑白', '长条', '条漫', '页漫', '竖版', '横版',
  '完结', '已完结', '连载', '连载中', '完本', '全本',
  '最新', '热门', '推荐', '更新', '新作',
  '汉化', '生肉', '双语', '单行本', '四格', '短篇', '长篇',
  'completed', 'ongoing', 'full color', 'webtoon', 'long strip',
};

bool isGenericMangaTag(String name) =>
    _genericMangaTags.contains(name.trim().toLowerCase());

/// Batch 97: builds a weighted taste profile from several
/// seed manga's tag lists. Each seed contributes its
/// non-generic tags at its weight (favorites outweigh
/// casual reads — the caller picks the weights); a tag
/// named by several seeds accumulates. Keys are normalized
/// (trimmed, lowercased); the returned map also remembers
/// one display spelling per tag for catalogue matching.
({Map<String, double> weights, Map<String, String> display})
    buildMangaTasteProfile(
  List<({List<String> tags, double weight})> seeds,
) {
  final weights = <String, double>{};
  final display = <String, String>{};
  for (final seed in seeds) {
    final seenInSeed = <String>{};
    for (final raw in seed.tags) {
      final name = raw.trim();
      if (name.isEmpty || isGenericMangaTag(name)) continue;
      final key = name.toLowerCase();
      if (!seenInSeed.add(key)) continue;
      weights[key] = (weights[key] ?? 0) + seed.weight;
      display.putIfAbsent(key, () => name);
    }
  }
  return (weights: weights, display: display);
}

/// Batch 97: ranks 猜你喜欢 candidates against a taste
/// profile. A candidate's score is the summed profile
/// weight of its own tags. Unlike the detail page's rail
/// (batch 89, where candidates arrive FROM a tag listing
/// and are related by construction), this rail gathers
/// from several tags and several seeds — a candidate that
/// shares NOTHING measurable with the user's taste is the
/// "不相关的" the user complained about, so when tag data
/// exists it is dropped, not kept at the tail. Candidates
/// whose list payload carries no tags at all can only be
/// judged when NOTHING in the pool has tags; then the
/// source order stands (some sources never expose tags in
/// lists). Exclusions (favorites / already reading / the
/// seeds themselves) and dedupe apply throughout.
List<MangaItem> rankForYouCandidates({
  required Map<String, double> profile,
  required List<MangaItem> candidates,
  required Set<String> excludeKeys,
  int limit = 10,
}) {
  final seen = <String>{};
  final scored = <({int index, double score, MangaItem item})>[];
  var anyTagged = false;
  for (var i = 0; i < candidates.length; i++) {
    final item = candidates[i];
    if (excludeKeys.contains(item.storageKey)) continue;
    if (!seen.add(item.storageKey)) continue;
    var score = 0.0;
    var tagged = false;
    for (final raw in item.tags) {
      final key = raw.trim().toLowerCase();
      if (key.isEmpty) continue;
      tagged = true;
      score += profile[key] ?? 0;
    }
    if (tagged) anyTagged = true;
    scored.add((index: i, score: score, item: item));
  }
  if (!anyTagged) {
    return [for (final e in scored.take(limit)) e.item];
  }
  final relevant = [
    for (final e in scored)
      if (e.score > 0) e,
  ];
  relevant.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return [for (final e in relevant.take(limit)) e.item];
}

/// Batch 105: second-chance catalogue match for a tag
/// name — a display tag from a manga's info rarely differs
/// from its source's catalogue entry by more than a suffix
/// or a wrapper word (热血 vs 热血漫）, and an exact-only
/// match made those tags unsearchable in their own source.
/// A candidate qualifies when either name contains the
/// other (both at least 2 characters); the closest-length
/// candidate wins. Returns at most one tag.
List<MangaTag> matchTagByPartialName(
  String name,
  List<MangaTag> catalogue,
) {
  final needle = name.trim().toLowerCase();
  if (needle.length < 2) return const [];
  MangaTag? best;
  var bestDiff = 1 << 30;
  for (final tag in catalogue) {
    final candidate = tag.name.trim().toLowerCase();
    if (candidate.length < 2) continue;
    if (!candidate.contains(needle) && !needle.contains(candidate)) {
      continue;
    }
    final diff = (candidate.length - needle.length).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = tag;
    }
  }
  return best == null ? const [] : [best];
}

/// Batch 99: tag search BY NAME across every installed
/// source. A manga's detail tags do not always appear in
/// its own source's category catalogue; the old fallback
/// for those was a keyword search — but source search
/// matches TITLES, so a tag name like 热血 searched as a
/// keyword returned nothing ("标签搜索后什么也没有").
/// This resolves the name against each source's catalogue
/// (30-minute cached) and merges the byTag results of the
/// sources that actually carry the tag. Per-source steps
/// are timeout-guarded and failure-isolated, mirroring
/// the all-source keyword search (batch 95). [sources]
/// defaults to the installed registry (tests inject
/// doubles); batch 105's search page passes exactly ONE
/// source — the tagged manga's own — because a tag search
/// is a search of that manga's source, not of all of them.
Future<List<MangaItem>> fetchMangaByTagName(
  String name, {
  int limit = 24,
  List<MangaSource>? sources,
}) async {
  final all = sources ?? MangaSources.all();
  final perSource = await Future.wait([
    for (final source in all)
      () async {
        try {
          final catalogue = await MangaApi.fetchTagsFor(source)
              .timeout(const Duration(seconds: 20));
          var matched = matchTagsByName([name], catalogue);
          if (matched.isEmpty) {
            // Batch 105: near-name second chance within the
            // same catalogue (see matchTagByPartialName).
            matched = matchTagByPartialName(name, catalogue);
          }
          if (matched.isEmpty) return const <MangaItem>[];
          return await source
              .byTag(matched.first.id, limit: limit)
              .timeout(const Duration(seconds: 25));
        } catch (_) {
          return const <MangaItem>[];
        }
      }(),
  ]);
  return dedupeMangaItems([
    for (final list in perSource) ...list,
  ]);
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

/// Batch 90: a shuffled copy of [items] (the input list is
/// not mutated). The explore grid shuffles on entry and on
/// pull-refresh so the same source catalogue does not greet
/// the user in the same order every time.
List<MangaItem> shuffledMangaItems(List<MangaItem> items) =>
    [...items]..shuffle();

/// Batch 90: decides how one fetched page merges into a
/// paged grid. [incoming] is deduped against
/// [existingKeys] (and within itself); the merge reports
/// the genuinely new items as [additions]. [hasMore] is
/// false only when the source proves the listing is over:
/// an empty page, or a page whose every item was already
/// shown (a source ignoring the page parameter and
/// repeating itself — continuing would loop forever).
/// A short-but-new page is NOT the end: sources return
/// their own page sizes (10/12/20…), and treating "fewer
/// than requested" as the end was the explore grid's
/// false-end bug.
({List<MangaItem> additions, bool hasMore}) nextMangaPageBatch(
  Iterable<String> existingKeys,
  List<MangaItem> incoming,
) {
  final seen = {...existingKeys};
  final additions = [
    for (final item in incoming)
      if (seen.add(item.storageKey)) item,
  ];
  return (
    additions: additions,
    hasMore: incoming.isNotEmpty && additions.isNotEmpty,
  );
}

/// Batch 188: end-of-list decisions take TWO consecutive
/// dud pages (empty, or nothing new on them), not one.
/// A single replayed or flaked page used to latch "no
/// more content" for the whole grid session while the
/// source still had pages left — a refresh re-armed and
/// showed them. One dud is forgiven (the caller advances
/// past it); two in a row is the source proving the
/// listing is over. Any page with new items resets the
/// count.
class MangaEndOfList {
  int _duds = 0;

  /// Records one fetched page; returns whether more
  /// pages should be attempted.
  bool record({required bool addedNew}) {
    if (addedNew) {
      _duds = 0;
      return true;
    }
    _duds++;
    return _duds < 2;
  }

  void reset() => _duds = 0;
}

/// Verifies that a manga can actually be read from its source
/// (it has at least one readable chapter). Results are cached
/// per session; the check powers the search pages' auto-hide of
/// entries a source lists but cannot serve.
class MangaAvailabilityChecker {
MangaAvailabilityChecker._();

/// Batch 90: verdicts carry their timestamp. A positive
/// verdict stays cached for the session, but a NEGATIVE
/// one now expires after 90 s: a source that answered one
/// transient empty chapter list (a captcha page, a hiccup
/// parsed as zero chapters) previously marked the manga
/// unreadable until the app restarted — one half of the
/// "sometimes readable, sometimes not" reports.
static const Duration _negativeTtl = Duration(seconds: 90);

static final Map<String, (DateTime, bool)> _cache = {};

static Future<bool> isReadable(MangaItem item) async {
final cached = _cache[item.storageKey];
if (cached!= null) {
if (cached.$2) return true;
if (DateTime.now().difference(cached.$1) < _negativeTtl) return false;
_cache.remove(item.storageKey);
}
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
_cache[item.storageKey] = (DateTime.now(), readable);
return readable;
}

/// Checks a batch with limited concurrency, reporting each
/// verdict as it lands. Batch 91: [shouldContinue] is
/// consulted before every new check — when it turns false
/// (the owning page was covered by a detail, superseded by
/// a newer search, or disposed) workers stop launching new
/// checks instead of grinding through the whole batch
/// behind the user's back; a check already in flight still
/// completes and reports.
static Future<void> checkAll(
List<MangaItem> items, {
required void Function(MangaItem item, bool readable) onResult,
int concurrency = 4,
bool Function()? shouldContinue,
}) async {
final queue = [...items];
Future<void> worker() async {
while (queue.isNotEmpty) {
if (shouldContinue != null && !shouldContinue()) return;
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
