// Batch 12: manga search ranking / dedupe / info filtering.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/manga/manga_search_utils.dart';

MangaItem item(String id, String title, {String source = 'mangadex'}) {
  return MangaItem(
    id: id,
    title: title,
    description: '',
    coverUrl: '',
    author: '',
    status: '',
    year: null,
    tags: const [],
    source: source,
  );
}

void main() {
  test('normalization strips spaces and punctuation, lowercases', () {
    expect(normalizeMangaTitle('One Piece!'), 'onepiece');
    expect(normalizeMangaTitle('海贼王 '), '海贼王');
    expect(normalizeMangaTitle(' 咒术 回战（第2季）'), '咒术回战第2季');
  });

  test('ranking puts exact, then prefix, then contains first', () {
    final items = [
      item('1', '航海王外传'),
      item('2', '海贼王'),
      item('3', '我是海贼王'),
      item('4', '无关作品'),
    ];
    final ranked = rankMangaResults(items, '海贼王');
    expect(ranked.map((i) => i.id), ['2', '3', '1', '4']);
  });

  test('dedupe keys on source+id, keeping other sources copies', () {
    final items = [
      item('1', 'A'),
      item('1', 'A duplicate'),
      item('1', 'A elsewhere', source: 'zaimanhua'),
    ];
    final deduped = dedupeMangaItems(items);
    expect(deduped.length, 2);
    expect(deduped.first.title, 'A');
    expect(deduped.last.source, 'zaimanhua');
  });

  test('info check requires id and a non-blank title', () {
    expect(mangaHasInfo(item('1', 'A')), isTrue);
    expect(mangaHasInfo(item('', 'A')), isFalse);
    expect(mangaHasInfo(item('1', '  ')), isFalse);
  });
}
