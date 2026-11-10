// Batch 174 probe: can the flutter_js QuickJS runtime
// (a) resolve a JS Promise from an async Dart channel
// handler, and (b) let Dart await a JS Promise via
// pending-job pumping? The MoYuan bridge design stands
// or falls on these two directions.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String?> pumpUntil(
  JavascriptRuntime runtime,
  String readExpr, {
  int rounds = 200,
  Future<void> Function()? tick,
}) async {
  for (var i = 0; i < rounds; i++) {
    runtime.executePendingJob();
    final r = runtime.evaluate(readExpr);
    if (!r.isError &&
        r.stringResult != 'null' &&
        r.stringResult != 'pending' &&
        r.stringResult.isNotEmpty) {
      return r.stringResult;
    }
    if (tick != null) {
      await tick();
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('host promises via callback registry; JS promise readable',
      (tester) async {
    final runtime = QuickJsRuntime2();
    addTearDown(runtime.dispose);
    // The pattern the MoYuan host will use: JS wraps
    // sendMessage in its own Promise registry; Dart
    // completes calls by evaluating the resolver.
    runtime.onMessage('probeEcho', (dynamic args) {
      final map = (args as Map).cast<String, dynamic>();
      final id = map['id'] as int;
      final payload = map['payload'];
      // ignore: avoid_print
      print('handler fired id=$id payload=$payload');
      Future<void>.delayed(const Duration(milliseconds: 30), () {
        final done = runtime.evaluate(
          '__hostComplete($id, ${jsonEncode(jsonEncode({'echo': payload, 'ok': true}))})',
        );
        // ignore: avoid_print
        print('complete evaluate isError=${done.isError} result=${done.stringResult}');
      });
      return null;
    });
    final boot = runtime.evaluate('''
      globalThis.__hostCallbacks = {};
      globalThis.__hostSeq = 0;
      globalThis.hostCall = (payload) => new Promise((resolve, reject) => {
        const id = ++globalThis.__hostSeq;
        globalThis.__hostCallbacks[id] = {resolve, reject};
        sendMessage('probeEcho', JSON.stringify({id, payload}));
      });
      globalThis.__hostComplete = (id, json) => {
        const cb = globalThis.__hostCallbacks[id];
        delete globalThis.__hostCallbacks[id];
        if (cb) cb.resolve(JSON.parse(json));
      };
      globalThis.__r1 = 'pending';
      globalThis.__r2 = 'pending';
      hostCall({x: 41})
        .then(v => { globalThis.__r1 = JSON.stringify(v); })
        .catch(e => { globalThis.__r1 = 'ERR:' + e; });
      (async () => {
        const v = await hostCall({y: 7});
        return 'async:' + JSON.stringify(v);
      })().then(s => { globalThis.__r2 = s; })
        .catch(e => { globalThis.__r2 = 'ERR:' + e; });
    ''');
    expect(boot.isError, isFalse, reason: boot.stringResult);
    Future<void> tick() => tester.pump(const Duration(milliseconds: 10));
    final r1 = await pumpUntil(runtime, 'String(globalThis.__r1)', tick: tick);
    expect(r1, contains('"x":41'), reason: 'r1=$r1');
    expect(r1, contains('"ok":true'));
    final r2 = await pumpUntil(runtime, 'String(globalThis.__r2)', tick: tick);
    expect(r2, contains('"y":7'), reason: 'r2=$r2');
  });

  test('the real MoYuan bundle loads and builds a bridge', () async {
    final bundleFile = File('../../../moyuan/dist/moyuan.js');
    expect(bundleFile.existsSync(), isTrue);
    final runtime = QuickJsRuntime2();
    addTearDown(runtime.dispose);
    final loaded = runtime.evaluate(bundleFile.readAsStringSync());
    expect(loaded.isError, isFalse, reason: loaded.stringResult);
    final probe = runtime.evaluate('''
      JSON.stringify({
        hasMoYuan: typeof MoYuan === 'object',
        hasQuickJsFactory: typeof MoYuan.createQuickJSEngine === 'function',
        hasBridgeFactory: typeof MoYuan.createAnikumoBridge === 'function',
        hasImport: typeof MoYuan.importAnikumoInstalledJson === 'function',
      })
    ''');
    expect(probe.isError, isFalse, reason: probe.stringResult);
    expect(probe.stringResult, contains('"hasMoYuan":true'));
    expect(probe.stringResult, contains('"hasQuickJsFactory":true'));
    expect(probe.stringResult, contains('"hasBridgeFactory":true'));
    expect(probe.stringResult, contains('"hasImport":true'));
  });
}
