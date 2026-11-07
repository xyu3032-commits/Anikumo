import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/modules/manga/manga_item.dart';

/// The three-way scope of the unified search used by both the
/// anime search page and the manga search page.
enum CrossSearchMode {
  all('全部'),
  anime('动漫'),
  manga('漫画'),
  // Batch 48: the novel mode the cross search never had —
  // users reported the 搜索小说 button "disappeared"; it was
  // never in this switch. Both search pages now serve it.
  novel('小说');

  const CrossSearchMode(this.label);

  final String label;
}

// Cross-media matching helpers: given an anime, find its manga
// counterpart (and vice versa). Pure and unit-tested — the pages
// feed real search results through these.

final RegExp _seasonSuffix = RegExp(
  r'[\s·]*(第[一二三四五六七八九十百\d]+[季期]|season\s*\d+|part\s*\d+|\d+(st|nd|rd|th)\s*season)\s*$',
  caseSensitive: false,
);

/// Strips a trailing season/part marker: 某番 第二季 → 某番.
String stripSeasonSuffix(String title) {
  return title.replaceAll(_seasonSuffix, '').trim();
}

/// Ordered, de-duplicated title variants to try when searching the
/// other medium: primary title, fallback (original) title, then
/// season-stripped bases of both.
List<String> buildCrossQueries({
  required String primary,
  String fallback = '',
}) {
  final queries = <String>[];
  void add(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && !queries.contains(trimmed)) {
      queries.add(trimmed);
    }
  }

  add(primary);
  add(fallback);
  add(stripSeasonSuffix(primary));
  add(stripSeasonSuffix(fallback));
  return queries;
}

String _normalizeTitle(String title) {
  return title
      .toLowerCase()
      .replaceAll(RegExp(r'[\s·・:：\-—_.,，。!！?？]'), '');
}

/// Ranks manga results for an anime title: exact-normalized title
/// matches first, then titles containing / contained by the query,
/// then everything else in source order.
List<MangaItem> rankCrossManga(List<MangaItem> results, String title) {
  final target = _normalizeTitle(stripSeasonSuffix(title));
  if (target.isEmpty) return results;
  final exact = <MangaItem>[];
  final related = <MangaItem>[];
  final rest = <MangaItem>[];
  for (final item in results) {
    final candidate = _normalizeTitle(item.title);
    if (candidate == target) {
      exact.add(item);
    } else if (candidate.contains(target) || target.contains(candidate)) {
      related.add(item);
    } else {
      rest.add(item);
    }
  }
  return [...exact, ...related, ...rest];
}

/// Same ranking for anime results of a manga title, checking both
/// the Chinese and original names.
List<BangumiItem> rankCrossAnime(List<BangumiItem> results, String title) {
  final target = _normalizeTitle(stripSeasonSuffix(title));
  if (target.isEmpty) return results;
  final exact = <BangumiItem>[];
  final related = <BangumiItem>[];
  final rest = <BangumiItem>[];
  for (final item in results) {
    final candidates = [
      _normalizeTitle(item.nameCn),
      _normalizeTitle(item.name),
    ];
    if (candidates.contains(target)) {
      exact.add(item);
    } else if (candidates
        .any((c) => c.contains(target) || target.contains(c))) {
      related.add(item);
    } else {
      rest.add(item);
    }
  }
  return [...exact, ...related, ...rest];
}
