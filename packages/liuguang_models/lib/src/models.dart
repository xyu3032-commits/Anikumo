
enum MediaType { movie, series }
enum PersonRole { actor, director, writer, producer, other }
enum VideoFormat { mp4, hls, dash, webm, mkv, unknown }

String _s(Object? v, [String d = '']) => v?.toString() ?? d;
int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? d;
double _d(Object? v, [double d = 0]) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? d;
bool _b(Object? v, [bool d = false]) => v is bool ? v : d;
List<String> _sl(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];
DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
Map<String, String> _sm(Object? v) => v is Map ? v.map((k, e) => MapEntry(k.toString(), e.toString())) : const {};

class Genre {
  final String id; final String name;
  const Genre({required this.id, required this.name});
  Genre copyWith({String? id, String? name}) => Genre(id: id ?? this.id, name: name ?? this.name);
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Genre.fromJson(Map<String, dynamic> j) => Genre(id: _s(j['id']), name: _s(j['name']));
  @override bool operator ==(Object o) => o is Genre && o.id == id && o.name == name;
  @override int get hashCode => Object.hash(id, name);
}
class Country {
  final String code; final String name;
  const Country({required this.code, required this.name});
  Map<String, dynamic> toJson() => {'code': code, 'name': name};
  factory Country.fromJson(Map<String, dynamic> j) => Country(code: _s(j['code']), name: _s(j['name']));
}
class Studio {
  final String id; final String name;
  const Studio({required this.id, required this.name});
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Studio.fromJson(Map<String, dynamic> j) => Studio(id: _s(j['id']), name: _s(j['name']));
}
class Person {
  final String id; final String name; final PersonRole role; final String? character; final String? photoUrl;
  const Person({required this.id, required this.name, this.role = PersonRole.actor, this.character, this.photoUrl});
  Person copyWith({String? id, String? name, PersonRole? role, String? character, String? photoUrl}) =>
      Person(id: id ?? this.id, name: name ?? this.name, role: role ?? this.role, character: character ?? this.character, photoUrl: photoUrl ?? this.photoUrl);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role.name, 'character': character, 'photoUrl': photoUrl};
  factory Person.fromJson(Map<String, dynamic> j) => Person(id: _s(j['id']), name: _s(j['name']),
      role: PersonRole.values.firstWhere((e) => e.name == j['role'], orElse: () => PersonRole.other),
      character: j['character']?.toString(), photoUrl: j['photoUrl']?.toString());
}
typedef Actor = Person;
typedef Director = Person;
class Rating {
  final double score; final int votes; final String source;
  const Rating({this.score = 0, this.votes = 0, this.source = ''});
  Rating copyWith({double? score, int? votes, String? source}) => Rating(score: score ?? this.score, votes: votes ?? this.votes, source: source ?? this.source);
  Map<String, dynamic> toJson() => {'score': score, 'votes': votes, 'source': source};
  factory Rating.fromJson(Map<String, dynamic> j) => Rating(score: _d(j['score']), votes: _i(j['votes']), source: _s(j['source']));
}
class Artwork {
  final String? poster; final String? backdrop; final String? logo; final List<String> stills;
  const Artwork({this.poster, this.backdrop, this.logo, this.stills = const []});
  Artwork copyWith({String? poster, String? backdrop, String? logo, List<String>? stills}) =>
      Artwork(poster: poster ?? this.poster, backdrop: backdrop ?? this.backdrop, logo: logo ?? this.logo, stills: stills ?? this.stills);
  Map<String, dynamic> toJson() => {'poster': poster, 'backdrop': backdrop, 'logo': logo, 'stills': stills};
  factory Artwork.fromJson(Map<String, dynamic> j) => Artwork(poster: j['poster']?.toString(), backdrop: j['backdrop']?.toString(), logo: j['logo']?.toString(), stills: _sl(j['stills']));
}
class ExternalIds {
  final String? tmdb; final String? imdb; final String? bangumi;
  const ExternalIds({this.tmdb, this.imdb, this.bangumi});
  Map<String, dynamic> toJson() => {'tmdb': tmdb, 'imdb': imdb, 'bangumi': bangumi};
  factory ExternalIds.fromJson(Map<String, dynamic> j) => ExternalIds(tmdb: j['tmdb']?.toString(), imdb: j['imdb']?.toString(), bangumi: j['bangumi']?.toString());
}

