
import 'package:liuguang_models/liuguang_models.dart';
class SourceCancelToken { bool _c=false; bool get isCancelled=>_c; void cancel()=>_c=true; }
class SourceCapabilities { final bool supportsSeasons; final bool supportsPagination; final bool supportsDirectPlayback; final bool requiresLogin; final bool requiresWebViewResolver;
  const SourceCapabilities({this.supportsSeasons=true,this.supportsPagination=true,this.supportsDirectPlayback=true,this.requiresLogin=false,this.requiresWebViewResolver=false});
  Map<String,dynamic> toJson()=>{'supportsSeasons':supportsSeasons,'supportsPagination':supportsPagination,'supportsDirectPlayback':supportsDirectPlayback,'requiresLogin':requiresLogin,'requiresWebViewResolver':requiresWebViewResolver};
  factory SourceCapabilities.fromJson(Map<String,dynamic> j)=>SourceCapabilities(supportsSeasons:j['supportsSeasons']!=false,supportsPagination:j['supportsPagination']!=false,supportsDirectPlayback:j['supportsDirectPlayback']!=false,requiresLogin:j['requiresLogin']==true,requiresWebViewResolver:j['requiresWebViewResolver']==true);
}
class SourceDescriptor {
  final String id; final String name; final String version; final SourceCapabilities capabilities; final String homepage; final List<String> permissions;
  const SourceDescriptor({required this.id,required this.name,this.version='1.0.0',this.capabilities=const SourceCapabilities(),this.homepage='',this.permissions=const[]});
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'version':version,'capabilities':capabilities.toJson(),'homepage':homepage,'permissions':permissions};
  factory SourceDescriptor.fromJson(Map<String,dynamic> j)=>SourceDescriptor(id:j['id']?.toString()??'',name:j['name']?.toString()??'',version:j['version']?.toString()??'1.0.0',capabilities:j['capabilities'] is Map?SourceCapabilities.fromJson(Map<String,dynamic>.from(j['capabilities'] as Map)):const SourceCapabilities(),homepage:j['homepage']?.toString()??'',permissions:(j['permissions'] as List? ??[]).map((e)=>e.toString()).toList());
}
class SourceHealth { final bool healthy; final String message; final Duration latency; const SourceHealth(this.healthy,this.message,this.latency); factory SourceHealth.ok(Duration l)=>SourceHealth(true,'ok',l); factory SourceHealth.fail(String m)=>SourceHealth(false,m,Duration.zero); Map<String,dynamic> toJson()=>{'healthy':healthy,'message':message,'latencyMs':latency.inMilliseconds}; }
abstract interface class MediaSourceProvider {
  SourceDescriptor get descriptor;
  Future<SearchPage> search(SearchRequest request,{SourceCancelToken? cancel});
  Future<MediaDetail?> getDetail(String mediaId);
  Future<List<Season>> getSeasons(String seriesId);
  Future<List<Episode>> getEpisodes(String seasonId);
  Future<List<VideoSource>> getPlaybackSources(PlaybackQuery query);
  Future<SourceHealth> healthCheck();
}
class SourceManifest {
  final SourceDescriptor descriptor; final String kind; final Map<String,dynamic> config;
  const SourceManifest({required this.descriptor,this.kind='dart',this.config=const{}});
  Map<String,dynamic> toJson()=>{'descriptor':descriptor.toJson(),'kind':kind,'config':config};
  factory SourceManifest.fromJson(Map<String,dynamic> j)=>SourceManifest(descriptor:SourceDescriptor.fromJson(Map<String,dynamic>.from(j['descriptor'] as Map)),kind:j['kind']?.toString()??'dart',config:j['config'] is Map?Map<String,dynamic>.from(j['config'] as Map):const{});
}
