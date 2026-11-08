import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:image/image.dart' as img;
import 'package:anikumo/services/manga/js/gbk_table.dart';
import 'package:anikumo/services/manga/js/manga_ui_gateway.dart';
import 'package:anikumo/services/manga/js/venera_bridge.dart';
import 'package:anikumo/services/manga/js/venera_scripts.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 34: the manga JS source runtime, rebuilt on Venera's
/// own architecture after studying how the original project
/// runs these exact sources. What changed versus the
/// flutter_js design of batches 13–33:
///
/// 1. Engine binding: **flutter_qjs** (Venera's fork) instead
///    of flutter_js. Its value conversion is native both ways:
///    a Dart Future returned from a bridge function becomes a
///    real JS Promise, and a JS Promise from `evaluate` comes
///    back as a Dart Future. The batch-24 `rawResult` recovery
///    trick — the layer that kept failing on real devices —
///    is gone entirely.
/// 2. **One shared runtime on a background isolate** hosts
///    every installed source (Venera's model: sources register
///    into one engine). Calls cross isolates as task messages
///    with ids and completers, like Venera's JSPool. The old
///    per-source runtimes and their LRU eviction pool are
///    deleted — the eviction churn was itself a suspect in
///    the "only the first N sources work" failures.
/// 3. The bridge is a **real injected Dart function**
///    (`__anikumoNativeBridge`), not a string channel: JS calls
///    it with (channel, payload); Dart Futures become JS
///    Promises natively. Per-source data/settings are keyed
///    by the source key the library includes in every data
///    message, so concurrent sources cannot see each other's
///    KV in the shared runtime.
///
/// What deliberately did NOT change: the bundled library,
/// the compat/override scripts (pure-JS HTML + Convert), the
/// JS dispatcher's call shapes, the KV storage format, and
/// the [call] API this class exposes to JsMangaSource. The
/// novel zone's Legado engine keeps its own flutter_js host;
/// it is a separate runtime and out of this batch's scope.
class VeneraEngine {
  VeneraEngine({required this.sourceKey, required this.code});

  /// The Venera source key (e.g. 'copy_manga').
  final String sourceKey;

  /// The downloaded .js file's full text.
  final String code;

  bool _disposed = false;
  Future<void>? _registerFuture;

  /// Batch 37: the host generation this engine registered
  /// into. A wedged call kills the whole isolate; the fresh
  /// one has never heard of this source, and the cached
  /// registration future would happily skip re-registering —
  /// every later call then died with "source not
  /// initialized" until the app restarted (seen in the
  /// plaza sweep after a slow source timed out).
  int _hostGeneration = -1;

  /// Extracts the source class name from a source file
  /// (`class X extends ComicSource`).
  static String? extractClassName(String code) {
    final match = RegExp(
      r'class\s+([A-Za-z_$][\w$]*)\s+extends\s+ComicSource',
    ).firstMatch(code);
    return match?.group(1);
  }

  // ---- call concurrency (batch 101, reworking batch 31) --
  // Batch 31 serialized EVERY call into one source: sources
  // keep conversational state that interleaved calls could
  // corrupt. But the strict queue also meant a slow search
  // blocked the same source's detail/chapter/image calls
  // behind its full round trip — a standing "half the taps
  // feel stuck" tax, and not how the reference runtime
  // behaves: Venera dispatches concurrently, and sources
  // are written for it (the shared runtime already
  // interleaves different sources' calls at every bridge
  // await). Batch 101 keeps serialization ONLY for the
  // kinds that mutate conversational state — login/logout
  // (auth tokens, UI-driven captcha flows). All read kinds
  // (search, explore, categories, categoryComics, loadInfo,
  // loadEp, imageConfigs, thumbnailConfigs, account) go
  // straight through and interleave at await points.
  static const _serialKinds = {'login', 'logout'};
  Future<void> _callTail = Future<void>.value();
  int _activeCalls = 0;

  /// Calls one dispatcher operation and returns the decoded
  /// JSON result (Map / List / null).
  Future<dynamic> call(String kind, Map<String, dynamic> args) {
    if (_disposed) {
      return Future<dynamic>.error(
        StateError('JS 源已被卸载：$sourceKey'),
      );
    }
    _activeCalls++;
    if (!_serialKinds.contains(kind)) {
      return _callInner(kind, args)
          .whenComplete(() => _activeCalls--);
    }
    final run = _callTail.then((_) => _callInner(kind, args));
    _callTail = run.then<void>((_) {}, onError: (_) {});
    return run.whenComplete(() => _activeCalls--);
  }

