import 'package:dio/dio.dart';
import 'package:anikumo/request/core/dio_factory.dart';
import 'package:anikumo/request/core/network_error_mapper.dart';
import 'package:anikumo/utils/dandan_credentials.dart';
import 'package:anikumo/utils/http_headers.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/crypto.dart';

class DanmakuClient {
  DanmakuClient._();

  /// Batch 25: whether usable DanDanPlay credentials exist
  /// (build-injected or user-filled in 设置 → 弹幕设置）. The
  /// API 403s every call without them, so the source sheet
  /// checks this BEFORE firing a doomed search and shows a
  /// setup guide instead of an auth-failure error page.
  static bool get hasCredentials {
    final envId = dandanCredentials['id'] ?? '';
    final envKey = dandanCredentials['value'] ?? '';
    if (envId.isNotEmpty && envKey.isNotEmpty) return true;
    return hasUserCredentials;
  }

  /// Batch 193: whether the user stored their own pair.
  /// The settings entry for it is gone, but a pair stored
  /// by an earlier version stays valid and keeps priority
  /// over the built-in pair, so this distinction now drives
  /// both signing and the built-in service gate.
  static bool get hasUserCredentials =>
      GStorage.getSetting(SettingsKeys.danmakuAppId).isNotEmpty &&
      GStorage.getSetting(SettingsKeys.danmakuAppKey).isNotEmpty;

  static final DanmakuClient instance = DanmakuClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uri = Uri.parse(url);
    // Batch 18: fall back to the user's own DanDanPlay
    // credentials (设置 → 弹幕设置） when the build injected
    // none — empty credentials make the API 403 everything.
    // Batch 193: the priority flipped to match every other
    // built-in key in the app — the user's own pair wins
    // over the build-carried pair.
    final envId = dandanCredentials['id'] ?? '';
    final envKey = dandanCredentials['value'] ?? '';
    final userId = GStorage.getSetting(SettingsKeys.danmakuAppId);
    final userKey = GStorage.getSetting(SettingsKeys.danmakuAppKey);
    final appId = userId.isNotEmpty ? userId : envId;
    final appKey = userKey.isNotEmpty ? userKey : envKey;
    final requestHeaders = <String, dynamic>{
      'user-agent': getRandomUA(),
      'referer': '',
      'X-Auth': 1,
      'X-AppId': appId,
      'X-Timestamp': timestamp,
      'X-Signature':
          generateDandanSignatureFor(appId, appKey, uri.path, timestamp),
      ...headers,
    };

    try {
      final response = await DioFactory.apiDio.get(
        url,
        queryParameters: queryParameters,
        options: Options(headers: requestHeaders),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  /// Batch 163: unsigned GET for endpoints that do not
  /// use the credential signature (the built-in service
  /// authenticates by its URL, not by headers).
  Future<dynamic> getPlain(
    String url, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await DioFactory.apiDio.get(
        url,
        queryParameters: queryParameters,
        options: Options(headers: {
          'user-agent': getRandomUA(),
          'referer': '',
        }),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }
}
