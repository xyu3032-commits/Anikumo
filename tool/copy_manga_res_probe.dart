// Batch 69-side diagnosis (device report 2026-11-08):
// CopyManga loadInfo throws "ReferenceError: res is not
// defined". Offline proof with a stubbed Network — no
// real site is contacted. Two scenarios over the user's
// own pasted source file (/tmp/copy_manga_user.js):
//  A) comic2 answers 200 → loadInfo succeeds.
//  B) comic2 answers 403 → the res ReferenceError fires,
//     i.e. the source's own error path is broken, and the
//     real failure (non-200) hides behind it.
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

const _stubs = r'''
class ComicSource {
  loadData(k) { return (this.__data || {})[k]; }
  saveData(k, v) { this.__data = this.__data || {}; this.__data[k] = v; }
  deleteData(k) { if (this.__data) delete this.__data[k]; }
  loadSetting(k) {
    const s = this.settings && this.settings[k];
    if (s && s.default !== undefined) return s.default;
    if (k === 'base_url') return 'api.example.test';
    if (k === 'region') return '0';
    return null;
  }
}
function randomInt(a, b) { return a; }
var APP = { version: '2.4.3' };
var Convert = {
  decodeBase64: function (s) { return 'key'; },
  encodeUtf8: function (s) { return s; },
  encodeBase64: function (s) { return s; },
  hmacString: function (k, d, a) { return 'sig'; },
};
var __MODE = 'ok';
var Network = {
  get: async function (url, headers) {
    if (url.indexOf('marketing.') >= 0) {
      return { status: 200, body: '{"results":{"request_id":"r1"}}' };
    }
    if (url.indexOf('/comic2/') >= 0 && url.indexOf('/query') >= 0) {
      return { status: 200, body: '{"results":{"collect":null}}' };
    }
    if (url.indexOf('/comic2/') >= 0) {
      if (__MODE === 'fail') return { status: 403, body: '{}' };
      return { status: 200, body: JSON.stringify({ results: {
        comic: {
          name: 'T', cover: 'c', uuid: 'u1', brief: 'b',
          datetime_updated: '2026-01-01',
          author: [{ name: 'A', path_word: 'a1' }],
          theme: [{ name: 'X' }],
          status: { display: '连载中' },
        },
        groups: { default: { name: '默认', path_word: 'default' } },
      } }) };
    }
    if (url.indexOf('/group/') >= 0) {
      return { status: 200, body: JSON.stringify({ results: {
        list: [{ name: '第1话', uuid: 'e1' }], total: 1 } }) };
    }
    return { status: 404, body: '{}' };
  },
  post: async function (url, headers, body) {
    return { status: 200, body: '{}' };
  },
};
''';

Future<(String?, String?)> _runLoadInfo(
  JavascriptRuntime runtime,
  String mode,
) async {
  runtime.evaluate('__MODE = ${mode == 'fail' ? "'fail'" : "'ok'"};');
  runtime.evaluate('''
globalThis.__out = null; globalThis.__err = null;
__src.comic.loadInfo('some-comic').then(function (r) {
  var ch = r.chapters;
  var n = 0;
  if (ch && typeof ch.forEach === 'function') ch.forEach(function (v) { n += (v && v.size !== undefined) ? v.size : 1; });
  globalThis.__out = 'title=' + r.title + ';groups-in-chapters=' + n + ';fav=' + r.isFavorite;
}).catch(function (e) {
  globalThis.__err = String((e && e.name) || '') + ': ' +
      String((e && e.message) || e) + ' | ' + String((e && e.stack) || '');
});
''');
  for (var i = 0; i < 200; i++) {
    runtime.executePendingJob();
    final done = runtime.evaluate('__out !== null || __err !== null');
    if (done.stringResult == 'true') break;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  final out = runtime.evaluate('__out');
  final err = runtime.evaluate('__err');
  return (
    out.stringResult == 'null' ? null : out.stringResult,
    err.stringResult == 'null' ? null : err.stringResult,
  );
}

void main() {
  test('copy_manga loadInfo: 200 works, non-200 hits the res bug',
      () async {
    final code = await File('/tmp/copy_manga_user.js').readAsString();
    final runtime = getJavascriptRuntime(xhr: false);
    runtime.evaluate(_stubs);
    runtime.evaluate(code);
    runtime.evaluate('globalThis.__src = new CopyManga(); __src.init();');

    final ok = await _runLoadInfo(runtime, 'ok');
    // ignore: avoid_print
    print('MODE ok  -> out: ${ok.$1} | err: ${ok.$2}');
    expect(ok.$2, isNull, reason: 'with comic2=200 loadInfo must succeed');
    expect(ok.$1, contains('title=T'));

    final fail = await _runLoadInfo(runtime, 'fail');
    // ignore: avoid_print
    print('MODE fail -> out: ${fail.$1} | err: ${fail.$2}');
    expect(fail.$1, isNull);
    expect(fail.$2, contains("'res' is not defined"),
        reason: 'the source checks res.status after renaming to results');
  });
}
