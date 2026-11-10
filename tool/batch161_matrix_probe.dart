// ignore_for_file: avoid_print
// Batch 161 matrix probe: which JS constructs make THIS
// QuickJS throw "invalid first character of private name"
// (or any error)? Candidates gathered from real-world
// Legado source idioms.
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
    final dir = await Directory.systemTemp.createTemp('b161m_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('construct matrix', () async {
    final host = LegadoJsHost.forSource('matrix', null);
    final cases = <String, String>{
      'private field decl': '(class A { #x = 1; get v() { return this.#x; } }, new A().v)',
      'private field access': '(class A { #x = 2; }, 0)',
      'private in check': '(class A { static is(o) { return #x in o; } #x = 1; }, A.is(new A()))',
      'bare hash ident': '(x = #y)',
      'hash in regex': '("a#b".replace(/#/, "-"))',
      'hash char class': '("a#b".match(/[#]/)[0])',
      'hash template': '(`#${1+1}`)',
      'obj hash key': '({ "#k": 1 }["#k"])',
      'jqueryish string': r'''(String("$('#id')"))''',
      'url hash var': '(function(){ var u = "http://x/#/p"; return u.split("#")[1]; })()',
      'optional chain': '(var o = null; o?.a?.b)',
      'nullish': '(var n = null; n ?? 42)',
      'logical assign': '(var a = 1; a &&= 2; a)',
      'numeric sep': '(100_000)',
      'replaceAll': '("a-b-c".replaceAll("-", "+"))',
      'matchAll': '(Array.from("a1b2".matchAll(/\\d/g)).length)',
      'object spread': '({...{a:1}, b: 2}).b',
      'array at': '([1,2,3].at(-1))',
      'string at': '("abc".at(-1))',
      'hashbang mid': '(1 + 1)',
      'globalThis': '(typeof globalThis)',
      'bigint': '(10n + 1n).toString()',
      'top await-ish': '(Promise.resolve(3))',
      'class static block': '(class A { static { A.x = 5; } }, A.x)',
      'error cause': '(new Error("e", {cause: 1}).cause)',
      'findLast': '([1,2,3].findLast(x => x > 1))',
      'toSorted': '([3,1,2].toSorted())',
      'unicode escape ident': '(var \\u0061bc = 7; abc)',
      'legacy octal': '(010)',
      'getter in literal': '({ get x() { return 9; } }.x)',
      'labeled break': '(function(){ l: for (var i = 0; i < 3; i++) { if (i == 1) break l; } return i; })()',
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
