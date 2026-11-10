// ignore_for_file: avoid_print
// Batch 161 matrix probe #2: private-name variants with
// correct scoping, plus modern syntax checks in statement
// form. Hunting the exact "invalid first character of
// private name" throw.
import 'dart:io';

import 'package:anikumo/services/novel/legado_js.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b161n_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('private name matrix', () async {
    final host = LegadoJsHost.forSource('matrix2', null);
    final cases = <String, String>{
      'pf baseline': 'class A { #x = 1; get v() { return this.#x; } } new A().v;',
      'pf cjk name': 'class A { #数据 = 1; get v() { return this.#数据; } } new A().v;',
      'pf digit after hash': '#1;',
      'pf method': 'class A { #m() { return 3; } call() { return this.#m(); } } new A().call();',
      'pf static': 'class A { static #s = 4; static get() { return A.#s; } } A.get();',
      'pf getter': 'class A { #x = 5; get #y() { return this.#x; } get v() { return this.#y; } } new A().v;',
      'optional chain': 'var o = {a: {b: 5}}; o?.a?.b;',
      'optional chain null': 'var o2 = null; o2?.a;',
      'nullish': 'var n = null; n ?? 42;',
      'array at via stmt': 'var arr = [1, 2, 3]; arr.at(-1);',
      'hash in ident pos': 'var o3 = {}; o3.#p = 1;',
      'css id concat': 'var id = "list"; "#" + id;',
      'selector string': 'java.getString("x");',
      'spread call': 'var f = function () { return arguments.length; }; f(...[1, 2]);',
      'async fn decl': 'async function af() { return 1; } typeof af;',
      'generator': 'function* g() { yield 1; } g().next().value;',
      'unicode ident var': 'var 数据 = 3; 数据 + 1;',
      'regex unicode flag': '"abc".match(/b/u)[0];',
      'regex sticky': '"abc".match(/b/y)[0];',
      'named groups': '"a1".match(/(?<d>\\d)/).groups.d;',
      'lookbehind': '"a1".match(/(?<=a)\\d/)[0];',
      'dotAll': '"a\\nb".match(/a.b/s)[0].length;',
      'promise finally': 'typeof Promise.prototype.finally;',
      'object hasOwn': 'typeof Object.hasOwn;',
      'structuredClone': 'typeof structuredClone;',
      'string matchAll str': '"x".matchAll(/x/g); "ok";',
    };
    for (final entry in cases.entries) {
      try {
        final out = await host.run(code: entry.value, baseUrl: 'http://x/');
        print('CASE ${entry.key} => OK $out');
      } catch (e) {
        print('CASE ${entry.key} => ERROR $e');
      }
    }
  });
}
