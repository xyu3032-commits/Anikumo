import 'dart:async';
import 'dart:math' as math;

import 'package:liuguang_core/liuguang_core.dart';
import 'package:liuguang_network/liuguang_network.dart';

import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 204: a direct JSON interface source for the 影视
/// zone — the interface family the TVBox-ecosystem data
/// test (2026-11-11) verified as live: one base address
/// serving list/search/detail with category, year, area and
/// genre filters, and detail payloads carrying named play
/// lines of direct stream URLs. (Internal naming only; the
/// UI never names the interface family — see the standing
/// no-naming rule.)
///
/// Wire shape (all GET, JSON responses):
///   ?ac=list&wd=&t=&pg=&area=&year=&class=  → {code, page,
///     pagecount, total, list: [vod…], class: [type…]}
///   ?ac=detail&ids=VODID                  → {list: [vod…]}
/// A vod carries vod_play_from （线路名， '$$$'-separated)
/// and vod_play_url (same grouping; episodes '#'-separated,
/// each '名称$地址').

class CmsCategory {
  const CmsCategory({
    required this.id,
    required this.name,
    required this.parentId,
  });

  final int id;
  final String name;
  final int parentId;

  bool get isRoot => parentId == 0;
}

class CmsEpisode {
  const CmsEpisode({required this.name, required this.url});
  final String name;
  final String url;
}

class CmsPlayLine {
  const CmsPlayLine({required this.name, required this.episodes});
  final String name;
  final List<CmsEpisode> episodes;
}

/// Parses the vod_play_from / vod_play_url pair into lines
/// of episodes. Pure and total: malformed groups degrade to
/// fewer episodes instead of throwing.
List<CmsPlayLine> parseCmsPlayLines(String from, String url) {
  final names = from.split('\$\$\$');
  final groups = url.split('\$\$\$');
  final lines = <CmsPlayLine>[];
  for (var i = 0; i < groups.length; i++) {
    final episodes = <CmsEpisode>[];
    for (final part in groups[i].split('#')) {
      final token = part.trim();
      if (token.isEmpty) continue;
      final sep = token.indexOf('\$');
      if (sep < 0) {
        episodes.add(CmsEpisode(name: token, url: ''));
      } else {
        episodes.add(
          CmsEpisode(
            name: token.substring(0, sep).trim(),
            url: token.substring(sep + 1).trim(),
          ),
        );
      }
    }
    if (episodes.isEmpty) continue;
    final name = i < names.length && names[i].trim().isNotEmpty
        ? names[i].trim()
        : '线路${i + 1}';
    lines.add(CmsPlayLine(name: name, episodes: episodes));
  }
  return lines;
}

