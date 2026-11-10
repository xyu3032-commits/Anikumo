// Batch 163: the built-in danmaku service — token codec
// round-trip and the pure title/episode matching that
// replaces the credential flow's id conventions. Fixtures
// mirror the service's real response shapes (decorated
// titles, per-season entries, 第N集 episodes).
import 'package:flutter_test/flutter_test.dart';

import 'package:anikumo/modules/danmaku/danmaku_episode_response.dart';
import 'package:anikumo/modules/danmaku/danmaku_search_response.dart';
import 'package:anikumo/services/danmaku/builtin_danmu.dart';
import 'package:anikumo/services/danmaku/danmu_token.dart';

DanmakuSearchAnime _anime(int id, String title) => DanmakuSearchAnime(
animeId: id,
animeTitle: title,
typeDescription: '动画',
);

DanmakuEpisode _ep(int id, String title) =>
DanmakuEpisode(episodeId: id, episodeTitle: title);

void main() {
group('token codec (batch 163)', () {
test('round-trips and stays empty when unset', () {
expect(decodeDanmuToken(''), '');
expect(builtinDanmuToken, '');
expect(BuiltinDanmu.available, isFalse);
const sample = 'SampleToken-1234-abcd';
expect(decodeDanmuToken(encodeDanmuToken(sample)), sample);
expect(encodeDanmuToken(sample), isNot(contains(sample)));
});
});

group('title matching (batch 163)', () {
final results = [
_anime(59070, '药屋少女的呢喃 第三季(2026)【动画】from renren'),
_anime(51476, '药屋少女的呢喃 第二季(2025)【动画】from renren'),
_anime(45973, '药屋少女的呢喃(2023)【动画】from renren'),
];

test('normalizeTitle strips decorations', () {
expect(
BuiltinDanmu.normalizeTitle('药屋少女的呢喃 第三季(2026)【动画】from renren'),
BuiltinDanmu.normalizeTitle('药屋少女的呢喃 第三季'),
);
});

test('a plain first-season title lands on season 1, not 3', () {
expect(BuiltinDanmu.pickAnimeId(results, '药屋少女的呢喃'), 45973);
});

test('stated seasons pick their own entries', () {
expect(BuiltinDanmu.pickAnimeId(results, '药屋少女的呢喃 第二季'), 51476);
expect(BuiltinDanmu.pickAnimeId(results, '药屋少女的呢喃 第三季'), 59070);
});

test('unknown titles fall back to the first result; empty stays 0', () {
expect(BuiltinDanmu.pickAnimeId(results, '完全无关的作品'), 59070);
expect(BuiltinDanmu.pickAnimeId(const [], '药屋少女的呢喃'), 0);
});
});

group('episode matching (batch 163)', () {
final episodes = [
_ep(10002, ' 第01集'),
_ep(10003, ' 第02集'),
_ep(10004, ' 第03集'),
];

test('numbers parse out of decorated episode titles', () {
expect(BuiltinDanmu.episodeIdForNumber(episodes, 1), 10002);
expect(BuiltinDanmu.episodeIdForNumber(episodes, 3), 10004);
});

test('out of range is 0', () {
expect(BuiltinDanmu.episodeIdForNumber(episodes, 24), 0);
expect(BuiltinDanmu.episodeIdForNumber(episodes, 0), 0);
});
});
}