  Future<dynamic> _callInner(String kind, Map<String, dynamic> args) {
    // Batch 74: login gets a longer leash — the source may
    // pop a captcha input dialog (UI channel) and wait for
    // the user to read and type the code.
    // Batch 90: content calls get 60 s, matching the facade
    // budgets (fetchChapters / fetchChapterPages allow
    // 60 s). At 40 s a merely SLOW source — multi-request
    // loadInfo on a long series, a sleepy site — was killed
    // as "wedged" and, the host being shared, took every
    // other source's in-flight calls down with it: one
    // concrete shape of "sometimes readable, sometimes
    // not". A truly wedged call still dies at the cap.
    final timeout =
        kind == 'login' ? const Duration(seconds: 180) : const Duration(seconds: 60);
    return _callInnerBody(kind, args).timeout(
      timeout,
      onTimeout: () async {
        // Batch 101: a timeout is no longer an automatic
        // death sentence for the whole engine. The old rule
        // killed the shared isolate on ANY 60 s call, so one
        // slow source reset every other source's in-flight
        // work (the batch-43 self-repair then had to redo
        // them all on a cold engine). Most timeouts are a
        // call merely suspended on a slow network await —
        // the runtime's event loop is perfectly alive. So:
        // probe the host first. Only a host that cannot
        // answer a ping (its thread is truly wedged, e.g. a
        // synchronous JS infinite loop) gets killed; a live
        // host keeps everyone's work and only THIS call
        // fails. (A user slowly typing a login captcha also
        // stops being an engine-kill offence: the loop is
        // free while the call waits on the UI channel.)
        final reset =
            await QjsEngineHost.instance.probeAndKillIfWedged();
        throw TimeoutException(
          reset
              ? 'JS 源调用超时（$kind），引擎卡死已重置'
              : 'JS 源调用超时（$kind）',
        );
      },
    );
  }

  Future<dynamic> _callInnerBody(String kind, Map<String, dynamic> args) async {
    try {
      return await _callOnce(kind, args);
    } catch (e) {
      if (!_isHostDeath(e)) rethrow;
      // Batch 43 (self-repair): the shared isolate died
      // under this call — another source's timeout killed
      // it, or the runtime hit a fatal. That is a HOST
      // failure, not a source answer: a fresh isolate plus
      // re-registration makes the very same call viable, so
      // retry it exactly once before surfacing anything.
      _registerFuture = null;
      return _callOnce(kind, args);
    }
  }

  Future<dynamic> _callOnce(String kind, Map<String, dynamic> args) async {
    await _ensureRegistered();
    final text = await QjsEngineHost.instance.execute(sourceKey, kind, args);
    if (text.isEmpty || text == 'null' || text == 'undefined') return null;
    return jsonDecode(text);
  }

  /// Failure shapes that mean the engine HOST died (killed,
  /// fatal, never started, or this source's registration
  /// died with the old isolate) as opposed to the source
  /// itself answering with an error.
  static bool _isHostDeath(Object e) {
    final t = e.toString();
    return t.contains('JS 引擎已重置') ||
        t.contains('JS 引擎故障') ||
        t.contains('JS 引擎未就绪') ||
        t.contains('引擎启动超时') ||
        t.contains('not initialized') ||
        t.contains('未初始化');
  }

  /// Pre-registers this source in the shared runtime
  /// (the manga home page warms the active source up so the
  /// first tap doesn't pay the engine spin-up cost).
  Future<void> ensureInitialized() {
    if (_disposed) return Future<void>.value();
    return _ensureRegistered();
  }

  Future<void> _ensureRegistered() {
    final host = QjsEngineHost.instance;
    if (_registerFuture != null && _hostGeneration != host.generation) {
      _registerFuture = null;
    }
    return _registerFuture ??= host
        .register(sourceKey, code)
        .then<void>((_) {
          _hostGeneration = host.generation;
        })
        .catchError((Object e) {
      // A failed registration must not be cached — the next
      // call retries (batch 31's init rule, kept).
      _registerFuture = null;
      throw e;
    });
  }

