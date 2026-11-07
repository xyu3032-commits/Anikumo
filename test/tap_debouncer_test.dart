import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/utils/tap_debouncer.dart';

void main() {
  setUp(TapDebouncer.reset);

  test('first tap for a key is accepted', () {
    expect(TapDebouncer.accept('info:1', now: DateTime(2026)), isTrue);
  });

  test('a repeat tap inside the window is dropped', () {
    final t0 = DateTime(2026, 1, 1, 12);
    expect(TapDebouncer.accept('info:1', now: t0), isTrue);
    expect(
      TapDebouncer.accept('info:1',
          now: t0.add(const Duration(milliseconds: 300))),
      isFalse,
    );
  });

  test('a tap after the window is accepted again', () {
    final t0 = DateTime(2026, 1, 1, 12);
    expect(TapDebouncer.accept('info:1', now: t0), isTrue);
    expect(
      TapDebouncer.accept('info:1',
          now: t0.add(TapDebouncer.window + const Duration(milliseconds: 1))),
      isTrue,
    );
  });

  test('different keys never block each other', () {
    final t0 = DateTime(2026, 1, 1, 12);
    expect(TapDebouncer.accept('info:1', now: t0), isTrue);
    expect(TapDebouncer.accept('info:2', now: t0), isTrue);
    expect(TapDebouncer.accept('manga:1', now: t0), isTrue);
  });
}
