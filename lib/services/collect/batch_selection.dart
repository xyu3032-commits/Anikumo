/// Batch 283 (#22): the pure core of the multi-select
/// modes on the collect page and the history page —
/// selection bookkeeping and batch planning, kept free
/// of widgets and storage so both pages share one
/// tested implementation. The pages own the writes.
abstract final class BatchSelection {
  /// Toggles [id] in a copy of [selected].
  static Set<T> toggle<T>(Set<T> selected, T id) {
    final next = {...selected};
    if (!next.remove(id)) next.add(id);
    return next;
  }

  static Set<T> selectAll<T>(Iterable<T> ids) => {...ids};

  /// Drops selected ids that no longer exist (a row was
  /// deleted elsewhere, a filter changed the list).
  static Set<T> prune<T>(Set<T> selected, Iterable<T> existing) {
    final alive = {...existing};
    return selected.where(alive.contains).toSet();
  }
}

/// The plan for a history-page "mark watched" batch:
/// which of the selected works can move to 看过 and
/// how many are skipped because they were never
/// collected (marking them would silently CREATE a
/// collection entry the user never asked for).
class MarkWatchedPlan {
  final List<int> toMark;
  final int skipped;

  const MarkWatchedPlan({required this.toMark, required this.skipped});
}

MarkWatchedPlan planMarkWatched(
  Iterable<int> selectedBangumiIds,
  Set<int> collectedBangumiIds,
) {
  final toMark = <int>[];
  var skipped = 0;
  for (final id in selectedBangumiIds) {
    if (collectedBangumiIds.contains(id)) {
      toMark.add(id);
    } else {
      skipped++;
    }
  }
  return MarkWatchedPlan(toMark: toMark, skipped: skipped);
}
