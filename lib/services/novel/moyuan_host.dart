import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:hive_ce/hive.dart';

import '../storage/storage.dart';
import 'legado_gbk.dart';

/// Batch 174: host for the MoYuan novel engine.
///
/// The novel zone's book sources run on the MoYuan JS
/// engine (assets/moyuan/moyuan.js, a single-file bundle)
/// inside a QuickJS runtime owned here. The bundle is
/// host-agnostic: this class supplies the three things it
/// asks of its host —
///
///  * an async HTTP transport (novelHostRequest), served
///    by [_transport]: raw status/headers/final-URL out,
///    GBK-aware decoding in, NO cookie handling (the
///    engine keeps its own jar and persists it through
///    the storage channel);
///  * a string key/value store (novelHostStorage*),
///    backed by a dedicated Hive box;
///  * completion plumbing: flutter_js channel calls do
///    not bridge Dart futures into JS promises, so host
///    calls run through a small JS promise registry
///    (__moyuanHostCall / __moyuanComplete) and engine
///    calls through result slots (__moyuanSlot) that the
///    Dart side pumps with executePendingJob.
///
/// novelHostRequestSync exists but never answers inline:
/// it records the attempt (see __moyuanSyncAttempts) and
/// throws a marked suspension; [callWithReplay] performs
/// the fetch through the async transport, primes the
/// adapter's sync-response cache, and replays the whole
/// call so scripts read the real response synchronously.
/// Attempts a script catches itself (probe patterns with
/// try/catch around java.ajax) are recovered the same
/// way: the recorded attempts are primed after the round
/// and the call replays once more with real data.
/// Batch 180: a bare "Stack Overflow" error text is Dart's own
/// [StackOverflowError] — JS engine failures always reach Dart
/// prefixed ("MoYuan JS error:" / "MoYuan call failed:"), so an
/// unprefixed one means the overflow happened in Dart code, not
/// in the JS engine or a source rule. Catch it at layer
/// boundaries and rethrow with the layer and context attached,
/// mirroring the engine-side content() guard (batch 179), so
/// the next occurrence names its layer instead of guessing.
Future<T> guardDartStack<T>(
  Future<T> Function() body,
  String layer,
  String context,
) async {
  try {
    return await body();
  } on StackOverflowError {
    throw StateError('Stack Overflow ($layer) — $context');
  }
}

class MoyuanHost {
  MoyuanHost._();

  static final MoyuanHost instance = MoyuanHost._();

  /// Test seams (null in production).
  static Future<Map<String, dynamic>> Function(
    String url,
    Map<String, dynamic> options,
  )? debugTransportOverride;
  static Future<String> Function()? debugBundleLoaderOverride;
  static JavascriptRuntime Function()? debugRuntimeFactoryOverride;

  JavascriptRuntime? _runtime;
  Future<void>? _starting;
  String _appliedSourcesHash = '';

  /// Recent 'source:unsupported' events from the engine:
  /// {sourceId, feature, at}. Diagnostics reads this so a
  /// source's gaps are visible instead of silent.
  final List<Map<String, dynamic>> unsupportedLog = [];

  /// Heads of recent response bodies by final URL (last
  /// dozen, 6000 chars each). The diagnostics report
  /// quotes the directory response from here when a
  /// chapter list comes back suspiciously short.
  final Map<String, String> recentBodies = {};

  void _recordBody(String url, String body) {
    if (url.isEmpty) return;
    recentBodies.remove(url);
    recentBodies[url] =
        body.length <= 6000 ? body : body.substring(0, 6000);
    while (recentBodies.length > 12) {
      recentBodies.remove(recentBodies.keys.first);
    }
  }

  bool get isStarted => _runtime != null;

  // ---------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------

  Future<void> ensureStarted() {
    if (_runtime != null) return Future.value();
    return _starting ??= _start().catchError((Object e) {
      // A failed start must not poison the singleton:
      // the next call retries instead of re-awaiting the
      // same failed future for the rest of the session.
      _starting = null;
      _runtime = null;
      throw e;
    });
  }

  Future<void> _start() async {
    final runtime = debugRuntimeFactoryOverride?.call() ?? QuickJsRuntime2();
    _runtime = runtime;
    runtime.onMessage('moyuanRequest', _onRequestMessage);
    runtime.onMessage('moyuanStorage', _onStorageMessage);
    runtime.onMessage('moyuanEvent', _onEventMessage);
    _evaluate(_bootstrapJs);
    final bundle = await (debugBundleLoaderOverride?.call() ??
        rootBundle.loadString('assets/moyuan/moyuan.js'));
    _evaluate(bundle);
    _buildEngine();
    await syncSourcesIfChanged(force: true);
  }

