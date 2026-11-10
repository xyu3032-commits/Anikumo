import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/novel_source.dart';
import 'package:anikumo/services/storage/storage.dart';

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

// Batch 186 diagnosis (user report, v54/B185): the novel
// reader renders a finished, empty chapter for EVERY
// source — no spinner, no error, no empty-state — while
// the in-app diagnostics (NovelApi.content) returns blocks
// for the same sources. This probe drives the READER's
// exact call (LegadoNovelSource.contentDetailed) through
// the full search -> bookInfo -> chapters flow with the
// user's own 22k definition and prints what comes back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b186probe');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    // The test binding's mock HttpClient 400s everything;
    // this probe is a live-chain diagnosis, so restore the
    // real client.
    HttpOverrides.global = null;
  });
  test('22k reader-path content', () async {
    final json = jsonDecode(
      await File(
        '/home/hatch/workspace/kazumi_analysis/b186_probe/def_22k.json',
      ).readAsString(),
    ) as Map<String, dynamic>;
    final def = LegadoSourceDef.fromJson(json)!;
    final source = LegadoNovelSource(def);

    final results = await source.search('斗罗大陆');
    print('== search: ${results.length} items');
    var item = results.first;
    print('== first: ${item.title} bookUrl=${item.bookUrl}');
    item = await source.bookInfo(item);
    print('== after bookInfo: bookUrl=${item.bookUrl}');
    final chapters = await source.chapters(item);
    print('== chapters: ${chapters.length}');
    final chapter = chapters.first;
    print('== chapter[0]: ${chapter.title} url=${chapter.url} '
        'webView=${chapter.webView}');

    final detailed = await source.contentDetailed(item, chapter);
    print('== contentDetailed: ${detailed.blocks.length} blocks, '
        'truncated=${detailed.possiblyTruncated}, '
        'haveContent=${novelBlocksHaveContent(detailed.blocks)}');
    for (final b in detailed.blocks.take(3)) {
      print('   block: ${b.runtimeType} '
          '${b is NovelTextBlock ? b.text.substring(0, b.text.length > 40 ? 40 : b.text.length) : (b as NovelImageBlock).url}');
    }
    final plain = await source.content(item, chapter);
    print('== content(): ${plain.length} blocks, '
        'haveContent=${novelBlocksHaveContent(plain)}');

    // Batch 187 measurement: find the first TEXT chapter
    // (22k mixes comic versions in) and report its real
    // size through the same engine path.
    for (var i = 0; i < chapters.length && i < 8; i++) {
      final r = await source.contentDetailed(item, chapters[i]);
      final chars = r.blocks
          .whereType<NovelTextBlock>()
          .fold<int>(0, (sum, b) => sum + b.text.length);
      if (chars > 0) {
        print('== text chapter[$i] "${chapters[i].title}": '
            '${r.blocks.length} blocks, $chars chars, '
            'truncated=${r.possiblyTruncated}');
        break;
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
