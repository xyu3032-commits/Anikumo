// ignore_for_file: avoid_print
// Batch 161 scope probe: does a jsLib top-level binding
// survive into later LegadoJsHost.run() calls? Compares
// var / let / const / function declarations, and plain
// assignment. Real Legado keeps ONE scope per source, so
// sources that stash state in jsLib globals (mirror hosts,
// tokens) break with "X is not defined" if these do not
// persist.
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
    final dir = await Directory.systemTemp.createTemp('b161s_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
  });

  test('jsLib binding persistence', () async {
    const lib = '''
var vVar = 'var-ok';
let vLet = 'let-ok';
const vConst = 'const-ok';
function vFn() { return 'fn-ok'; }
vBare = 'bare-ok';
class vCls { static hi() { return 'cls-ok'; } }
''';
    final host = LegadoJsHost.forSource(
      'scope-probe',
      lib,
      sourceName: 'scope-probe',
    );
    for (final expr in [
      'vVar',
      'vLet',
      'vConst',
      'vFn()',
      'vBare',
      'vCls.hi()',
    ]) {
      try {
        final out = await host.run(code: '($expr)', baseUrl: 'http://x/');
        print('EXPR $expr => $out');
      } catch (e) {
        print('EXPR $expr => ERROR $e');
      }
    }
    // Mutation persistence: a run that bumps a jsLib var,
    // then a later run reads it.
    try {
      await host.run(code: '(vVar = "var-mutated")', baseUrl: 'http://x/');
      final out = await host.run(code: '(vVar)', baseUrl: 'http://x/');
      print('MUTATE var => $out');
    } catch (e) {
      print('MUTATE var => ERROR $e');
    }
    try {
      await host.run(code: '(vLet = "let-mutated")', baseUrl: 'http://x/');
      final out = await host.run(code: '(vLet)', baseUrl: 'http://x/');
      print('MUTATE let => $out');
    } catch (e) {
      print('MUTATE let => ERROR $e');
    }
  });
}
