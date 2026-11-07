/// Per-plugin circuit breaker for rule (plugin) requests.
///
/// Baseline problem (measured from the request stack): a dead plugin costs
/// a full connect (15s) + receive (30s) timeout window in
/// `PluginSearchService.queryAllSource`, and it costs that again on *every*
/// search, because the only health record was [PluginValidityTracker],
/// which remembers successes and forgets failures entirely.
///
/// This breaker remembers failures instead: after [failureThreshold]
/// consecutive failures a plugin is skipped instantly for [cooldown], then
/// a single half-open probe decides whether it rejoins rotation. A "no
/// result" or "captcha required" outcome means the site answered, so
/// callers should report those via [recordAlive], not [recordFailure].
library;

enum PluginCircuitState { closed, open, halfOpen }

class _PluginCircuit {
  int consecutiveFailures = 0;
  DateTime? openedAt;
  bool probeInFlight = false;
}

class PluginCircuitBreaker {
  PluginCircuitBreaker({
    this.failureThreshold = 3,
    this.cooldown = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Consecutive failures required to open the circuit.
  final int failureThreshold;

  /// How long an open circuit skips requests before allowing one probe.
  final Duration cooldown;

  final DateTime Function() _clock;
  final Map<String, _PluginCircuit> _circuits = {};

  PluginCircuitState stateOf(String pluginName) {
    final circuit = _circuits[pluginName];
    if (circuit == null || circuit.openedAt == null) {
      return PluginCircuitState.closed;
    }
    if (circuit.probeInFlight) return PluginCircuitState.halfOpen;
    return _cooldownElapsed(circuit)
        ? PluginCircuitState.halfOpen
        : PluginCircuitState.open;
  }

  int consecutiveFailures(String pluginName) =>
      _circuits[pluginName]?.consecutiveFailures ?? 0;

  bool isOpen(String pluginName) =>
      stateOf(pluginName) == PluginCircuitState.open;

  /// Whether a request for [pluginName] may run now.
  ///
  /// In half-open state exactly one probe is admitted; concurrent callers
  /// are rejected until that probe reports back. With [forceProbe] (the
  /// user explicitly tapping that source) a single manual probe is admitted
  /// even while the circuit is open.
  bool canExecute(String pluginName, {bool forceProbe = false}) {
    final circuit = _circuits.putIfAbsent(pluginName, _PluginCircuit.new);
    if (circuit.openedAt == null) return true;
    if (circuit.probeInFlight) return false;
    if (forceProbe || _cooldownElapsed(circuit)) {
      circuit.probeInFlight = true;
      return true;
    }
    return false;
  }

  /// The site produced a usable result. Closes the circuit.
  void recordSuccess(String pluginName) => _close(pluginName);

  /// The site answered but yielded nothing usable (no results, or a
  /// captcha challenge). The site is alive, so this also closes the
  /// circuit — only transport/parse failures count against it.
  void recordAlive(String pluginName) => _close(pluginName);

  /// A transport or parse failure. Opens the circuit once the consecutive
  /// failure count reaches [failureThreshold]; a failed half-open probe
  /// re-opens it immediately and restarts the cooldown.
  void recordFailure(String pluginName) {
    final circuit = _circuits.putIfAbsent(pluginName, _PluginCircuit.new);
    final wasProbe = circuit.probeInFlight;
    circuit.probeInFlight = false;
    circuit.consecutiveFailures++;
    if (wasProbe || circuit.consecutiveFailures >= failureThreshold) {
      circuit.openedAt = _clock();
    }
  }

  /// Releases a half-open probe slot without changing the circuit state.
  /// Used when an admitted probe is abandoned for a reason that says
  /// nothing about the site's health (query superseded or cancelled).
  void releaseProbe(String pluginName) {
    final circuit = _circuits[pluginName];
    if (circuit != null) circuit.probeInFlight = false;
  }

  void reset(String pluginName) {
    _circuits.remove(pluginName);
  }

  void resetAll() {
    _circuits.clear();
  }

  void _close(String pluginName) {
    final circuit = _circuits[pluginName];
    if (circuit == null) return;
    circuit.consecutiveFailures = 0;
    circuit.openedAt = null;
    circuit.probeInFlight = false;
  }

  bool _cooldownElapsed(_PluginCircuit circuit) {
    final openedAt = circuit.openedAt;
    if (openedAt == null) return false;
    return !_clock().isBefore(openedAt.add(cooldown));
  }
}