List<String> cmsSplitTokens(String raw) => raw
    .split(RegExp(r'[,，、/]'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

String cmsStripHtml(String raw) => raw
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The 电视剧/电影 kind of a category root name. Roots that
/// are inherently episodic （电视剧/综艺/动漫/纪录片/短剧…)
/// count as series.
MediaType? cmsKindForRootName(String name) {
  if (name.contains('电影')) return MediaType.movie;
  if (name.contains('电视') ||
      name.contains('连续剧') ||
      name.contains('剧集') ||
      name.contains('综艺') ||
      name.contains('动漫') ||
      name.contains('纪录') ||
      name.contains('短剧') ||
      name.contains('少儿') ||
      name.contains('剧')) {
    return MediaType.series;
  }
  return null;
}

/// Batch 213: kind from the vod's own (leaf) category name,
/// for stations whose payloads never carry the category
/// tree — without this, their series fell through to the
/// movie default and showed up under 电影.
MediaType? cmsKindForLeafName(String typeName) {
  const seriesMarkers = [
    '电视剧',
    '连续剧',
    '剧集',
    '综艺',
    '真人秀',
    '动漫',
    '纪录',
    '短剧',
    '国产剧',
    '欧美剧',
    '日韩剧',
    '港剧',
    '台剧',
    '泰剧',
    '美剧',
    '韩剧',
    '日剧',
    '英剧',
  ];
  for (final marker in seriesMarkers) {
    if (typeName.contains(marker)) return MediaType.series;
  }
  if (typeName.contains('电影') || typeName.endsWith('片')) {
    return MediaType.movie;
  }
  return null;
}

/// Batch 213: 综艺 (variety) marker — a root or leaf
/// category name mentioning variety / reality shows.
bool cmsIsVarietyName(String name) =>
    name.contains('综艺') || name.contains('真人秀');

/// Whether a mapped item is a variety show (Batch 213) —
/// the marker _mapVod stamps into raw.
bool cmsItemIsVariety(MediaItem item) => item.raw['variety'] == true;

/// Batch 226: live-channel marker — a root or leaf category
/// name mentioning live streaming. Live channels are their
/// own shelf; they must never leak into 电影 / 电视剧 / 综艺
/// (their leaf names resolve to the movie default and
/// polluted the movie shelf).
bool cmsIsLiveName(String name) => name.contains('直播');

/// Whether a mapped item is a live channel (Batch 226).
bool cmsItemIsLive(MediaItem item) => item.raw['live'] == true;

/// Batch 228: anime marker — a root or leaf category name
/// mentioning animation, or the item's own genre tokens.
/// Anime series get their own shelf instead of hiding
/// inside 真人电视剧.
bool cmsIsAnimeName(String name) =>
    name.contains('动漫') || name.contains('动画') || name.contains('番剧');

/// Whether a mapped item is an anime series (Batch 228).
/// Batch 241: 漫剧 never counts as anime — stations file
/// manju under 动漫 chains, and the user wants them on
/// their own shelf, not inside 动漫.
bool cmsItemIsAnime(MediaItem item) =>
    !cmsItemIsManju(item) &&
    (item.raw['anime'] == true ||
        item.genres.any((g) => g.name == '动漫' || g.name == '动画'));

/// Batch 241: short-drama marker — a category name about
/// short / vertical dramas. Short dramas are their own
/// shelf now instead of dissolving into 电视剧.
bool cmsIsShortDramaName(String name) =>
    name.contains('短剧') || name.contains('竖屏剧');

/// Whether a mapped item is a short drama (Batch 241) —
/// the category-chain marker, or the item's own genre
/// tokens saying so.
bool cmsItemIsShortDrama(MediaItem item) =>
    item.raw['shortDrama'] == true ||
    item.genres.any((g) => g.name.contains('短剧'));

/// Batch 256: whether a name/token carries the word
/// 漫剧 as itself — 动漫剧 (anime drama, as in 动漫剧场)
/// contains the characters 漫+剧 without being manju,
/// and used to stamp ordinary anime as 漫剧. Stripping
/// 动漫 first keeps 动漫漫剧 (a chain naming both) a hit
/// while 动漫剧场 falls out.
bool cmsHasManjuWord(String name) => name.replaceAll('动漫', '').contains('漫剧');

/// Batch 241: manju (漫剧, AI comic-drama) marker — a
/// category name mentioning 漫剧. Stations file these
/// under 动漫； they get their own shelf.
bool cmsIsManjuName(String name) => cmsHasManjuWord(name);

/// Whether a mapped item is a manju (Batch 241) — the
/// category-chain marker, or the item's own genre tokens.
bool cmsItemIsManju(MediaItem item) =>
    item.raw['manju'] == true ||
    item.genres.any((g) => cmsHasManjuWord(g.name));

/// Batch 236: sports marker — a category name about
/// sports / matches. Sports rows (NBA games and the like)
/// used to fall into the movie default and pollute 电影 —
/// the same leak 直播 had before Batch 226.
bool cmsIsSportsName(String name) =>
    name.contains('体育') ||
    name.contains('赛事') ||
    name.contains('足球') ||
    name.contains('篮球') ||
    name.toUpperCase().contains('NBA');

/// Whether a mapped item is a sports programme
/// (Batch 236) — the category-chain marker, or the
/// item's own genre tokens saying so.
bool cmsItemIsSports(MediaItem item) =>
    item.raw['sports'] == true ||
    item.genres.any((g) => g.name.contains('体育') || g.name.contains('赛事'));

/// Batch 214: a title's base form for cross-source
/// matching — season / variant suffixes stripped, so the
/// same work named 星河公寓第二季 here and 星河公寓 第2季
/// there still compares equal.
String cmsBaseTitle(String title) {
  var t = title.trim();
  t = t.replaceAll(RegExp(r'[（(【\[][^）)】\]]*[）)】\]]'), ' ');
  t = t.replaceAll(
    RegExp(
      r'(第\s*[0-9一二三四五六七八九十]+\s*[季部]|season\s*\d+|s\d{1,2})\s*$',
      caseSensitive: false,
    ),
    '',
  );
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Batch 214: whether two catalogue items from different
/// sources are the same work — exact normalized title, or
/// the same base title with agreeing years. Used by the
/// detail page's 切换接口 (source switcher).
bool cmsSameWork(MediaItem a, MediaItem b) {
  String norm(String t) =>
      t.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (norm(a.title) == norm(b.title)) return true;
  if (cmsBaseTitle(a.title) != cmsBaseTitle(b.title)) return false;
  return a.year == null || b.year == null || a.year == b.year;
}

/// Batch 230: whether a catalogue item is the TMDB work
/// described by [title] / [year] / [isSeries] — the
/// cmsSameWork rules (exact normalized title, or the same
/// base title with agreeing years) plus a media-kind
/// agreement. Live channels never match. Used by the
/// search page's TMDB mode to find playable versions.
bool cmsMatchesTmdbWork(
  MediaItem item, {
  required String title,
  required int? year,
  required bool isSeries,
}) {
  if (cmsItemIsLive(item)) return false;
  if ((item.mediaType == MediaType.series) != isSeries) return false;
  String norm(String t) =>
      t.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final titleAgrees = year == null || item.year == null || item.year == year;
  if (norm(item.title) == norm(title)) return titleAgrees;
  if (cmsBaseTitle(item.title) != cmsBaseTitle(title)) return false;
  return titleAgrees;
}

/// Batch 216/256: client-side browse filters. Verified
/// live: major stations silently IGNORE the genre
/// (class) list parameter — identical totals and items
/// for any value — while area is honored by some and
/// ignored by others. The item's own metadata is
/// therefore the only reliable filter. Batch 256: an
/// item carrying NO value for a dimension no longer
/// matches a named value — the batch-216 leniency put
/// untagged works on every genre/area/year rail (a
/// work with no 喜剧 anywhere sat in the 喜剧 rail).
/// That leniency is safe to drop now: browse enriches
/// list rows from detail data (batch 225/236) BEFORE
/// filtering, so a still-empty dimension is genuinely
/// untagged — and untagged is what 其他 collects.
bool cmsMatchesGenre(MediaItem item, String genre) {
  if (item.genres.isEmpty) return false;
  final wanted = cmsGenreKey(genre);
  return item.genres.any((g) => cmsGenreTokenKeys(g.name).contains(wanted));
}

/// The FIXED genre taxonomy (user's standing rule,
/// re-affirmed batch 259 after batch 255's interface-
/// harvested vocabulary was overturned on device): the
/// discover chips and home rails are exactly this list
/// plus 其他. Interface class words, TMDB genres and
/// Bangumi tags only ever MAP a work onto this table
/// (via cmsGenreKey / cmsGenreTokenKeys folding); a
/// work whose words fold to nothing here belongs to
/// 其他. The table doubles as the suffix-stripping
/// lexicon for cmsGenreKey.
const List<String> kFilmGenres = [
  '爱情', '喜剧', '动作', '科幻', '悬疑', '剧情', '惊悚', '恐怖',
  '犯罪', '战争', '古装', '武侠', '家庭', '动画',
  '冒险', '奇幻', '历史', '音乐', '纪录', '电视电影', '西部',
  '动作冒险', '儿童', '真人秀', '肥皂剧', '脱口秀', '新闻',
  '都市', '言情', '校园', '青春', '年代', '军事', '谍战', '职场',
  '仙侠', '玄幻', '穿越', '甜宠',
  // Batch 247: more station staples the first table
  // missed — works tagged only with these used to fall
  // into 其他 despite having a real genre.
  '灾难', '伦理', '歌舞', '体育', '宫廷', '民国', '励志', '传记',
];

/// The FIXED area taxonomy, same doctrine as
/// [kFilmGenres]: discover chips are this list plus
/// 其他； interface area words map onto it through
/// cmsMatchesArea's alias folding （内地/大陆 → 中国）,
/// and a work matching none of them belongs to 其他.
const List<String> kFilmAreas = [
  '中国',
  '香港',
  '台湾',
  '美国',
  '日本',
  '韩国',
  '英国',
  '法国',
  '德国',
  '意大利',
  '西班牙',
  '俄罗斯',
  '泰国',
  '印度',
  '加拿大',
  '澳大利亚',
  '新加坡',
  '马来西亚',
];

/// Batch 243: genre labels that arrive without a Chinese
/// name (TMDB's untranslated pair, plus its English names
/// in 海外 mode) map onto their Chinese counterpart —
/// the user asked for automatic correspondence rather
/// than English chips or dropped tags.
const Map<String, String> kGenreAliasMap = {
  'Sci-Fi & Fantasy': '科幻',
  'War & Politics': '战争',
  'Science Fiction': '科幻',
  'Action & Adventure': '动作冒险',
  'Action': '动作',
  'Adventure': '冒险',
  'Animation': '动画',
  'Comedy': '喜剧',
  'Crime': '犯罪',
  'Documentary': '纪录',
  'Drama': '剧情',
  'Family': '家庭',
  'Fantasy': '奇幻',
  'History': '历史',
  'Horror': '恐怖',
  'Music': '音乐',
  'Mystery': '悬疑',
  'News': '新闻',
  'Reality': '真人秀',
  'Romance': '爱情',
  'Soap': '肥皂剧',
  'Talk': '脱口秀',
  'TV Movie': '电视电影',
  'Thriller': '惊悚',
  'War': '战争',
  'Western': '西部',
  'Kids': '儿童',
};

/// Batch 243: a genre token with aliases folded in.
String cmsNormalizeGenre(String name) {
  final trimmed = name.trim();
  return kGenreAliasMap[trimmed] ?? trimmed;
}

/// Batch 247: traditional characters that show up in
/// genre/area vocabulary from 繁体 sources — folded to
/// simplified before any comparison or display.
const Map<String, String> kTraditionalGenreChars = {
  '劇': '剧',
  '愛': '爱',
  '倫': '伦',
  '戰': '战',
  '歷': '历',
  '醫': '医',
  '諜': '谍',
  '職': '职',
  '園': '园',
  '記': '记',
  '俠': '侠',
  '偵': '侦',
  '驚': '惊',
  '靈': '灵',
  '喪': '丧',
  '屍': '尸',
  '國': '国',
  '產': '产',
  '灣': '湾',
  '臺': '台',
  '韓': '韩',
  '歐': '欧',
  '陸': '陆',
  '時': '时',
  '間': '间',
  '點': '点',
  '盜': '盗',
  '義': '义',
  '陰': '阴',
  '謀': '谋',
  '獄': '狱',
  '幫': '帮',
  '團': '团',
};

String cmsFoldTraditional(String input) {
  var out = input;
  kTraditionalGenreChars.forEach((from, to) {
    out = out.replaceAll(from, to);
  });
  return out;
}

/// Batch 247: station synonyms that are the same genre
/// wearing another name — folded onto the table entry.
const Map<String, String> kGenreSynonymFold = {
  '搞笑': '喜剧',
  '幽默': '喜剧',
  '推理': '悬疑',
  '刑侦': '犯罪',
  '警匪': '犯罪',
  '黑帮': '犯罪',
  '灵异': '恐怖',
  '僵尸': '恐怖',
  '丧尸': '恐怖',
  '抗战': '战争',
  '动漫': '动画',
  '小说改': '小说改编',
  '小说改编': '小说改编',
};

/// Batch 247: the one genre key every comparison and
/// dedupe goes through. Real-world class words arrive
/// as 剧情片 / 古装剧 / 劇情 / 搞笑 / Sci-Fi — the key
/// folds traditional characters, drops inner spaces,
/// translates English (tmdbDisplayTerm), strips one
/// medium suffix （片/剧） when the stem is a known
/// genre, and folds station synonyms. Fixes the device
/// reports behind this batch: tagged works landing in
/// 其他 (their tokens never equalled a table entry) and
/// merged chips showing 剧情 next to 剧情片.
String cmsGenreKey(String raw) {
  var s = cmsFoldTraditional(raw).trim();
  // English aliases contain spaces ('Sci-Fi & Fantasy')
  // — translate before any space is stripped.
  s = tmdbDisplayTerm(s);
  s = s.replaceAll(RegExp(r'[\s·、,，/|]+'), '');
  if (s.isEmpty) return s;
  for (final suffix in const ['片', '剧']) {
    if (s.length > suffix.length && s.endsWith(suffix)) {
      final stem = s.substring(0, s.length - suffix.length);
      final stemKey = kGenreSynonymFold[stem] ?? stem;
      if (kFilmGenres.contains(stemKey) ||
          kGenreSynonymFold.containsKey(stem)) {
        s = stemKey;
        break;
      }
    }
  }
  return kGenreSynonymFold[s] ?? s;
}

/// Batch 247: the canonical display form of a genre or
/// tag — its key when the key is a table genre or a
/// folded synonym target, the folded original otherwise
/// （沪语 stays 沪语， 剧情片 becomes 剧情）.
String cmsGenreDisplay(String raw) {
  final key = cmsGenreKey(raw);
  if (kFilmGenres.contains(key) || kGenreSynonymFold.values.contains(key)) {
    return key;
  }
  return cmsFoldTraditional(raw).trim();
}

/// Batch 247: every genre key one class token carries —
/// its own key plus any table genre it contains, so a
/// compound token like 都市爱情 counts for both 都市 and
/// 爱情 instead of for nothing.
Set<String> cmsGenreTokenKeys(String token) {
  final key = cmsGenreKey(token);
  final out = <String>{if (key.isNotEmpty) key};
  final folded = cmsFoldTraditional(token);
  for (final genre in kFilmGenres) {
    if (genre.length >= 2 && folded.contains(genre)) out.add(genre);
  }
  return out;
}

/// Batch 247: an item's full tag-key set — every genre
/// token's keys plus any extra raw terms (enrichment
/// tags), keyed the same way.
Set<String> cmsItemTagKeys(
  MediaItem item, {
  Iterable<String> extra = const [],
}) {
  final out = <String>{};
  for (final g in item.genres) {
    out.addAll(cmsGenreTokenKeys(g.name));
  }
  for (final term in extra) {
    final key = cmsGenreKey(term);
    if (key.isNotEmpty) out.add(key);
  }
  return out;
}

/// Batch 247: the tag a search keyword names, when it
/// names one — the keyword's genre key, if that key is a
/// table genre （剧情片 → 剧情）. Search offers a
/// browse-by-tag entry for these.
String? filmTagForKeyword(String keyword) {
  final key = cmsGenreKey(keyword);
  return kFilmGenres.contains(key) ? key : null;
}

/// Batch 247: 猜你喜欢 ranking — candidates sharing more
/// of the base work's tag keys rank first (rating breaks
/// ties). The base work itself and same-title re-issues
/// are excluded; a candidate must share at least one key.
List<MediaItem> rankFilmRecommendations({
  required MediaItem base,
  required Set<String> baseKeys,
  required List<MediaItem> candidates,
  int cap = 12,
}) {
  final baseTitle = cmsBaseTitle(base.title);
  final scored = <({MediaItem item, int score})>[];
  final seenIds = <String>{};
  for (final candidate in candidates) {
    if (candidate.id == base.id) continue;
    if (cmsBaseTitle(candidate.title) == baseTitle &&
        candidate.year == base.year) {
      continue;
    }
    if (!seenIds.add(candidate.id)) continue;
    final keys = cmsItemTagKeys(candidate);
    final score = keys.intersection(baseKeys).length;
    if (score == 0) continue;
    scored.add((item: candidate, score: score));
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byRating = b.item.rating.score.compareTo(a.item.rating.score);
    if (byRating != 0) return byRating;
    return a.item.title.compareTo(b.item.title);
  });
  return [for (final s in scored.take(cap)) s.item];
}

/// Batch 246: translations for TMDB keyword tags — the
/// open-ended vocabulary TMDB attaches to a work
/// (lowercase English phrases). Genres are a closed set
/// and [kGenreAliasMap] already covers every official
/// name; keywords cannot be enumerated, so this table
/// carries the common ones and anything unlisted keeps
/// its original wording rather than inventing a gloss.
const Map<String, String> kTmdbKeywordTranslations = {
  'superhero': '超级英雄',
  'based on novel': '小说改编',
  'based on true story': '真实事件改编',
  'revenge': '复仇',
  'time travel': '时间穿越',
  'space': '太空',
  'alien': '外星人',
  'aliens': '外星人',
  'robot': '机器人',
  'artificial intelligence': '人工智能',
  'zombie': '丧尸',
  'vampire': '吸血鬼',
  'werewolf': '狼人',
  'ghost': '幽灵',
  'magic': '魔法',
  'wizard': '巫师',
  'martial arts': '武术',
  'kung fu': '功夫',
  'love': '爱情',
  'friendship': '友情',
  'school': '校园',
  'high school': '高中校园',
  'detective': '侦探',
  'murder': '谋杀',
  'serial killer': '连环杀手',
  'heist': '劫案',
  'survival': '生存',
  'dystopia': '反乌托邦',
  'post-apocalyptic': '末日',
  'apocalypse': '末日',
  'cyberpunk': '赛博朋克',
  'steampunk': '蒸汽朋克',
  'spy': '间谍',
  'mafia': '黑帮',
  'gangster': '黑帮',
  'prison': '监狱',
  'courtroom': '法庭',
  'hospital': '医院',
  'police': '警察',
  'soldier': '军人',
  'samurai': '武士',
  'ninja': '忍者',
  'pirate': '海盗',
  'dragon': '龙',
  'demon': '恶魔',
  'angel': '天使',
  'mythology': '神话',
  'reincarnation': '转生',
  'parallel universe': '平行世界',
  'virtual reality': '虚拟现实',
  'video game': '游戏',
  'dance': '舞蹈',
  'football': '足球',
  'basketball': '篮球',
  'racing': '赛车',
  'cooking': '美食',
  'wedding': '婚礼',
  'amnesia': '失忆',
  'kidnapping': '绑架',
  'conspiracy': '阴谋',
  'coming of age': '成长',
  'bullying': '霸凌',
  'hacker': '黑客',
  'clone': '克隆',
  'virus': '病毒',
  'disaster': '灾难',
  'earthquake': '地震',
  'future': '未来',
  'ancient china': '古代中国',
  'world war ii': '二战',
  'cold war': '冷战',
  'forbidden love': '禁忌之恋',
  'love triangle': '三角恋',
  'arranged marriage': '包办婚姻',
  'royalty': '王室',
  'emperor': '皇帝',
  'palace': '宫廷',
  'investigation': '调查',
  'undercover': '卧底',
  'hostage': '人质',
  'escape': '逃亡',
  'journey': '旅程',
};

/// Batch 246: how a TMDB genre or keyword reads on
/// screen — the translation tables first (the genre
/// table is complete for TMDB's closed genre set, in
/// either casing), the original wording otherwise.
String tmdbDisplayTerm(String term) {
  final trimmed = term.trim();
  if (trimmed.isEmpty) return trimmed;
  final genre = kGenreAliasMap[trimmed];
  if (genre != null) return genre;
  final lower = trimmed.toLowerCase();
  for (final entry in kGenreAliasMap.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return kTmdbKeywordTranslations[lower] ?? trimmed;
}

/// Batch 243/255: the discover filter's genre
/// semantics — a named genre matches as before; 其他 is
/// the bucket for works the interface gave NO genre at
/// all. (Batch 255: every word an interface actually
/// uses gets its own chip, so "outside a fixed table"
/// no longer means 其他.)
bool cmsMatchesGenreFilter(MediaItem item, String genre) {
  if (genre != '其他') return cmsMatchesGenre(item, genre);
  // Batch 259 (fixed taxonomy): 其他 collects works
  // whose class words fold to NO fixed genre — whether
  // the interface gave an unmappable word （土耳其 /
  // 皮影戏） or nothing at all.
  return !item.genres.any(
    (g) => cmsGenreTokenKeys(g.name).any(kFilmGenres.contains),
  );
}

/// Batch 255: the genre vocabulary of a set of items —
/// the interface's own genre words (display-folded via
/// [cmsGenreDisplay]), most frequent first. This, not
/// any fixed table, is what the discover chips and the
/// home rails are built from.
/// Batch 255/259: one catalogue country name folded
/// onto the fixed area taxonomy — （显示名， 接口值）.
/// Mainland aliases （内地 / 中国大陆 / 大陆 / 国产 /
/// 华语） fold onto the one chip 中国 with the
/// interface value 内地; everything else keeps its
/// own word for both.
(String, String) cmsAreaChip(String rawName) {
  final name = cmsFoldTraditional(rawName).trim();
  if (name.isEmpty) return ('', '');
  if (cmsAreaAliases('内地').contains(name) || name == '国产' || name == '华语') {
    return ('中国', '内地');
  }
  return (name, name);
}

/// The home shelf's rail specs for one
/// channel, derived from a sample of the winning
/// interface's own catalogue for that channel: its top
/// genre words as genre rails, its top areas as area
/// rails, and the current-year rail last. A channel
/// whose interface carries no genre/area words at all
/// honestly gets just the year rail.
/// Batch 259: rails come from the FIXED tables only,
/// ranked by how many sampled works map onto each
/// entry (batch 255's interface-word rails overturned
/// with the vocabulary). Zero-hit entries get no rail.
List<(String, String?, String?, int?)> filmRailSpecsFor(
  List<MediaItem> sample, {
  required int year,
}) {
  List<String> ranked(
    List<String> table,
    bool Function(MediaItem, String) hit,
  ) {
    final scored =
        [
          for (var i = 0; i < table.length; i++)
            (table[i], sample.where((item) => hit(item, table[i])).length, i),
        ]..sort((a, b) {
          final byHits = b.$2.compareTo(a.$2);
          return byHits != 0 ? byHits : a.$3.compareTo(b.$3);
        });
    return [
      for (final s in scored)
        if (s.$2 > 0) s.$1,
    ];
  }

  return [
    for (final g in ranked(kFilmGenres, cmsMatchesGenre).take(8))
      (g, g, null, null),
    for (final a in ranked(kFilmAreas, cmsMatchesArea).take(4))
      (a, null, a, null),
    ('$year 新作', null, null, year),
  ];
}

/// Batch 243/255/259: the discover filter's area
/// semantics — a named area matches as before; 其他
/// collects works whose countries map to NO fixed
/// area （土耳其 / 巴西）, or that carry no country.
bool cmsMatchesAreaFilter(MediaItem item, String area) {
  if (area != '其他') return cmsMatchesArea(item, area);
  return !kFilmAreas.any((a) => cmsMatchesArea(item, a));
}

/// Area aliases: the UI asks for 内地， catalogues answer
/// 中国 / 中国大陆 / 大陆 for the same place.
Set<String> cmsAreaAliases(String area) => switch (area) {
  '内地' || '中国' => {'内地', '中国', '中国大陆', '大陆', '中国内地'},
  _ => {area},
};

bool cmsMatchesArea(MediaItem item, String area) {
  // Batch 256: no country = no named-area match （其他
  // collects it), same rule as genres.
  if (item.countries.isEmpty) return false;
  final wanted = cmsAreaAliases(area);
  return item.countries.any(
    // Batch 259: the item's country folds through
    // cmsAreaChip too — a station answering 国产 means
    // the fixed 中国， same as 内地 / 中国大陆.
    (c) =>
        wanted.contains(c.name) ||
        wanted.contains(cmsAreaChip(c.name).$1) ||
        c.name.contains(area),
  );
}

/// Batch 256: an unknown year is not this year's work.
bool cmsMatchesYear(MediaItem item, int year) => item.year == year;

/// Batch 213: series evidence in the remarks text
/// （更新至第N集 / 全N集 / 连载中）, the only episodic signal
/// slim list payloads still carry.
/// Batch 241: 全集 / 完结 count too — a finished short
/// drama whose row says nothing but 全集 used to fall
/// through to the movie default and wear the 电影 label.
bool cmsRemarksImplySeries(String remarks) {
  if (remarks.contains('连载')) return true;
  if (remarks.contains('全集')) return true;
  if (remarks.contains('完结')) return true;
  final match = RegExp(r'(\d+)\s*集').firstMatch(remarks);
  if (match != null && (int.tryParse(match.group(1)!) ?? 0) > 1) {
    return true;
  }
  return false;
}

class _ListResult {
  const _ListResult({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalResults,
  });
  final List<MediaItem> items;
  final int page;
  final int totalPages;
  final int totalResults;
}

class _BrowseStream {
  final List<MediaItem> buffer = [];
  final Set<String> seenIds = {};
  int nextRawPage = 1;
  bool exhausted = false;
}

/// Batch 210: cleans a browse result list for display.
///
/// Two kinds of duplicates show up in these catalogues:
///   * the same record (same media id) served twice —
///     paging overlap or a filter stream re-reading a page;
///   * "stub twins": the same work collected twice under
///     different ids, one record complete (poster, score,
///     synopsis) and one a bare stub with no poster at all —
///     the user sees two identical cards, one of which "has
///     no info". Only the poster-less twin is dropped, and
///     only when a poster-bearing record with the same
///     title AND year exists; two complete records (genuine
///     alternate versions) are both kept.
List<MediaItem> dedupeBrowseItems(List<MediaItem> items) {
  final byId = <String, MediaItem>{};
  for (final item in items) {
    byId.putIfAbsent(item.id, () => item);
  }
  final unique = byId.values.toList();
  final withPoster = <String>{};
  for (final item in unique) {
    if ((item.artwork.poster ?? '').isNotEmpty) {
      withPoster.add('${item.title.trim()}|${item.year}');
    }
  }
  if (withPoster.isEmpty) return unique;
  return unique.where((item) {
    if ((item.artwork.poster ?? '').isNotEmpty) return true;
    return !withPoster.contains('${item.title.trim()}|${item.year}');
  }).toList();
}

/// Batch 238: merges browse pages from several sources
/// into one de-duplicated grid for the discover page's
/// 全部接口 mode. [lists] arrive in priority order
/// (fastest measured source first); the same work —
/// same kind, same title, same year — appears once, won
/// by the highest-priority copy. A winner without a
/// poster borrows the first duplicate's poster, so a
/// card never stays blank while another source has the
/// art. Different years or kinds are different works and
/// are all kept.
List<MediaItem> mergeFilmBrowseItems(List<List<MediaItem>> lists) {
  final order = <String>[];
  final byKey = <String, MediaItem>{};
  String keyOf(MediaItem item) =>
      '${item.mediaType.name}|${item.title.trim()}|${item.year ?? ''}';
  for (final list in lists) {
    for (final item in list) {
      final key = keyOf(item);
      final winner = byKey[key];
      if (winner == null) {
        byKey[key] = item;
        order.add(key);
        continue;
      }
      if ((winner.artwork.poster ?? '').isEmpty &&
          (item.artwork.poster ?? '').isNotEmpty) {
        byKey[key] = _graftArtwork(winner, item.artwork);
      }
    }
  }
  return [for (final key in order) byKey[key]!];
}

MediaItem _graftArtwork(MediaItem item, Artwork artwork) {
  return switch (item) {
    TVSeries s => TVSeries(
      id: s.id,
      title: s.title,
      year: s.year,
      overview: s.overview,
      genres: s.genres,
      countries: s.countries,
      people: s.people,
      rating: s.rating,
      artwork: artwork,
      sourceId: s.sourceId,
      raw: s.raw,
      seasons: s.seasons,
      status: s.status,
      totalEpisodes: s.totalEpisodes,
    ),
    Movie m => m.copyWith(artwork: artwork),
    _ => item,
  };
}

class _DetailCache {
  const _DetailCache(this.at, this.vod, this.lines);
  final DateTime at;
  final Map<String, dynamic> vod;
  final List<CmsPlayLine> lines;
}

/// Batch 225: the filterable metadata of one vod, harvested
/// from its detail record.
class _MetaBackfill {
  const _MetaBackfill({
    required this.genres,
    required this.area,
    required this.year,
    required this.poster,
    this.episodic = false,
    this.totalEpisodes = 0,
  });
  final List<String> genres;
  final String area;
  final int? year;
  final String poster;

  /// Batch 231: the detail record's play structure proves
  /// a series the list row was filed as a movie.
  final bool episodic;
  final int totalEpisodes;
}

class CmsApiSource implements MediaSourceProvider {
  CmsApiSource(this.entry, {LiuGuangHttpClient? client})
    : _client = client ?? LiuGuangHttpClient();

  final VideoSourceEntry entry;
  final LiuGuangHttpClient _client;

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      'Chrome/120.0 Mobile Safari/537.36';

  List<CmsCategory>? _categories;
  final Map<int, _DetailCache> _detailCache = {};
  final Map<String, _BrowseStream> _streams = {};

  /// Batch 225: metadata backfill cache (vod id → genres /
  /// area / year / poster taken from the detail payload).
  /// Slim stations ship list rows with vod_class, vod_area
  /// and vod_year all absent; the genre / area / year
  /// filters then know nothing, keep everything, and every
  /// home rail collapses into the same unfiltered list
  /// (only the first rail — 爱情 — survived de-duplication
  /// on a real device). One batched detail call per list
  /// page fills the gaps; the cache is shared by every
  /// browse stream of this source.
  final Map<int, _MetaBackfill> _metaCache = {};

  /// Batch 217: caps for the browse-stream bookkeeping
  /// (see the fill loop in browse()).
  static const _maxStreams = 16;
  static const _maxScanPagesPerFill = 8;

  @override
  SourceDescriptor get descriptor =>
      SourceDescriptor(id: entry.id, name: entry.name, homepage: entry.api);

  String get _prefix => '${entry.id}::';

  String mediaIdFor(int vodId) => '$_prefix$vodId';

  int? vodIdOf(String mediaId) {
    if (!mediaId.startsWith(_prefix)) return null;
    return int.tryParse(mediaId.substring(_prefix.length));
  }

  Uri _uri(Map<String, String> params) {
    final base = entry.api;
    final sep = base.contains('?') ? '&' : '?';
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return Uri.parse('$base$sep$query');
  }

  Future<Map<String, dynamic>> _getJson(Map<String, String> params) async {
    final decoded = await _client.getJson(
      _uri(params).toString(),
      headers: const {'User-Agent': _ua},
    );
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      _harvestCategories(map);
      return map;
    }
    throw const FormatException('interface returned a non-JSON payload');
  }

  void _harvestCategories(Map<String, dynamic> payload) {
    final raw = payload['class'];
    if (raw is List && raw.isNotEmpty) {
      _categories = raw
          .whereType<Map>()
          .map(
            (e) => CmsCategory(
              id: _asInt(e['type_id']),
              name: e['type_name']?.toString() ?? '',
              parentId: _asInt(e['type_pid']),
            ),
          )
          .where((c) => c.id > 0 && c.name.isNotEmpty)
          .toList();
    }
  }

  static int _asInt(Object? v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  /// Drops the browse-stream buffers and the detail cache
  /// (pull-to-refresh). The category tree is kept.
  void invalidateBrowseCache() {
    _streams.clear();
    _detailCache.clear();
  }

  /// The category tree (flat list; roots have parentId 0).
  /// Fetched lazily from any list response and cached.
  Future<List<CmsCategory>> categories() async {
    if (_categories != null) return _categories!;
    await _listPage(page: 1);
    return _categories ?? const [];
  }

  /// The root category name for a vod, when the tree is
  /// known ('' otherwise).
  String _rootNameOf(Map<String, dynamic> vod) {
    final names = _ancestorNames(vod);
    return names.isEmpty ? '' : names.last;
  }

  /// Batch 231: every category name on the vod's chain,
  /// leaf first, root last — the marker checks used to
  /// look at the leaf and the root only, so a 直播 sitting
  /// in the middle of the chain (频道 → 直播 → CCTV-1)
  /// never marked its channels as live.
  List<String> _ancestorNames(Map<String, dynamic> vod) {
    final typeId = _asInt(vod['type_id']);
    final cats = _categories;
    if (cats == null || typeId <= 0) return const [];
    final byId = {for (final c in cats) c.id: c};
    final names = <String>[];
    var node = byId[typeId];
    var guard = 0;
    while (node != null && guard++ < 8) {
      names.add(node.name);
      if (node.isRoot) break;
      node = byId[node.parentId];
    }
    return names;
  }

  /// Batch 231: hard episodic structure in a vod payload —
  /// a play line holding more than one episode, or a
  /// stated episode total above one. This outranks the
  /// filing labels: a full season filed under a 电影 leaf
  /// is still a series. Remarks are softer evidence (a
  /// movie row can carry 更新至第3集 by station sloppiness)
  /// and only decide when the names say nothing.
  bool _vodHasEpisodicStructure(Map<String, dynamic> vod) {
    final lines = parseCmsPlayLines(
      vod['vod_play_from']?.toString() ?? '',
      vod['vod_play_url']?.toString() ?? '',
    );
    if (lines.any((l) => l.episodes.length > 1)) return true;
    return _asInt(vod['vod_total']) > 1 || _asInt(vod['vod_serial']) > 1;
  }

  MediaType? _kindOf(Map<String, dynamic> vod) {
    // Batch 231: hard episodic structure outranks the
    // filing labels — stations file whole seasons under
    // 电影 leaves, and the old name-first order never
    // reached the shape checks for them. Remarks sit
    // below the names (they lie on movie rows too).
    if (_vodHasEpisodicStructure(vod)) return MediaType.series;
    final rootName = _rootNameOf(vod);
    if (rootName.isNotEmpty) {
      final kind = cmsKindForRootName(rootName);
      if (kind != null) return kind;
    }
    // Batch 213: the leaf category name speaks for itself
    // when the tree is missing or its root is ambiguous
    // (a bare 影视 root says nothing; 国产剧/动作片 do).
    final leaf = cmsKindForLeafName(vod['type_name']?.toString() ?? '');
    if (leaf != null) return leaf;
    // Batch 213: slim payloads may carry nothing but the
    // remarks text — 更新至第8集 is still proof of a series.
    if (cmsRemarksImplySeries(vod['vod_remarks']?.toString() ?? '')) {
      return MediaType.series;
    }
    return MediaType.movie;
  }

  MediaItem _mapVod(Map<String, dynamic> vod) {
    final vodId = _asInt(vod['vod_id']);
    // Batch 231: markers scan the whole category chain,
    // and a live channel is series-shaped by nature — a
    // single-entry channel must not fall into 电影 just
    // because it has one play entry.
    final ancestors = _ancestorNames(vod);
    final leafName = vod['type_name']?.toString() ?? '';
    bool chainHas(bool Function(String) test) =>
        ancestors.any(test) || test(leafName);
    final isLive = chainHas(cmsIsLiveName);
    final kind = isLive ? MediaType.series : (_kindOf(vod) ?? MediaType.movie);
    final title = vod['vod_name']?.toString() ?? '';
    final genres = cmsSplitTokens(
      vod['vod_class']?.toString() ?? '',
    ).map((g) => Genre(id: g, name: g)).toList();
    // Batch 259: vod_area splits like vod_class — some
    // stations ship "香港，中国大陆" as one string, which
    // used to become a single combined area chip.
    final areas = cmsSplitTokens(vod['vod_area']?.toString() ?? '');
    final people = <Person>[
      for (final name in cmsSplitTokens(vod['vod_actor']?.toString() ?? ''))
        Person(id: name, name: name, role: PersonRole.actor),
      for (final name in cmsSplitTokens(vod['vod_director']?.toString() ?? ''))
        Person(id: name, name: name, role: PersonRole.director),
    ];
    final score =
        double.tryParse(vod['vod_score']?.toString() ?? '') ??
        double.tryParse(vod['vod_douban_score']?.toString() ?? '') ??
        0;
    final common = (
      id: mediaIdFor(vodId),
      title: title,
      year: _asInt(vod['vod_year']) == 0 ? null : _asInt(vod['vod_year']),
      overview: cmsStripHtml(vod['vod_content']?.toString() ?? ''),
      genres: genres,
      countries: [for (final a in areas) Country(code: '', name: a)],
      people: people,
      rating: Rating(score: score, source: entry.name),
      artwork: Artwork(poster: vod['vod_pic']?.toString()),
      sourceId: entry.id,
      raw: <String, dynamic>{
        'remarks': vod['vod_remarks']?.toString() ?? '',
        'typeId': _asInt(vod['type_id']),
        'typeName': vod['type_name']?.toString() ?? '',
        // Batch 213/231: shelf markers, scanned over the
        // whole category chain (leaf → root).
        if (chainHas(cmsIsVarietyName)) 'variety': true,
        if (isLive) 'live': true,
        // Batch 241: a manju chain stamps manju INSTEAD of
        // anime — the two shelves never share an item.
        if (chainHas(cmsIsManjuName))
          'manju': true
        else if (chainHas(cmsIsAnimeName))
          'anime': true,
        if (chainHas(cmsIsSportsName)) 'sports': true,
        if (chainHas(cmsIsShortDramaName)) 'shortDrama': true,
      },
    );
    return kind == MediaType.series
        ? TVSeries(
            id: common.id,
            title: common.title,
            year: common.year,
            overview: common.overview,
            genres: common.genres,
            countries: common.countries,
            people: common.people,
            rating: common.rating,
            artwork: common.artwork,
            sourceId: common.sourceId,
            raw: common.raw,
            totalEpisodes: _asInt(vod['vod_total']),
          )
        : Movie(
            id: common.id,
            title: common.title,
            year: common.year,
            overview: common.overview,
            genres: common.genres,
            countries: common.countries,
            people: common.people,
            rating: common.rating,
            artwork: common.artwork,
            sourceId: common.sourceId,
            raw: common.raw,
          );
  }

  Future<_ListResult> _listPage({
    required int page,
    String? keyword,
    int? typeId,
    String? genre,
    int? year,
    String? area,
    bool enrich = false,
  }) async {
    final payload = await _getJson({
      'ac': 'list',
      'pg': '$page',
      if (keyword != null && keyword.isNotEmpty) 'wd': keyword,
      if (typeId != null) 't': '$typeId',
      if (genre != null && genre.isNotEmpty) 'class': genre,
      if (year != null) 'year': '$year',
      if (area != null && area.isNotEmpty) 'area': area,
    });
    final list = payload['list'];
    var items = list is List
        ? list
              .whereType<Map>()
              .map((e) => _mapVod(Map<String, dynamic>.from(e)))
              .where((i) => i.title.isNotEmpty)
              .toList()
        : <MediaItem>[];
    // Batch 225: browse paths opt into metadata backfill —
    // without it the client-side filters are blind on slim
    // stations (see _metaCache).
    if (enrich && items.isNotEmpty) items = await _enrichMeta(items);
    return _ListResult(
      items: items,
      page: _asInt(payload['page']) == 0 ? page : _asInt(payload['page']),
      totalPages: _asInt(payload['pagecount']) == 0
          ? page
          : _asInt(payload['pagecount']),
      totalResults: _asInt(payload['total']),
    );
  }

  /// Batch 225: fill the filterable metadata (genres /
  /// area / year, poster as a bonus) of metadata-bare list
  /// items from ONE batched detail call, cached per vod.
  /// Best-effort — any failure returns the items untouched.
  Future<List<MediaItem>> _enrichMeta(List<MediaItem> items) async {
    // Batch 236: a candidate misses ANY filterable
    // dimension — the batch-225 gate required all three
    // missing, so half-slim stations whose list rows carry
    // year + area but no vod_class never got their genres
    // backfilled, and every genre filter waved their items
    // through (the identical-rails bug, back again).
    bool missingMeta(MediaItem i) =>
        i.genres.isEmpty || i.countries.isEmpty || i.year == null;
    final wanted = <int>[];
    for (final item in items) {
      // Batch 231: movies are backfill candidates too —
      // their detail record is the only place a misfiled
      // season's episode structure shows.
      if (!missingMeta(item) && item is! Movie) continue;
      final vodId = vodIdOf(item.id);
      if (vodId != null && !_metaCache.containsKey(vodId)) {
        wanted.add(vodId);
      }
    }
    if (wanted.isNotEmpty) {
      try {
        final payload = await _getJson({
          'ac': 'detail',
          'ids': wanted.join(','),
        });
        final list = payload['list'];
        if (list is List) {
          for (final row in list.whereType<Map>()) {
            final vodId = _asInt(row['vod_id']);
            if (vodId <= 0) continue;
            final year = _asInt(row['vod_year']);
            _metaCache[vodId] = _MetaBackfill(
              genres: cmsSplitTokens(row['vod_class']?.toString() ?? ''),
              area: row['vod_area']?.toString().trim() ?? '',
              year: year == 0 ? null : year,
              poster: row['vod_pic']?.toString() ?? '',
              episodic: _vodHasEpisodicStructure(
                Map<String, dynamic>.from(row),
              ),
              totalEpisodes: _asInt(row['vod_total']),
            );
          }
        }
      } catch (_) {
        // A failed backfill must never break the browse.
      }
      if (_metaCache.length > 2000) {
        for (final key in _metaCache.keys.take(500).toList()) {
          _metaCache.remove(key);
        }
      }
    }
    return [for (final item in items) _applyMeta(item)];
  }

  MediaItem _applyMeta(MediaItem item) {
    final vodId = vodIdOf(item.id);
    final meta = vodId == null ? null : _metaCache[vodId];
    if (meta == null) return item;
    final genres = item.genres.isNotEmpty
        ? item.genres
        : [for (final g in meta.genres) Genre(id: g, name: g)];
    final countries = item.countries.isNotEmpty
        ? item.countries
        : [
            for (final a in cmsSplitTokens(meta.area))
              Country(code: '', name: a),
          ];
    final year = item.year ?? meta.year;
    final poster = (item.artwork.poster ?? '').isNotEmpty
        ? item.artwork.poster
        : (meta.poster.isEmpty ? item.artwork.poster : meta.poster);
    // Batch 231: promote a misfiled movie whose detail
    // record is episodic — it joins the series shelves
    // instead of polluting 电影.
    if (item is Movie && meta.episodic) {
      return TVSeries(
        id: item.id,
        title: item.title,
        year: year,
        overview: item.overview,
        genres: genres,
        countries: countries,
        people: item.people,
        rating: item.rating,
        artwork: Artwork(poster: poster),
        sourceId: item.sourceId,
        raw: item.raw,
        totalEpisodes: meta.totalEpisodes,
      );
    }
    if (genres.length == item.genres.length &&
        countries.length == item.countries.length &&
        year == item.year &&
        poster == item.artwork.poster) {
      return item;
    }
    final artwork = Artwork(poster: poster);
    return switch (item) {
      TVSeries s => TVSeries(
        id: s.id,
        title: s.title,
        year: year,
        overview: s.overview,
        genres: genres,
        countries: countries,
        people: s.people,
        rating: s.rating,
        artwork: artwork,
        sourceId: s.sourceId,
        raw: s.raw,
        totalEpisodes: s.totalEpisodes,
      ),
      Movie m => Movie(
        id: m.id,
        title: m.title,
        year: year,
        overview: m.overview,
        genres: genres,
        countries: countries,
        people: m.people,
        rating: m.rating,
        artwork: artwork,
        sourceId: m.sourceId,
        raw: m.raw,
      ),
      _ => item,
    };
  }

  /// Zone-level browse for 发现/精选 (not part of the engine
  /// interface): server-side filters where the interface
  /// supports them; the 电视剧/电影 kind has no server
  /// parameter on most deployments, so kind-only browsing
  /// streams raw pages through a client-side filter with a
  /// per-filter buffer (no duplicates across pages).
  Future<SearchPage> browse({
    int page = 1,
    int? typeId,
    MediaType? kind,
    String? genre,
    int? year,
    String? area,
    bool? variety,
    bool? anime,
    bool? shortDrama,
    bool? manju,
  }) async {
    if (typeId != null || kind == null) {
      final raw = await _listPage(
        page: page,
        typeId: typeId,
        // Batch 243: 其他 is a client-side bucket — the
        // server must not receive it as a class/area value.
        genre: genre == '其他' ? null : genre,
        year: year,
        area: area == '其他' ? null : area,
        enrich: true,
      );
      // A chosen category already implies its kind; filtering
      // again here could only empty the page.
      var items = dedupeBrowseItems(raw.items);
      // Batch 213: a variety constraint without a category
      // still applies (the category route implies it).
      if (variety != null && typeId == null) {
        items = items.where((i) => cmsItemIsVariety(i) == variety).toList();
      }
      // Batch 226/228: without a chosen category, live
      // channels never mix into the catalogue flows, and an
      // anime constraint applies like the variety one. An
      // explicit category (typeId) bypasses both — tapping
      // the 直播 or 动漫 category itself must show its items.
      if (typeId == null) {
        items = items.where((i) => !cmsItemIsLive(i)).toList();
        // Batch 236: sports programmes stay out of the
        // catalogue flows too (explicit category only).
        items = items.where((i) => !cmsItemIsSports(i)).toList();
        if (anime != null) {
          items = items.where((i) => cmsItemIsAnime(i) == anime).toList();
        }
        // Batch 241: the short-drama / manju constraints
        // apply like the anime one.
        if (shortDrama != null) {
          items = items
              .where((i) => cmsItemIsShortDrama(i) == shortDrama)
              .toList();
        }
        if (manju != null) {
          items = items.where((i) => cmsItemIsManju(i) == manju).toList();
        }
      }
      // Batch 216: same client-side filter as the stream
      // path — the server parameters alone are unreliable.
      // Batch 259: these three apply even when a category
      // is bound — a picked 题材/地区/年份 is an explicit
      // user filter and must never be silently dropped
      // (it was, when a category chip with the same label
      // as a kind chip — 电视剧 — bound a category while a
      // genre was selected: the grid filled with the
      // category's unfiltered items). The shelf exclusions
      // above keep their category bypass by design: an
      // explicit category is its own shelf.
      if (genre != null) {
        items = items.where((i) => cmsMatchesGenreFilter(i, genre)).toList();
      }
      if (area != null) {
        items = items.where((i) => cmsMatchesAreaFilter(i, area)).toList();
      }
      if (year != null) {
        items = items.where((i) => cmsMatchesYear(i, year)).toList();
      }
      return SearchPage(
        items: items,
        page: page,
        totalPages: raw.totalPages,
        totalResults: raw.totalResults,
      );
    }
    final key =
        '${kind.name}|$genre|$year|$area|$variety|$anime|$shortDrama|$manju';
    final stream = _streams.putIfAbsent(key, _BrowseStream.new);
    // Batch 217: stream bookkeeping is capped — at most
    // _maxStreams live filters per source (least recently
    // created evicted), and one fill scans at most
    // _maxScanPagesPerFill raw pages. Before this, a
    // filter-deaf station (client-side filters match
    // sparsely) made a single shelf scan hundreds of
    // catalogue pages in a tight loop, all through the
    // shared HTTP client — the whole app, playback
    // included, stuttered behind it. A capped fill returns
    // what it has; the next page request resumes scanning.
    if (_streams.length > _maxStreams) {
      _streams.remove(_streams.keys.first);
    }
    var scanned = 0;
    while (stream.buffer.length < page * 20 &&
        !stream.exhausted &&
        scanned < _maxScanPagesPerFill) {
      scanned++;
      final raw = await _listPage(
        page: stream.nextRawPage,
        genre: genre == '其他' ? null : genre,
        year: year,
        area: area == '其他' ? null : area,
        enrich: true,
      );
      stream.nextRawPage++;
      // Batch 210: a record must never enter the buffer
      // twice (paging overlap made the same title appear
      // two times in one filter result).
      for (final item in raw.items) {
        if (item.mediaType != kind) continue;
        // Batch 226: live channels live on their own shelf,
        // never inside a kind stream.
        if (cmsItemIsLive(item)) continue;
        // Batch 236: sports programmes likewise — they
        // default to Movie and filled the 电影 shelves.
        if (cmsItemIsSports(item)) continue;
        // Batch 213: 电视剧 excludes variety, 综艺 is
        // variety-only — the two never mix.
        if (variety != null && cmsItemIsVariety(item) != variety) continue;
        // Batch 228: anime is its own shelf too — 真人剧
        // excludes it, the 动漫 stream is anime-only.
        if (anime != null && cmsItemIsAnime(item) != anime) continue;
        // Batch 241: short dramas and manju are shelves
        // of their own the same way.
        if (shortDrama != null && cmsItemIsShortDrama(item) != shortDrama) {
          continue;
        }
        if (manju != null && cmsItemIsManju(item) != manju) continue;
        // Batch 216: the genre/area/year parameters are
        // not honored by every station — filter again on
        // the item's own metadata so the shelves differ.
        if (genre != null && !cmsMatchesGenreFilter(item, genre)) continue;
        if (area != null && !cmsMatchesAreaFilter(item, area)) continue;
        if (year != null && !cmsMatchesYear(item, year)) continue;
        if (!stream.seenIds.add(item.id)) continue;
        stream.buffer.add(item);
      }
      if (raw.items.isEmpty || stream.nextRawPage - 1 >= raw.totalPages) {
        stream.exhausted = true;
      }
    }
    final start = (page - 1) * 20;
    final slice = start >= stream.buffer.length
        ? <MediaItem>[]
        : stream.buffer.sublist(
            start,
            math.min(start + 20, stream.buffer.length),
          );
    return SearchPage(
      items: slice,
      page: page,
      totalPages: stream.exhausted ? page : page + 1,
      totalResults: stream.buffer.length,
    );
  }

  @override
  Future<SearchPage> search(
    SearchRequest request, {
    SourceCancelToken? cancel,
  }) async {
    if (request.sourceId != null && request.sourceId != entry.id) {
      return const SearchPage(items: []);
    }
    final raw = await _listPage(page: request.page, keyword: request.keyword);
    var items = raw.items;
    if (request.mediaType != null) {
      items = items.where((i) => i.mediaType == request.mediaType).toList();
    }
    if (request.year != null) {
      items = items.where((i) => i.year == request.year).toList();
    }
    return SearchPage(
      items: items,
      page: request.page,
      totalPages: raw.totalPages,
      totalResults: raw.totalResults,
      perSourceStatus: {entry.id: 'ok'},
    );
  }

  /// Batch 212: poster URLs for a batch of media ids, from
  /// ONE detail call (the interface accepts comma-separated
  /// ids). Some stations ship slim list payloads with no
  /// poster field at all — cards backfill from here.
  /// Ids whose detail record has no poster are simply
  /// absent from the result.
  Future<Map<String, String>> fetchPosterUrls(List<String> mediaIds) async {
    final vodIds = <int>[];
    for (final id in mediaIds) {
      final vodId = vodIdOf(id);
      if (vodId != null) vodIds.add(vodId);
    }
    if (vodIds.isEmpty) return const {};
    final payload = await _getJson({'ac': 'detail', 'ids': vodIds.join(',')});
    final list = payload['list'];
    if (list is! List) return const {};
    final out = <String, String>{};
    for (final row in list.whereType<Map>()) {
      final vodId = _asInt(row['vod_id']);
      final pic = row['vod_pic']?.toString() ?? '';
      if (vodId > 0 && pic.isNotEmpty) out[mediaIdFor(vodId)] = pic;
    }
    return out;
  }

  Future<_DetailCache> _detail(int vodId) async {
    final cached = _detailCache[vodId];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
      return cached;
    }
    final payload = await _getJson({'ac': 'detail', 'ids': '$vodId'});
    final list = payload['list'];
    if (list is! List || list.isEmpty) {
      throw StateError('detail not found: $vodId');
    }
    final vod = Map<String, dynamic>.from(list.first as Map);
    final lines = parseCmsPlayLines(
      vod['vod_play_from']?.toString() ?? '',
      vod['vod_play_url']?.toString() ?? '',
    );
    final cache = _DetailCache(DateTime.now(), vod, lines);
    _detailCache[vodId] = cache;
    return cache;
  }

  List<Season> _seasonsOf(String mediaId, _DetailCache detail) {
    return [
      for (var i = 0; i < detail.lines.length; i++)
        Season(
          id: '$mediaId::line::$i',
          seriesId: mediaId,
          seasonNumber: i + 1,
          title: detail.lines[i].name,
          episodes: [
            for (var j = 0; j < detail.lines[i].episodes.length; j++)
              Episode(
                id: '$mediaId::$i::$j',
                seasonId: '$mediaId::line::$i',
                seriesId: mediaId,
                episodeNumber: j + 1,
                title: detail.lines[i].episodes[j].name,
              ),
          ],
        ),
    ];
  }

  @override
  Future<MediaDetail?> getDetail(String mediaId) async {
    final vodId = vodIdOf(mediaId);
    if (vodId == null) return null;
    final detail = await _detail(vodId);
    return MediaDetail(
      item: _mapVod(detail.vod),
      seasons: _seasonsOf(mediaId, detail),
    );
  }

  @override
  Future<List<Season>> getSeasons(String seriesId) async {
    final vodId = vodIdOf(seriesId);
    if (vodId == null) return const [];
    final detail = await _detail(vodId);
    return _seasonsOf(seriesId, detail);
  }

  @override
  Future<List<Episode>> getEpisodes(String seasonId) async {
    // seasonId = '<mediaId>::line::<lineIdx>'
    final marker = '::line::';
    final at = seasonId.lastIndexOf(marker);
    if (at < 0) return const [];
    final mediaId = seasonId.substring(0, at);
    final lineIdx = int.tryParse(seasonId.substring(at + marker.length));
    final vodId = vodIdOf(mediaId);
    if (vodId == null || lineIdx == null) return const [];
    final detail = await _detail(vodId);
    final seasons = _seasonsOf(mediaId, detail);
    if (lineIdx < 0 || lineIdx >= seasons.length) return const [];
    return seasons[lineIdx].episodes;
  }

  @override
  Future<List<VideoSource>> getPlaybackSources(PlaybackQuery query) async {
    final vodId = vodIdOf(query.mediaId);
    if (vodId == null) return const [];
    final detail = await _detail(vodId);
    // episodeId = '<mediaId>::<lineIdx>::<epIdx>'; a movie
    // query may carry no episodeId → first line, first item.
    var lineIdx = 0;
    var epIdx = 0;
    final episodeId = query.episodeId;
    if (episodeId != null) {
      final parts = episodeId.split('::');
      if (parts.length >= 2) {
        lineIdx = int.tryParse(parts[parts.length - 2]) ?? 0;
        epIdx = int.tryParse(parts.last) ?? 0;
      }
    }
    VideoSource? build(int li, int ei) {
      if (li < 0 || li >= detail.lines.length) return null;
      final line = detail.lines[li];
      if (ei < 0 || ei >= line.episodes.length) return null;
      final url = line.episodes[ei].url;
      if (url.isEmpty) return null;
      return VideoSource(
        id: '${query.mediaId}::$li::$ei',
        sourceId: entry.id,
        mediaId: query.mediaId,
        episodeId: episodeId ?? '${query.mediaId}::$li::$ei',
        url: url,
        quality: line.name,
        format: url.toLowerCase().contains('.m3u8')
            ? VideoFormat.hls
            : url.toLowerCase().contains('.mp4')
            ? VideoFormat.mp4
            : VideoFormat.unknown,
        headers: const {'User-Agent': _ua},
      );
    }

    final out = <VideoSource>[];
    final primary = build(lineIdx, epIdx);
    if (primary != null) out.add(primary);
    // Same episode on the other lines, as switchable
    // alternates （线路）.
    for (var li = 0; li < detail.lines.length; li++) {
      if (li == lineIdx) continue;
      final alt = build(li, epIdx);
      if (alt != null) out.add(alt);
    }
    return out;
  }

  @override
  Future<SourceHealth> healthCheck() async {
    final sw = Stopwatch()..start();
    try {
      final payload = await _getJson({'ac': 'list', 'pg': '1'});
      sw.stop();
      if (payload['list'] is List) {
        return SourceHealth(true, 'ok', sw.elapsed);
      }
      return SourceHealth.fail('接口返回格式异常');
    } catch (e) {
      return SourceHealth.fail(e.toString());
    }
  }
}
