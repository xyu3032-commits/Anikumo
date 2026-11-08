// Batch 104 benchmark probe (no external site): what does
// first-touching N installed JS sources cost on the shared
// QuickJS runtime? Each synthetic source carries ~40 KB of
// code (the size class of real-world sources) and answers
// search with a small JSON list. Registration is lazy, so
// this measures exactly what the home bands / explore /
// search pay the first time each source is used in a
// session.
// Run: LD_LIBRARY_PATH=/tmp/qjsbuild flutter test tool/many_sources_bench_probe.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/storage/storage.dart';
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

String sourceCode(String key) {
  final filler = 'x'.padLeft(40000, 'a');
  return '''
class S$key extends ComicSource {
  name = "S$key";
  key = "$key";
  version = "1.0.0";
  minAppVersion = "1.0.0";
  url = "http://127.0.0.1:9";
  _pad = "$filler";
  search = {
    load: async (keyword, options, page) => {
      return { comics: [{ id: "1", title: "t", cover: "", tags: [] }], maxPage: 1 };
    }
  };
  comic = {
    loadInfo: async (id) => {
      return { title: "t", cover: "", description: "", tags: {}, chapters: { e1: "第一话" } };
    }
  };
}
''';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first touch of 30 sources: register + one call each', () async {
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('many_sources_bench');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();

    const n = 30;
    final sources = [
      for (var i = 0; i < n; i++)
        JsMangaSource(
          jsKey: 'bench_$i',
          displayName: 'Bench $i',
          version: '1.0.0',
          fileName: 'bench_$i.js',
          code: sourceCode('bench_$i'),
        ),
    ];

    final totalWatch = Stopwatch()..start();
    var worst = 0;
    for (final source in sources) {
      final watch = Stopwatch()..start();
      final items = await source.search('key');
      watch.stop();
      expect(items.length, 1);
      if (watch.elapsedMilliseconds > worst) {
        worst = watch.elapsedMilliseconds;
      }
    }
    totalWatch.stop();
    // ignore: avoid_print
    print(
      'BENCH first-touch x$n: total ${totalWatch.elapsedMilliseconds} ms, '
      'avg ${(totalWatch.elapsedMilliseconds / n).toStringAsFixed(1)} ms, '
      'worst $worst ms',
    );

    // Second touch: registration is memoized — calls only.
    final secondWatch = Stopwatch()..start();
    for (final source in sources) {
      await source.search('key');
    }
    secondWatch.stop();
    // ignore: avoid_print
    print('BENCH second-touch x$n: total ${secondWatch.elapsedMilliseconds} ms');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
