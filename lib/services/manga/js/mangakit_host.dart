import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/services/manga/js/manga_ui_gateway.dart';
import 'package:anikumo/services/manga/js/mangakit_image_registry.dart';
import 'package:anikumo/services/manga/js/venera_engine.dart';

/// Batch 198: an error surfaced from the MangaKit runtime,
/// carrying the framework's stable error code (e.g.
/// MK_VERIFICATION_REQUIRED) so the UI can react precisely
/// instead of string-matching messages.
class MangaKitException implements Exception {
  const MangaKitException(this.code, this.message);

  final String code;
  final String message;

  bool get isVerificationRequired => code == 'MK_VERIFICATION_REQUIRED';

  @override
  String toString() => message.isEmpty ? code : message;
}

/// Batch 198: the production MangaKit host. One QuickJS
/// runtime for the whole manga zone (the framework is built
/// for a shared runtime with per-source isolation), loaded
/// with the MangaKit bundle and driven through the bridge
/// protocol v1: a single injected native function
/// (`__mkNative`) shaped by a JS bootstrap into the
/// `__mangakitHost` object, plus a synchronous image-op
/// function (`__mkImageSync`) backing modifyImage snippets.
///
/// Bridge backing stores deliberately reuse the legacy
/// engine's persistence (per-source KV and the shared cookie
/// jar live in the same settings entries), so source data,
/// settings, logins and earned anti-bot cookies survive the
/// engine swap untouched.
class MangaKitRuntime {
  MangaKitRuntime._();

  static final MangaKitRuntime instance = MangaKitRuntime._();

  /// Set by the manga module: opens a WebView for [url] so
  /// the USER personally clears the verification wall; the
  /// implementation plants the harvested cookies into this
  /// runtime's jar (see [plantCookies]) and returns whether
  /// the user completed the flow. Null = no UI available
  /// (background/tests): solves report unsolved and callers
  /// surface MK_VERIFICATION_REQUIRED instead.
  static Future<bool> Function({required String url, required String kind})?
  onSolveVerification;

  // Batch 253: the QuickJS runtime now lives in a
  // dedicated isolate. It used to run on the UI isolate
  // (batch 198), so every framework call — the bundle
  // eval at start-up and each explore/search call's
  // HTML parsing — executed synchronously on the UI
  // thread; entering the zone fired a warm-up plus a
  // home rail plus up to ten source bands into it and
  // the zone stuttered for seconds. The legacy engine
  // moved behind an isolate host earlier (QjsEngineHost);
  // MangaKit follows the same shape. Everything stateful
  // stays on THIS side: the bridge services
  // (_handleNative: http / store / cookies / ui / log)
  // run here unchanged, the isolate only evaluates JS
  // and calls back for them, and the synchronous image
  // ops stay local to the isolate (pure Dart CPU work).
  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _receive;
  Completer<void>? _ready;
  Future<void>? _starting;
  int _seq = 0;
  final Map<int, Completer<String>> _tasks = {};

  final Map<String, Future<Map<String, dynamic>>> _registrations = {};
  final Map<String, void Function(Map<String, dynamic> section)> _sectionSinks =
      {};
  var _sectionSeq = 0;

  bool get started => _port != null;

