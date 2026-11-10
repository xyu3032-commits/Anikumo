// Batch 154 (user report): manga JS sources sometimes
// error out and only a force-quit + relaunch recovers
// them. Root cause: a source's async init() failure was
// only a warning inside the runtime while registration
// reported success, so nothing ever re-ran init in
// process. The fix records the init outcome and heals a
// failed call with a forced clean re-registration,
// governed by the pure policy tested here (the live
// engine behaviour is covered by tool/batch154_probe).
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';

void main() {
  group('parseJsInitState (batch 154)', () {
    test('parses a failed state with its error text', () {
      final parsed = parseJsInitState(
        '{"state":"failed","error":"Error: flaky 500"}',
      );
      expect(parsed.state, 'failed');
      expect(parsed.error, 'Error: flaky 500');
    });

    test('parses ok and pending states', () {
      expect(parseJsInitState('{"state":"ok","error":""}').state, 'ok');
      expect(
        parseJsInitState('{"state":"pending","error":""}').state,
        'pending',
      );
    });

    test('unreadable replies map to none, never to failed', () {
      expect(parseJsInitState('').state, 'none');
      expect(parseJsInitState('not json').state, 'none');
      expect(parseJsInitState('[]').state, 'none');
      expect(parseJsInitState('{}').state, 'none');
      expect(parseJsInitState('{}').error, '');
    });
  });

  group('shouldAttemptInitHeal (batch 154)', () {
    final now = DateTime(2026, 11, 9, 21, 0);

    test('a failed init with no prior attempt heals', () {
      expect(
        shouldAttemptInitHeal(
          initState: 'failed',
          lastAttemptAt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('non-failed states never heal', () {
      for (final state in ['ok', 'pending', 'none', '']) {
        expect(
          shouldAttemptInitHeal(
            initState: state,
            lastAttemptAt: null,
            now: now,
          ),
          isFalse,
          reason: state,
        );
      }
    });

    test('the cooldown suppresses immediate repeat heals', () {
      expect(
        shouldAttemptInitHeal(
          initState: 'failed',
          lastAttemptAt: now.subtract(const Duration(seconds: 10)),
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldAttemptInitHeal(
          initState: 'failed',
          lastAttemptAt: now.subtract(const Duration(seconds: 29)),
          now: now,
        ),
        isFalse,
      );
    });

    test('after the cooldown another heal is allowed', () {
      expect(
        shouldAttemptInitHeal(
          initState: 'failed',
          lastAttemptAt: now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldAttemptInitHeal(
          initState: 'failed',
          lastAttemptAt: now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
