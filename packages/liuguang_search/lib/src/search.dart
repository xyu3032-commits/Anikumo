
import 'dart:async'; import 'package:liuguang_models/liuguang_models.dart'; import 'package:liuguang_source_sdk/liuguang_source_sdk.dart'; import 'package:liuguang_matcher/liuguang_matcher.dart'; import 'package:liuguang_cache/liuguang_cache.dart'; import 'package:liuguang_metadata/liuguang_metadata.dart' show MetadataDeduplicator;
class AggregatedSearch {
  final int maxConcurrency; final Duration perSourceTimeout; final LruCache<String,SearchPage>? cache;
  AggregatedSearch({this.maxConcurrency=4,this.perSourceTimeout=const Duration(seconds:10),this.cache});
  Future<SearchPage> search(List<MediaSourceProvider> providers, SearchRequest request,{SourceCancelToken? cancel}) async {
    final cached=cache?.get(request.cacheKey); if(cached!=null) return cached;
    final results=<MediaItem>[]; final status=<String,String>{}; int idx=0;
    Future<void> worker() async { while(idx<providers.length){ if(cancel?.isCancelled??false) return; final p=providers[idx++]; try{ final page=await p.search(request,cancel:cancel).timeout(perSourceTimeout); results.addAll(page.items); status[p.descriptor.id]='ok:${page.items.length}'; } catch(e){ status[p.descriptor.id]='error:$e'; } } }
    await Future.wait(List.generate(providers.length<maxConcurrency?providers.length:maxConcurrency,(_)=>worker()));
    var items=MetadataDeduplicator().deduplicate(results);
    if(request.mediaType!=null) items=items.where((e)=>e.mediaType==request.mediaType).toList();
    if(request.year!=null) items=items.where((e)=>e.year==null||(e.year!-request.year!).abs()<=1).toList();
    final query=Movie(id:'_q',title:request.keyword,year:request.year);
    items.sort((a,b)=> TitleMatcher.score(query,b).score.compareTo(TitleMatcher.score(query,a).score));
    final pageSize=request.pageSize; final start=(request.page-1)*pageSize;
    final sliced=start>=items.length?<MediaItem>[]:items.sublist(start, start+pageSize>items.length?items.length:start+pageSize);
    final totalPages=items.isEmpty?1:((items.length+pageSize-1)~/pageSize);
    final page=SearchPage(items:sliced,page:request.page,totalPages:totalPages,totalResults:items.length,perSourceStatus:status);
    cache?.put(request.cacheKey,page); return page;
  }
}