  void dispose() {
    _disposed = true;
    QjsEngineHost.instance.unregister(sourceKey);
  }

  // ---- per-source persisted KV (data + settings) -----------
  // Storage format unchanged since batch 13: one settings
  // entry holding {sourceKey: {data: {...}, settings: {...}}}.

  static Map<String, dynamic> allKv() {
    final raw = GStorage.getSetting(SettingsKeys.mangaJsDataJson);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    } catch (_) {
      return {};
    }
  }

  static String kvJsonFor(String key) {
    final mine = allKv()[key];
    if (mine is Map) {
      return jsonEncode({
        'data': mine['data'] is Map ? mine['data'] : {},
        'settings': mine['settings'] is Map ? mine['settings'] : {},
      });
    }
    return '{"data":{},"settings":{}}';
  }

  static void persistKv(String key, String kvJson) {
    try {
      final kv = jsonDecode(kvJson);
      if (kv is! Map) return;
      final all = allKv();
      all[key] = kv;
      unawaited(
        GStorage.putSetting(SettingsKeys.mangaJsDataJson, jsonEncode(all)),
      );
    } catch (e) {
      debugPrint('[venera:$key] kv persist failed: $e');
    }
  }

  // ---- persisted cookie jar (batch 101) -------------------
  // The jar itself lives in the JS runtime (host → name →
  // value); until this batch it died with the isolate, so
  // every engine kill and every app restart forgot all
  // anti-bot/session cookies and sources had to re-earn
  // them (a quiet source of first-load 403s). The runtime
  // now reports jar changes over the 'cookies' message and
  // the host restores the jar at spawn.

  static String cookiesJson() {
    final raw = GStorage.getSetting(SettingsKeys.mangaJsCookiesJson);
    if (raw.isEmpty || raw.length > 256 * 1024) return '{}';
    try {
      return jsonDecode(raw) is Map ? raw : '{}';
    } catch (_) {
      return '{}';
    }
  }

  static String? _pendingCookies;
  static Timer? _cookiesTimer;

  static void persistCookies(String jarJson) {
    if (jarJson.length > 256 * 1024) return;
    _pendingCookies = jarJson;
    // Jar updates ride along with responses (every
    // set-cookie); coalesce the disk writes.
    _cookiesTimer?.cancel();
    _cookiesTimer = Timer(const Duration(milliseconds: 800), () {
      final pending = _pendingCookies;
      _pendingCookies = null;
      if (pending == null) return;
      unawaited(
        GStorage.putSetting(SettingsKeys.mangaJsCookiesJson, pending),
      );
    });
  }
}

/// The UI-isolate side of the shared engine: owns the isolate,
/// the task table, and lazily (re)spawns everything after a
/// kill. Modeled on Venera's JSPool (one instance here — a
/// single-user reader does not need the pool's parallelism,
/// and one runtime keeps source state coherent).
class QjsEngineHost {
  QjsEngineHost._();

  static final QjsEngineHost instance = QjsEngineHost._();

  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _receive;
  Completer<void>? _ready;
  Future<void>? _starting;

  /// Bumped every time the isolate is torn down, so engine
  /// wrappers can tell their registration died with it.
  int generation = 0;

  int _seq = 0;
  final Map<int, Completer<String>> _tasks = {};

  /// jsKey → source code, for the current isolate generation.
  final Map<String, String> _registeredCode = {};

  /// Library instance key → registry jsKey (persist routing).
  final Map<String, String> _libToJsKey = {};

  /// Registry jsKey → library instance key.
  final Map<String, String> _instanceKeys = {};

  static String? _libraryCache;

