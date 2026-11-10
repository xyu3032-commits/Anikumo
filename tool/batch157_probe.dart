// Batch 157 probe (desktop QuickJS + local HTTP only):
// mainstream Legado bundle shapes that used to error out —
// 1. a searchUrl starting with {{cookie.removeCookie(...)}}
//    (the braces used to reach the server verbatim),
// 2. an explore URL carrying {{cookie.getKey(...)}},
// 3. jsLib functions and ternaries inside {{...}},
// 4. the prelude tail: cookie / cache / toast / connect /
//    getStringList / source identity.
import 'dart:convert';
import 'dart:io';

import 'package:anikumo/services/novel/legado_def.dart';
import 'package:anikumo/services/novel/legado_engine.dart';
import 'package:anikumo/services/novel/legado_http.dart';
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

  late HttpServer server;
  late String base;
  final seen = <String>[];

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('b157_hive');
    PathProviderPlatform.instance = _TestPaths(dir.path);
    Hive.init(dir.path);
    await GStorage.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final path = req.uri.path;
      seen.add('${req.method} ${req.uri}');
      if (path == '/set') {
        req.response.headers.add(
          'Set-Cookie',
          '_csrfToken=tok123; Path=/',
        );
        req.response.write('ok');
      } else if (path.startsWith('/search')) {
        final bytes = <int>[];
        await for (final chunk in req) {
          bytes.addAll(chunk);
        }
        final body = utf8.decode(bytes);
        seen.add('BODY $body');
        req.response.headers.contentType = ContentType.html;
        req.response.write(
          '<html><body><div class="book">'
          '<a class="t" href="/b/1">斗罗大陆</a>'
          '<span class="a">唐家三少</span></div></body></html>',
        );
      } else if (path == '/rank') {
        seen.add('TOKEN ${req.uri.queryParameters['token']}');
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'data': [
            {'name': '剑来', 'id': 9},
          ],
        }));
      } else if (path == '/echo') {
        req.response.write('ECHO-OK');
      } else {
        req.response.statusCode = 404;
        req.response.write('nf');
      }
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  LegadoSourceDef defOf(Map<String, dynamic> json) =>
      LegadoSourceDef.fromJson(json)!;

  test('searchUrl with a cookie template prefix fetches clean', () async {
    final def = defOf({
      'bookSourceName': '探针甲',
      'bookSourceUrl': '$base/ma',
      'searchUrl':
          '{{cookie.removeCookie("$base")}} $base/search,{"method":"POST","body":"keyboard={{key}}"}',
      'ruleSearch': {
        'bookList': 'class.book',
        'name': 'class.t@text',
        'author': 'class.a@text',
        'bookUrl': 'class.t@href',
      },
    });
    final items = await LegadoEngine(def).search('斗罗');
    expect(items, hasLength(1));
    expect(items.single.title, '斗罗大陆');
    expect(items.single.author, '唐家三少');
    expect(seen.any((s) => s.startsWith('POST /search')), isTrue);
    expect(seen.any((s) => s.contains('{{')), isFalse,
        reason: 'no template braces may reach the server: $seen');
    expect(seen.any((s) => s == 'BODY keyboard=%E6%96%97%E7%BD%97'), isTrue,
        reason: 'POST body template filled: $seen');
  });

  test('explore URL reads the CSRF cookie out of the jar', () async {
    await LegadoHttp.fetchRaw('$base/set');
    final def = defOf({
      'bookSourceName': '探针乙',
      'bookSourceUrl': '$base/mb',
      'searchUrl': '$base/search',
      'exploreUrl': jsonEncode([
        {
          'title': '月票榜',
          'url':
              '/rank?token={{cookie.getKey("$base","_csrfToken")}}&page={{page}}',
        },
      ]),
      'ruleExplore': {
        'bookList': r'$.data[*]',
        'name': r'$.name',
        'bookUrl': r'/book/{{$.id}}',
      },
    });
    final cats = def.exploreCategories;
    expect(cats, hasLength(1));
    final items = await LegadoEngine(def).explore(cats.single);
    expect(items, hasLength(1));
    expect(items.single.title, '剑来');
    expect(items.single.bookUrl, '$base/book/9');
    expect(seen.any((s) => s == 'TOKEN tok123'), isTrue,
        reason: 'cookie.getKey resolved from the jar: $seen');
  });

  test('jsLib functions and ternaries in URL templates', () async {
    final def = defOf({
      'bookSourceName': '探针丙',
      'bookSourceUrl': '$base/mc',
      'jsLib': 'function bhost() { return "$base"; }',
      'searchUrl': "{{bhost()}}/search{{page==1?'':'_'+page}}",
      'ruleSearch': {
        'bookList': 'class.book',
        'name': 'class.t@text',
        'bookUrl': 'class.t@href',
      },
    });
    final items = await LegadoEngine(def).search('x', page: 2);
    expect(items, hasLength(1));
    expect(seen.any((s) => s == 'GET /search_2'), isTrue,
        reason: 'jsLib + ternary resolved: $seen');
  });

  test('prelude tail: cookie/cache/toast/connect/source', () async {
    final host = LegadoJsHost.forSource(
      'probe157',
      null,
      sourceName: '探针宿主',
    );
    final r1 = await host.run(
      code: "java.toast('x'); java.longToast('y');"
          "Packages.java.lang.Thread.sleep(1);"
          "cache.put('k', 'v1', 60);"
          "cookie.setKey('$base', 'sess', 's-1');"
          "[source.getKey(), source.bookSourceName].join('|')",
      baseUrl: base,
    );
    expect(r1, 'probe157|探针宿主');
    expect(LegadoHttp.cookieHeaderFor('$base/x'), contains('sess=s-1'));
    final r2 = await host.run(
      code: "java.connect('$base/echo').body() + '|' + cache.get('k') + '|' +"
          "cookie.getKey('$base', 'sess') + '|' + java.getWebViewUA().length",
      baseUrl: base,
    );
    expect(r2, startsWith('ECHO-OK|v1|s-1|'));
    final r3 = await host.run(
      code: r"java.getStringList('$.a').join(',')",
      result: {
        'a': [1, 2, 3],
      },
      baseUrl: base,
    );
    expect(r3, '1,2,3');
  });
}
