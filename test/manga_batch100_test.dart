import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/pages/manga/manga_main_page.dart';

// Batch 100: the home refresh gate. A pull-refresh used to
// fire every section's forced fetch at once and sites
// answered the burst with 403 while the same source
// refreshed fine alone. The gate must (a) cap how many
// loads run at once, (b) space successive starts by at
// least minGap, (c) serve every waiter eventually.
void main() {
  test('gate caps concurrency and spaces starts', () async {
    final gate = MangaHomeRefreshGate(
      maxConcurrent: 2,
      minGap: const Duration(milliseconds: 60),
    );
    var active = 0;
    var maxActive = 0;
    final starts = <DateTime>[];

    Future<void> task() async {
      await gate.acquire();
      starts.add(DateTime.now());
      active++;
      if (active > maxActive) maxActive = active;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      active--;
      gate.release();
    }

    await Future.wait([for (var i = 0; i < 5; i++) task()]);

    expect(maxActive, lessThanOrEqualTo(2));
    expect(starts, hasLength(5));
    final sorted = [...starts]..sort();
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].difference(sorted[i - 1]);
      // 60 ms configured; allow timer slack.
      expect(gap.inMilliseconds, greaterThanOrEqualTo(45),
          reason: 'starts $i-1..$i were only ${gap.inMilliseconds} ms apart');
    }
  });

  test('a released slot wakes the next waiter', () async {
    final gate = MangaHomeRefreshGate(
      maxConcurrent: 1,
      minGap: Duration.zero,
    );
    await gate.acquire();
    var secondRan = false;
    final second = () async {
      await gate.acquire();
      secondRan = true;
      gate.release();
    }();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(secondRan, isFalse);
    gate.release();
    await second;
    expect(secondRan, isTrue);
  });
}