  Future<void> _ensureStarted() {
    if (_port != null) return Future<void>.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    _libraryCache ??= (await rootBundle.loadString(
      'assets/venera/_venera_.js',
    ))
        .replaceFirst('let console = {', 'console = {');
    final receive = ReceivePort();
    _receive = receive;
    final ready = Completer<void>();
    _ready = ready;
    receive.listen(_onMessage);
    _isolate = await Isolate.spawn(
      _qjsIsolateMain,
      _QjsInit(
        receive.sendPort,
        _libraryCache!,
        cookiesJson: VeneraEngine.cookiesJson(),
      ),
      debugName: 'anikumo-qjs-engine',
    );
    await ready.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        kill();
        throw TimeoutException('JS 引擎启动超时');
      },
    );
  }

  void _onMessage(dynamic message) {
    if (message is! List || message.isEmpty) return;
    switch (message[0]) {
      case 'ready':
        _port = message[1] as SendPort;
        _ready?.complete();
      case 'result':
        final id = message[1] as int;
        final completer = _tasks.remove(id);
        if (completer == null) return;
        if (message[2] == true) {
          completer.complete(message[3]?.toString() ?? '');
        } else {
          completer.completeError(
            StateError('JS 源调用失败：${message[3]}'),
          );
        }
      case 'persist':
        final libKey = message[1]?.toString() ?? '';
        final jsKey = _libToJsKey[libKey] ?? libKey;
        VeneraEngine.persistKv(jsKey, message[2]?.toString() ?? '{}');
      case 'cookies':
        // Batch 101: the JS cookie jar changed; persist it
        // (debounced) so it survives engine/app restarts.
        VeneraEngine.persistCookies(message[1]?.toString() ?? '{}');
      case 'ui':
        // Batch 74: a source asked for UI (dialog / input /
        // toast). Render it here on the UI isolate and send
        // the outcome back; the engine isolate is waiting on
        // this id.
        final uiId = message[1] as int;
        final uiPayload = message[2]?.toString() ?? '{}';
        unawaited(() async {
          final result = await MangaUiGateway.handle(uiPayload);
          _port?.send(['ui_result', uiId, result]);
        }());
      case 'fatal':
        final error = StateError('JS 引擎故障：${message[1]}');
        _failAll(error);
        _teardown();
    }
  }

  void _failAll(Object error) {
    final pending = _tasks.values.toList();
    _tasks.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  void _teardown() {
    generation++;
    _port = null;
    _registeredCode.clear();
    _libToJsKey.clear();
    _instanceKeys.clear();
    _receive?.close();
    _receive = null;
    _isolate = null;
  }

  /// Kills the engine isolate (poisoned-runtime recovery).
  /// The next call respawns it and re-registers sources from
  /// their stored code.
  void kill() {
    _failAll(StateError('JS 引擎已重置'));
    _isolate?.kill(priority: Isolate.immediate);
    _teardown();
  }

  Future<bool>? _probeFuture;

  /// Batch 101: liveness probe used by call timeouts.
  /// Sends a no-op ping task: a host whose JS thread is
  /// merely busy-or-waiting answers immediately (its event
  /// loop is free); a host wedged in a synchronous JS loop
  /// can never take the message, so the ping times out and
  /// the host is killed. Returns true when a reset happened
  /// (or was already in flight). Concurrent probes join the
  /// same future — a burst of timeouts probes once.
  Future<bool> probeAndKillIfWedged() {
    return _probeFuture ??= _probe().whenComplete(() {
      _probeFuture = null;
    });
  }

  Future<bool> _probe() async {
    final gen = generation;
    try {
      await _task(['ping']).timeout(const Duration(seconds: 3));
      return false;
    } catch (_) {
      // No answer (or the host is down): kill only the
      // generation we probed — a fresher host that replaced
      // it in the meantime is healthy by construction.
      if (generation == gen) kill();
      return true;
    }
  }

  Future<String> _task(List<dynamic> message) async {
    await _ensureStarted();
    final port = _port;
    if (port == null) throw StateError('JS 引擎未就绪');
    final id = ++_seq;
    final completer = Completer<String>();
    _tasks[id] = completer;
    port.send([message[0], id, ...message.sublist(1)]);
    return completer.future;
  }

  /// Registers [code] under [jsKey] in the shared runtime and
  /// returns the source instance's own key. Re-registering
  /// with changed code restarts the isolate (a class cannot
  /// be redeclared inside one QuickJS context).
  Future<String> register(String jsKey, String code) async {
    await _ensureStarted();
    final existing = _registeredCode[jsKey];
    if (existing == code) return _instanceKeys[jsKey] ?? jsKey;
    if (existing != null) {
      // Code changed under a live key: the old instance is
      // dropped and the new file registers fresh (the IIFE
      // wrap makes re-evaluation safe — no class collision).
      unregister(jsKey);
    }
    final instanceKey = await _task([
      'register',
      jsKey,
      code,
      VeneraEngine.kvJsonFor(jsKey),
    ]);
    _registeredCode[jsKey] = code;
    final libKey = instanceKey.isEmpty ? jsKey : instanceKey;
    _libToJsKey[libKey] = jsKey;
    _instanceKeys[jsKey] = libKey;
    return libKey;
  }

  /// Drops one source from the runtime (best effort).
  void unregister(String jsKey) {
    _registeredCode.remove(jsKey);
    _instanceKeys.remove(jsKey);
    _libToJsKey.removeWhere((_, v) => v == jsKey);
    final port = _port;
    if (port != null) {
      port.send(['unregister', jsKey]);
    }
  }

  /// Runs one dispatcher call for a registered source and
  /// returns the dispatcher's JSON string.
  Future<String> execute(
    String jsKey,
    String kind,
    Map<String, dynamic> args,
  ) {
    return _task(['call', jsKey, kind, jsonEncode(args)]);
  }
}