  /// (Re)create the engine + bridge objects inside the
  /// already-loaded bundle. Pending calls are failed
  /// first: their promises belong to the old engine.
  void _buildEngine() {
    _evaluate('''
      for (const k in globalThis.__moyuanSlots) {
        const s = globalThis.__moyuanSlots[k];
        if (s.state === 'pending') { s.state = 'err'; s.err = 'engine rebuilt'; }
      }
      globalThis.__moyuanEngine = MoYuan.createQuickJSEngine({});
      globalThis.__moyuanEngine.setJsEvaluator(globalThis.__moyuanEvalWithScope);
      globalThis.__moyuanBridge = MoYuan.createAnikumoBridge(globalThis.__moyuanEngine);
      globalThis.__moyuanEngine.on('source:unsupported', function (e) {
        sendMessage('moyuanEvent', JSON.stringify({
          type: 'unsupported',
          sourceId: (e && e.sourceId) || '',
          feature: (e && e.feature) || '',
        }));
      });
    ''');
    _seedLoginInfo();
    _seedSourceVars();
  }

  static const _bootstrapJs = r'''
    globalThis.__moyuanCallbacks = {};
    globalThis.__moyuanSeq = 0;
    globalThis.__moyuanHostCall = function (channel, payload) {
      return new Promise(function (resolve, reject) {
        const id = ++globalThis.__moyuanSeq;
        globalThis.__moyuanCallbacks[id] = { resolve: resolve, reject: reject };
        sendMessage(channel, JSON.stringify({ id: id, payload: payload }));
      });
    };
    globalThis.__moyuanComplete = function (id, json, err) {
      const cb = globalThis.__moyuanCallbacks[id];
      delete globalThis.__moyuanCallbacks[id];
      if (!cb) return;
      if (err !== null && err !== undefined) cb.reject(new Error(String(err)));
      else cb.resolve(json ? JSON.parse(json) : null);
    };
    globalThis.novelHostRequest = function (url, optJson) {
      return globalThis.__moyuanHostCall('moyuanRequest', { url: url, optJson: optJson });
    };
    globalThis.novelHostStorageGet = function (key) {
      return globalThis.__moyuanHostCall('moyuanStorage', { op: 'get', key: key });
    };
    globalThis.novelHostStorageSet = function (key, value) {
      return globalThis.__moyuanHostCall('moyuanStorage', { op: 'set', key: key, value: value });
    };
    globalThis.novelHostStorageDelete = function (key) {
      return globalThis.__moyuanHostCall('moyuanStorage', { op: 'delete', key: key });
    };
    globalThis.novelHostStorageKeys = function () {
      return globalThis.__moyuanHostCall('moyuanStorage', { op: 'keys' });
    };
    // Rule-script evaluator with true completion-value
    // semantics: the engine's built-in evaluator only
    // surfaces an assigned `result` variable or a single
    // expression, so statement-form scripts that end in
    // a bare expression (the common shape for generated
    // explore kinds, among others) come back empty. A
    // direct eval inside a scope-parameter function
    // yields the script's completion value — what the
    // rules were written against — and falls back to an
    // assigned `result` when the completion is undefined.
    globalThis.__moyuanEvalCache = {};
    globalThis.__moyuanGuardDeadline = 0;
    globalThis.__guard = function () {
      if (Date.now() > globalThis.__moyuanGuardDeadline) {
        throw new Error('JS rule timed out');
      }
    };
    globalThis.__moyuanEvalWithScope = function (code, scope, lib) {
      scope = scope || {};
      var keys = Object.keys(scope).filter(function (k) {
        return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(k) && k !== '__src__';
      });
      var sig = keys.join(',');
      var fn = globalThis.__moyuanEvalCache[sig];
      if (!fn) {
        var hasResult = keys.indexOf('result') >= 0;
        var body = hasResult
          ? 'var __c = eval(__src__); return __c !== undefined ? __c : result;'
          : 'return eval(__src__);';
        fn = new Function('__src__', ...keys, body);
        globalThis.__moyuanEvalCache[sig] = fn;
      }
      var src = (lib ? String(lib) + '\n' : '') +
        String(code === null || code === undefined ? '' : code);
      // The custom-evaluator path bypasses the engine's
      // own loop-guard injection, so apply it here (with
      // the __guard above standing in for the engine's
      // watchdog, same 5s budget).
      if (typeof MoYuan !== 'undefined' && MoYuan.injectLoopGuards) {
        try { src = MoYuan.injectLoopGuards(src); } catch (e) { /* keep raw */ }
      }
      var args = [src];
      for (var i = 0; i < keys.length; i++) args.push(scope[keys[i]]);
      globalThis.__moyuanGuardDeadline = Date.now() + 5000;
      try {
        return fn.apply(null, args);
      } catch (e) {
        // A top-level `return` is a parse-time SyntaxError for
        // eval (nothing has executed yet, so retrying is safe),
        // but the rules were written against a runtime that
        // accepts it. Recompile the script AS the function
        // body, where `return` is legal; falling off the end
        // yields an assigned `result`, mirroring the eval path.
        if (!(e instanceof SyntaxError)) throw e;
        var bodyFn = new Function(...keys,
          src + '\n;return (typeof result !== "undefined") ? result : undefined;');
        var vals = [];
        for (var j = 0; j < keys.length; j++) vals.push(scope[keys[j]]);
        return bodyFn.apply(null, vals);
      } finally {
        globalThis.__moyuanGuardDeadline = 0;
      }
    };
    // Timer surface: QuickJS has no setTimeout, but the
    // engine's pacing/backoff code calls it. Timers live
    // in a registry the Dart pump advances between job
    // drains (__moyuanRunTimers), so a promise the engine
    // awaits via setTimeout settles while a call pumps.
    globalThis.__moyuanTimers = new Map();
    globalThis.__moyuanTimerSeq = 0;
    globalThis.setTimeout = function (cb, ms) {
      var args = Array.prototype.slice.call(arguments, 2);
      var id = ++globalThis.__moyuanTimerSeq;
      globalThis.__moyuanTimers.set(id, {
        at: Date.now() + Math.max(0, ms | 0), cb: cb, args: args, every: 0,
      });
      return id;
    };
    globalThis.setInterval = function (cb, ms) {
      var args = Array.prototype.slice.call(arguments, 2);
      var id = ++globalThis.__moyuanTimerSeq;
      var every = Math.max(1, ms | 0);
      globalThis.__moyuanTimers.set(id, {
        at: Date.now() + every, cb: cb, args: args, every: every,
      });
      return id;
    };
    globalThis.clearTimeout = function (id) {
      globalThis.__moyuanTimers.delete(id);
    };
    globalThis.clearInterval = globalThis.clearTimeout;
    globalThis.__moyuanRunTimers = function () {
      var now = Date.now();
      var due = [];
      globalThis.__moyuanTimers.forEach(function (t, id) {
        if (t.at <= now) due.push([id, t]);
      });
      due.sort(function (a, b) { return a[1].at - b[1].at; });
      for (var i = 0; i < due.length; i++) {
        var id = due[i][0], t = due[i][1];
        if (!globalThis.__moyuanTimers.has(id)) continue;
        if (t.every > 0) t.at = now + t.every;
        else globalThis.__moyuanTimers.delete(id);
        try { t.cb.apply(null, t.args); } catch (e) { /* timer errors stay local */ }
      }
    };
    // Synchronous rule-script fetches (java.ajax & kin):
    // a Dart isolate cannot block on its own event loop,
    // so this channel cannot answer inline. Instead it
    // throws a marked suspension error; the Dart side
    // performs the fetch through the async transport,
    // primes the adapter's sync-response cache
    // (__moyuanPrimeSync), and replays the whole call —
    // the scripts then read the real response from the
    // cache, synchronously, exactly as written. (The
    // engine checks that cache before this channel, and
    // skips its literal-URL prefetch because a sync
    // channel nominally exists; dynamic URLs simply take
    // one replay round each.)
    globalThis.__moyuanSyncAttempts = [];
    globalThis.novelHostRequestSync = function (url, options) {
      var o = options || {};
      var spec = {
        url: String(url),
        method: o.method || 'GET',
        headers: o.headers || {},
        body: o.body === undefined ? null : o.body,
      };
      // Record before throwing: a script may catch the
      // suspension itself (line-probe patterns wrap
      // java.ajax in try/catch and fall back to a default
      // address). The host drains this registry after the
      // round, primes whatever was attempted, and replays
      // the call — the script then reads real data and
      // its probe result actually takes effect.
      try {
        var arr = globalThis.__moyuanSyncAttempts;
        if (arr && arr.length < 50) arr.push(JSON.stringify(spec));
      } catch (e) {}
      throw new Error('MOYUAN_SYNC_FETCH:' + JSON.stringify(spec));
    };
    globalThis.__moyuanPrimeSync = function (sourceId, method, url, body, response) {
      var eng = globalThis.__moyuanEngine;
      var a = eng && eng.sources ? eng.sources.get(sourceId) : null;
      if (!a || !a._ajaxCache) return false;
      var resp = {
        body: response.body || '',
        headers: response.headers || {},
        status: response.status || 200,
        url: response.url || url,
      };
      try {
        a._ajaxCache.set(MoYuan.ajaxCacheKey(method, url, body), resp);
      } catch (e) { return false; }
      try {
        var resolved = new URL(url, sourceId).toString();
        if (resolved !== url) {
          a._ajaxCache.set(MoYuan.ajaxCacheKey(method, resolved, body), resp);
        }
      } catch (e) { /* raw key already primed */ }
      return true;
    };
    globalThis.__moyuanSlots = {};
    globalThis.__moyuanSlotSeq = 0;
    globalThis.__moyuanSlot = function (promise) {
      const id = ++globalThis.__moyuanSlotSeq;
      const s = { state: 'pending', json: null, err: null };
      globalThis.__moyuanSlots[id] = s;
      Promise.resolve(promise).then(
        function (v) {
          s.state = 'ok';
          try { s.json = JSON.stringify(v === undefined ? null : v); } catch (e) { s.json = 'null'; }
        },
        function (e) {
          s.state = 'err';
          s.err = String((e && e.message) || e);
        }
      );
      return id;
    };
    globalThis.__moyuanSlotTake = function (id) {
      const s = globalThis.__moyuanSlots[id];
      if (!s) return '{"state":"err","err":"slot gone"}';
      if (s.state !== 'pending') delete globalThis.__moyuanSlots[id];
      return JSON.stringify(s);
    };
  ''';

