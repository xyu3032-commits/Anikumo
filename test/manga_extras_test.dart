// Batch 15: pure logic behind the manga extras.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/manga_extras.dart';
import 'package:anikumo/services/manga/manga_library.dart';

void main() {
  test('search history dedupes, prepends and caps', () {
    var history = addKeywordToHistory(const [], ' 海贼王 ');
    history = addKeywordToHistory(history, '火影');
    history = addKeywordToHistory(history, '海贼王');
    expect(history, ['海贼王', '火影']);
    var capped = List<String>.generate(25, (i) => 'k$i');
    capped = addKeywordToHistory(capped, 'new');
    expect(capped.length, 20);
    expect(capped.first, 'new');
  });

  test('updates only count growth past a known baseline', () {
    final updates = mangaUpdatesFor(
      {'a': 10, 'b': 5},
      {'a': 13, 'b': 5, 'c': 99},
    );
    expect(updates, {'a': 3});
  });

  test('pinned favorites float first, then the chosen order', () {
    const favorites = [
      MangaFavorite(id: '1', title: 'Beta', coverUrl: ''),
      MangaFavorite(id: '2', title: 'Alpha', coverUrl: ''),
      MangaFavorite(id: '3', title: 'Gamma', coverUrl: ''),
    ];
    final sorted = sortFavorites(
      favorites,
      pinned: {'mangadex:3'},
      progress: const {},
      ratings: const {},
      mode: MangaFavoriteSort.title,
    );
    expect([for (final f in sorted) f.title], ['Gamma', 'Alpha', 'Beta']);
  });

  test('reading stats aggregate by day and week', () {
    final stats = MangaReadingStats(
      secondsByDay: {
        MangaReadingStats.dayKey(DateTime(2026, 11, 6)): 600,
        MangaReadingStats.dayKey(DateTime(2026, 11, 1)): 300,
        MangaReadingStats.dayKey(DateTime(2026, 10, 1)): 999,
      },
    );
    expect(stats.secondsOn(DateTime(2026, 11, 6)), 600);
    expect(stats.secondsInLastWeek(DateTime(2026, 11, 6)), 900);
    final roundTrip = MangaReadingStats.fromJson(stats.toJson());
    expect(roundTrip.secondsByDay, stats.secondsByDay);
  });

  test('rating codec round-trips and drops empty keys', () {
    const rating = MangaRating(
      key: 'mangadex:1',
      stars: 4.5,
      note: '好看',
      updatedAtMs: 42,
    );
    final back = MangaRating.fromJson(rating.toJson());
    expect(back?.stars, 4.5);
    expect(back?.note, '好看');
    expect(MangaRating.fromJson(const {'key': ''}), isNull);
  });
}
