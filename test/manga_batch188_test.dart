import 'dart:io';

import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Batch 188: the manga zone's three device reports —
/// explore latching "no more content" mid-list, the
/// detail page's script error with zero chapters, and
/// the reader's black screen at a chapter switch — were
/// one family: spurious empty pages and unhealed engine
/// failures. These tests pin the Dart-side contracts;
/// the paged-chain hardening itself is JS inside the
/// runtime and is pinned as a source contract.
void main() {
  group('end-of-list takes two duds (batch 188)', () {
    test('one dud page is forgiven, the second ends it', () {
      final latch = MangaEndOfList();
      expect(latch.record(addedNew: false), isTrue);
      expect(latch.record(addedNew: false), isFalse);
    });

    test('a page with new items resets the dud count', () {
      final latch = MangaEndOfList();
      expect(latch.record(addedNew: false), isTrue);
      expect(latch.record(addedNew: true), isTrue);
      expect(latch.record(addedNew: false), isTrue);
      expect(latch.record(addedNew: false), isFalse);
    });

    test('reset re-arms after a refresh', () {
      final latch = MangaEndOfList();
      latch.record(addedNew: false);
      expect(latch.record(addedNew: false), isFalse);
      latch.reset();
      expect(latch.record(addedNew: false), isTrue);
    });
  });

  group('host reset heal predicate (batch 188)', () {
    final t0 = DateTime(2026, 11, 10, 12);

    test('never attempted -> allowed', () {
      expect(
        shouldAttemptHostReset(lastAttemptAt: null, now: t0),
        isTrue,
      );
    });

    test('inside the cooldown -> refused', () {
      expect(
        shouldAttemptHostReset(
          lastAttemptAt: t0,
          now: t0.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });

    test('after the cooldown -> allowed again', () {
      expect(
        shouldAttemptHostReset(
          lastAttemptAt: t0,
          now: t0.add(const Duration(minutes: 3)),
        ),
        isTrue,
      );
    });
  });

  group('mapJsComicList all-dropped page (batch 188)', () {
    test('a page whose entries all lack ids throws', () {
      expect(
        () => mapJsComicList([
          {'title': 'NoId', 'cover': 'ca'},
          {'id': ' ', 'title': 'Blank', 'cover': 'cb'},
        ], sourceId: 'js:x'),
        throwsStateError,
      );
    });

    test('a genuinely empty page still maps to empty', () {
      expect(mapJsComicList(const [], sourceId: 'js:x'), isEmpty);
      expect(
        mapJsComicList({'comics': const []}, sourceId: 'js:x'),
        isEmpty,
      );
    });
  });

  group('paged chain + wiring contracts (batch 188)', () {
    test('walks are serialized and mid-chain flakes throw', () {
      final scripts = File(
        'lib/services/manga/js/venera_scripts.dart',
      ).readAsStringSync();
      expect(scripts, contains('__anikumoPagedWalk'));
      expect(scripts, contains('__anikumoChainLocks'));
      expect(
        scripts,
        contains('paged load returned an empty page mid-chain'),
      );
    });

    test('unregister drops the source token chains', () {
      final engine = File(
        'lib/services/manga/js/venera_engine.dart',
      ).readAsStringSync();
      expect(engine, contains('ck.split(":")[1] === key'));
      expect(engine, contains('_tryHostResetHeal'));
    });

    test('both grids use the two-dud latch', () {
      for (final path in [
        'lib/pages/manga/manga_explore_page.dart',
        'lib/pages/manga/manga_categories_page.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('MangaEndOfList'), reason: path);
        expect(source, contains('_endOfList.record'), reason: path);
      }
    });

    test('reader loading state names the chapter', () {
      final reader = File(
        'lib/pages/manga/manga_reader_page.dart',
      ).readAsStringSync();
      final loadingAt = reader.indexOf('if (_loading) {');
      expect(loadingAt, greaterThanOrEqualTo(0));
      final window = reader.substring(loadingAt, loadingAt + 700);
      expect(window, contains('_chapter.title'));
    });
  });
}