class _QjsInit {
  const _QjsInit(this.uiPort, this.library, {this.cookiesJson = '{}'});

  final SendPort uiPort;

  /// The bundled _venera_.js library text (with the batch-18
  /// console downgrade already applied on the UI side, where
  /// rootBundle lives).
  final String library;

  /// Batch 101: the persisted cookie jar JSON, restored
  /// into the fresh runtime at spawn.
  final String cookiesJson;
}

/// The isolate entry: owns the FlutterQjs runtime, injects
/// the bridge as a real Dart function, evaluates the shared
/// scripts once, then serves register/call tasks.
/// Batch 103: decoded-image registry backing the library's
/// synchronous Image API (used by modifyImage snippets to
/// descramble pages). Lives in the engine isolate; JS only
/// ever holds integer keys, exactly like the reference
/// runtime. Entries are released wholesale after each
/// modifyImage run, and the map self-caps as a backstop.
final Map<int, img.Image> _anikumoImageRegistry = <int, img.Image>{};
int _anikumoImageSeq = 0;

String _anikumoImageReply({required bool ok, Object? v, String? fmt}) {
  return jsonEncode(<String, Object?>{
    'ok': ok,
    'v': v,
    'fmt': ?fmt,
  });
}

String _sniffImageFormat(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'jpeg';
  }
  if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50) {
    return 'png';
  }
  if (bytes.length >= 3 && bytes[0] == 0x47 && bytes[1] == 0x49) {
    return 'gif';
  }
  if (bytes.length >= 12 && bytes[8] == 0x57 && bytes[9] == 0x45) {
    return 'webp';
  }
  return 'other';
}

