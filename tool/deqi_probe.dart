import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/novel_source.dart';

void main() {
  test('deqi/kuaishu full errors', () async {
    final text = await File('/tmp/xiu2.json').readAsString();
    final defs = (jsonDecode(text) as List).cast<Map<String, dynamic>>();
    for (final name in ['得奇小说网', '快书网', '铅笔小说']) {
      final json = defs.firstWhere((d) => d['bookSourceName'] == name);
      final def = LegadoSourceDef.fromJson(json)!;
      final source = LegadoNovelSource(def);
      final cat = source.exploreCategories.first;
      try {
        final items = await source.explore(cat, page: 1);
        print('== $name [${cat.title}] ${items.length} items');
      } catch (e) {
        print('== $name [${cat.title}] ERROR>>> ${e.toString().replaceAll('\n', ' | ')}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
