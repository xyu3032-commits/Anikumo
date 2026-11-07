// Batch 15: pure logic behind the twelve big features.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/ui/app_extras.dart';

void main() {
  test('scheduled dark window is 21:00-06:00', () {
    expect(isScheduledDark(DateTime(2026, 1, 1, 21)), isTrue);
    expect(isScheduledDark(DateTime(2026, 1, 1, 23, 59)), isTrue);
    expect(isScheduledDark(DateTime(2026, 1, 1, 0)), isTrue);
    expect(isScheduledDark(DateTime(2026, 1, 1, 5, 59)), isTrue);
    expect(isScheduledDark(DateTime(2026, 1, 1, 6)), isFalse);
    expect(isScheduledDark(DateTime(2026, 1, 1, 12)), isFalse);
    expect(isScheduledDark(DateTime(2026, 1, 1, 20, 59)), isFalse);
  });

  test('title filter matches case-insensitively, ignores blanks', () {
    expect(titleBlocked('某剧场版 动画', ['剧场版']), isTrue);
    expect(titleBlocked('My Hero', ['hero']), isTrue);
    expect(titleBlocked('普通标题', ['剧场版', '  ']), isFalse);
    expect(titleBlocked('普通标题', const []), isFalse);
  });

  test('PIN hashing is deterministic and pin-shaped', () {
    expect(PinLock.hashPin('1234'), PinLock.hashPin('1234'));
    expect(PinLock.hashPin('1234'), isNot(PinLock.hashPin('1235')));
    expect(PinLock.hashPin('1234').length, 64);
  });

  test('CSV builders escape commas and quotes', () {
    final csv = buildMangaHistoryCsv(const []);
    expect(csv.startsWith('type,title,chapter,page,time,source'), isTrue);
  });
}