/// Handles one `anikumoImage` channel message SYNCHRONOUSLY
/// (all ops are CPU work in the `image` package) and returns
/// the JSON envelope string the JS shim unwraps.
String _anikumoImageOpSync(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return _anikumoImageReply(ok: false);
    final msg = decoded.cast<String, dynamic>();
    final fn = msg['function']?.toString() ?? '';
    int intOf(String name) => (msg[name] as num?)?.toInt() ?? 0;
    img.Image? imageOf(String name) =>
        _anikumoImageRegistry[(msg[name] as num?)?.toInt()];
    int register(img.Image image) {
      if (_anikumoImageRegistry.length >= 32) {
        _anikumoImageRegistry.clear();
      }
      final key = ++_anikumoImageSeq;
      _anikumoImageRegistry[key] = image;
      return key;
    }

    switch (fn) {
      case 'createFromBytes':
        final bytes = base64Decode(msg['dataB64']?.toString() ?? '');
        final image = img.decodeImage(bytes);
        if (image == null) return _anikumoImageReply(ok: false);
        return _anikumoImageReply(
          ok: true,
          v: register(image),
          fmt: _sniffImageFormat(bytes),
        );
      case 'encode':
        final image = imageOf('key');
        if (image == null) return _anikumoImageReply(ok: false);
        final bytes = msg['fmt']?.toString() == 'jpeg'
            ? img.encodeJpg(image, quality: 96)
            : img.encodePng(image);
        return _anikumoImageReply(ok: true, v: base64Encode(bytes));
      case 'copyRange':
        final image = imageOf('key');
        if (image == null) return _anikumoImageReply(ok: true);
        final copy = img.copyCrop(
          image,
          x: intOf('x'),
          y: intOf('y'),
          width: intOf('width'),
          height: intOf('height'),
        );
        return _anikumoImageReply(ok: true, v: register(copy));
      case 'copyAndRotate90':
        final image = imageOf('key');
        if (image == null) return _anikumoImageReply(ok: true);
        return _anikumoImageReply(
          ok: true,
          v: register(img.copyRotate(image, angle: 90)),
        );
      case 'fillImageAt':
        final dst = imageOf('key');
        final src = imageOf('image');
        if (dst == null || src == null) return _anikumoImageReply(ok: true);
        img.compositeImage(dst, src, dstX: intOf('x'), dstY: intOf('y'));
        return _anikumoImageReply(ok: true);
      case 'fillImageRangeAt':
        final dst = imageOf('key');
        final src = imageOf('image');
        if (dst == null || src == null) return _anikumoImageReply(ok: true);
        img.compositeImage(
          dst,
          src,
          dstX: intOf('x'),
          dstY: intOf('y'),
          srcX: intOf('srcX'),
          srcY: intOf('srcY'),
          srcW: intOf('width'),
          srcH: intOf('height'),
        );
        return _anikumoImageReply(ok: true);
      case 'getWidth':
        return _anikumoImageReply(ok: true, v: imageOf('key')?.width);
      case 'getHeight':
        return _anikumoImageReply(ok: true, v: imageOf('key')?.height);
      case 'emptyImage':
        return _anikumoImageReply(
          ok: true,
          v: register(img.Image(width: intOf('width'), height: intOf('height'))),
        );
      case 'releaseAll':
        _anikumoImageRegistry.clear();
        return _anikumoImageReply(ok: true);
      default:
        return _anikumoImageReply(ok: false);
    }
  } catch (_) {
    return _anikumoImageReply(ok: false);
  }
}

void _qjsIsolateMain(_QjsInit init) async {
  final uiPort = init.uiPort;
  final receive = ReceivePort();
  uiPort.send(['ready', receive.sendPort]);

  final qjs = FlutterQjs();
  unawaited(qjs.dispatch());
  // Batch 74: pending UI requests — a source's UI call waits
  // here until the UI isolate renders it and answers with
  // ['ui_result', id, json].
  var uiSeq = 0;
  final uiPending = <int, Completer<String>>{};
  try {
    // Inject the native bridge as a real Dart function —
    // the piece flutter_js could never provide. Dart Futures
    // returned here become JS Promises natively.
    final setter = qjs.evaluate('(function (k, v) { this[k] = v; })');
    (setter as JSInvokable).invoke([
      '__anikumoNativeBridge',
      (dynamic channel, dynamic payload) {
        if (channel == 'anikumoLog') {
          debugPrint('[js] ${payload?.toString()}');
          return null;
        }
        if (channel == 'anikumoPersist') {
          try {
            final decoded = jsonDecode(payload?.toString() ?? '');
            if (decoded is Map && decoded['key'] != null) {
              uiPort.send([
                'persist',
                decoded['key'].toString(),
                jsonEncode(decoded['kv'] ?? const {}),
              ]);
            }
          } catch (_) {}
          return null;
        }
        if (channel == 'anikumoPersistCookies') {
          // Batch 101: forward the jar snapshot to the UI
          // isolate, which owns storage.
          uiPort.send(['cookies', payload?.toString() ?? '{}']);
          return null;
        }
        if (channel == 'anikumoImage') {
          // Batch 103: synchronous image ops — the closure
          // returns a plain String here, which reaches JS as
          // a plain value (not a Promise), matching the
          // reference runtime's synchronous Image API.
          return _anikumoImageOpSync(payload?.toString() ?? '');
        }
        if (channel == 'anikumoUi') {
          final id = ++uiSeq;
          final completer = Completer<String>();
          uiPending[id] = completer;
          uiPort.send(['ui', id, payload?.toString() ?? '{}']);
          return completer.future;
        }
        return VeneraBridge.handle(payload?.toString() ?? '');
      },
    ]);
    setter.free();

    qjs.evaluate(veneraScriptStash);
    qjs.evaluate(veneraBridgeScript);
    qjs.evaluate(init.library);
    qjs.evaluate(veneraCompatScript);
    qjs.evaluate(veneraOverridesScript);
    // Batch 76: GBK codec — after the overrides (it binds
    // Convert.encodeGbk/decodeGbk and uses __anikumoBytes).
    qjs.evaluate(veneraGbkScript);
    qjs.evaluate(veneraDispatcherScript);
    // Batch 101: restore the persisted cookie jar (the
    // scripts just reset it to an empty object).
    try {
      qjs.evaluate('globalThis.__anikumoJar = ${init.cookiesJson};');
    } catch (_) {}
  } catch (e) {
    uiPort.send(['fatal', '引擎脚本初始化失败：$e']);
    return;
  }

  await for (final message in receive) {
    if (message is List && message.isNotEmpty) {
      if (message[0] == 'ui_result') {
        final completer = uiPending.remove(message[1]);
        if (completer != null && !completer.isCompleted) {
          completer.complete(message[2]?.toString() ?? 'null');
        }
        continue;
      }
      unawaited(_qjsHandleTask(qjs, uiPort, message));
    }
  }
}

