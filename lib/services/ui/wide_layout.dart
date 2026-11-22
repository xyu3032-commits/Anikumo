/// Batch 284 (#30): wide-screen layout breakpoints.
///
/// Pure functions/constants so the shell, the list pages
/// and the tests all share one definition of "wide".
/// At or above [kWideLayoutMinWidth] the shell switches
/// from the portrait masthead to the left navigation rail
/// and caps the content width instead of stretching the
/// phone layout edge to edge.
library;

/// Window width (dp) at or above which the layout is wide.
const double kWideLayoutMinWidth = 900;

/// Content is never wider than this on wide screens; the
/// remaining space becomes side margin.
const double kWideContentMaxWidth = 1280;

bool isWideLayout(double width) => width >= kWideLayoutMinWidth;

/// Horizontal margin to apply on each side of the content
/// area so it stays centered at [kWideContentMaxWidth].
double wideContentSideMargin(double width) {
  if (!isWideLayout(width) || width <= kWideContentMaxWidth) return 0;
  return (width - kWideContentMaxWidth) / 2;
}

/// Poster-grid column count for a [contentWidth]-wide
/// area: one column per [minCardWidth], clamped to
/// [min]..[max]. Used by grids that size by formula
/// instead of fixed breakpoints.
int wideGridColumns(
  double contentWidth, {
  double minCardWidth = 190,
  int min = 3,
  int max = 10,
}) {
  if (contentWidth <= 0) return min;
  final raw = (contentWidth / minCardWidth).floor();
  return raw.clamp(min, max);
}
