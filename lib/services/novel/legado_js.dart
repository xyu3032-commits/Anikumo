import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';

import 'legado_http.dart';
import 'legado_js_prelude.dart';

/// QuickJS host for one Legado source's rule JS.
///
/// Legado's Rhino bridge is synchronous (java.post returns a
/// response inline). QuickJS here is synchronous too, but
/// Dart HTTP is not — so network calls from JS throw a
/// marked error; the host performs the request, caches the
/// response, and re-runs the whole script with the cache
/// warm (see the prelude). Rule scripts are pure functions
/// of the page plus responses, so replay is deterministic.
///
/// Hosts are kept in a small LRU (3) like the manga JS
/// engine: creating a QuickJS runtime per call would lose
/// jsLib state (e.g. bilinovel's glyph `map`).
class LegadoJsHost {
  LegadoJsHost._(this.sourceId, this._jsLib);

  final String sourceId;
  final String? _jsLib;

  JavascriptRuntime? _runtime;
  String? _initError;

  /// java.put/java.get variables, mirrored in and out of
  /// each run (JSON-safe values only in this subset).
  final Map<String, dynamic> vars = {};

  static final Map<String, LegadoJsHost> _cache = {};
  static const _maxHosts = 3;

  static LegadoJsHost forSource(String sourceId, String? jsLib) {
    final existing = _cache.remove(sourceId);
    if (existing != null) {
      _cache[sourceId] = existing;
      return existing;
    }
    final host = LegadoJsHost._(sourceId, jsLib);
    _cache[sourceId] = host;
    while (_cache.length > _maxHosts) {
      final evicted = _cache.remove(_cache.keys.first);
      evicted?.dispose();
    }
    return host;
  }

  void dispose() {
    try {
      _runtime?.dispose();
    } catch (_) {}
    _runtime = null;
  }

  JavascriptRuntime _ensureRuntime() {
    if (_runtime != null) return _runtime!;
    final runtime = getJavascriptRuntime();
    final preludeResult = runtime.evaluate(legadoJsPrelude);
    if (preludeResult.isError) {
      _initError = '书源脚本桥初始化失败：${preludeResult.stringResult}';
      throw StateError(_initError!);
    }
    final lib = _jsLib;
    if (lib != null && lib.trim().isNotEmpty) {
      final libResult = runtime.evaluate(lib);
      if (libResult.isError) {
        _initError = '书源 jsLib 执行失败：${libResult.stringResult}';
        throw StateError(_initError!);
      }
    }
    _runtime = runtime;
    return runtime;
  }

  /// Run one rule script. [result] is bound as the JS global
  /// `result` (a JSON value, a raw string, or null); [domJson]
  /// is the serialized page for java.getElements; [baseUrl]
  /// is bound as `baseUrl`. Returns the decoded JS value
  /// (Maps/Lists/Strings/nums/null; DOM elements come back as
  /// {'__elHtml': ...} maps for the engine to rehydrate).
  Future<dynamic> run({
    required String code,
    dynamic result,
    Map<String, dynamic>? domJson,
    required String baseUrl,
    Map<String, String> sourceHeaders = const {},
  }) async {
    final runtime = _ensureRuntime();
    final netCache = <String, Map<String, dynamic>>{};

    for (var round = 0; round < 7; round++) {
      final script = StringBuffer()
        ..writeln('__netCache = ${jsonEncode(netCache)};')
        ..writeln('__vars = ${jsonEncode(vars)};')
        ..writeln('__doc = ${jsonEncode(domJson ?? const {'t': '#root', 'a': <String, String>{}, 'c': <dynamic>[]})};')
        ..writeln('var result = ${jsonEncode(result)};')
        ..writeln('var baseUrl = ${jsonEncode(baseUrl)};')
        ..writeln('var __out = null, __err = null;')
        ..writeln('try { __out = eval(${jsonEncode(code)}); }')
        ..writeln('catch (e) { __err = (e && e.message) ? String(e.message) : String(e); }')
        ..writeln('JSON.stringify({out: __out === undefined ? null : __out, err: __err, vars: __vars});');
      final evaluated = runtime.evaluate(script.toString());
      if (evaluated.isError) {
        throw StateError('书源 JS 运行失败：${evaluated.stringResult}');
      }
      final envelope = jsonDecode(evaluated.stringResult);
      if (envelope is! Map) {
        throw StateError('书源 JS 返回异常');
      }
      final newVars = envelope['vars'];
      if (newVars is Map) {
        vars
          ..clear()
          ..addAll(newVars.cast<String, dynamic>());
      }
      final err = envelope['err']?.toString();
      if (err == null) return envelope['out'];
      if (!err.startsWith('__LEGADO_NET__')) {
        throw StateError('书源 JS 报错：$err');
      }
      // Suspend-replay: perform the request the script
      // asked for, then re-run with the cache warm.
      final payload = jsonDecode(err.substring('__LEGADO_NET__'.length));
      final method = payload['method']?.toString() ?? 'GET';
      final url = payload['url']?.toString() ?? '';
      final body = payload['body']?.toString() ?? '';
      final headers = <String, String>{
        ...sourceHeaders,
        if (payload['headers'] is Map)
          for (final e in (payload['headers'] as Map).entries)
            e.key.toString(): e.value.toString(),
      };
      final response = await LegadoHttp.fetchRaw(
        url,
        method: method,
        body: body.isEmpty ? null : body,
        headers: {'user-agent': LegadoHttp.defaultUa, ...headers},
      );
      final cacheKey = method == 'GET'
          ? 'GET|$url||'
          : 'POST|$url|$body|${jsonEncode(payload['headers'] ?? const {})}';
      netCache[cacheKey] = {
        'code': response.statusCode,
        'body': response.body,
      };
    }
    throw StateError('书源 JS 网络请求次数过多');
  }
}
