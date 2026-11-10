import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';

import 'legado_dom.dart';
import 'legado_http.dart';
import 'legado_js_prelude.dart';
import 'login_info.dart';

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
  LegadoJsHost._(
    this.sourceId,
    this._jsLib,
    this._sourceName,
    this._loginUrl,
    this._loginUiRaw,
  );

  final String sourceId;
  final String? _jsLib;
  final String _sourceName;

  /// Batch 169: the source's raw loginUi declaration
  /// (list or JSON string), used to materialize the
  /// login-info map scripts read.
  final dynamic _loginUiRaw;

  /// Batch 169: where browser requests from rule scripts
  /// go (java.startBrowserAwait). The login page registers
  /// itself while open; null means "no surface available"
  /// and requests resolve as handled-empty.
  static Future<void> Function(String url, String title)? browseHandler;

  /// Batch 162: the source's loginUrl script text, bound
  /// as `source.loginUrl` on every run. Sources eval() it
  /// from their search/explore scripts to set up shared
  /// globals (霹雳书屋's `sz` / `url`); without the binding
  /// the eval silently did nothing and the script died
  /// with "'sz' is not defined".
  final String _loginUrl;

  JavascriptRuntime? _runtime;
  String? _initError;

  /// java.put/java.get variables, mirrored in and out of
  /// each run (JSON-safe values only in this subset).
  final Map<String, dynamic> vars = {};

  /// Batch 157: the source's JS memory cache (cache.get /
  /// cache.put in rule scripts), mirrored in and out of
  /// each run like [vars].
  final Map<String, dynamic> cacheStore = {};

  /// Batch 157: per-book variable stores (book.getVariable
  /// / setVariable), keyed by the run's baseUrl — bookInfo,
  /// TOC and content runs for one book share a baseUrl
  /// lineage closely enough for this subset.
  final Map<String, Map<String, dynamic>> _bookVarsByBase = {};

  static final Map<String, LegadoJsHost> _cache = {};
  static const _maxHosts = 3;

  static LegadoJsHost forSource(
    String sourceId,
    String? jsLib, {
    String sourceName = '',
    String loginUrl = '',
    dynamic loginUi,
  }) {
    final existing = _cache.remove(sourceId);
    if (existing != null) {
      _cache[sourceId] = existing;
      return existing;
    }
    final host = LegadoJsHost._(sourceId, jsLib, sourceName, loginUrl, loginUi);
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
    // Batch 169: the login script's function declarations
    // join the shared scope (helpers declared there are
    // called from library and template code — the filter
    // builder is the canonical case). Failures are
    // swallowed: a login script that cannot eval must not
    // take the source's ordinary rules down with it, and
    // scripts can still eval() the raw text themselves.
    final loginCode = _loginScriptCode;
    if (loginCode.isNotEmpty) {
      try {
        runtime.evaluate(loginCode);
      } catch (_) {
        // See above.
      }
    }
    _runtime = runtime;
    return runtime;
  }

  /// The loginUrl field as executable code: the '@js:'
  /// body or the first js block's contents; a plain URL
  /// yields nothing.
  String get _loginScriptCode {
    final text = _loginUrl.trim();
    if (text.startsWith('@js:')) return text.substring(4).trim();
    final match = RegExp(r'<js>([\s\S]*?)</js>').firstMatch(text);
    return match?.group(1)?.trim() ?? '';
  }

  /// The loginUrl text as rule scripts consume it: a
  /// leading '@js:' marker is rule syntax, and eval() of
  /// the raw field would die on it, so it is stripped.
  String get _exposedLoginUrl {
    final text = _loginUrl.trim();
    return text.startsWith('@js:') ? text.substring(4).trim() : text;
  }

  static Map<String, dynamic>? _decodeLoginMap(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // Unparseable stored info reads as no info.
    }
    return null;
  }

  /// Batch 161: the failing script's head, flattened to a
  /// single line. Error reports from devices carry only the
  /// error text, and messages like "not a function" or
  /// "'sz' is not defined" cannot be traced without the
  /// code that raised them.
  static String _codeSnippet(String code) {
    final flat = code.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Batch 166: 160 chars cut the Qidian search script off
    // before its failing call twice in a row; whole scripts
    // in the wild run a few hundred chars, so carry 1000.
    return flat.length <= 1000 ? flat : '${flat.substring(0, 1000)}…';
  }

  /// Batch 170: the book/chapter snapshots as the most
  /// recent run left them (scripts may rewrite fields —
  /// book.tocUrl above all). The engine reads these after
  /// a flow's runs to adopt rewrites.
  Map<String, dynamic>? lastBookData;
  Map<String, dynamic>? lastChapterData;

  /// Batch 173: the flow-persistent infoMap the reference
  /// binds into explore/URL scripts (filter state rides
  /// in it). Kept on the host so it survives across runs
  /// of the same source, adopted back from every envelope.
  final Map<String, dynamic> infoMap = {};

  static final _bindingName = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// Run one rule script. [result] is bound as the JS global
  /// `result` (a JSON value, a raw string, or null); [domJson]
  /// is the serialized page for java.getElements; [baseUrl]
  /// is bound as `baseUrl`. Returns the decoded JS value
  /// (Maps/Lists/Strings/nums/null; DOM elements come back as
  /// {'__elHtml': ...} maps for the engine to rehydrate).
  ///
  /// Batch 170: [bindings] adds flow globals (key/page/
  /// title/src/nextChapterUrl…), [book]/[chapter] are the
  /// current entity snapshots merged onto the long-lived
  /// JS objects, and [strResponse] binds `result` to a
  /// response-shaped object instead (login checks).
  Future<dynamic> run({
    required String code,
    dynamic result,
    Map<String, dynamic>? domJson,
    required String baseUrl,
    Map<String, String> sourceHeaders = const {},
    Map<String, dynamic> bindings = const {},
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
    ({String body, String url, int code})? strResponse,
  }) async {
    final runtime = _ensureRuntime();
    final netCache = <String, Map<String, dynamic>>{};
    final docCache = <String, Map<String, dynamic>>{};
    final browseCache = <String, String>{};
    // Batch 169: the login info this run's scripts see —
    // raw string exactly as saved (null when never saved),
    // map materialized from the declared form rows.
    final loginRows = LoginUi.parse(_loginUiRaw);
    final loginRaw = NovelLoginInfo.rawFor(sourceId);
    final Map<String, dynamic>? loginMap = loginRows.isNotEmpty
        ? NovelLoginInfo.valuesFor(sourceId, loginRows)
        : _decodeLoginMap(loginRaw);

    for (var round = 0; round < 7; round++) {
      final jar = LegadoHttp.jarSnapshot();
      final script = StringBuffer()
        ..writeln('__netCache = ${jsonEncode(netCache)};')
        ..writeln('__docCache = ${jsonEncode(docCache)};')
        ..writeln('__browseCache = ${jsonEncode(browseCache)};')
        ..writeln('__loginInfoRaw = ${jsonEncode(loginRaw)};')
        ..writeln('__loginInfoMap = ${jsonEncode(loginMap)};')
        ..writeln('var infoMap = ${jsonEncode(infoMap)};')
        ..writeln('__vars = ${jsonEncode(vars)};')
        ..writeln('__cookies = ${jsonEncode(jar)};')
        ..writeln('__cookieWrites = [];')
        ..writeln('__cacheStore = ${jsonEncode(cacheStore)};')
        ..writeln('__bookVars = ${jsonEncode(_bookVarsByBase[baseUrl] ?? const <String, dynamic>{})};')
        ..writeln('source.__key = ${jsonEncode(sourceId)};')
        ..writeln('source.bookSourceName = ${jsonEncode(_sourceName)};')
        ..writeln('source.bookSourceUrl = ${jsonEncode(sourceId)};')
        ..writeln('source.loginUrl = ${jsonEncode(_exposedLoginUrl)};')
        ..writeln('__doc = ${jsonEncode(domJson ?? const {'t': '#root', 'a': <String, String>{}, 'c': <dynamic>[]})};')
        ..writeln(
          strResponse == null
              ? 'var result = ${jsonEncode(result)};'
              : 'var result = __strResponse(${jsonEncode(strResponse.body)}, ${jsonEncode(strResponse.url)}, ${strResponse.code});',
        )
        ..writeln('var baseUrl = ${jsonEncode(baseUrl)};')
        ..writeAll([
          for (final e in bindings.entries)
            if (_bindingName.hasMatch(e.key))
              'var ${e.key} = ${jsonEncode(e.value)};\n',
          if (book != null)
            '__mergeSnapshot(book, ${jsonEncode(book)}, "book");\n',
          if (chapter != null)
            '__mergeSnapshot(chapter, ${jsonEncode(chapter)}, "chapter");\n',
        ])
        ..writeln('var __out = null, __err = null;')
        ..writeln('try { __out = eval(${jsonEncode(code)}); }')
        ..writeln('catch (e) { __err = (e && e.message) ? String(e.message) : String(e); }')
        ..writeln('JSON.stringify({out: __out === undefined ? null : __out, err: __err, vars: __vars, cookies: __cookieWrites, cache: __cacheStore, bookVars: __bookVars, bookData: __snapshotOut("book", book), chapterData: __snapshotOut("chapter", chapter), infoMap: infoMap});');
      final evaluated = runtime.evaluate(script.toString());
      if (evaluated.isError) {
        throw StateError(
          '书源 JS 运行失败：${evaluated.stringResult}'
          '（脚本：${_codeSnippet(code)}）',
        );
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
      final newCache = envelope['cache'];
      if (newCache is Map) {
        cacheStore
          ..clear()
          ..addAll(newCache.cast<String, dynamic>());
      }
      final newBookVars = envelope['bookVars'];
      if (newBookVars is Map) {
        _bookVarsByBase[baseUrl] = newBookVars.cast<String, dynamic>();
      }
      if (envelope['infoMap'] is Map) {
        infoMap
          ..clear()
          ..addAll((envelope['infoMap'] as Map).cast<String, dynamic>());
      }
      if (book != null && envelope['bookData'] is Map) {
        lastBookData = (envelope['bookData'] as Map).cast<String, dynamic>();
      }
      if (chapter != null && envelope['chapterData'] is Map) {
        lastChapterData =
            (envelope['chapterData'] as Map).cast<String, dynamic>();
      }
      await _applyCookieWrites(envelope['cookies']);
      final err = envelope['err']?.toString();
      if (err == null) return envelope['out'];
      if (err.startsWith('__LEGADO_BROWSE__')) {
        // Batch 169: a script asked to open a page. Route
        // it to the registered surface (the login page);
        // with none registered the request resolves as
        // handled-empty and the script continues.
        final payload =
            jsonDecode(err.substring('__LEGADO_BROWSE__'.length));
        final url = payload['url']?.toString() ?? '';
        final handler = browseHandler;
        if (handler != null && url.isNotEmpty) {
          await handler(url, payload['title']?.toString() ?? '');
        }
        browseCache[url] = '';
        continue;
      }
      if (err.startsWith('__LEGADO_DOC__')) {
        // Batch 168: java.setContent asked for a document
        // the host has not parsed yet — parse it Dart-side
        // and replay with the doc cache warm.
        final payload = jsonDecode(err.substring('__LEGADO_DOC__'.length));
        final key = payload['key']?.toString() ?? '';
        final html = payload['html']?.toString() ?? '';
        docCache[key] =
            LegadoDom.serializeDocument(LegadoDom.parseHtml(html));
        continue;
      }
      if (!err.startsWith('__LEGADO_NET__')) {
        throw StateError('书源 JS 报错：$err（脚本：${_codeSnippet(code)}）');
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
      final payloadHeaders = payload['headers'];
      final hasHeaders = payloadHeaders is Map && payloadHeaders.isNotEmpty;
      final cacheKey = method == 'GET'
          ? (hasHeaders
              ? 'GET|$url||${jsonEncode(payloadHeaders)}'
              : 'GET|$url||')
          : 'POST|$url|$body|${jsonEncode(payloadHeaders ?? const {})}';
      netCache[cacheKey] = {
        'code': response.statusCode,
        'body': response.body,
      };
    }
    throw StateError('书源 JS 网络请求次数过多');
  }

  /// Batch 157: apply the cookie writes a script collected
  /// (cookie.setKey / setCookie / removeKey / removeCookie)
  /// to the shared jar, through the same parsing the HTTP
  /// layer uses for real Set-Cookie headers.
  Future<void> _applyCookieWrites(dynamic writes) async {
    if (writes is! List) return;
    for (final w in writes) {
      if (w is! Map) continue;
      final op = w['op']?.toString();
      final url = w['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      switch (op) {
        case 'raw':
          final raw = w['raw']?.toString() ?? '';
          if (raw.isNotEmpty) await LegadoHttp.storeCookies(url, [raw]);
        case 'set':
          await LegadoHttp.storeCookies(
            url,
            ['${w['name']}=${w['value']}'],
          );
        case 'del':
          await LegadoHttp.storeCookies(url, ['${w['name']}=deleted']);
        case 'clear':
          final host = Uri.tryParse(url)?.host ?? '';
          if (host.isNotEmpty) await LegadoHttp.clearCookiesFor(host);
      }
    }
  }
}