Future<void> _qjsHandleTask(
  FlutterQjs qjs,
  SendPort uiPort,
  List<dynamic> message,
) async {
  final kind = message[0];
  if (kind == 'unregister') {
    try {
      qjs.evaluate(
        'delete globalThis.__anikumoSources[${jsonEncode(message[1])}];'
        'delete globalThis.__anikumoKvByKey[${jsonEncode(message[1])}];',
      );
    } catch (_) {}
    return;
  }
  final id = message[1] as int;
  try {
    if (kind == 'ping') {
      // Batch 101: liveness probe — deliberately evaluates
      // NOTHING. If this handler can run at all, the
      // isolate's event loop is turning; a wedged JS thread
      // blocks the loop itself, so the probe's absence is
      // the signal.
      uiPort.send(['result', id, true, 'pong']);
    } else if (kind == 'register') {
      final jsKey = message[2] as String;
      final code = message[3] as String;
      final kvJson = message[4] as String;
      final className = VeneraEngine.extractClassName(code);
      if (className == null) {
        throw const FormatException('源文件里没有找到 extends ComicSource 的类');
      }
      qjs.evaluate(
        'globalThis.__anikumoKvByKey[${jsonEncode(jsKey)}] = $kvJson;',
      );
      qjs.evaluate(veneraWrapSourceScript(className, jsKey, code));
      // Batch 37: wait for the source's async init() to
      // settle (bounded) — several sources fetch config in
      // init and break if a call lands first. A slow or
      // failed init must not block registration (the
      // warning path below still applies).
      try {
        final dynamic initPromise = qjs.evaluate(
          '(globalThis.__anikumoInitPromises || {})'
          '[${jsonEncode(jsKey)}] || null',
        );
        if (initPromise is Future) {
          await initPromise.timeout(const Duration(seconds: 15));
        }
      } catch (_) {}
      final initError = qjs.evaluate(
        '(globalThis.__anikumoInitErrors || {})[${jsonEncode(jsKey)}] || null',
      );
      if (initError != null && initError.toString().isNotEmpty) {
        throw StateError('源初始化失败：$initError');
      }
      final instanceKey = qjs.evaluate(
        '(globalThis.__anikumoSources[${jsonEncode(jsKey)}] || {}).key'
        ' || ${jsonEncode(jsKey)}',
      );
      uiPort.send(['result', id, true, instanceKey.toString()]);
    } else if (kind == 'call') {
      final jsKey = message[2] as String;
      final callKind = message[3] as String;
      final argsJson = message[4] as String;
      // The dispatcher is an async JS function: evaluate
      // returns a Dart Future for its Promise natively.
      final dynamic pending = qjs.evaluate(
        '__anikumoCall(${jsonEncode(jsKey)}, ${jsonEncode(callKind)},'
        ' $argsJson)',
      );
      final dynamic result = pending is Future ? await pending : pending;
      uiPort.send(['result', id, true, result?.toString() ?? '']);
    } else {
      uiPort.send(['result', id, false, 'unknown task: $kind']);
    }
  } catch (e) {
    uiPort.send(['result', id, false, e.toString()]);
  }
}
