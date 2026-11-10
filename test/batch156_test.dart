// Batch 156 (user report): tapping season 1 or season 2
// in 关联 opened that subject with the WRONG default
// season — season 1's stills, and no season slicing for
// combined subjects. Cause: statedSeasonNumber only
// recognised 第N期/第N季 and "Season N". Bangumi titles
// also state seasons as "2nd Season" / "3rd season"
// (Re:ゼロ's actual subject names), 第Nシーズン, "S2",
// and trailing roman numerals; every unrecognised form
// fell back to season 1 downstream.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/tmdb/tmdb_episodes.dart';

void main() {
  group('statedSeasonNumber recognised forms (batch 156)', () {
    test('the original forms still work', () {
      expect(statedSeasonNumber('薬屋のひとりごと 第2期'), 2);
      expect(statedSeasonNumber('药屋少女的呢喃 第三季'), 3);
      expect(statedSeasonNumber('标题 第二季'), 2);
      expect(statedSeasonNumber('Some Show Season 2'), 2);
    });

    test('ordinal-before-Season (the Re:Zero shape)', () {
      expect(
        statedSeasonNumber('Re:ゼロから始める異世界生活 3rd season'),
        3,
      );
      expect(statedSeasonNumber('Some Show 2nd Season'), 2);
      expect(statedSeasonNumber('Some Show 1st Season'), 1);
    });

    test('katakana season word', () {
      expect(statedSeasonNumber('タイトル 第2シーズン'), 2);
    });

    test('standalone S token', () {
      expect(statedSeasonNumber('タイトル S2'), 2);
      expect(statedSeasonNumber('Some Show S3'), 3);
      expect(statedSeasonNumber('タイトルS2'), 2);
    });

    test('trailing roman numerals', () {
      expect(statedSeasonNumber('タイトル II'), 2);
      expect(statedSeasonNumber('Some Title III'), 3);
      expect(statedSeasonNumber('タイトル IV'), 4);
    });

    test('an explicit 第N form beats looser forms', () {
      expect(statedSeasonNumber('タイトル 第2期 S3'), 2);
    });
  });

  group('statedSeasonNumber stays quiet when unstated (batch 156)', () {
    test('plain titles have no season', () {
      expect(statedSeasonNumber('薬屋のひとりごと'), isNull);
      expect(statedSeasonNumber('Some Show'), isNull);
      expect(statedSeasonNumber('タイトル 2024'), isNull);
    });

    test('episode and product tokens are not seasons', () {
      expect(statedSeasonNumber('タイトル 第2話'), isNull);
      expect(statedSeasonNumber('PS2 the Animation'), isNull);
      expect(statedSeasonNumber('タイトル 第II話'), isNull);
    });
  });
}