  // ---------------------------------------------------------------
  // Source registry sync
  // ---------------------------------------------------------------

  /// Feed the engine the app's installed-source documents
  /// (the same JSON the Dart registry persists). Rebuilds
  /// the engine when the document set changed so removals
  /// take effect; a no-op while nothing changed.
  Future<void> syncSourcesIfChanged({bool force = false}) async {
    await ensureStarted();
    final installed =
        GStorage.getSetting(SettingsKeys.novelInstalledSourcesJson);
    final rss = GStorage.getSetting(SettingsKeys.novelRssSourcesJson);
    final hash = Object.hash(installed, rss).toString();
    if (!force && hash == _appliedSourcesHash) return;
    _appliedSourcesHash = hash;
    _buildEngine();
    if (installed.trim().isNotEmpty) {
      _evaluate(
        'MoYuan.importAnikumoInstalledJson(globalThis.__moyuanEngine, '
        '${jsonEncode(installed)});',
      );
    }
    if (rss.trim().isNotEmpty) {
      final defs = _parseJsonArray(rss);
      if (defs.isNotEmpty) {
        await callAsync(
          '__moyuanEngine.rss.registerMany(${jsonEncode(defs)})',
        );
      }
    }
    _seedLoginInfo();
    _seedSourceVars();
  }