  Future<void> ensureStarted() {
    if (_port != null) return Future<void>.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    final bundle = await rootBundle.loadString('assets/mangakit/mangakit.js');
    final receive = ReceivePort();
    _receive = receive;
    final ready = Completer<void>();
    _ready = ready;
    receive.listen(_onMessage);
    final exitPort = ReceivePort();
    exitPort.listen((_) => _onIsolateGone());
    _isolate = await Isolate.spawn(
      _mangakitIsolateMain,
      _MkInit(receive.sendPort, _hostBootstrapJs, bundle),
      debugName: 'anikumo-mangakit-engine',
      onExit: exitPort.sendPort,
    );
    await ready.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _killIsolate();
        throw TimeoutException('MangaKit 引擎启动超时');
      },
    );
  }

  void _killIsolate() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port = null;
    _receive?.close();
    _receive = null;
  }

  /// The engine isolate died (killed / crashed): fail
  /// everything in flight and forget registrations, so
  /// the next call respawns a clean runtime and sources
  /// re-register from their stored code.
  void _onIsolateGone() {
    _isolate = null;
    _port = null;
    _receive?.close();
    _receive = null;
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('MangaKit 引擎进程退出'));
    }
    final pending = _tasks.values.toList();
    _tasks.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('MangaKit 引擎进程退出'));
      }
    }
    _registrations.clear();
  }

  void _onMessage(dynamic message) {
    if (message is! List || message.isEmpty) return;
    switch (message[0]) {
      case 'ready':
        _port = message[1] as SendPort;
        _ready?.complete();
      case 'startError':
        final ready = _ready;
        if (ready != null && !ready.isCompleted) {
          ready.completeError(StateError('MangaKit 引擎启动失败：${message[1]}'));
        }
      case 'result':
        final completer = _tasks.remove(message[1] as int);
        if (completer == null) return;
        if (message[2] == true) {
          completer.complete(message[3]?.toString() ?? '');
        } else {
          completer.completeError(StateError('MangaKit 调用失败：${message[3]}'));
        }
      case 'native':
        final seq = message[1] as int;
        final group = message[2]?.toString() ?? '';
        final method = message[3]?.toString() ?? '';
        final envelopeJson = message[4]?.toString() ?? '{}';
        unawaited(() async {
          final reply = await _handleNative(group, method, envelopeJson);
          _port?.send(['nativeResult', seq, reply]);
        }());
    }
  }

  /// One evaluation inside the engine isolate: sets the
  /// given string globals, evaluates [js], awaits a
  /// returned promise, and answers with the result as a
  /// string (every kit-level snippet stringifies its own
  /// envelope).
  Future<String> _evalRaw(
    String js, {
    Map<String, String> globals = const {},
  }) async {
    await ensureStarted();
    final port = _port;
    if (port == null) throw StateError('MangaKit 运行时尚未启动');
    final seq = ++_seq;
    final completer = Completer<String>();
    _tasks[seq] = completer;
    port.send(['eval', seq, globals, js]);
    return completer.future;
  }

  /// Evaluate JS in the engine isolate; a returned
  /// Promise is awaited there.
  Future<dynamic> evalJson(String js) => _evalRaw(js);

  /// Runs one kit-level JS expression expected to produce a
  /// `{ok, ...}` / `{ok:0, error:{code,message}}` JSON
  /// envelope string; unwraps it into a Map or throws a
  /// [MangaKitException].
  Future<Map<String, dynamic>> _evalEnvelope(
    String js, {
    Map<String, String> globals = const {},
  }) async {
    final raw = await _evalRaw(js, globals: globals);
    final text = raw;
    Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('bad envelope');
      envelope = decoded.cast<String, dynamic>();
    } catch (_) {
      throw MangaKitException('MK_HOST_CALL_FAILED', '引擎返回了无法识别的结果：$text');
    }
    if (envelope['ok'] == 1 || envelope['ok'] == true) return envelope;
    final error = envelope['error'];
    if (error is Map) {
      throw MangaKitException(
        error['code']?.toString() ?? 'MK_HOST_CALL_FAILED',
        error['message']?.toString() ?? '引擎调用失败',
      );
    }
    throw const MangaKitException('MK_HOST_CALL_FAILED', '引擎调用失败');
  }

  /// Registers a Venera-format source file with the
  /// framework's compat layer. Idempotent per [jsKey]; the
  /// result is the registration envelope
  /// ({manifest, diagnostics}).
  Future<Map<String, dynamic>> registerVeneraSource(String jsKey, String code) {
    final existing = _registrations[jsKey];
    if (existing != null) return existing;
    final future = () async {
      await ensureStarted();
      return _evalEnvelope(
        '(async () => { try {'
        ' const r = await MangaKit.compat.registerSource(__mkPendingCode);'
        ' return JSON.stringify({ok: 1, manifest: r.manifest, diagnostics: r.diagnostics});'
        '} catch (e) {'
        ' return JSON.stringify({ok: 0, error: {code: (e && e.code) || "", message: String((e && e.message) || e)}});'
        '} })()',
        globals: {'__mkPendingCode': code},
      );
    }();
    _registrations[jsKey] = future;
    // A failed registration must not poison the key forever:
    // evict it so the next use retries (network recovery,
    // fixed source file).
    future.then(
      (_) {},
      onError: (_) {
        if (identical(_registrations[jsKey], future)) {
          _registrations.remove(jsKey);
        }
      },
    );
    return future;
  }

  /// Forgets a registration (source removed or reinstalled):
  /// the next use re-registers from the stored code.
  Future<void> removeSource(String jsKey, String manifestKey) async {
    _registrations.remove(jsKey);
    if (!started) return;
    try {
      await _evalRaw(
        'MangaKit.engine.removeSource(__mkPendingKey)',
        globals: {'__mkPendingKey': manifestKey},
      );
    } catch (_) {
      // Removal is best-effort; a dead runtime forgets anyway.
    }
  }

  /// One framework call (search / explore / details /
  /// chapters / pages / categories / category / thumbnails /
  /// account / login / logout / imageOnResponse /
  /// imageModify / imageFallback). [onSection] streams
  /// explore sections as they land (progressive output).
  Future<Map<String, dynamic>> call(
    String manifestKey,
    String kind,
    Map<String, dynamic> args, {
    void Function(Map<String, dynamic> section)? onSection,
    bool refresh = false,
  }) async {
    await ensureStarted();
    String? token;
    if (onSection != null) {
      token = 's${++_sectionSeq}';
      _sectionSinks[token] = onSection;
    }
    try {
      final pendingArgs = jsonEncode({
        'key': manifestKey,
        'kind': kind,
        'args': args,
        'refresh': refresh,
        'token': token,
      });
      return await _evalEnvelope(
        '(async () => { try {'
        ' const p = JSON.parse(__mkPendingArgs);'
        ' const args = p.args || {};'
        ' if (p.refresh) args.refresh = true;'
        ' if (p.token) args.onSection = (section) => {'
        '   __mkNative("ui", "section", JSON.stringify({payload: {token: p.token, section}}));'
        ' };'
        ' const r = await MangaKit.call(p.key, p.kind, args);'
        ' return JSON.stringify({ok: 1, result: r});'
        '} catch (e) {'
        ' return JSON.stringify({ok: 0, error: {code: (e && e.code) || "", message: String((e && e.message) || e)}});'
        '} })()',
        globals: {'__mkPendingArgs': pendingArgs},
      ).then((envelope) {
        final result = envelope['result'];
        return result is Map
            ? result.cast<String, dynamic>()
            : <String, dynamic>{};
      });
    } finally {
      if (token != null) _sectionSinks.remove(token);
    }
  }

  /// The source's declared settings schema, in declaration
  /// order (framework management surface).
  Future<List<Map<String, dynamic>>> settingsSchema(String manifestKey) async {
    await ensureStarted();
    final envelope = await _evalEnvelope(
      '(async () => { try {'
      ' const r = MangaKit.engine.settingsSchema(__mkPendingKey);'
      ' return JSON.stringify({ok: 1, result: r});'
      '} catch (e) {'
      ' return JSON.stringify({ok: 0, error: {code: (e && e.code) || "", message: String((e && e.message) || e)}});'
      '} })()',
      globals: {'__mkPendingKey': manifestKey},
    );
    final result = envelope['result'];
    if (result is List) {
      return [
        for (final entry in result)
          if (entry is Map) entry.cast<String, dynamic>(),
      ];
    }
    return const [];
  }

  Future<void> writeSetting(
    String manifestKey,
    String name,
    Object? value,
  ) async {
    await ensureStarted();
    await _evalEnvelope(
      '(async () => { try {'
      ' const p = JSON.parse(__mkPendingArgs);'
      ' await MangaKit.engine.writeSetting(p.key, p.name, p.value);'
      ' return JSON.stringify({ok: 1});'
      '} catch (e) {'
      ' return JSON.stringify({ok: 0, error: {code: (e && e.code) || "", message: String((e && e.message) || e)}});'
      '} })()',
      globals: {
        '__mkPendingArgs': jsonEncode({
          'key': manifestKey,
          'name': name,
          'value': value,
        }),
      },
    );
  }

  Future<void> invokeSettingCallback(String manifestKey, String name) async {
    await ensureStarted();
    await _evalEnvelope(
      '(async () => { try {'
      ' const p = JSON.parse(__mkPendingArgs);'
      ' await MangaKit.engine.invokeSettingCallback(p.key, p.name);'
      ' return JSON.stringify({ok: 1});'
      '} catch (e) {'
      ' return JSON.stringify({ok: 0, error: {code: (e && e.code) || "", message: String((e && e.message) || e)}});'
      '} })()',
      globals: {
        '__mkPendingArgs': jsonEncode({'key': manifestKey, 'name': name}),
      },
    );
  }

  // ---- bridge native side --------------------------------

  Future<String> _handleNative(
    String group,
    String method,
    String envelopeJson,
  ) async {
    try {
      final envelope = (jsonDecode(envelopeJson) as Map)
          .cast<String, dynamic>();
      final payload = envelope['payload'];
      final payloadMap = payload is Map
          ? payload.cast<String, dynamic>()
          : <String, dynamic>{};
      switch ('$group.$method') {
        case 'delay.delay':
          final ms = (payloadMap['ms'] as num?)?.toInt() ?? 0;
          await Future<void>.delayed(Duration(milliseconds: ms));
          return '{}';
        case 'http.request':
          return jsonEncode(await _http(envelope));
        case 'store.get':
          return jsonEncode({'value': _storeGet(envelope)});
        case 'store.set':
          _storeSet(envelope);
          return 'true';
        case 'store.delete':
          _storeDelete(envelope);
          return 'true';
        case 'store.all':
          return jsonEncode(_storeAll(envelope));
        case 'cookies.get':
          return jsonEncode({
            'value': cookieHeaderFor(payloadMap['url']?.toString() ?? ''),
          });
        case 'cookies.set':
          final raw = payloadMap['cookies'];
          if (raw is List) {
            plantRawSetCookies(payloadMap['url']?.toString() ?? '', [
              for (final c in raw) c.toString(),
            ]);
          }
          return 'true';
        case 'cookies.delete':
          _deleteCookiesFor(payloadMap['url']?.toString() ?? '');
          return 'true';
        case 'ui.toast':
          AnikumoDialog.showToast(
            message: payloadMap['message']?.toString() ?? '',
          );
          return 'true';
        case 'ui.openUrl':
          await MangaUiGateway.handle(
            jsonEncode({
              'function': 'launchUrl',
              'url': payloadMap['url']?.toString() ?? '',
            }),
          );
          return 'true';
        case 'ui.dialog':
          final reply = await MangaUiGateway.handle(
            jsonEncode({
              'function': 'showDialog',
              'title': payloadMap['title']?.toString() ?? '',
              'content': payloadMap['content']?.toString() ?? '',
              'actions': [
                if (payloadMap['actions'] is List)
                  for (final a in payloadMap['actions'] as List)
                    {
                      'text': a is Map
                          ? a['text']?.toString() ?? ''
                          : a.toString(),
                      'style': 'text',
                    },
              ],
            }),
          );
          return reply;
        case 'ui.input':
          final reply = await MangaUiGateway.handle(
            jsonEncode({
              'function': 'showInputDialog',
              'title': payloadMap['title']?.toString() ?? '',
              'hint': payloadMap['hint']?.toString() ?? '',
            }),
          );
          try {
            final decoded = jsonDecode(reply);
            if (decoded is Map && decoded['value'] != null) {
              return jsonEncode(decoded['value']);
            }
          } catch (_) {}
          return 'null';
        case 'ui.solveVerification':
          final solver = onSolveVerification;
          if (solver == null) return jsonEncode({'solved': false});
          final solved = await solver(
            url: payloadMap['url']?.toString() ?? '',
            kind: payloadMap['kind']?.toString() ?? 'captcha',
          );
          return jsonEncode({'solved': solved});
        case 'ui.section':
          final token = payloadMap['token']?.toString() ?? '';
          final section = payloadMap['section'];
          final sink = _sectionSinks[token];
          if (sink != null && section is Map) {
            sink(section.cast<String, dynamic>());
          }
          return 'true';
        case 'log.write':
          debugPrint(
            '[mangakit] ${payloadMap['level'] ?? 'info'}: ${payloadMap['message'] ?? ''}',
          );
          return 'true';
        default:
          return jsonEncode({'error': 'unsupported: $group.$method'});
      }
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  // ---- store: legacy per-source KV -----------------------
  // The framework speaks in strings (its own JSON encoding);
  // the legacy KV stores real JSON values (other readers —
  // account session marks, the settings panel — read them
  // directly). Transcode at this seam: values are parsed on
  // the way in and re-encoded on the way out, which
  // round-trips both worlds.

  ({String sourceKey, String kind, Map<String, dynamic> bucket}) _bucketOf(
    Map<String, dynamic> envelope,
  ) {
    final sourceKey = envelope['sourceKey']?.toString() ?? '';
    final payload = envelope['payload'];
    final kind = payload is Map && payload['kind']?.toString() == 'settings'
        ? 'settings'
        : 'data';
    final all = VeneraEngine.allKv();
    final mine = all[sourceKey];
    final bucket = <String, dynamic>{};
    if (mine is Map && mine[kind] is Map) {
      bucket.addAll((mine[kind] as Map).cast<String, dynamic>());
    }
    return (sourceKey: sourceKey, kind: kind, bucket: bucket);
  }

  void _persistBucket(
    String sourceKey,
    String kind,
    Map<String, dynamic> bucket,
  ) {
    final all = VeneraEngine.allKv();
    final mine = <String, dynamic>{
      'data': <String, dynamic>{},
      'settings': <String, dynamic>{},
    };
    final existing = all[sourceKey];
    if (existing is Map) {
      if (existing['data'] is Map) {
        mine['data'] = (existing['data'] as Map).cast<String, dynamic>();
      }
      if (existing['settings'] is Map) {
        mine['settings'] = (existing['settings'] as Map)
            .cast<String, dynamic>();
      }
    }
    mine[kind] = bucket;
    VeneraEngine.persistKv(sourceKey, jsonEncode(mine));
  }

  static String _encodeStoreValue(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return jsonEncode(value);
  }

  static Object? _decodeStoreValue(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  String? _storeGet(Map<String, dynamic> envelope) {
    final payload = envelope['payload'];
    final key = payload is Map ? payload['key']?.toString() : null;
    if (key == null) return null;
    final value = _bucketOf(envelope).bucket[key];
    return value == null ? null : _encodeStoreValue(value);
  }

  void _storeSet(Map<String, dynamic> envelope) {
    final payload = envelope['payload'];
    if (payload is! Map) return;
    final key = payload['key']?.toString() ?? '';
    if (key.isEmpty) return;
    final parts = _bucketOf(envelope);
    parts.bucket[key] = _decodeStoreValue(payload['value']?.toString() ?? '');
    _persistBucket(parts.sourceKey, parts.kind, parts.bucket);
  }

  void _storeDelete(Map<String, dynamic> envelope) {
    final payload = envelope['payload'];
    if (payload is! Map) return;
    final parts = _bucketOf(envelope);
    parts.bucket.remove(payload['key']?.toString() ?? '');
    _persistBucket(parts.sourceKey, parts.kind, parts.bucket);
  }

  Map<String, String> _storeAll(Map<String, dynamic> envelope) {
    final bucket = _bucketOf(envelope).bucket;
    return {
      for (final entry in bucket.entries)
        entry.key: _encodeStoreValue(entry.value),
    };
  }

  // ---- cookies: legacy shared jar -------------------------
  // One jar, host -> name -> value, persisted in the same
  // settings entry the legacy engine used, so cookies earned
  // under either engine (and cookies planted by the WebView
  // login / verification flows) are shared.

  Map<String, Map<String, String>>? _jarCache;

  Map<String, Map<String, String>> get _jar {
    final cached = _jarCache;
    if (cached != null) return cached;
    final jar = <String, Map<String, String>>{};
    try {
      final decoded = jsonDecode(VeneraEngine.cookiesJson());
      if (decoded is Map) {
        decoded.forEach((host, pairs) {
          if (pairs is Map) {
            jar[host.toString()] = {
              for (final e in pairs.entries)
                e.key.toString(): e.value.toString(),
            };
          }
        });
      }
    } catch (_) {}
    return _jarCache = jar;
  }

  void _persistJar() {
    VeneraEngine.persistCookies(jsonEncode(_jar));
  }

  /// Cookie header for [url]: exact host plus parent-domain
  /// entries (a cookie stored for a parent domain rides on
  /// its subdomains).
  String cookieHeaderFor(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return '';
    final pairs = <String, String>{};
    _jar.forEach((domain, values) {
      if (host == domain || host.endsWith('.$domain')) {
        pairs.addAll(values);
      }
    });
    return pairs.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Plants raw Set-Cookie header values (from the bridge or
  /// a WebView harvest) into the jar.
  void plantRawSetCookies(String url, List<String> rawCookies) {
    final fallbackHost = Uri.tryParse(url)?.host ?? '';
    var changed = false;
    for (final raw in rawCookies) {
      final parts = raw.split(';');
      final first = parts.first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      var domain = fallbackHost;
      for (final attr in parts.skip(1)) {
        final kv = attr.trim();
        if (kv.toLowerCase().startsWith('domain=')) {
          domain = kv.substring(7).trim();
          if (domain.startsWith('.')) domain = domain.substring(1);
        }
      }
      if (domain.isEmpty || name.isEmpty) continue;
      (_jar[domain] ??= {})[name] = value;
      changed = true;
    }
    if (changed) _persistJar();
  }

  /// Plants already-parsed name/value pairs for [url]'s host
  /// (the verification page's WebView harvest path).
  void plantCookies(String url, Map<String, String> pairs) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty || pairs.isEmpty) return;
    (_jar[host] ??= {}).addAll(pairs);
    _persistJar();
  }

  void _deleteCookiesFor(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return;
    if (_jar.remove(host) != null) _persistJar();
  }

  // ---- http transport --------------------------------------
  // One pooled Dio for the runtime's whole life. No GET
  // cache here on purpose: the framework implements the
  // short cache + in-flight dedupe itself (with the correct
  // Set-Cookie exclusion), so the transport stays a dumb
  // pipe and there is exactly one cache layer.

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  Future<Map<String, dynamic>> _http(Map<String, dynamic> envelope) async {
    final payload = (envelope['payload'] as Map).cast<String, dynamic>();
    final method = payload['method']?.toString() ?? 'GET';
    final url = payload['url']?.toString() ?? '';
    final wantBytes = payload['bytes'] == true;
    final headers = <String, dynamic>{};
    final rawHeaders = payload['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        headers[k.toString()] = v.toString();
      });
    }
    Object? data;
    final rawData = payload['data'];
    if (rawData is String) {
      data = rawData;
    } else if (rawData != null) {
      data = rawData;
      headers.putIfAbsent('content-type', () => 'application/json');
    }
    final response = await _dio.request<List<int>>(
      url,
      data: data,
      options: Options(
        method: method,
        headers: headers,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
        followRedirects: true,
        maxRedirects: 5,
      ),
    );
    final replyHeaders = <String, dynamic>{};
    response.headers.forEach((name, values) {
      replyHeaders[name] = name.toLowerCase() == 'set-cookie'
          ? values
          : values.join(', ');
    });
    final bytes = response.data ?? const <int>[];
    return {
      'status': response.statusCode ?? 0,
      'headers': replyHeaders,
      'body': wantBytes ? '' : utf8.decode(bytes, allowMalformed: true),
      'bodyB64': wantBytes ? base64Encode(bytes) : null,
    };
  }
}

