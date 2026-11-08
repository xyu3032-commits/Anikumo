import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Dart half of the Venera bridge: everything the JS
/// `sendMessage` forwards here (see venera_scripts.dart).
/// Requests and responses are JSON strings; the JS side parses
/// the returned string back into values.
class VeneraBridge {
  VeneraBridge._();

  static final Dio _dio = Dio(
    BaseOptions(
      // Batch 26: tightened from 15s/30s — a dead or
      // throttling source held its home section on a
      // skeleton for the better part of a minute. Source
      // payloads are small JSON; 10s/20s is ample.
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  /// Handles one bridge message; always returns a JSON
  /// string (never throws across the bridge). Batch 34: the
  /// caller is the qjs isolate's injected Dart function; the
  /// source key rides inside the message itself when the
  /// library provides one.
  static Future<String> handle(String rawMessage) async {
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map) return jsonEncode({'error': 'bad message'});
      message = decoded.cast<String, dynamic>();
    } catch (_) {
      return jsonEncode({'error': 'bad message json'});
    }
    try {
      return switch (message['method']) {
        'http' => await _http(message),
        'delay' => await _delay(message),
        'log' => _log(message),
        'random' => _random(message),
        'getLocale' => jsonEncode('zh-CN'),
        'getPlatform' => jsonEncode('android'),
        'getClipboard' => await _getClipboard(),
        'setClipboard' => await _setClipboard(message),
        // Batch 74: 'UI' never arrives here — the JS shim
        // routes it to the isolate's 'anikumoUi' channel,
        // which relays to MangaUiGateway on the UI isolate.
        _ => jsonEncode({'error': 'unsupported method: ${message['method']}'})
      };
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  /// Batch 101: 5-second in-memory cache for plain GET
  /// responses (the reference runtime's network layer does
  /// the same). A single screen often asks a source for the
  /// same JSON twice in one breath — a section load and its
  /// thumbnail pass, a detail open racing a prefetch — and
  /// every duplicate was a real round trip through a
  /// throttled site. Only bodiless GETs with a 200 are
  /// cached, keyed by URL + headers (cookies ride in the
  /// headers, so per-session variants stay distinct).
  static final Map<String, ({int at, String json})> _getCache = {};
  static const _getCacheTtlMs = 5000;
  static const _getCacheMaxEntries = 64;
  static const _getCacheMaxBody = 512 * 1024;

  static String _getCacheKey(String url, Map<String, dynamic> headers) {
    final names = headers.keys.toList()..sort();
    return '$url\n${names.map((n) => '$n=${headers[n]}').join('&')}';
  }

  static Future<String> _http(Map<String, dynamic> message) async {
    final method = message['http_method']?.toString() ?? 'GET';
    final url = message['url']?.toString() ?? '';
    final headers = <String, dynamic>{};
    final rawHeaders = message['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        headers[entry.key.toString()] = entry.value;
      }
    }
    final cacheable = method == 'GET' && message['data'] == null;
    final cacheKey = cacheable ? _getCacheKey(url, headers) : null;
    if (cacheKey != null) {
      final hit = _getCache[cacheKey];
      if (hit != null &&
          DateTime.now().millisecondsSinceEpoch - hit.at < _getCacheTtlMs) {
        return hit.json;
      }
    }
    dynamic data = message['data'];
    // Batch 41: `bytes: true` (Network.fetchBytes) takes the
    // binary path — the body crosses back base64-encoded in
    // body_b64 because the message channel is a JSON string.
    // The old plain-string body corrupted binary payloads
    // (hitomi's index files: "ArrayBuffer object expected").
    final wantBytes = message['bytes'] == true;
    try {
      final response = await _dio.request<dynamic>(
        url,
        data: data,
        options: Options(
          method: method,
          headers: headers,
          responseType: wantBytes ? ResponseType.bytes : ResponseType.plain,
          validateStatus: (_) => true,
          contentType: data is Map ? Headers.jsonContentType : null,
        ),
      );
      final responseHeaders = <String, dynamic>{};
      response.headers.forEach((name, values) {
        // set-cookie keeps its values separate (the JS mirror
        // splits them back into individual cookies).
        responseHeaders[name.toLowerCase()] =
            name.toLowerCase() == 'set-cookie' ? values : values.join(', ');
      });
      if (wantBytes) {
        final bytes = response.data;
        return jsonEncode({
          'status': response.statusCode ?? 0,
          'headers': responseHeaders,
          'body': '',
          'body_b64': bytes is List<int> ? base64Encode(bytes) : '',
        });
      }
      final encoded = jsonEncode({
        'status': response.statusCode ?? 0,
        'headers': responseHeaders,
        'body': response.data?.toString() ?? '',
      });
      // Batch 101: fill the short GET cache (see above).
      // Responses that SET cookies are never cached: they
      // are session/token issuers, and replaying one would
      // hand back the pre-rotation cookie and body.
      if (cacheKey != null &&
          (response.statusCode ?? 0) == 200 &&
          !responseHeaders.containsKey('set-cookie') &&
          encoded.length <= _getCacheMaxBody) {
        _getCache[cacheKey] = (
          at: DateTime.now().millisecondsSinceEpoch,
          json: encoded,
        );
        while (_getCache.length > _getCacheMaxEntries) {
          _getCache.remove(_getCache.keys.first);
        }
      }
      return encoded;
    } on DioException catch (e) {
      return jsonEncode({'error': '网络请求失败: ${e.message ?? e.type}'});
    }
  }

  static Future<String> _delay(Map<String, dynamic> message) async {
    final ms = (message['time'] as num?)?.toInt() ?? 0;
    if (ms > 0) {
      await Future<void>.delayed(Duration(milliseconds: ms));
    }
    return 'null';
  }

  static String _log(Map<String, dynamic> message) {
    debugPrint(
      '[venera:${message['key'] ?? '?'}] ${message['level'] ?? 'info'}: '
      '${message['content'] ?? message['message'] ?? ''}',
    );
    return 'null';
  }

  static String _random(Map<String, dynamic> message) {
    final random = Random();
    final min = (message['min'] as num?)?.toDouble() ?? 0;
    final max = (message['max'] as num?)?.toDouble() ?? 1;
    if (message['type'] == 'int') {
      final lo = min.toInt();
      final hi = max.toInt();
      final value = hi > lo ? lo + random.nextInt(hi - lo) : lo;
      return jsonEncode(value);
    }
    return jsonEncode(min + random.nextDouble() * (max - min));
  }

  static Future<String> _getClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return jsonEncode(data?.text ?? '');
  }

  static Future<String> _setClipboard(Map<String, dynamic> message) async {
    await Clipboard.setData(
      ClipboardData(text: message['text']?.toString() ?? ''),
    );
    return 'true';
  }
}
