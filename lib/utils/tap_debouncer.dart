/// Batch 58: shared guard against double-tap navigation.
///
/// The app's lists open detail pages with pushNamed. When a
/// page feels slow, users tap again — and without a guard
/// the same route stacks twice, so one back press lands on
/// the same detail page again and back feels broken. Every
/// detail-open funnel now asks [accept] first: the first
/// tap for a key proceeds, repeats inside [window] are
/// dropped. Keys are per destination (zone + item id), so
/// tapping a *different* item is never blocked.
class TapDebouncer {
  TapDebouncer._();

  static const Duration window = Duration(milliseconds: 650);

  static final Map<String, DateTime> _lastAccepted = {};

  /// Whether a tap identified by [key] should go through.
  /// [now] is injectable for tests.
  static bool accept(String key, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final last = _lastAccepted[key];
    if (last != null && at.difference(last) < window) {
      return false;
    }
    _lastAccepted[key] = at;
    // Bound the map: entries older than the window can
    // never reject again, so they are safe to drop.
    if (_lastAccepted.length > 256) {
      _lastAccepted.removeWhere(
        (_, time) => at.difference(time) >= window,
      );
    }
    return true;
  }

  /// Test hook: forget all recorded taps.
  static void reset() => _lastAccepted.clear();
}
