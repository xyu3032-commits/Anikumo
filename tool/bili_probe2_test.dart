// Batch 50 probe 2: skip search (this host's IP gets an
// empty /search response). Hand-build the item exactly as
// the phone would hold it (bookUrl on the .com domain from
// the source def) and run bookInfo -> chapters through the
// production LegadoNovelSource.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_parse.dart';
import 'package:anikumo/services/novel/novel_source.dart';

Future<LegadoSourceDef> loadDef(String asset) async {
  final text = await File(asset).readAsString();
  return LegadoSourceDef.fromJson(
    LegadoParse.parseSourceArray(text).single,
    builtin: true,
  )!;
}

void main() {
  test('bilinovel info+chapters from a .com bookUrl', () async {
    final def = await loadDef('assets/legado/bilinovel.json');
    final source = LegadoNovelSource(def);
    final item = NovelItem(
      title: 'probe',
      bookUrl: 'https://www.bilinovel.com/novel/5131.html',
      source: def.id,
    );

    // Batch 174: the MoYuan engine's bookInfo returns the
    // enriched item alone (the bridge resolves the toc
    // address internally; it is no longer surfaced).
    final enriched = await source.engine.bookInfo(item);
    // ignore: avoid_print
    print('INFO title=${enriched.title} author=${enriched.author} '
        'cover=${enriched.coverUrl}');

    try {
      final chapters = await source.chapters(item);
      // ignore: avoid_print
      print('CHAPTERS: ${chapters.length}');
      for (final c in chapters.take(3)) {
        // ignore: avoid_print
        print('  * ${c.title} -> ${c.url} webView=${c.webView}');
      }
      if (chapters.isNotEmpty) {
        final blocks = await source.content(item, chapters.first);
        // ignore: avoid_print
        print('CONTENT blocks: ${blocks.length}');
      }
    } catch (e) {
      // ignore: avoid_print
      print('CHAIN ERROR: $e');
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