abstract class MediaItem {
  final String id; final MediaType mediaType; final String title; final String originalTitle;
  final Map<String, String> localizedTitles; final List<String> aliases; final int? year; final String overview;
  final List<Genre> genres; final List<Country> countries; final List<Studio> studios; final List<Person> people;
  final Rating rating; final Artwork artwork; final ExternalIds externalIds; final String sourceId;
  final DateTime? updatedAt; final Map<String, dynamic> raw;
  const MediaItem({required this.id, required this.mediaType, required this.title, this.originalTitle = '',
    this.localizedTitles = const {}, this.aliases = const [], this.year, this.overview = '', this.genres = const [],
    this.countries = const [], this.studios = const [], this.people = const [], this.rating = const Rating(),
    this.artwork = const Artwork(), this.externalIds = const ExternalIds(), this.sourceId = '', this.updatedAt, this.raw = const {}});
  Map<String, dynamic> baseJson() => {
    'id': id, 'mediaType': mediaType.name, 'title': title, 'originalTitle': originalTitle,
    'localizedTitles': localizedTitles, 'aliases': aliases, 'year': year, 'overview': overview,
    'genres': genres.map((e) => e.toJson()).toList(), 'countries': countries.map((e) => e.toJson()).toList(),
    'studios': studios.map((e) => e.toJson()).toList(), 'people': people.map((e) => e.toJson()).toList(),
    'rating': rating.toJson(), 'artwork': artwork.toJson(), 'externalIds': externalIds.toJson(),
    'sourceId': sourceId, 'updatedAt': updatedAt?.toIso8601String(), 'raw': raw};
  static ({String id, MediaType mediaType, String title, String originalTitle, Map<String,String> localizedTitles, List<String> aliases, int? year, String overview, List<Genre> genres, List<Country> countries, List<Studio> studios, List<Person> people, Rating rating, Artwork artwork, ExternalIds externalIds, String sourceId, DateTime? updatedAt, Map<String,dynamic> raw}) parseBase(Map<String, dynamic> j) {
    List<T> pl<T>(Object? v, T Function(Map<String, dynamic>) f) => v is List ? v.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList() : <T>[];
    return (id: _s(j['id']), mediaType: j['mediaType'] == 'series' ? MediaType.series : MediaType.movie,
      title: _s(j['title']), originalTitle: _s(j['originalTitle']), localizedTitles: _sm(j['localizedTitles']),
      aliases: _sl(j['aliases']), year: j['year'] == null ? null : _i(j['year']), overview: _s(j['overview']),
      genres: pl(j['genres'], Genre.fromJson), countries: pl(j['countries'], Country.fromJson),
      studios: pl(j['studios'], Studio.fromJson), people: pl(j['people'], Person.fromJson),
      rating: j['rating'] is Map ? Rating.fromJson(Map<String, dynamic>.from(j['rating'] as Map)) : const Rating(),
      artwork: j['artwork'] is Map ? Artwork.fromJson(Map<String, dynamic>.from(j['artwork'] as Map)) : const Artwork(),
      externalIds: j['externalIds'] is Map ? ExternalIds.fromJson(Map<String, dynamic>.from(j['externalIds'] as Map)) : const ExternalIds(),
      sourceId: _s(j['sourceId']), updatedAt: _dt(j['updatedAt']),
      raw: j['raw'] is Map ? Map<String, dynamic>.from(j['raw'] as Map) : const {});
  }
  Map<String, dynamic> toJson();
}

