// Batch 277 (#2): pure A-B segment-loop decisions for the
// player. The playback controller owns the two points as
// observable state; everything testable about the feature
// lives here so it can be verified without a media player.
//
// Rules:
// - The loop is active only when both points are set and
//   B is strictly after A.
// - Setting A at or past an existing B discards B (the
//   segment would be empty or inverted).
// - Setting B at or before an existing A is rejected
//   (the previous state is kept), so a stray tap cannot
//   destroy a good A point.
// - When the playhead reaches B, playback seeks back
//   to A.

/// The (a, b) pair after the user marks point A at [point].
({Duration? a, Duration? b}) abLoopApplyA({
  required Duration? a,
  required Duration? b,
  required Duration point,
}) {
  return (a: point, b: (b != null && point < b) ? b : null);
}

/// The (a, b) pair after the user marks point B at [point].
/// Without an A point, or with [point] not after A, the
/// state is returned unchanged.
({Duration? a, Duration? b}) abLoopApplyB({
  required Duration? a,
  required Duration? b,
  required Duration point,
}) {
  if (a == null || point <= a) return (a: a, b: b);
  return (a: a, b: point);
}

/// Whether the A-B loop is currently armed.
bool abLoopActive({required Duration? a, required Duration? b}) =>
    a != null && b != null && b > a;

/// Where playback should seek to keep looping, or null
/// when the playhead has not reached B yet (or the loop
/// is not armed).
Duration? abLoopSeekTarget({
  required Duration position,
  required Duration? a,
  required Duration? b,
}) {
  if (!abLoopActive(a: a, b: b)) return null;
  return position >= b! ? a : null;
}
