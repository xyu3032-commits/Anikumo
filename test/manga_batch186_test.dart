// Batch 186: three reader-facing fixes.
//  (0) The novel reader rendered NOTHING for every source
//      (user: "all sources are like this") while diagnostics
//      returned content fine: the reader state's _item field
//      self-initialized (`late NovelItem _item = _item`), so
//      the first read threw StackOverflowError before any
//      chapter could render — and the catch's error text
//      reads the same field, so not even the error showed.
//  (1) Manga JS sources dying after long reading sessions
//      ("JS source errors until I force-quit"): session
//      state cached on a source instance (tokens, API
//      domains fetched at init) expires while initState
//      still reads 'ok', so the batch-154 init heal never
//      fires. The streak heal force re-registers after 3
//      consecutive call failures (bounded by a cooldown);
//      its pure policy is tested here.
//  (2) The manga reader loads the next chapter when the
//      reader scrolls/swipes to the end, in addition to
//      the chapter-end button (source-scan guards below).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';

void main() {
  group('shouldAttemptStreakHeal (batch 186)', () {
    final now = DateTime(2026, 11, 10, 19, 0);

    test('below the threshold never heals', () {
      for (final failures in [0, 1, 2]) {
        expect(
          shouldAttemptStreakHeal(
            failures: failures,
            lastAttemptAt: null,
            now: now,
          ),
          isFalse,
        );
      }
    });

    test('three consecutive failures with no prior attempt heals', () {
      expect(
        shouldAttemptStreakHeal(failures: 3, lastAttemptAt: null, now: now),
        isTrue,
      );
      expect(
        shouldAttemptStreakHeal(failures: 7, lastAttemptAt: null, now: now),
        isTrue,
      );
    });

    test('the cooldown blocks an immediate second heal', () {
      expect(
        shouldAttemptStreakHeal(
          failures: 3,
          lastAttemptAt: now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        isFalse,
      );
    });

    test('after the cooldown a still-failing source may heal again', () {
      expect(
        shouldAttemptStreakHeal(
          failures: 3,
          lastAttemptAt: now.subtract(const Duration(seconds: 91)),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('novel reader blank page (batch 186)', () {
    test('no self-initializing late fields anywhere in lib/', () {
      // `late T _x = _x;` compiles, but the initializer
      // reads the field itself and throws StackOverflowError
      // on first access — the novel reader's _item did
      // exactly this, so every chapter load died before
      // rendering (and the error message, which reads the
      // field too, never rendered either).
      final pattern = RegExp(r'late\s+\S+\s+(_?\w+)\s*=\s*\1\s*;');
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          for (final m in pattern.allMatches(entity.readAsStringSync())) {
            offenders.add('${entity.path}: ${m.group(0)}');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('the reader seeds _item from the route arguments', () {
      final reader = File(
        'lib/pages/novel/novel_reader_page.dart',
      ).readAsStringSync();
      expect(reader, contains('late NovelItem _item = widget.args.item;'));
    });
  });

  group('reader scroll-to-next wiring (batch 186)', () {
    final reader = File(
      'lib/pages/manga/manga_reader_page.dart',
    ).readAsStringSync();

    test('the chapter-end button is still there (tap to load)', () {
      expect(reader, contains('onPressed: _nextChapter'));
      expect(reader, contains("const Text('下一话')"));
    });

    test('continuous mode auto-loads on overscroll and on bottom rest', () {
      expect(reader, contains('_maybeAutoNextChapter'));
      expect(reader, contains('notification.overscroll > 0'));
      expect(reader, contains('_bottomDwell'));
    });

    test('paged modes auto-load past the reading-end edge', () {
      expect(reader, contains('_atReadingEnd'));
      expect(reader, contains('notification.overscroll < 0'));
    });

    test('auto-next is armed per chapter and cannot chain-fire', () {
      expect(reader, contains('_autoNextArmed = true'));
      expect(reader, contains('_autoNextArmed = false'));
    });
  });
}