class Movie extends MediaItem {
  final Duration? runtime; final DateTime? releaseDate;
  const Movie({required super.id, required super.title, super.originalTitle, super.localizedTitles, super.aliases,
    super.year, super.overview, super.genres, super.countries, super.studios, super.people, super.rating, super.artwork,
    super.externalIds, super.sourceId, super.updatedAt, super.raw, this.runtime, this.releaseDate}) : super(mediaType: MediaType.movie);
  Movie copyWith({String? title, String? overview, Rating? rating, Artwork? artwork, Duration? runtime}) => Movie(
    id: id, title: title ?? this.title, originalTitle: originalTitle, localizedTitles: localizedTitles, aliases: aliases,
    year: year, overview: overview ?? this.overview, genres: genres, countries: countries, studios: studios, people: people,
    rating: rating ?? this.rating, artwork: artwork ?? this.artwork, externalIds: externalIds, sourceId: sourceId,
    updatedAt: updatedAt, raw: raw, runtime: runtime ?? this.runtime, releaseDate: releaseDate);
  @override Map<String, dynamic> toJson() => {...baseJson(), 'runtimeMinutes': runtime?.inMinutes, 'releaseDate': releaseDate?.toIso8601String()};
  factory Movie.fromJson(Map<String, dynamic> j) { final b = MediaItem.parseBase(j); return Movie(id: b.id, title: b.title,
    originalTitle: b.originalTitle, localizedTitles: b.localizedTitles, aliases: b.aliases, year: b.year, overview: b.overview,
    genres: b.genres, countries: b.countries, studios: b.studios, people: b.people, rating: b.rating, artwork: b.artwork,
    externalIds: b.externalIds, sourceId: b.sourceId, updatedAt: b.updatedAt, raw: b.raw,
    runtime: j['runtimeMinutes'] == null ? null : Duration(minutes: _i(j['runtimeMinutes'])), releaseDate: _dt(j['releaseDate'])); }
}
class TVSeries extends MediaItem {
  final List<Season> seasons; final String status; final int totalEpisodes;
  const TVSeries({required super.id, required super.title, super.originalTitle, super.localizedTitles, super.aliases,
    super.year, super.overview, super.genres, super.countries, super.studios, super.people, super.rating, super.artwork,
    super.externalIds, super.sourceId, super.updatedAt, super.raw, this.seasons = const [], this.status = '', this.totalEpisodes = 0}) : super(mediaType: MediaType.series);
  TVSeries copyWith({String? title, String? overview, List<Season>? seasons, Rating? rating}) => TVSeries(id: id, title: title ?? this.title,
    originalTitle: originalTitle, localizedTitles: localizedTitles, aliases: aliases, year: year, overview: overview ?? this.overview,
    genres: genres, countries: countries, studios: studios, people: people, rating: rating ?? this.rating, artwork: artwork,
    externalIds: externalIds, sourceId: sourceId, updatedAt: updatedAt, raw: raw, seasons: seasons ?? this.seasons, status: status, totalEpisodes: totalEpisodes);
  @override Map<String, dynamic> toJson() => {...baseJson(), 'seasons': seasons.map((e) => e.toJson()).toList(), 'status': status, 'totalEpisodes': totalEpisodes};
  factory TVSeries.fromJson(Map<String, dynamic> j) { final b = MediaItem.parseBase(j); return TVSeries(id: b.id, title: b.title,
    originalTitle: b.originalTitle, localizedTitles: b.localizedTitles, aliases: b.aliases, year: b.year, overview: b.overview,
    genres: b.genres, countries: b.countries, studios: b.studios, people: b.people, rating: b.rating, artwork: b.artwork,
    externalIds: b.externalIds, sourceId: b.sourceId, updatedAt: b.updatedAt, raw: b.raw,
    seasons: j['seasons'] is List ? (j['seasons'] as List).whereType<Map>().map((e) => Season.fromJson(Map<String, dynamic>.from(e))).toList() : const [],
    status: _s(j['status']), totalEpisodes: _i(j['totalEpisodes'])); }
  static MediaItem mediaFromJson(Map<String, dynamic> j) => j['mediaType'] == 'series' ? TVSeries.fromJson(j) : Movie.fromJson(j);
}
class Season {
  final String id; final String seriesId; final int seasonNumber; final String title; final List<Episode> episodes; final DateTime? airDate;
  const Season({required this.id, required this.seriesId, required this.seasonNumber, this.title = '', this.episodes = const [], this.airDate});
  Season copyWith({String? title, List<Episode>? episodes}) => Season(id: id, seriesId: seriesId, seasonNumber: seasonNumber, title: title ?? this.title, episodes: episodes ?? this.episodes, airDate: airDate);
  Map<String, dynamic> toJson() => {'id': id, 'seriesId': seriesId, 'seasonNumber': seasonNumber, 'title': title, 'episodes': episodes.map((e) => e.toJson()).toList(), 'airDate': airDate?.toIso8601String()};
  factory Season.fromJson(Map<String, dynamic> j) => Season(id: _s(j['id']), seriesId: _s(j['seriesId']), seasonNumber: _i(j['seasonNumber']),
    title: _s(j['title']), episodes: j['episodes'] is List ? (j['episodes'] as List).whereType<Map>().map((e) => Episode.fromJson(Map<String, dynamic>.from(e))).toList() : const [], airDate: _dt(j['airDate']));
}
class Episode {
  final String id; final String seasonId; final String seriesId; final int episodeNumber; final String title; final String? still; final DateTime? airDate; final Duration? runtime; final String overview;
  const Episode({required this.id, required this.seasonId, this.seriesId = '', required this.episodeNumber, this.title = '', this.still, this.airDate, this.runtime, this.overview = ''});
  Episode copyWith({String? title, String? overview}) => Episode(id: id, seasonId: seasonId, seriesId: seriesId, episodeNumber: episodeNumber, title: title ?? this.title, still: still, airDate: airDate, runtime: runtime, overview: overview ?? this.overview);
  Map<String, dynamic> toJson() => {'id': id, 'seasonId': seasonId, 'seriesId': seriesId, 'episodeNumber': episodeNumber, 'title': title, 'still': still, 'airDate': airDate?.toIso8601String(), 'runtimeMinutes': runtime?.inMinutes, 'overview': overview};
  factory Episode.fromJson(Map<String, dynamic> j) => Episode(id: _s(j['id']), seasonId: _s(j['seasonId']), seriesId: _s(j['seriesId']),
    episodeNumber: _i(j['episodeNumber']), title: _s(j['title']), still: j['still']?.toString(), airDate: _dt(j['airDate']),
    runtime: j['runtimeMinutes'] == null ? null : Duration(minutes: _i(j['runtimeMinutes'])), overview: _s(j['overview']));
}
class SubtitleTrack {
  final String id; final String language; final String label; final bool isDefault; final bool isForced; final String? url; final int? embeddedIndex; final String format;
  const SubtitleTrack({required this.id, this.language = '', this.label = '', this.isDefault = false, this.isForced = false, this.url, this.embeddedIndex, this.format = ''});
  Map<String, dynamic> toJson() => {'id': id, 'language': language, 'label': label, 'isDefault': isDefault, 'isForced': isForced, 'url': url, 'embeddedIndex': embeddedIndex, 'format': format};
  factory SubtitleTrack.fromJson(Map<String, dynamic> j) => SubtitleTrack(id: _s(j['id']), language: _s(j['language']), label: _s(j['label']), isDefault: _b(j['isDefault']), isForced: _b(j['isForced']), url: j['url']?.toString(), embeddedIndex: j['embeddedIndex'] == null ? null : _i(j['embeddedIndex']), format: _s(j['format']));
}
class AudioTrack {
  final String id; final String language; final String label; final bool isDefault; final String? codec; final int? channels;
  const AudioTrack({required this.id, this.language = '', this.label = '', this.isDefault = false, this.codec, this.channels});
  Map<String, dynamic> toJson() => {'id': id, 'language': language, 'label': label, 'isDefault': isDefault, 'codec': codec, 'channels': channels};
  factory AudioTrack.fromJson(Map<String, dynamic> j) => AudioTrack(id: _s(j['id']), language: _s(j['language']), label: _s(j['label']), isDefault: _b(j['isDefault']), codec: j['codec']?.toString(), channels: j['channels'] == null ? null : _i(j['channels']));
}
class VideoSource {
  final String id; final String sourceId; final String mediaId; final String? episodeId; final String url; final String quality; final VideoFormat format; final Map<String, String> headers; final List<SubtitleTrack> subtitles; final List<AudioTrack> audioTracks; final DateTime? expiresAt;
  const VideoSource({required this.id, required this.sourceId, required this.mediaId, this.episodeId, required this.url, this.quality = '', this.format = VideoFormat.unknown, this.headers = const {}, this.subtitles = const [], this.audioTracks = const [], this.expiresAt});
  VideoSource copyWith({String? url, String? quality}) => VideoSource(id: id, sourceId: sourceId, mediaId: mediaId, episodeId: episodeId, url: url ?? this.url, quality: quality ?? this.quality, format: format, headers: headers, subtitles: subtitles, audioTracks: audioTracks, expiresAt: expiresAt);
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  Map<String, dynamic> toJson() => {'id': id, 'sourceId': sourceId, 'mediaId': mediaId, 'episodeId': episodeId, 'url': url, 'quality': quality, 'format': format.name, 'headers': headers, 'subtitles': subtitles.map((e) => e.toJson()).toList(), 'audioTracks': audioTracks.map((e) => e.toJson()).toList(), 'expiresAt': expiresAt?.toIso8601String()};
  factory VideoSource.fromJson(Map<String, dynamic> j) => VideoSource(id: _s(j['id']), sourceId: _s(j['sourceId']), mediaId: _s(j['mediaId']), episodeId: j['episodeId']?.toString(), url: _s(j['url']), quality: _s(j['quality']),
    format: VideoFormat.values.firstWhere((e) => e.name == j['format'], orElse: () => VideoFormat.unknown), headers: _sm(j['headers']),
    subtitles: j['subtitles'] is List ? (j['subtitles'] as List).whereType<Map>().map((e) => SubtitleTrack.fromJson(Map<String, dynamic>.from(e))).toList() : const [],
    audioTracks: j['audioTracks'] is List ? (j['audioTracks'] as List).whereType<Map>().map((e) => AudioTrack.fromJson(Map<String, dynamic>.from(e))).toList() : const [], expiresAt: _dt(j['expiresAt']));
}
class PlaybackHistory {
  final String mediaId; final String? episodeId; final String title; final Duration position; final Duration duration; final DateTime lastPlayedAt; final String playerKernelId; final bool completed;
  const PlaybackHistory({required this.mediaId, this.episodeId, this.title = '', this.position = Duration.zero, this.duration = Duration.zero, required this.lastPlayedAt, this.playerKernelId = '', this.completed = false});
  double get progress => duration.inMilliseconds <= 0 ? 0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1).toDouble();
  PlaybackHistory copyWith({Duration? position, Duration? duration, DateTime? lastPlayedAt, bool? completed, String? title}) => PlaybackHistory(mediaId: mediaId, episodeId: episodeId, title: title ?? this.title, position: position ?? this.position, duration: duration ?? this.duration, lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt, playerKernelId: playerKernelId, completed: completed ?? this.completed);
  Map<String, dynamic> toJson() => {'mediaId': mediaId, 'episodeId': episodeId, 'title': title, 'positionMs': position.inMilliseconds, 'durationMs': duration.inMilliseconds, 'lastPlayedAt': lastPlayedAt.toIso8601String(), 'playerKernelId': playerKernelId, 'completed': completed};
  factory PlaybackHistory.fromJson(Map<String, dynamic> j) => PlaybackHistory(mediaId: _s(j['mediaId']), episodeId: j['episodeId']?.toString(), title: _s(j['title']), position: Duration(milliseconds: _i(j['positionMs'])), duration: Duration(milliseconds: _i(j['durationMs'])), lastPlayedAt: _dt(j['lastPlayedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0), playerKernelId: _s(j['playerKernelId']), completed: _b(j['completed']));
}
typedef PlaybackSession = PlaybackHistory;
class Collection {
  final String id; final String name; final DateTime createdAt;
  const Collection({required this.id, required this.name, required this.createdAt});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'createdAt': createdAt.toIso8601String()};
  factory Collection.fromJson(Map<String, dynamic> j) => Collection(id: _s(j['id']), name: _s(j['name']), createdAt: _dt(j['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0));
}
class Favorite {
  final String mediaId; final String collectionId; final String note; final DateTime createdAt; final int revision; final DateTime updatedAt; final String deviceId; final Map<String, dynamic> mediaSnapshot;
  const Favorite({required this.mediaId, this.collectionId = 'default', this.note = '', required this.createdAt, this.revision = 1, required this.updatedAt, this.deviceId = '', this.mediaSnapshot = const {}});
  Favorite copyWith({String? note, String? collectionId, int? revision, DateTime? updatedAt}) => Favorite(mediaId: mediaId, collectionId: collectionId ?? this.collectionId, note: note ?? this.note, createdAt: createdAt, revision: revision ?? this.revision, updatedAt: updatedAt ?? this.updatedAt, deviceId: deviceId, mediaSnapshot: mediaSnapshot);
  Map<String, dynamic> toJson() => {'mediaId': mediaId, 'collectionId': collectionId, 'note': note, 'createdAt': createdAt.toIso8601String(), 'revision': revision, 'updatedAt': updatedAt.toIso8601String(), 'deviceId': deviceId, 'mediaSnapshot': mediaSnapshot};
  factory Favorite.fromJson(Map<String, dynamic> j) => Favorite(mediaId: _s(j['mediaId']), collectionId: _s(j['collectionId'], 'default'), note: _s(j['note']), createdAt: _dt(j['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0), revision: _i(j['revision'], 1), updatedAt: _dt(j['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0), deviceId: _s(j['deviceId']), mediaSnapshot: j['mediaSnapshot'] is Map ? Map<String, dynamic>.from(j['mediaSnapshot'] as Map) : const {});
}
