import 'dart:convert';

/// Batch 75: shared plumbing for the cross-zone search's
/// "three sources at a time" rule. A cross search (the manga
/// and novel sections of the anime zone's search page) runs
/// at most [maxCrossSearchSources] sources in parallel by
/// default; the user may pin WHICH sources those are, and a
/// 「更多搜索」 action in the results widens the search to
/// every remaining source on demand.

/// How many sources a default cross search fans out to.
const int maxCrossSearchSources = 3;

/// Decodes a persisted cross-search source-id list (a JSON
/// array setting). Anything unparsable reads as "no pin".
List<String> decodeCrossSearchIds(String raw) {
  if (raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return [
        for (final entry in decoded)
          if (entry != null && entry.toString().isNotEmpty) entry.toString(),
      ];
    }
  } catch (_) {}
  return const [];
}

/// Resolves which of [ordered] (the zone's sources in
/// display order) a default cross search uses: the pinned
/// ids when any of them is still installed (kept in display
/// order), otherwise the head of [ordered]. At most
/// [maxCrossSearchSources] either way.
List<T> resolveCrossSearchTrio<T>(
  List<T> ordered, {
  required String Function(T source) idOf,
  required List<String> pinnedIds,
}) {
  if (ordered.isEmpty) return const [];
  if (pinnedIds.isNotEmpty) {
    final pinned = pinnedIds.toSet();
    final picked = [
      for (final source in ordered)
        if (pinned.contains(idOf(source))) source,
    ];
    if (picked.isNotEmpty) {
      return picked.take(maxCrossSearchSources).toList();
    }
  }
  return ordered.take(maxCrossSearchSources).toList();
}
