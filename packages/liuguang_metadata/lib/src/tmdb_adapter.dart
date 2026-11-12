
import 'package:liuguang_models/liuguang_models.dart'; import 'package:liuguang_network/liuguang_network.dart'; import 'metadata.dart';
class TmdbNotConfiguredException implements Exception { @override String toString()=>'TmdbNotConfiguredException: TMDB api key not provided'; }
/// TMDB adapter. Requires a user-supplied API key; without one it throws
/// [TmdbNotConfiguredException] instead of returning invented data.
class TmdbMetadataProvider implements MetadataProvider {
  final String? apiKey; final LiuGuangHttpClient http; final String baseUrl;
  TmdbMetadataProvider({this.apiKey, LiuGuangHttpClient? http, this.baseUrl='https://api.themoviedb.org/3'}): http=http??LiuGuangHttpClient();
  @override String get providerId=>'tmdb';
  void _requireKey(){ if(apiKey==null||apiKey!.isEmpty) throw TmdbNotConfiguredException(); }
  MediaItem _map(Map<String,dynamic> j, bool isTv){
    final title=(isTv?j['name']:j['title'])?.toString()??''; final original=(isTv?j['original_name']:j['original_title'])?.toString()??'';
    final date=(isTv?j['first_air_date']:j['release_date'])?.toString(); final year=date!=null&&date.length>=4?int.tryParse(date.substring(0,4)):null;
    final poster=j['poster_path']?.toString(); final backdrop=j['backdrop_path']?.toString();
    final base='src:tmdb:${j['id']}';
    final commonArt=Artwork(poster:poster==null?null:'https://image.tmdb.org/t/p/w500$poster', backdrop:backdrop==null?null:'https://image.tmdb.org/t/p/w780$backdrop');
    if(isTv) return TVSeries(id:base,title:title,originalTitle:original,year:year,overview:j['overview']?.toString()??'',rating:Rating(score:(j['vote_average'] as num?)?.toDouble()??0, votes:(j['vote_count'] as num?)?.toInt()??0, source:'tmdb'),artwork:commonArt,externalIds:ExternalIds(tmdb:j['id']?.toString()),sourceId:'tmdb');
    return Movie(id:base,title:title,originalTitle:original,year:year,overview:j['overview']?.toString()??'',rating:Rating(score:(j['vote_average'] as num?)?.toDouble()??0, votes:(j['vote_count'] as num?)?.toInt()??0, source:'tmdb'),artwork:commonArt,externalIds:ExternalIds(tmdb:j['id']?.toString()),sourceId:'tmdb');
  }
  @override Future<MediaItem?> byId(String externalId) async { _requireKey(); final j=await http.getJson('$baseUrl/movie/$externalId?api_key=$apiKey'); if(j is! Map) return null; return _map(Map<String,dynamic>.from(j),false); }
  @override Future<List<MediaItem>> byTitle(String title,{int? year}) async { _requireKey(); final q=Uri.encodeQueryComponent(title); final j=await http.getJson('$baseUrl/search/multi?api_key=$apiKey&query=$q${year!=null?'&year=$year':''}'); if(j is! Map) return []; final results=j['results']; if(results is! List) return []; return results.whereType<Map>().map((e){ final m=Map<String,dynamic>.from(e); return _map(m, m['media_type']=='tv'); }).toList(); }
}
