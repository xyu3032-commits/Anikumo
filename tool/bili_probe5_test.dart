// Batch 50 probe 5: which content-encoding does each page
// get when the engine's exact headers are sent?
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_parse.dart';

Future<LegadoSourceDef> loadDef(String asset) async {
  final text = await File(asset).readAsString();
  return LegadoSourceDef.fromJson(
    LegadoParse.parseSourceArray(text).single,
    builtin: true,
  )!;
}

void main() {
  test('encodings per page', () async {
    final def = await loadDef('assets/legado/bilinovel.json');
    // ignore: avoid_print
    print('DEF HEADERS: ${def.headers}');
    final dio = Dio(BaseOptions(
      responseType: ResponseType.bytes,
      validateStatus: (_) => true,
    ));
    for (final url in [
      'https://www.bilinovel.net/novel/5131.html',
      'https://www.bilinovel.net/novel/5131/catalog',
    ]) {
      final r = await dio.get<List<int>>(url,
          options: Options(headers: def.headers));
      final bytes = r.data!;
      // ignore: avoid_print
      print('$url enc=${r.headers.value('content-encoding')} '
          'len=${bytes.length} first=${bytes.take(6).toList()}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
