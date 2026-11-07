import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/plugin/plugin_circuit_breaker.dart';

void main() {
  group('PluginCircuitBreaker', () {
    late DateTime now;
    late PluginCircuitBreaker breaker;

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      breaker = PluginCircuitBreaker(
        failureThreshold: 3,
        cooldown: const Duration(minutes: 5),
        clock: () => now,
      );
    });

    test('closed circuit admits requests and stays closed below threshold', () {
      expect(breaker.canExecute('a'), isTrue);
      breaker.recordFailure('a');
      breaker.recordFailure('a');
      expect(breaker.stateOf('a'), PluginCircuitState.closed);
      expect(breaker.canExecute('a'), isTrue);
      expect(breaker.consecutiveFailures('a'), 2);
    });

    test('opens after threshold consecutive failures and skips instantly', () {
      for (var i = 0; i < 3; i++) {
        expect(breaker.canExecute('a'), isTrue);
        breaker.recordFailure('a');
      }
      expect(breaker.stateOf('a'), PluginCircuitState.open);
      expect(breaker.canExecute('a'), isFalse);
    });

    test('success resets the failure streak', () {
      breaker.recordFailure('a');
      breaker.recordFailure('a');
      breaker.recordSuccess('a');
      expect(breaker.consecutiveFailures('a'), 0);
      breaker.recordFailure('a');
      breaker.recordFailure('a');
      expect(breaker.stateOf('a'), PluginCircuitState.closed);
    });

    test('recordAlive closes the circuit (site answered)', () {
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure('a');
      }
      expect(breaker.isOpen('a'), isTrue);
      breaker.recordAlive('a');
      expect(breaker.stateOf('a'), PluginCircuitState.closed);
      expect(breaker.canExecute('a'), isTrue);
    });

    test('half-open admits exactly one probe after cooldown', () {
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure('a');
      }
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(breaker.canExecute('a'), isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(breaker.stateOf('a'), PluginCircuitState.halfOpen);
      expect(breaker.canExecute('a'), isTrue);
      // The single probe is in flight; concurrent callers are rejected.
      expect(breaker.canExecute('a'), isFalse);
    });

    test('failed probe re-opens immediately and restarts cooldown', () {
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure('a');
      }
      now = now.add(const Duration(minutes: 5));
      expect(breaker.canExecute('a'), isTrue);
      breaker.recordFailure('a');
      expect(breaker.stateOf('a'), PluginCircuitState.open);
      now = now.add(const Duration(minutes: 4));
      expect(breaker.canExecute('a'), isFalse);
    });

    test('successful probe closes the circuit', () {
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure('a');
      }
      now = now.add(const Duration(minutes: 5));
      expect(breaker.canExecute('a'), isTrue);
      breaker.recordSuccess('a');
      expect(breaker.stateOf('a'), PluginCircuitState.closed);
      expect(breaker.consecutiveFailures('a'), 0);
    });

    test('forceProbe admits one manual probe while open', () {
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure('a');
      }
      expect(breaker.canExecute('a'), isFalse);
      expect(breaker.canExecute('a', forceProbe: true), isTrue);
      expect(breaker.canExecute('a', forceProbe: true), isFalse);
      breaker.releaseProbe('a');
      expect(breaker.canExecute('a', forceProbe: true), isTrue);
    });

    test('circuits are independent per plugin', () {
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure('a');
      }
      expect(breaker.isOpen('a'), isTrue);
      expect(breaker.canExecute('b'), isTrue);
      expect(breaker.stateOf('b'), PluginCircuitState.closed);
    });
  });
}
