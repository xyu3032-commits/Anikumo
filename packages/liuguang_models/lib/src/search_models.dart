
import 'models.dart';
class SearchRequest {
  final String keyword; final int page; final int pageSize; final MediaType? mediaType; final int? year; final String? sourceId;
  const SearchRequest({required this.keyword, this.page = 1, this.pageSize = 20, this.mediaType, this.year, this.sourceId});
  SearchRequest copyWith({String? keyword, int? page}) => SearchRequest(keyword: keyword ?? this.keyword, page: page ?? this.page, pageSize: pageSize, mediaType: mediaType, year: year, sourceId: sourceId);
  Map<String, dynamic> toJson() => {'keyword': keyword, 'page': page, 'pageSize': pageSize, 'mediaType': mediaType?.name, 'year': year, 'sourceId': sourceId};
  factory SearchRequest.fromJson(Map<String, dynamic> j) => SearchRequest(keyword: j['keyword']?.toString() ?? '', page: j['page'] is num ? (j['page'] as num).toInt() : 1, pageSize: j['pageSize'] is num ? (j['pageSize'] as num).toInt() : 20, mediaType: j['mediaType'] == 'series' ? MediaType.series : (j['mediaType'] == 'movie' ? MediaType.movie : null), year: j['year'] is num ? (j['year'] as num).toInt() : null, sourceId: j['sourceId']?.toString());
  String get cacheKey => '$keyword|$page|$pageSize|${mediaType?.name}|$year|$sourceId';
}
class SearchPage {
  final List<MediaItem> items; final int page; final int totalPages; final int totalResults; final Map<String, String> perSourceStatus;
  const SearchPage({required this.items, this.page = 1, this.totalPages = 1, this.totalResults = 0, this.perSourceStatus = const {}});
  bool get hasMore => page < totalPages;
  Map<String, dynamic> toJson() => {'items': items.map((e) => e.toJson()).toList(), 'page': page, 'totalPages': totalPages, 'totalResults': totalResults, 'perSourceStatus': perSourceStatus};
  factory SearchPage.fromJson(Map<String, dynamic> j) => SearchPage(items: j['items'] is List ? (j['items'] as List).whereType<Map>().map((e) => TVSeries.mediaFromJson(Map<String, dynamic>.from(e))).toList() : const [], page: j['page'] is num ? (j['page'] as num).toInt() : 1, totalPages: j['totalPages'] is num ? (j['totalPages'] as num).toInt() : 1, totalResults: j['totalResults'] is num ? (j['totalResults'] as num).toInt() : 0, perSourceStatus: j['perSourceStatus'] is Map ? (j['perSourceStatus'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())) : const {});
}
class MediaDetail {
  final MediaItem item; final List<Season> seasons;
  const MediaDetail({required this.item, this.seasons = const []});
  Map<String, dynamic> toJson() => {'item': item.toJson(), 'seasons': seasons.map((e) => e.toJson()).toList()};
  factory MediaDetail.fromJson(Map<String, dynamic> j) => MediaDetail(item: TVSeries.mediaFromJson(Map<String, dynamic>.from(j['item'] as Map)), seasons: j['seasons'] is List ? (j['seasons'] as List).whereType<Map>().map((e) => Season.fromJson(Map<String, dynamic>.from(e))).toList() : const []);
}
class PlaybackQuery {
  final String mediaId; final String? episodeId; final String? preferredQuality;
  const PlaybackQuery({required this.mediaId, this.episodeId, this.preferredQuality});
  Map<String, dynamic> toJson() => {'mediaId': mediaId, 'episodeId': episodeId, 'preferredQuality': preferredQuality};
}
