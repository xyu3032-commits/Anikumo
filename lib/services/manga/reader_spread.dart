/// Two-page spread math for the manga reader's landscape
/// paged modes (batch 14). Pages are paired (0,1), (2,3), …
/// A spread's identity page is its first (even) page; progress
/// is always recorded against real page indexes, never spread
/// indexes.
library;

/// How many spreads [pageCount] pages make.
int spreadCount(int pageCount) =>
    pageCount <= 0 ? 0 : (pageCount + 1) ~/ 2;

/// The spread a real page belongs to.
int spreadIndexOfPage(int page) => page ~/ 2;

/// The first (identity) page of a spread.
int spreadFirstPage(int spreadIndex) => spreadIndex * 2;

/// The real pages shown in [spreadIndex], in left-to-right
/// VISUAL order: LTR reading shows (even, odd); RTL reading
/// puts the earlier page on the right, so the visual order is
/// (odd, even). A trailing odd spread yields a single page.
List<int> spreadVisualPages(
  int spreadIndex,
  int pageCount, {
  required bool rtl,
}) {
  final first = spreadFirstPage(spreadIndex);
  if (first < 0 || first >= pageCount) return const [];
  final second = first + 1;
  if (second >= pageCount) return [first];
  return rtl ? [second, first] : [first, second];
}