/// JS bootstrap: shapes the single native function into the
/// `__mangakitHost` object the framework's bridge consumes
/// (bridge protocol v1). Values cross as JSON strings;
/// store.get / cookies.get unwrap their {value} envelope.
const String _hostBootstrapJs = r'''
globalThis.__mangakitHost = {
  delay: function (ms) {
    return __mkNative('delay', 'delay', JSON.stringify({ payload: { ms: ms } }))
      .then(function () { return true; });
  },
  http: {
    request: function (env) {
      return __mkNative('http', 'request', JSON.stringify(env))
        .then(function (s) { return JSON.parse(s); });
    }
  },
  store: {
    get: function (env) {
      return __mkNative('store', 'get', JSON.stringify(env))
        .then(function (s) { var v = JSON.parse(s); return v.value === undefined ? null : v.value; });
    },
    set: function (env) {
      return __mkNative('store', 'set', JSON.stringify(env)).then(function () { return true; });
    },
    delete: function (env) {
      return __mkNative('store', 'delete', JSON.stringify(env)).then(function () { return true; });
    },
    all: function (env) {
      return __mkNative('store', 'all', JSON.stringify(env))
        .then(function (s) { return JSON.parse(s); });
    }
  },
  cookies: {
    get: function (env) {
      return __mkNative('cookies', 'get', JSON.stringify(env))
        .then(function (s) { var v = JSON.parse(s); return v.value || ''; });
    },
    set: function (env) {
      return __mkNative('cookies', 'set', JSON.stringify(env)).then(function () { return true; });
    },
    delete: function (env) {
      return __mkNative('cookies', 'delete', JSON.stringify(env)).then(function () { return true; });
    }
  },
  ui: {
    toast: function (env) {
      return __mkNative('ui', 'toast', JSON.stringify(env)).then(function () { return true; });
    },
    openUrl: function (env) {
      return __mkNative('ui', 'openUrl', JSON.stringify(env)).then(function () { return true; });
    },
    dialog: function (env) {
      return __mkNative('ui', 'dialog', JSON.stringify(env))
        .then(function (s) { try { return JSON.parse(s); } catch (e) { return null; } });
    },
    input: function (env) {
      return __mkNative('ui', 'input', JSON.stringify(env))
        .then(function (s) { try { return JSON.parse(s); } catch (e) { return null; } });
    },
    solveVerification: function (env) {
      return __mkNative('ui', 'solveVerification', JSON.stringify(env))
        .then(function (s) { try { return JSON.parse(s); } catch (e) { return { solved: false }; } });
    }
  },
  log: {
    write: function (env) {
      return __mkNative('log', 'write', JSON.stringify(env)).then(function () { return true; });
    }
  }
};
''';

