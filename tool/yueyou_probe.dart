// Batch 36 probe: 阅友小说 explore through the full
// production Legado path (real fetch + real JS host).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/novel_source.dart';

void main() {
  test('yueyou explore', () async {
    final text = await File('/tmp/xiu2.json').readAsString();
    final defs = (jsonDecode(text) as List).cast<Map<String, dynamic>>();
    final json = defs.firstWhere((d) => d['bookSourceName'] == '阅友小说');
    final def = LegadoSourceDef.fromJson(json)!;
    final source = LegadoNovelSource(def);
    for (final cat in source.exploreCategories.take(3)) {
      try {
        final items = await source.explore(cat, page: 1);
        print('== [${cat.title}] ${items.length} items');
        for (final it in items.take(2)) {
          print('   - ${it.title} | ${it.bookUrl}');
        }
      } catch (e) {
        print('== [${cat.title}] ERROR: $e');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
