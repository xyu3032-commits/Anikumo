
import 'package:liuguang_models/liuguang_models.dart'; import 'package:liuguang_matcher/liuguang_matcher.dart';
abstract interface class MetadataProvider {
  String get providerId;
  Future<MediaItem?> byId(String externalId);
  Future<List<MediaItem>> byTitle(String title,{int? year});
}
class FieldPriority { final Map<String,List<String>> order; const FieldPriority(this.order); factory FieldPriority.defaults()=>FieldPriority({'*':[]}); List<String> forField(String f)=>order[f]??order['*']??const[]; }
class MetadataMerger {
  final FieldPriority priority; MetadataMerger({FieldPriority? priority}):priority=priority??FieldPriority.defaults();
  MediaItem merge(List<MediaItem> items){
    if(items.isEmpty) throw ArgumentError('nothing to merge');
    final sorted=[...items]; final pref=priority.forField('*');
    sorted.sort((a,b){ int ia=pref.indexOf(a.sourceId); int ib=pref.indexOf(b.sourceId); if(ia<0)ia=999; if(ib<0)ib=999; return ia.compareTo(ib); });
    final base=sorted.first;
    String bestStr(String Function(MediaItem) f){ for(final it in sorted){ final v=f(it); if(v.isNotEmpty) return v; } return ''; }
    List<T> bestList<T>(List<T> Function(MediaItem) f){ for(final it in sorted){ final v=f(it); if(v.isNotEmpty) return v; } return <T>[]; }
    double bestScore=0; Rating bestRating=base.rating;
    for(final it in sorted){ if(it.rating.score>bestScore){bestScore=it.rating.score; bestRating=it.rating;} }
    final ext=ExternalIds(tmdb: sorted.map((e)=>e.externalIds.tmdb).whereType<String>().firstOrNull, imdb: sorted.map((e)=>e.externalIds.imdb).whereType<String>().firstOrNull, bangumi: sorted.map((e)=>e.externalIds.bangumi).whereType<String>().firstOrNull);
    final people=<String,Person>{}; for(final it in sorted) for(final p in it.people) people['${p.id}:${p.role.name}']=p;
    final aliases=<String>{...base.aliases}; for(final it in sorted) aliases.addAll(it.aliases);
    if(base.mediaType==MediaType.series){
      return TVSeries(id:base.id,title:bestStr((e)=>e.title),originalTitle:bestStr((e)=>e.originalTitle),year:sorted.map((e)=>e.year).whereType<int>().firstOrNull,overview:bestStr((e)=>e.overview),genres:bestList((e)=>e.genres),countries:bestList((e)=>e.countries),studios:bestList((e)=>e.studios),people:people.values.toList(),rating:bestRating,artwork:Artwork(poster:sorted.map((e)=>e.artwork.poster).whereType<String>().firstOrNull,backdrop:sorted.map((e)=>e.artwork.backdrop).whereType<String>().firstOrNull,logo:sorted.map((e)=>e.artwork.logo).whereType<String>().firstOrNull,stills:bestList((e)=>e.artwork.stills)),externalIds:ext,sourceId:sorted.map((e)=>e.sourceId).join(','),aliases:aliases.toList(),seasons: base is TVSeries?base.seasons:const[], totalEpisodes: base is TVSeries?base.totalEpisodes:0);
    }
    return Movie(id:base.id,title:bestStr((e)=>e.title),originalTitle:bestStr((e)=>e.originalTitle),year:sorted.map((e)=>e.year).whereType<int>().firstOrNull,overview:bestStr((e)=>e.overview),genres:bestList((e)=>e.genres),countries:bestList((e)=>e.countries),studios:bestList((e)=>e.studios),people:people.values.toList(),rating:bestRating,artwork:Artwork(poster:sorted.map((e)=>e.artwork.poster).whereType<String>().firstOrNull,backdrop:sorted.map((e)=>e.artwork.backdrop).whereType<String>().firstOrNull),externalIds:ext,sourceId:sorted.map((e)=>e.sourceId).join(','),aliases:aliases.toList(),runtime: base is Movie?base.runtime:null, releaseDate: base is Movie?base.releaseDate:null);
  }
}
class MetadataDeduplicator {
  final MetadataMerger merger; MetadataDeduplicator({MetadataMerger? merger}):merger=merger??MetadataMerger();
  List<MediaItem> deduplicate(List<MediaItem> items){
    final groups=<String,List<MediaItem>>{}; final order=<String>[];
    for(final it in items){
      String? key;
      for(final k in groups.keys){ if(groups[k]!.any((o)=>TitleMatcher.score(o,it).isMatch)){ key=k; break; } }
      if(key==null){ key=TitleMatcher.fingerprint(it); if(!groups.containsKey(key)){order.add(key);} }
      groups.putIfAbsent(key,()=>[]).add(it);
    }
    return order.map((k){ final g=groups[k]!; return g.length==1?g.first:merger.merge(g); }).toList();
  }
}
class MetadataRepository {
  final List<MetadataProvider> providers; final MetadataDeduplicator dedup;
  MetadataRepository(this.providers,{MetadataDeduplicator? dedup}):dedup=dedup??MetadataDeduplicator();
  Future<List<MediaItem>> searchByTitle(String title,{int? year}) async { final all=<MediaItem>[]; for(final p in providers){ try{ all.addAll(await p.byTitle(title,year:year)); } catch(_){ /* provider failure isolated */ } } return dedup.deduplicate(all); }
  Future<MediaItem?> byId(String externalId) async { final found=<MediaItem>[]; for(final p in providers){ try{ final r=await p.byId(externalId); if(r!=null) found.add(r); } catch(_){} } if(found.isEmpty) return null; return found.length==1?found.first:dedup.merger.merge(found); }
}
