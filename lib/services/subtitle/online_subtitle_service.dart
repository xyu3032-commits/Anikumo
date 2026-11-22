import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'package:anikumo/request/core/dio_factory.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/subtitle/subtitle_document.dart';

/// Batch 278: one search hit from the online subtitle
/// service (OpenSubtitles' public REST API — named here
/// in code only; the UI copy stays neutral per the
/// project's no-naming rule for outside services).
class OnlineSubtitleResult {
  const OnlineSubtitleResult({
    required this.fileId,
    required this.language,
    required this.format,
    required this.downloadCount,
    required this.release,
    required this.fileName,
  });

  /// The file id the download endpoint exchanges for a
  /// one-shot download link.
  final int fileId;
  final String language;

  /// 'srt' / 'ass' / 'vtt' / ... as reported (may be
  /// empty when the payload omits it — the file name
  /// then decides).
  final String format;
  final int downloadCount;
  final String release;
  final String fileName;

  /// The format the downloaded file should be treated
  /// as: the reported one, else the file name's
  /// extension, else SRT.
  String get effectiveFormat {
    if (format.isNotEmpty) return format.toLowerCase();
    final ext = p.extension(fileName).replaceAll('.', '').toLowerCase();
    return ext.isNotEmpty ? ext : 'srt';
  }
}

/// Batch 278: online subtitle search + download.
///
/// Bring-your-own key, stored exactly like the TMDB key
/// (settings storage only — see [SettingsKeys
/// .onlineSubtitleApiKey]); without one the service is
/// inert and the subtitle sheet says so instead of
/// offering a dead button. Every network failure throws
/// and the sheet turns it into a toast — nothing here
/// retries or logs the key.
class OnlineSubtitleService {
  OnlineSubtitleService._();

  static const String _apiBase = 'https://api.opensubtitles.com/api/v1';

  static String get apiKey =>
      GStorage.getSetting(SettingsKeys.onlineSubtitleApiKey).trim();

  static bool get hasKey => apiKey.isNotEmpty;

  /// The query parameters a search sends. Pure, so the
  /// request shape is unit-testable without a network.
  static Map<String, String> buildSearchParams({
    required String query,
    int? episode,
    int? season,
    String? languages,
  }) {
    return {
      'query': query,
      if (episode != null && episode > 0) 'episode_number': '$episode',
      if (season != null && season > 0) 'season_number': '$season',
      if (languages != null && languages.isNotEmpty)
        'languages': languages,
      'order_by': 'download_count',
      'order_direction': 'desc',
    };
  }

  /// Parses the search response's `data` rows into
  /// results, skipping anything malformed. Pure.
  static List<OnlineSubtitleResult> parseSearchResults(dynamic data) {
    final rows = data is Map ? data['data'] : null;
    if (rows is! List) return const [];
    final results = <OnlineSubtitleResult>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final attrs = row['attributes'];
      if (attrs is! Map) continue;
      final files = attrs['files'];
      if (files is! List || files.isEmpty) continue;
      final firstFile = files.first;
      if (firstFile is! Map) continue;
      final fileId = (firstFile['file_id'] as num?)?.toInt();
      if (fileId == null) continue;
      results.add(OnlineSubtitleResult(
        fileId: fileId,
        language: attrs['language']?.toString() ?? '',
        format: attrs['format']?.toString() ?? '',
        downloadCount: (attrs['download_count'] as num?)?.toInt() ?? 0,
        release: attrs['release']?.toString() ?? '',
        fileName: firstFile['file_name']?.toString() ?? '',
      ));
    }
    return results;
  }

  /// What a downloaded payload actually is, from its
  /// magic bytes first and its file name second: 'gz',
  /// 'zip', or a subtitle format ('srt', 'ass', ...).
  /// Pure.
  static String detectPayloadKind(List<int> bytes, String fileName) {
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      return 'gz';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      return 'zip';
    }
    final ext = p.extension(fileName).replaceAll('.', '').toLowerCase();
    if (ext == 'gz') return 'gz';
    if (ext == 'zip') return 'zip';
    return ext.isEmpty ? 'srt' : ext;
  }

  static const Set<String> _subtitleExtensions = {
    'srt',
    'ass',
    'ssa',
    'vtt',
    'sub',
  };

  /// Unwraps a downloaded payload into raw subtitle
  /// bytes: gunzips a .gz, extracts the first subtitle
  /// file out of a .zip, passes anything else through.
  /// Throws when a container holds no subtitle file.
  static List<int> extractSubtitleBytes(List<int> bytes, String fileName) {
    final kind = detectPayloadKind(bytes, fileName);
    if (kind == 'gz') {
      return gzip.decode(bytes);
    }
    if (kind == 'zip') {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? fallback;
      for (final file in archive.files) {
        if (!file.isFile) continue;
        fallback ??= file;
        final ext =
            p.extension(file.name).replaceAll('.', '').toLowerCase();
        if (_subtitleExtensions.contains(ext)) {
          return file.content as List<int>;
        }
      }
      if (fallback != null) return fallback.content as List<int>;
      throw const FormatException('No file inside subtitle archive');
    }
    return bytes;
  }

  static Map<String, String> get _headers => {
        'Api-Key': apiKey,
        'User-Agent': 'Anikumo v1',
        'Accept': 'application/json',
      };

  /// Searches subtitles for [query] (+ [episode] when
  /// known). Throws on transport/HTTP failure.
  static Future<List<OnlineSubtitleResult>> search({
    required String query,
    int? episode,
  }) async {
    final dio = DioFactory.apiDio;
    final response = await dio.get(
      '$_apiBase/subtitles',
      queryParameters: buildSearchParams(query: query, episode: episode),
      options: Options(headers: _headers),
    );
    return parseSearchResults(response.data);
  }

  /// Exchanges [result]'s file id for a download link,
  /// fetches the payload, unwraps and re-encodes it as
  /// UTF-8, and stages it in [dir] under a stable name.
  /// Returns the staged file, ready to mount through the
  /// player's external-subtitle path. Throws on any
  /// failure along the way.
  static Future<File> download(
    OnlineSubtitleResult result, {
    required Directory dir,
  }) async {
    final dio = DioFactory.apiDio;
    final linkResponse = await dio.post(
      '$_apiBase/download',
      data: {'file_id': result.fileId},
      options: Options(headers: _headers),
    );
    final linkData = linkResponse.data;
    final link = linkData is Map ? linkData['link']?.toString() : null;
    if (link == null || link.isEmpty) {
      throw const FormatException('Subtitle download link missing');
    }
    final fileResponse = await DioFactory.downloadDio.get<List<int>>(
      link,
      options: Options(responseType: ResponseType.bytes),
    );
    final raw = fileResponse.data;
    if (raw == null || raw.isEmpty) {
      throw const FormatException('Subtitle download was empty');
    }
    final stagedName = (linkData['file_name']?.toString().isNotEmpty ?? false)
        ? linkData['file_name'].toString()
        : result.fileName;
    final extracted = extractSubtitleBytes(raw, stagedName);
    final kind = detectPayloadKind(raw, stagedName);
    final format = _subtitleExtensions.contains(kind)
        ? kind
        : result.effectiveFormat;
    final text = decodeSubtitleBytes(extracted);
    final target = File(
      p.join(dir.path, 'anikumo_online_sub_${result.fileId}.$format'),
    );
    await target.writeAsString(text, encoding: utf8);
    AnikumoLogger()
        .i('OnlineSubtitle: staged ${result.fileId} as $format');
    return target;
  }
}