/// Batch 253: spawn payload for the MangaKit engine
/// isolate — the two JS texts it boots with (the host
/// bootstrap and the framework bundle).
class _MkInit {
  const _MkInit(this.uiPort, this.bootstrapJs, this.bundle);

  final SendPort uiPort;
  final String bootstrapJs;
  final String bundle;
}

/// Batch 253: the MangaKit engine isolate. Owns the
/// QuickJS runtime, so every evaluation — the bundle
/// boot and each source call's parsing — runs off the
/// UI thread. Bridge calls (__mkNative) forward to the
/// UI isolate, which owns all state (http / store /
/// cookies / UI) and answers by sequence number; the
/// synchronous image ops stay local (pure Dart CPU work
/// in the `image` package, synchronous by contract).
void _mangakitIsolateMain(_MkInit init) async {
  final receive = ReceivePort();

  final qjs = FlutterQjs(
    stackSize: 1024 * 1024,
    memoryLimit: 256 * 1024 * 1024,
    timeout: 0,
  );
  unawaited(qjs.dispatch());

  var nativeSeq = 0;
  final nativePending = <int, Completer<String>>{};

  JSInvokable setter;
  try {
    setter = qjs.evaluate('(function (k, v) { this[k] = v; })') as JSInvokable;
    setter.invoke([
      '__mkNative',
      (dynamic group, dynamic method, dynamic envelopeJson) {
        final seq = ++nativeSeq;
        final completer = Completer<String>();
        nativePending[seq] = completer;
        init.uiPort.send([
          'native',
          seq,
          group?.toString() ?? '',
          method?.toString() ?? '',
          envelopeJson?.toString() ?? '{}',
        ]);
        return completer.future;
      },
    ]);
    setter.invoke([
      '__mkImageSync',
      (dynamic payload) => mangakitImageOpSync(payload?.toString() ?? ''),
    ]);
    qjs.evaluate(init.bootstrapJs);
    qjs.evaluate(init.bundle);
  } catch (e) {
    init.uiPort.send(['startError', e.toString()]);
    return;
  }

  receive.listen((dynamic message) async {
    if (message is! List || message.isEmpty) return;
    switch (message[0]) {
      case 'eval':
        final seq = message[1] as int;
        final globals = (message[2] as Map).cast<String, String>();
        final js = message[3]?.toString() ?? '';
        try {
          globals.forEach((name, value) => setter.invoke([name, value]));
          final dynamic pending = qjs.evaluate(js);
          final dynamic result = pending is Future ? await pending : pending;
          init.uiPort.send([
            'result',
            seq,
            true,
            result is String ? result : (result?.toString() ?? ''),
          ]);
        } catch (e) {
          init.uiPort.send(['result', seq, false, e.toString()]);
        }
      case 'nativeResult':
        final completer = nativePending.remove(message[1] as int);
        if (completer != null && !completer.isCompleted) {
          completer.complete(message[2]?.toString() ?? '');
        }
    }
  });
  init.uiPort.send(['ready', receive.sendPort]);
}
