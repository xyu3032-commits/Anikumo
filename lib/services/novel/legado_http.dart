import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';

import '../storage/storage.dart';
import 'legado_gbk.dart';
import 'legado_parse.dart';

/// One fetched page: body text plus the URL it finally came
/// from (after redirects), which relative links resolve
/// against.
class LegadoResponse {
  const LegadoResponse({
    required this.body,
    required this.url,
    required this.statusCode,
  });

  final String body;
  final String url;
  final int statusCode;
}

/// HTTP for Legado sources. A URL spec may carry a trailing
/// options object: method, body, headers/headerMap, and the
/// webView flag (accepted and ignored — pages here are
/// fetched as plain HTML; sources that truly need a rendered
/// WebView fail their rules and surface that honestly).
class LegadoHttp {
  LegadoHttp._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      responseType: ResponseType.bytes,
      validateStatus: (_) => true,
    ),
  );

  static const defaultUa =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  // ---- Batch 68: cookie jar --------------------------------
  //
  // Every request used to go out cookie-less and every
  // Set-Cookie was thrown away. Whole families of sources
  // need a session: login-gated sites （源注释自述「要登入
  // 才能用」) and ordinary sites that set a cookie on the
  // first visit and serve a different (empty) page without
  // it. The jar persists per domain in settings, is fed
  // by responses and by the WebView login page, and rides
  // on every fetch unless the caller set its own Cookie.

  static Map<String, Map<String, String>>? _jarCache;

  static Map<String, Map<String, String>> get _jar {
    final cached = _jarCache;
    if (cached != null) return cached;
    // Storage may be unavailable (early startup, headless
    // test harnesses): the jar then just starts empty —
    // a storage hiccup must never take fetching down.
    var raw = '';
    try {
      raw = GStorage.getSetting(SettingsKeys.novelCookieJarJson);
    } catch (_) {}
    final out = <String, Map<String, String>>{};
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            if (e.value is Map) {
              out[e.key.toString()] = {
                for (final c in (e.value as Map).entries)
                  c.key.toString(): c.value.toString(),
              };
            }
          }
        }
      } catch (_) {}
    }
    _jarCache = out;
    return out;
  }

  static Future<void> _saveJar() async {
    try {
      await GStorage.putSetting(
        SettingsKeys.novelCookieJarJson,
        jsonEncode(_jar),
      );
    } catch (_) {
      // In-memory jar keeps working for the session.
    }
  }

  /// The Cookie header value for [url] ('' when the jar
  /// has nothing for its host). A stored domain matches
  /// the host itself and its subdomains.
  static String cookieHeaderFor(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return '';
    final pairs = <String>[];
    for (final entry in _jar.entries) {
      if (host == entry.key || host.endsWith('.${entry.key}')) {
        for (final c in entry.value.entries) {
          pairs.add('${c.key}=${c.value}');
        }
      }
    }
    return pairs.join('; ');
  }

  /// Records Set-Cookie header values from a response to
  /// [url] (a Domain attribute re-keys the entry; an empty
  /// or "deleted" value removes the cookie).
  static Future<void> storeCookies(
    String url,
    List<String> setCookies,
  ) async {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty || setCookies.isEmpty) return;
    var changed = false;
    for (final header in setCookies) {
      final parts = header.split(';');
      final first = parts.first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      var domain = host;
      for (final attr in parts.skip(1)) {
        final kv = attr.trim().split('=');
        if (kv.length == 2 && kv[0].trim().toLowerCase() == 'domain') {
          domain = kv[1].trim().replaceFirst(RegExp(r'^\.'), '');
        }
      }
      if (name.isEmpty || domain.isEmpty) continue;
      final bucket = _jar.putIfAbsent(domain, () => {});
      if (value.isEmpty || value.toLowerCase() == 'deleted') {
        if (bucket.remove(name) != null) changed = true;
      } else if (bucket[name] != value) {
        bucket[name] = value;
        changed = true;
      }
    }
    if (changed) await _saveJar();
  }

  /// Imports cookies harvested elsewhere (the WebView
  /// login page) under [host].
  static Future<void> importCookies(
    String host,
    Map<String, String> cookies,
  ) async {
    if (host.isEmpty || cookies.isEmpty) return;
    _jar.putIfAbsent(host, () => {}).addAll(cookies);
    await _saveJar();
  }

  /// Drops every stored cookie for [host] (exact domain).
  static Future<void> clearCookiesFor(String host) async {
    if (_jar.remove(host) != null) await _saveJar();
  }

  /// How many cookies would ride on a request to [host].
  static int cookieCountFor(String host) {
    var n = 0;
    for (final entry in _jar.entries) {
      if (host == entry.key || host.endsWith('.${entry.key}')) {
        n += entry.value.length;
      }
    }
    return n;
  }

  /// Fetch [urlSpec] with the source-level [sourceHeaders]
  /// merged under any per-URL option headers.
  static Future<LegadoResponse> fetch(
    String urlSpec, {
    Map<String, String> sourceHeaders = const {},
  }) async {
    final (rawUrl, options) = LegadoParse.splitUrlOptions(urlSpec);
    final method =
        (options['method']?.toString() ?? 'GET').toUpperCase();
    // Case-insensitive merge: sources spell 'User-Agent'
    // while the default is lowercase — a naive map merge
    // would send BOTH and the wrong one can win (a real
    // 403 on dumanwu's book pages proved it).
    final merged = <String, (String, String)>{};
    void putHeader(String key, String value) =>
        merged[key.toLowerCase()] = (key, value);
    putHeader('user-agent', defaultUa);
    // Batch 47: browsers always send a same-origin Referer;
    // a share of imported sources 403 every request without
    // one. The source's own Referer (merged next) wins.
    final origin = Uri.tryParse(rawUrl);
    if (origin != null && origin.host.isNotEmpty) {
      putHeader('referer', '${origin.scheme}://${origin.host}/');
    }
    sourceHeaders.forEach(putHeader);
    final optHeaders = options['headers'] ?? options['headerMap'];
    if (optHeaders is Map) {
      optHeaders.forEach(
        (k, v) => putHeader(k.toString(), v.toString()),
      );
    }
    // Batch 50: never advertise encodings this stack cannot
    // decode. Several source defs (the builtin bilinovel
    // among them) ship browser-copied headers with
    // 'Accept-Encoding: gzip, deflate, br, zstd'; CDN edges
    // then answer zstd or br, dart:io only auto-decompresses
    // gzip, and the still-compressed bytes were decoded as
    // UTF-8 garbage — every rule on the page matched nothing
    // ("目录页没有匹配到章节", empty searches) while the
    // same pages worked in a browser. Real readers/browsers
    // only offer what they can inflate; force gzip last so
    // neither source nor per-URL headers can re-add the rest.
    putHeader('accept-encoding', 'gzip');
    final headers = {
      for (final entry in merged.values) entry.$1: entry.$2,
    };
    // Batch 31: a source may declare charset gbk/gb2312 —
    // the site then expects GBK-encoded keywords (request)
    // and serves GBK pages (response). Both directions are
    // handled in the fetch below via this flag.
    final charset = (options['charset']?.toString() ?? '').toLowerCase();
    final gbk = charset.contains('gb');
    var url = rawUrl;
    var body = options['body']?.toString();
    if (gbk) {
      await Gb2312.ensureLoaded();
      url = Gb2312.percentEncodeNonAscii(url);
      if (body != null) body = Gb2312.percentEncodeNonAscii(body);
    }
    return fetchRaw(
      url,
      method: method,
      body: body,
      headers: headers,
      forceGbkDecode: gbk,
    );
  }

  /// Fetch a concrete URL with an explicit method/body —
  /// used by the JS bridge's suspend-replay for java.post /
  /// java.ajax, and by [fetch] itself.
  // Batch 47: per-host request pacing. The multi-source
  // home and search-all fire bursts at the same host in the
  // same instant; a share of these sites answer bursts with
  // 403/503 where a paced request succeeds. Starts to the
  // same host are spaced by [_hostInterval]; bodies still
  // run concurrently once started.
  static const _hostInterval = Duration(milliseconds: 350);
  static final Map<String, Future<void>> _hostGates = {};
  static final Map<String, int> _hostLastStart = {};

  static Future<void> _pace(String url) async {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return;
    final previous = _hostGates[host] ?? Future<void>.value();
    final gate = Completer<void>();
    _hostGates[host] = gate.future;
    try {
      await previous;
      final now = DateTime.now().millisecondsSinceEpoch;
      final waitMs =
          _hostInterval.inMilliseconds - (now - (_hostLastStart[host] ?? 0));
      if (waitMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      }
      _hostLastStart[host] = DateTime.now().millisecondsSinceEpoch;
    } finally {
      gate.complete();
    }
  }

  static Future<LegadoResponse> fetchRaw(
    String url, {
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
    bool forceGbkDecode = false,
  }) async {
    await _pace(url);
    // One retry on timeouts: mobile CDNs (and some of these
    // source sites) drop first connections often enough that
    // reader apps retry as a matter of course.
    try {
      return await _fetchRawOnce(url,
          method: method,
          body: body,
          headers: headers,
          forceGbkDecode: forceGbkDecode);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        return _fetchRawOnce(url,
            method: method,
            body: body,
            headers: headers,
            forceGbkDecode: forceGbkDecode);
      }
      rethrow;
    }
  }

  static Future<LegadoResponse> _fetchRawOnce(
    String url, {
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
    bool forceGbkDecode = false,
    bool encodingRetried = false,
  }) async {
    // Batch 68: attach the jar's cookies unless the caller
    // set its own Cookie header for this request.
    final effectiveHeaders = Map<String, String>.of(headers);
    if (!effectiveHeaders.keys
        .any((k) => k.toLowerCase() == 'cookie')) {
      final cookie = cookieHeaderFor(url);
      if (cookie.isNotEmpty) effectiveHeaders['Cookie'] = cookie;
    }
    final lower = <String, String>{};
    effectiveHeaders.forEach((k, v) => lower[k.toLowerCase()] = v);
    final response = await _dio.request<List<int>>(
      url,
      data: method == 'GET' ? null : body,
      options: Options(
        method: method,
        headers: effectiveHeaders,
        contentType: lower['content-type'] ??
            (method == 'POST'
                ? 'application/x-www-form-urlencoded'
                : null),
      ),
    );
    // Batch 68: harvest whatever the response set.
    final setCookies = response.headers.map['set-cookie'];
    if (setCookies != null && setCookies.isNotEmpty) {
      await storeCookies(url, setCookies);
    }
    var bytes = response.data ?? const <int>[];
    // Batch 50: compression guard. fetch() forces
    // 'Accept-Encoding: gzip', but the JS bridge calls
    // fetchRaw directly and a stubborn edge can still answer
    // with an encoding dart:io did not inflate. Detect by
    // header and by magic bytes; inflate gzip ourselves
    // when it slipped through, and renegotiate ONCE for
    // zstd/br instead of feeding compressed bytes to the
    // HTML parser as garbage text.
    final encoding =
        (response.headers.value('content-encoding') ?? '').toLowerCase();
    bool hasMagic(List<int> magic) {
      if (bytes.length < magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) return false;
      }
      return true;
    }
    const zstdMagic = [0x28, 0xB5, 0x2F, 0xFD];
    if (hasMagic(const [0x1F, 0x8B])) {
      try {
        bytes = io.gzip.decode(bytes);
      } catch (_) {
        // Not actually gzip — fall through with raw bytes.
      }
    } else if (encoding.contains('zstd') ||
        encoding.contains('br') ||
        hasMagic(zstdMagic)) {
      if (!encodingRetried) {
        final renegotiated = Map<String, String>.of(headers);
        renegotiated.removeWhere(
            (k, _) => k.toLowerCase() == 'accept-encoding');
        renegotiated['Accept-Encoding'] = 'gzip';
        return _fetchRawOnce(
          url,
          method: method,
          body: body,
          headers: renegotiated,
          forceGbkDecode: forceGbkDecode,
          encodingRetried: true,
        );
      }
      throw StateError('源站返回了无法解码的压缩格式（$encoding），已重试仍失败');
    }
    final text = await _decodeBody(
      bytes,
      response.headers.map['content-type'],
      forceGbk: forceGbkDecode,
    );
    return LegadoResponse(
      body: text,
      url: response.realUri.toString(),
      statusCode: response.statusCode ?? 0,
    );
  }

  /// Decode a body: GBK/GB2312 when the source declared it
  /// (forceGbk), when the Content-Type says so, or when the
  /// page's own <meta charset> does (batch 31 — detail/TOC/
  /// content pages of GBK sources carry no charset option of
  /// their own, the meta tag is the only signal there).
  /// Otherwise UTF-8 with malformed tolerance so a mislabeled
  /// page still yields text instead of throwing.
  static Future<String> _decodeBody(
    List<int> bytes,
    List<String>? contentType, {
    bool forceGbk = false,
  }) async {
    var charset = '';
    if (contentType != null) {
      for (final value in contentType) {
        final m = RegExp(r'charset=([\w-]+)').firstMatch(value);
        if (m != null) charset = (m.group(1) ?? '').toLowerCase();
      }
    }
    var gbk = forceGbk || charset.contains('gb');
    if (!gbk && bytes.length > 32) {
      // Meta sniff over the first 2KB (ASCII-safe region).
      final head = latin1.decode(
        bytes.sublist(0, bytes.length > 2048 ? 2048 : bytes.length),
        allowInvalid: true,
      );
      final compact = head
          .toLowerCase()
          .replaceAll(RegExp(r'[\s"]'), '')
          .replaceAll("'", '');
      if (compact.contains('charset=gb')) {
        gbk = true;
      }
    }
    if (gbk) {
      await Gb2312.ensureLoaded();
      return Gb2312.decode(bytes);
    }
    if (charset.contains('iso-8859') || charset.contains('latin')) {
      return latin1.decode(bytes, allowInvalid: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