  static List<dynamic> _parseJsonArray(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  /// The engine keeps login info in memory only; the
  /// app's persisted store (novelLoginInfoJson) is seeded
  /// in after every engine build.
  void _seedLoginInfo() {
    final raw = GStorage.getSetting(SettingsKeys.novelLoginInfoJson);
    if (raw.trim().isEmpty) return;
    Map<String, dynamic> stored;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      stored = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }
    for (final entry in stored.entries) {
      final value = entry.value;
      if (value is! String || value.trim().isEmpty) continue;
      try {
        final info = jsonDecode(value);
        if (info is Map) {
          _evaluate(
            '__moyuanEngine.setLoginInfo(${jsonEncode(entry.key)}, '
            '${jsonEncode(info)});',
          );
        }
      } catch (_) {
        // One bad entry must not break the seeding loop.
      }
    }
  }

  /// Batch 176: the engine's per-source variable store
  /// (source.get/put, java.get/put) is memory-only too;
  /// seed the persisted values (novelSourceVarsJson) in
  /// after every engine build, mirroring login info.
  void _seedSourceVars() {
    final raw = GStorage.getSetting(SettingsKeys.novelSourceVarsJson);
    if (raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        try {
          _evaluate(
            '__moyuanEngine.setSourceVars(${jsonEncode(entry.key)}, '
            '${jsonEncode(value)});',
          );
        } catch (_) {
          // One bad entry must not break the seeding loop.
        }
      }
    } catch (_) {
      return;
    }
  }

  /// Batch 176: persist the engine's variable store back
  /// after a call settles, so line selections and other
  /// script state survive restarts. Runs on success and
  /// failure alike (a script may write before it throws);
  /// harvesting itself must never break a call.
  Future<void> _harvestSourceVars() async {
    try {
      final all = evalJson('__moyuanEngine.allSourceVars()');
      if (all is! Map) return;
      final cleaned = <String, dynamic>{};
      for (final entry in all.entries) {
        final value = entry.value;
        if (value is Map && value.isNotEmpty) {
          cleaned['${entry.key}'] = value;
        }
      }
      final encoded = jsonEncode(cleaned);
      if (GStorage.getSetting(SettingsKeys.novelSourceVarsJson) !=
          encoded) {
        await GStorage.putSetting(
          SettingsKeys.novelSourceVarsJson,
          encoded,
        );
      }
    } catch (_) {
      // Never break the call that triggered the harvest.
    }
  }

  // ---------------------------------------------------------------
  // Calling into the engine
  // ---------------------------------------------------------------

  String _evaluate(String code) {
    final runtime = _runtime;
    if (runtime == null) throw StateError('MoYuan host not started');
    final result = runtime.evaluate(code);
    if (result.isError) {
      throw StateError('MoYuan JS error: ${result.stringResult}');
    }
    return result.stringResult;
  }

  /// Evaluate a synchronous expression and JSON-decode
  /// its result (the expression must produce a value
  /// JSON.stringify can carry).
  dynamic evalJson(String expr) {
    final out = _evaluate('JSON.stringify(($expr) ?? null)');
    return jsonDecode(out);
  }

  /// Run an expression that evaluates to a promise (or a
  /// plain value) and await its settlement by pumping the
  /// runtime's job queue.
  Future<dynamic> callAsync(
    String promiseExpr, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    await ensureStarted();
    final id = _evaluate('String(__moyuanSlot(($promiseExpr)))');
    final deadline = DateTime.now().add(timeout);
    while (true) {
      _runtime!.executePendingJob();
      // Advance the timer registry: engine code awaiting
      // a setTimeout-delayed promise settles here.
      try {
        _runtime!.evaluate('__moyuanRunTimers()');
      } catch (_) {}
      _runtime!.executePendingJob();
      final slot =
          jsonDecode(_evaluate('__moyuanSlotTake(${jsonEncode(id)})'))
              as Map<String, dynamic>;
      switch (slot['state']) {
        case 'ok':
          final json = slot['json'];
          await _harvestSourceVars();
          return json is String ? jsonDecode(json) : null;
        case 'err':
          await _harvestSourceVars();
          throw StateError('MoYuan call failed: ${slot['err']}');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('MoYuan call timed out', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  /// Call one of the Anikumo bridge methods.
  Future<dynamic> callBridge(String method, List<dynamic> args) {
    final encoded = args.map(jsonEncode).join(', ');
    return callAsync('__moyuanBridge.$method($encoded)');
  }

  // ---------------------------------------------------------------
  // Synchronous-fetch suspension & replay
  // ---------------------------------------------------------------

  static const _syncMarker = 'MOYUAN_SYNC_FETCH:';

  /// Extract a suspension payload ({url, method,
  /// headers, body}) from an error text, or null when the
  /// error is not a sync-fetch suspension.
  static Map<String, dynamic>? _suspensionOf(String text) {
    final at = text.indexOf(_syncMarker);
    if (at < 0) return null;
    var rest = text.substring(at + _syncMarker.length).trim();
    final end = rest.lastIndexOf('}');
    if (end < 0) return null;
    rest = rest.substring(0, end + 1);
    try {
      final decoded = jsonDecode(rest);
      if (decoded is Map && decoded['url'] != null) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  /// Perform one suspended sync fetch through the async
  /// transport and prime the source adapter's
  /// sync-response cache with the result. Returns false
  /// when the source has no such cache (subscription
  /// sources), in which case replaying cannot help.
  Future<bool> _primeSuspended(
    String sourceId,
    Map<String, dynamic> suspension,
  ) async {
    final url = suspension['url']?.toString() ?? '';
    if (url.isEmpty) return false;
    final method = suspension['method']?.toString() ?? 'GET';
    final headers = suspension['headers'];
    final options = <String, dynamic>{
      'method': method,
      if (headers is Map) 'headers': headers,
      'body': suspension['body'],
    };
    final response = await _transport(url, options);
    final primed = _evaluate(
      '__moyuanPrimeSync(${jsonEncode(sourceId)}, '
      '${jsonEncode(method)}, ${jsonEncode(url)}, '
      '${jsonEncode(suspension['body'])}, ${jsonEncode(response)})',
    );
    return primed == 'true';
  }

  /// Drain the JS-side registry of synchronous-fetch
  /// attempts recorded during the last round (see the
  /// novelHostRequestSync shim). Returns the attempt
  /// specs ({url, method, headers, body}).
  List<Map<String, dynamic>> _drainSyncAttempts() {
    try {
      final raw = _evaluate(
        'JSON.stringify((globalThis.__moyuanSyncAttempts || [])'
        '.splice(0))',
      );
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final out = <Map<String, dynamic>>[];
        for (final entry in decoded) {
          if (entry is! String) continue;
          try {
            final spec = jsonDecode(entry);
            if (spec is Map && spec['url'] != null) {
              out.add(spec.cast<String, dynamic>());
            }
          } catch (_) {}
        }
        return out;
      }
    } catch (_) {}
    return const [];
  }

  static String _attemptKey(Map<String, dynamic> spec) =>
      '${spec['method']}|${spec['url']}|${spec['body']}';

  /// Run a promise expression with sync-fetch replay:
  /// when the engine suspends on a synchronous fetch,
  /// fetch it for real, prime the cache, and re-run the
  /// whole expression (bounded — each round serves at
  /// least one new URL). This is what makes rule-script
  /// java.ajax & friends return real content instead of
  /// the engine's empty-string fallback. Scripts that
  /// catch the suspension themselves (line probes) are
  /// covered too: their attempts are recorded by the
  /// shim, primed after the round, and the call replays
  /// once more so the probe result takes effect.
  Future<dynamic> callWithReplay(
    String sourceId,
    String promiseExpr, {
    int maxRounds = 12,
  }) {
    final m = RegExp(r'__moyuanBridge\.(\w+)').firstMatch(promiseExpr);
    final call = m != null
        ? m.group(1)!
        : (promiseExpr.length <= 60
            ? promiseExpr
            : promiseExpr.substring(0, 60));
    return guardDartStack(
      () => _callWithReplayInner(sourceId, promiseExpr,
          maxRounds: maxRounds),
      'Dart 宿主层',
      'source: $sourceId, call: $call',
    );
  }

  Future<dynamic> _callWithReplayInner(
    String sourceId,
    String promiseExpr, {
    int maxRounds = 12,
  }) async {
    await ensureStarted();
    _drainSyncAttempts(); // drop attempts of unrelated calls
    final primedKeys = <String>{};
    for (var round = 0; ; round++) {
      dynamic result;
      StateError? error;
      try {
        result = await callAsync(promiseExpr);
      } on StateError catch (e) {
        error = e;
      }
      var primedNew = false;
      if (round < maxRounds) {
        for (final attempt in _drainSyncAttempts()) {
          final key = _attemptKey(attempt);
          if (primedKeys.contains(key)) continue;
          if (await _primeSuspended(sourceId, attempt)) {
            primedKeys.add(key);
            primedNew = true;
          }
        }
      }
      if (error == null) {
        if (primedNew) continue; // replay with real data
        return result;
      }
      // New data was primed during this failed round: the
      // failure itself may be a consequence of the missing
      // data (a probe script caught the suspension, fell
      // back to a default address, and that fetch 404'd).
      // Replay before judging the error.
      if (primedNew) continue;
      final suspension = _suspensionOf(error.message);
      if (suspension == null || round >= maxRounds) throw error;
      if (!await _primeSuspended(sourceId, suspension)) {
        throw StateError(
          '这个源需要同步取数，但当前通道无法提供：'
          '${suspension['url']}',
        );
      }
      primedKeys.add(_attemptKey(suspension));
    }
  }

  /// Make sure a source definition is registered with
  /// the engine even when it is not (or not yet) part of
  /// the persisted installed set — a source object in
  /// hand must be callable on its own, the way the Dart
  /// engine's per-def construction always was.
  Future<void> ensureSourceRegistered(
    Map<String, dynamic> rawDef,
  ) async {
    await ensureStarted();
    final id = rawDef['bookSourceUrl']?.toString().trim() ?? '';
    if (id.isEmpty) return;
    final present = evalJson(
      '__moyuanEngine.sources.get(${jsonEncode(id)}) != null',
    );
    if (present == true) return;
    _evaluate(
      '__moyuanEngine.sourceManager.registerMany('
      '[${jsonEncode(rawDef)}], { replace: true })',
    );
  }

  // ---------------------------------------------------------------
  // Login support (used by the source login page)
  // ---------------------------------------------------------------

  /// Store form values in the engine and run the
  /// source's login hook when its loginUrl is a script.
  /// Returns the engine's result map ({stored,
  /// hookExecuted, needsWebLogin?, url?, error?}).
  Future<Map<String, dynamic>> submitLoginForm(
    String sourceId,
    Map<String, String> values,
  ) async {
    await syncSourcesIfChanged();
    // The adapter reports a failed login hook in the
    // result's error field instead of throwing, so a
    // sync-fetch suspension inside the hook is replayed
    // from here: fetch, prime, submit again.
    for (var round = 0; ; round++) {
      final out = await callAsync(
        '__moyuanEngine.sourceManager.submitLoginForm('
        '${jsonEncode(sourceId)}, ${jsonEncode(values)})',
      );
      final map = out is Map
          ? out.cast<String, dynamic>()
          : <String, dynamic>{};
      final suspension = _suspensionOf(map['error']?.toString() ?? '');
      if (suspension == null || round >= 12) return map;
      if (!await _primeSuspended(sourceId, suspension)) return map;
    }
  }

  /// Run a login form button's action script in the
  /// source's own context (its jsLib and bridges apply).
  Future<dynamic> runLoginAction(String sourceId, String code) async {
    await syncSourcesIfChanged();
    return callWithReplay(
      sourceId,
      '(() => { const a = __moyuanEngine.sources.get(${jsonEncode(sourceId)}); '
      'if (!a) throw new Error("source not registered"); '
      'const ctx = a._ctx("", { baseUrl: ${jsonEncode(sourceId)}, stage: "login" }); '
      'return MoYuan.evalScoped(${jsonEncode(code)}, ctx.scope("", {}), a._lib()); })()',
    );
  }

  /// Plant one cookie in the engine's jar (the login
  /// page's WebView harvest lands here).
  Future<void> setCookie(String url, String name, String value) async {
    await ensureStarted();
    _evaluate(
      '__moyuanEngine.requests.cookieJar.setCookie('
      '${jsonEncode(url)}, ${jsonEncode(name)}, ${jsonEncode(value)})',
    );
  }

  /// Forget a source's login: its stored form values
  /// plus every cookie under the given hosts.
  Future<void> clearSourceLogin(
    String sourceId,
    List<String> hosts,
  ) async {
    await ensureStarted();
    _evaluate(
      '__moyuanEngine.setLoginInfo(${jsonEncode(sourceId)}, {})',
    );
    for (final host in hosts) {
      _evaluate(
        '__moyuanEngine.requests.cookieJar.clear('
        '${jsonEncode('https://$host/')})',
      );
    }
  }

  // ---------------------------------------------------------------
  // Host channels (JS -> Dart)
  // ---------------------------------------------------------------

  void _complete(int id, Map<String, dynamic>? result, [Object? error]) {
    final runtime = _runtime;
    if (runtime == null) return;
    final json = result == null ? 'null' : jsonEncode(jsonEncode(result));
    final err = error == null ? 'null' : jsonEncode(error.toString());
    try {
      runtime.evaluate('__moyuanComplete($id, $json, $err)');
    } catch (_) {
      // The runtime may be mid-teardown; a lost completion
      // surfaces as a call timeout on the JS side's caller.
    }
  }

  void _onRequestMessage(dynamic args) {
    final map = (args as Map).cast<String, dynamic>();
    final id = (map['id'] as num).toInt();
    final payload = (map['payload'] as Map).cast<String, dynamic>();
    final url = payload['url']?.toString() ?? '';
    Map<String, dynamic> options = const {};
    final optJson = payload['optJson'];
    if (optJson is String && optJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(optJson);
        if (decoded is Map) options = decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    _transport(url, options).then(
      (result) {
        final body = result['body'];
        if (body is String) {
          _recordBody(result['url']?.toString() ?? url, body);
        }
        _complete(id, result);
      },
      onError: (Object e) => _complete(id, null, e),
    );
  }

  Future<Box<String>>? _boxFuture;

  Future<Box<String>> _box() =>
      _boxFuture ??= Hive.openBox<String>('moyuan_store');

  void _onStorageMessage(dynamic args) {
    final map = (args as Map).cast<String, dynamic>();
    final id = (map['id'] as num).toInt();
    final payload = (map['payload'] as Map).cast<String, dynamic>();
    () async {
      final box = await _box();
      switch (payload['op']) {
        case 'get':
          final value = box.get(payload['key']?.toString() ?? '');
          _completeRaw(id, value);
        case 'set':
          await box.put(
            payload['key']?.toString() ?? '',
            payload['value']?.toString() ?? '',
          );
          _complete(id, const {});
        case 'delete':
          await box.delete(payload['key']?.toString() ?? '');
          _complete(id, const {});
        case 'keys':
          _completeRaw(id, box.keys.map((k) => k.toString()).toList());
        default:
          _complete(id, const {});
      }
    }().catchError((Object e) {
      _complete(id, null, e);
      return null;
    });
  }

  /// Complete a host call with a raw JSON value (string,
  /// list, null) rather than an object envelope.
  void _completeRaw(int id, Object? value) {
    final runtime = _runtime;
    if (runtime == null) return;
    final json = jsonEncode(jsonEncode(value));
    try {
      runtime.evaluate('__moyuanComplete($id, $json, null)');
    } catch (_) {}
  }

  void _onEventMessage(dynamic args) {
    if (args is! Map) return;
    final map = args.cast<String, dynamic>();
    if (map['type'] == 'unsupported') {
      unsupportedLog.add({
        'sourceId': map['sourceId']?.toString() ?? '',
        'feature': map['feature']?.toString() ?? '',
        'at': DateTime.now().toIso8601String(),
      });
      if (unsupportedLog.length > 200) {
        unsupportedLog.removeRange(0, unsupportedLog.length - 200);
      }
    }
  }

  // ---------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------

  static final Dio _dio = _buildDio();

  static Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = io.HttpClient();
        client.badCertificateCallback = (_, _, _) => true;
        return client;
      },
    );
    return dio;
  }

  /// One raw HTTP exchange for the engine. Status codes
  /// are data, not errors (the engine's retry/status
  /// policy decides); only transport-level failures
  /// complete the host call with an error.
  Future<Map<String, dynamic>> _transport(
    String url,
    Map<String, dynamic> options,
  ) async {
    final override = debugTransportOverride;
    if (override != null) return override(url, options);
    final method = (options['method']?.toString() ?? 'GET').toUpperCase();
    final headers = <String, String>{};
    final rawHeaders = options['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (v != null) headers[k.toString()] = v.toString();
      });
    }
    Object? data;
    final body = options['body'];
    if (body != null && method != 'GET') {
      if (body is String) {
        data = body;
        // Form-post parity with the runtime these sources were
        // written for: a raw string body is form data. Without
        // the header, servers that read parsed form fields see
        // an empty submission (one real site's search arrived
        // with a blank keyword and returned its empty-search
        // page). An explicit content-type from the source wins.
        final hasContentType =
            headers.keys.any((k) => k.toLowerCase() == 'content-type');
        if (!hasContentType) {
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
        }
      } else if (body is Map) {
        final contentType = headers.keys
            .firstWhere(
              (k) => k.toLowerCase() == 'content-type',
              orElse: () => '',
            )
            .toLowerCase();
        if (contentType.contains('json')) {
          data = jsonEncode(body);
        } else {
          data = body.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } else {
        data = body.toString();
      }
    }
    final response = await _dio.request<List<int>>(
      url,
      data: data,
      options: Options(method: method, headers: headers),
    );
    var bytes = response.data ?? const <int>[];
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      try {
        bytes = io.gzip.decode(bytes);
      } catch (_) {
        // Not actually gzip — fall through with raw bytes.
      }
    }
    final text = await _decodeBody(bytes, response.headers.map['content-type']);
    final outHeaders = <String, dynamic>{};
    response.headers.map.forEach((key, values) {
      outHeaders[key] =
          key == 'set-cookie' ? values : values.join(', ');
    });
    return {
      'status': response.statusCode ?? 0,
      'headers': outHeaders,
      'body': text,
      'url': response.realUri.toString(),
    };
  }

  /// GBK-aware decoding mirroring the novel zone's long-
  /// standing rules: declared charset (Content-Type) or
  /// the page's own meta tag picks GBK; latin charsets
  /// decode as latin-1; everything else is tolerant
  /// UTF-8. Decoding here (rather than in the engine)
  /// keeps GBK bytes out of the JS layer entirely.
  static Future<String> _decodeBody(
    List<int> bytes,
    List<String>? contentType,
  ) async {
    var charset = '';
    if (contentType != null) {
      for (final value in contentType) {
        final m = RegExp(r'charset=([\w-]+)').firstMatch(value);
        if (m != null) charset = (m.group(1) ?? '').toLowerCase();
      }
    }
    var gbk = charset.contains('gb');
    if (!gbk && bytes.length > 32) {
      final head = latin1.decode(
        bytes.sublist(0, bytes.length > 2048 ? 2048 : bytes.length),
        allowInvalid: true,
      );
      final compact = head
          .toLowerCase()
          .replaceAll(RegExp(r'[\s"]'), '')
          .replaceAll("'", '');
      if (compact.contains('charset=gb')) gbk = true;
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
