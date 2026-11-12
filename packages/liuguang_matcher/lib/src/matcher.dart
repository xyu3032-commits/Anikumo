
import 'package:liuguang_models/liuguang_models.dart';
class SeasonEpisode { final int? season; final int? episode; const SeasonEpisode(this.season,this.episode); }
class MatchScore { final double score; final List<String> reasons; const MatchScore(this.score,this.reasons); bool get isMatch => score>=0.6; }
class TitleMatcher {
  static final _punct = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static String normalize(String input) {
    var s = input.toLowerCase();
    s = s.replaceAll(RegExp(r'\bs\d{1,2}e\d{1,3}\b'), ' ');
    s = s.replaceAll(RegExp(r'第[一二三四五六七八九十\d]+[季集]'), ' ');
    s = s.replaceAll(_punct, ' ');
    s = s.replaceAll(RegExp(r'\b(season|series|the)\b'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }
  static int? extractYear(String input) { final m = RegExp(r'(19|20)\d{2}').firstMatch(input); return m==null?null:int.parse(m.group(0)!); }
  static SeasonEpisode extractSeasonEpisode(String input) {
    var m = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})').firstMatch(input);
    if (m!=null) return SeasonEpisode(int.parse(m.group(1)!), int.parse(m.group(2)!));
    final cn = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9,'十':10};
    int? parseNum(String t)=> int.tryParse(t) ?? cn[t];
    int? season, episode;
    final sm = RegExp(r'第([一二三四五六七八九十\d]+)季').firstMatch(input); if (sm!=null) season=parseNum(sm.group(1)!);
    final em = RegExp(r'第([一二三四五六七八九十\d]+)集').firstMatch(input); if (em!=null) episode=parseNum(em.group(1)!);
    if (season!=null||episode!=null) return SeasonEpisode(season,episode);
    return const SeasonEpisode(null,null);
  }
  static String fingerprint(MediaItem item) {
    final ext = item.externalIds.tmdb ?? item.externalIds.imdb ?? item.externalIds.bangumi;
    if (ext!=null && ext.isNotEmpty) return 'ext:$ext:${item.mediaType.name}';
    return 'fp:${normalize(item.title)}|${item.year ?? extractYear(item.title) ?? ''}|${item.mediaType.name}';
  }
  static MatchScore score(MediaItem a, MediaItem b) {
    final reasons=<String>[]; double s=0;
    if (a.mediaType!=b.mediaType) { return MatchScore(0.1, ['mediaType mismatch']); }
    reasons.add('mediaType match'); s+=0.1;
    final ea=a.externalIds, eb=b.externalIds;
    if ((ea.tmdb!=null&&ea.tmdb==eb.tmdb)||(ea.imdb!=null&&ea.imdb==eb.imdb)||(ea.bangumi!=null&&ea.bangumi==eb.bangumi)) { return MatchScore(1.0, [...reasons,'external id match']); }
    final na=normalize(a.title), nb=normalize(b.title);
    if (na.isNotEmpty && na==nb) { s+=0.6; reasons.add('exact normalized title'); }
    else if (na.isNotEmpty && (na.contains(nb)||nb.contains(na))) { s+=0.35; reasons.add('title containment'); }
    else {
      final sa=na.split(' ').toSet(), sb=nb.split(' ').toSet(); final inter=sa.intersection(sb).length; final uni=sa.union(sb).length;
      if (uni>0) { final j=inter/uni; s+=j*0.4; reasons.add('token jaccard ${j.toStringAsFixed(2)}'); }
      for (final al in [...a.aliases, a.originalTitle]) { if (normalize(al)==nb && al.isNotEmpty) { s+=0.5; reasons.add('alias match'); break; } }
    }
    if (a.year!=null && b.year!=null) { if (a.year==b.year) { s+=0.25; reasons.add('year exact'); } else if ((a.year!-b.year!).abs()<=1) { s+=0.1; reasons.add('year within 1'); } else { s-=0.2; reasons.add('year far'); } }
    if (a.genres.isNotEmpty && b.genres.isNotEmpty) { final ga=a.genres.map((e)=>e.name.toLowerCase()).toSet(), gb=b.genres.map((e)=>e.name.toLowerCase()).toSet(); if (ga.intersection(gb).isNotEmpty) { s+=0.05; reasons.add('genre overlap'); } }
    return MatchScore(s.clamp(0,1).toDouble(), reasons);
  }
}
