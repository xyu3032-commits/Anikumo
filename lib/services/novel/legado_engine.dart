import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../models/novel_item.dart';
import 'legado_def.dart';
import 'legado_dom.dart';
import 'legado_http.dart';
import 'legado_js.dart';
import 'legado_parse.dart';

/// The Legado rule engine: runs one source definition's
/// search / explore / info / toc / content rules against
/// live pages, ReadCat-style — CSS (jsoup subset) + JSONPath
/// + `##` replacements + `<js>` blocks over the QuickJS
/// bridge in legado_js.dart.
///
/// Supported subset (honest scope): GET/POST with headers
/// and URL option objects, {{key}}/{{page}} templates,
/// @css selectors with @text/@ownText/@html/@attr, $. JSON
/// paths, key lookups on JS-returned objects, JS with the
/// java shim (getElements/getElement/getString/ajax/post/
/// md5/base64/put/get/log/timeFormat), jsLib, next-content
/// pagination, content replaceRegex. NOT supported: XPath
/// rules, login flows, cookie jars, WebView-rendered pages,
/// GBK decoding — sources needing those throw or return
/// empty and the UI says so per source.
class LegadoEngine {
  LegadoEngine(this.def);

  final LegadoSourceDef def;

  LegadoJsHost get _js => LegadoJsHost.forSource(def.id, def.jsLib);

  // ------------------------------------------------------------
  // Contexts
  // ------------------------------------------------------------

  /// A fetched page in every form the rules might need.
  Future<_Page> _fetchPage(String urlSpec) async {
    final response = await LegadoHttp.fetch(
      urlSpec,
      sourceHeaders: def.headers,
    );
    if (response.statusCode >= 400) {
      throw StateError('源站返回 ${response.statusCode}');
    }
    dynamic json;
    try {
      json = jsonDecode(response.body);
    } catch (_) {}
    return _Page(
      body: response.body,
      url: response.url,
      requestUrl: urlSpec,
      json: json,
      doc: json == null ? LegadoDom.parseHtml(response.body) : null,
    );
  }

  // ------------------------------------------------------------
  // Public flows
  // ------------------------------------------------------------

  /// Batch 31: turn a declared URL field (searchUrl /
  /// explore entry) into a fetchable absolute spec. Handles
  /// the three shapes real bundles use: '@js:' / whole-field
  /// '<js>' scripts that COMPUTE the URL (evaluated with
  /// key/page/baseUrl bound), the embedded-literal idiom
  /// (classified back to a literal), and relative specs
  /// (resolved against the source's own origin — most
  /// curated sources declare only a path).
  Future<String> _requestUrl(
    String spec, {
    required String key,
    required int page,
  }) async {
    final classified = LegadoParse.classifyUrlSpec(spec);
    var resolved = classified.body;
    if (classified.kind == 'js') {
      final script =
          'var key = ${jsonEncode(key)}; var page = $page;\n${classified.body}';
      final result = await _js.run(
        code: script,
        baseUrl: def.url,
        sourceHeaders: def.headers,
      );
      resolved = result?.toString() ?? '';
      if (resolved.isEmpty) {
        throw StateError('源的地址脚本没有返回地址');
      }
    }
    resolved = LegadoParse.fillTemplate(resolved, key: key, page: page);
    return _resolve(def.url, resolved);
  }

  Future<List<NovelItem>> search(String key, {int page = 1}) async {
    if (def.searchUrl.isEmpty) throw StateError('这个源没有搜索地址');
    final url = await _requestUrl(def.searchUrl, key: key, page: page);
    final fetched = await _fetchPage(url);
    return _extractBooks(fetched, def.ruleSearch);
  }

  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  }) async {
    final url = await _requestUrl(category.url, key: '', page: page);
    final fetched = await _fetchPage(url);
    final rules = def.ruleExplore['bookList'] != null
        ? def.ruleExplore
        : def.ruleSearch;
    return _extractBooks(fetched, rules);
  }

  /// Fetch the book info page; returns the enriched item and
  /// the TOC URL (defaults to the book URL itself).
  Future<(NovelItem, String)> bookInfo(NovelItem item) async {
    final fetched = await _fetchPage(item.bookUrl);
    final ctx = fetched.rootContext;
    final rules = def.ruleBookInfo;
    Future<String> field(String name) =>
        _evalScalar(ctx, rules[name] ?? '', fetched);
    final enriched = item.copyWith(
      title: _nonEmpty(await field('name'), item.title),
      author: _nonEmpty(await field('author'), item.author),
      coverUrl: _resolve(
        fetched.url,
        _nonEmpty(await field('coverUrl'), item.coverUrl),
      ),
      intro: _nonEmpty(await field('intro'), item.intro),
      kind: _nonEmpty(await field('kind'), item.kind),
      lastChapter:
          _nonEmpty(await field('lastChapter'), item.lastChapter),
      wordCount: _nonEmpty(await field('wordCount'), item.wordCount),
    );
    final tocUrl = _resolve(fetched.url, await field('tocUrl'));
    return (enriched, tocUrl.isEmpty ? item.bookUrl : tocUrl);
  }

  Future<List<NovelChapter>> chapters(
    NovelItem item, {
    String? tocUrl,
  }) async {
    final fetched = await _fetchPage(tocUrl ?? item.bookUrl);
    final listRule = def.ruleToc['chapterList'] ?? '';
    final contexts = await _evalList(fetched.rootContext, listRule, fetched);
    // Batch 40: a real chapterList rule that matches NOTHING
    // means the fetched page is not the chapter list the
    // rule expects (wrong page, a block/challenge page, or
    // the site changed). Report it as an error so callers
    // show error + retry instead of the misleading
    // "no readable chapters" dead end.
    if (listRule.trim().isNotEmpty && contexts.isEmpty) {
      throw StateError(
        '目录页没有匹配到章节（${def.name}）：${fetched.url}',
      );
    }
    final chapters = <NovelChapter>[];
    for (final ctx in contexts) {
      final title =
          await _evalScalar(ctx, def.ruleToc['chapterName'] ?? '', fetched);
      var rawUrl =
          await _evalScalar(ctx, def.ruleToc['chapterUrl'] ?? '', fetched);
      // Batch 66: a BLANK chapterUrl rule means "the list
      // element itself is the link" (the classic YueDu
      // convention, and how plain <a> chapter lists read).
      // Falling back to the element's own href — then a
      // nested anchor — keeps those TOCs from parsing to
      // an empty chapter list.
      if (rawUrl.isEmpty &&
          (def.ruleToc['chapterUrl'] ?? '').trim().isEmpty) {
        rawUrl = await _evalScalar(ctx, '@href', fetched);
        if (rawUrl.isEmpty) {
          rawUrl = await _evalScalar(ctx, 'tag.a@href', fetched);
        }
      }
      final url = _resolve(fetched.url, rawUrl);
      if (title.isNotEmpty && url.isNotEmpty) {
        chapters.add(NovelChapter(
          title: title,
          url: url,
          webView: LegadoParse.urlRequestsWebView(url),
        ));
      }
    }
    // Batch 40: the rule matched elements but none yielded a
    // usable title + URL — same failure shape as no match.
    if (chapters.isEmpty && contexts.isNotEmpty) {
      throw StateError(
        '目录页章节解析为空（${def.name}）：${fetched.url}',
      );
    }
    return chapters;
  }

  /// Fetch one chapter's content as blocks, following the
  /// source's next-page chain (capped) and applying its
  /// replaceRegex.
  Future<List<NovelBlock>> content(NovelChapter chapter) async {
    var url = chapter.url;
    var html = '';
    for (var hop = 0; hop < 8; hop++) {
      final fetched = await _fetchPage(url);
      final pageHtml = await _evalScalar(
        fetched.rootContext,
        def.ruleContent['content'] ?? '',
        fetched,
      );
      html = html.isEmpty ? pageHtml : '$html\n$pageHtml';
      final nextRule = def.ruleContent['nextContentUrl'];
      if (nextRule == null || nextRule.isEmpty) break;
      final next = await _evalScalar(fetched.rootContext, nextRule, fetched);
      final nextUrl = _resolve(fetched.url, next);
      if (nextUrl.isEmpty || nextUrl == url) break;
      url = nextUrl;
    }
    final replaceRule = def.ruleContent['replaceRegex'];
    if (replaceRule != null && replaceRule.isNotEmpty) {
      html = await _applyContentReplace(html, replaceRule, url);
    }
    return _blocksFromHtml(html);
  }

  // ------------------------------------------------------------
  // Extraction
  // ------------------------------------------------------------

  Future<List<NovelItem>> _extractBooks(
    _Page page,
    Map<String, String> rules,
  ) async {
    final listRule = rules['bookList'] ?? '';
    if (listRule.isEmpty) return const [];
    final contexts = await _evalList(page.rootContext, listRule, page);
    final items = <NovelItem>[];
    for (final ctx in contexts) {
      Future<String> field(String name) =>
          _evalScalar(ctx, rules[name] ?? '', page);
      final name = await field('name');
      final bookUrl = _resolve(page.url, await field('bookUrl'));
      if (name.isEmpty || bookUrl.isEmpty) continue;
      items.add(
        NovelItem(
          bookUrl: bookUrl,
          title: name,
          author: await field('author'),
          coverUrl: _resolve(page.url, await field('coverUrl')),
          intro: await field('intro'),
          kind: await field('kind'),
          lastChapter: await field('lastChapter'),
          source: def.id,
          sourceName: def.name,
        ),
      );
    }
    return items;
  }

  List<NovelBlock> _blocksFromHtml(String html) {
    final trimmed = html.trim();
    if (trimmed.isEmpty) return const [];
    final blocks = <NovelBlock>[];
    if (!trimmed.contains('<')) {
      for (final line in trimmed.split(RegExp(r'\n+'))) {
        final t = line.trim();
        if (t.isNotEmpty) blocks.add(NovelTextBlock(t));
      }
      return blocks;
    }
    final fragment = html_parser.parseFragment(trimmed);
    void walk(dom.Node node) {
      if (node is dom.Text) {
        final t = node.text.trim();
        if (t.isNotEmpty) blocks.add(NovelTextBlock(t));
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName ?? '';
      if (tag == 'img') {
        final rawSrc = node.attributes['src'] ??
            node.attributes['data-src'] ??
            '';
        if (rawSrc.isNotEmpty) {
          final (imgUrl, options) = LegadoParse.splitUrlOptions(rawSrc);
          final headers = <String, String>{};
          final optHeaders = options['headers'];
          if (optHeaders is Map) {
            optHeaders.forEach(
              (k, v) => headers[k.toString()] = v.toString(),
            );
          }
          blocks.add(NovelImageBlock(imgUrl, headers: headers));
        }
        return;
      }
      if (tag == 'p' || tag == 'div' || tag == 'section') {
        // A container whose element children are only <br>
        // or images: walk it; a leaf paragraph becomes one
        // text block.
        final elementChildren =
            node.children.where((c) => c.localName != 'br').toList();
        final hasImg = elementChildren.any((c) => c.localName == 'img');
        if (elementChildren.isEmpty || (hasImg && elementChildren.length == 1)) {
          if (hasImg) {
            walk(node.children.firstWhere((c) => c.localName == 'img'));
          } else {
            final t = LegadoDom.elementText(node);
            if (t.isNotEmpty) blocks.add(NovelTextBlock(t));
          }
          return;
        }
      }
      if (tag == 'br') return;
      for (final child in node.nodes) {
        walk(child);
      }
    }

    for (final node in fragment.nodes) {
      walk(node);
    }
    return blocks;
  }

  Future<String> _applyContentReplace(
    String html,
    String rule,
    String baseUrl,
  ) async {
    final trimmed = rule.trim();
    if (trimmed.startsWith('<js>') || trimmed.startsWith('@js:')) {
      final code = _jsCodeOf(trimmed);
      final out = await _js.run(
        code: code,
        result: html,
        baseUrl: baseUrl,
        sourceHeaders: def.headers,
      );
      return out?.toString() ?? html;
    }
    // Non-JS replaceRegex: 'pattern##replacement' pairs,
    // with an optional leading '##' marker.
    var parts = trimmed.split('##');
    if (parts.isNotEmpty && parts.first.isEmpty) {
      parts = parts.sublist(1);
    }
    final pairs = <(String, String)>[];
    for (var i = 0; i < parts.length; i += 2) {
      if (parts[i].isEmpty) continue;
      pairs.add((parts[i], i + 1 < parts.length ? parts[i + 1] : ''));
    }
    return LegadoParse.applyReplacements(html, pairs);
  }

  // ------------------------------------------------------------
  // Rule evaluation
  // ------------------------------------------------------------

  static String _nonEmpty(String value, String fallback) =>
      value.trim().isNotEmpty ? value.trim() : fallback;

  /// Resolve a field URL: keep any Legado options suffix
  /// intact while resolving the URL part.
  String _resolve(String base, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final (url, _) = LegadoParse.splitUrlOptions(value);
    final resolved = LegadoParse.resolveUrl(base, url);
    if (resolved == url) return value;
    final suffix = value.substring(url.length);
    return '$resolved$suffix';
  }

  static String _jsCodeOf(String rule) {
    final t = rule.trim();
    if (t.startsWith('@js:')) return t.substring(4);
    final m = RegExp(r'<js>([\s\S]*?)</js>').firstMatch(t);
    return m?.group(1) ?? t;
  }

  /// Evaluate a scalar field rule against a context.
  Future<String> _evalScalar(_Ctx ctx, String rule, _Page page) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return '';
    // `||` fallback chains (not inside JS blocks).
    if (!trimmed.contains('<js>') && trimmed.contains('||')) {
      for (final alt in trimmed.split('||')) {
        final value = await _evalScalar(ctx, alt, page);
        if (value.isNotEmpty) return value;
      }
      return '';
    }
    // '@js:' SUFFIX after a plain rule: the head evaluates
    // first, the JS transforms its string
    // ('{{$.a}},{{$.b}}@js:result.replace(...)').
    final jsSuffix = trimmed.indexOf('@js:');
    if (jsSuffix > 0 && !trimmed.contains('<js>')) {
      final head = trimmed.substring(0, jsSuffix);
      final code = trimmed.substring(jsSuffix + 4);
      final seed = await _evalScalarNoJs(ctx, head, page);
      final out = await _js.run(
        code: code,
        result: seed,
        domJson: page.domJson,
        baseUrl: page.requestUrl,
        sourceHeaders: def.headers,
      );
      return _stringify(out);
    }
    // JS segments: prefix rule feeds `result`, JS transforms.
    if (trimmed.contains('<js>') || trimmed.startsWith('@js:')) {
      final jsMatch = RegExp(r'<js>([\s\S]*?)</js>').allMatches(trimmed);
      dynamic seed;
      var rest = trimmed;
      if (trimmed.startsWith('@js:')) {
        seed = _defaultSeed(ctx, page);
        final out = await _js.run(
          code: trimmed.substring(4),
          result: seed,
          domJson: page.domJson,
          baseUrl: page.requestUrl,
          sourceHeaders: def.headers,
        );
        return _stringify(out);
      }
      final first = jsMatch.first;
      final prefix = trimmed.substring(0, first.start).trim();
      seed = prefix.isNotEmpty
          ? await _evalScalarNoJs(ctx, prefix, page)
          : _defaultSeed(ctx, page);
      for (final match in jsMatch) {
        seed = await _js.run(
          code: match.group(1) ?? '',
          result: seed,
          domJson: page.domJson,
          baseUrl: page.requestUrl,
          sourceHeaders: def.headers,
        );
      }
      rest = trimmed.substring(jsMatch.last.end).trim();
      if (rest.isNotEmpty) {
        return _evalScalar(_Ctx.fromValue(seed), rest, page);
      }
      return _stringify(seed);
    }
    return _evalScalarNoJs(ctx, trimmed, page);
  }

  dynamic _defaultSeed(_Ctx ctx, _Page page) {
    return switch (ctx) {
      _JsonCtx(:final value) => value,
      _DomCtx() => page.body,
      _TextCtx(:final text) => text,
    };
  }

  Future<String> _evalScalarNoJs(_Ctx ctx, String rule, _Page page) async {
    final (base, pairs) = LegadoParse.splitReplacements(rule.trim());
    var result = '';
    switch (ctx) {
      case _JsonCtx(:final value):
        if (base.contains('{{')) {
          // Template rules (bookUrl especially):
          // '/novels/api/book/{{$.book_id}}' — interpolate
          // JSONPath expressions into the literal text.
          result = base.replaceAllMapped(RegExp(r'\{\{(.+?)\}\}'), (m) {
            final expr = (m.group(1) ?? '').trim();
            if (expr.startsWith(r'$')) {
              return _stringify(_evalJsonPath(value, expr));
            }
            return m.group(0) ?? '';
          });
        } else {
          result = _stringify(_evalJsonPath(value, base));
        }
      case _DomCtx(:final node):
        result = _evalCssField(node, base);
      case _TextCtx(:final text):
        result = text;
    }
    if (pairs.isNotEmpty) {
      result = LegadoParse.applyReplacements(result, pairs);
    }
    return result.trim();
  }

  dynamic _evalJsonPath(dynamic root, String rule) {
    final r = rule.trim();
    if (r.startsWith(r'$')) return JsonPathLite.eval(root, r);
    if (r.startsWith('@json:')) {
      return JsonPathLite.eval(root, r.substring(6).trim());
    }
    // Plain key path on maps: 'name', 'data.list' etc.
    dynamic current = root;
    for (final part in r.split('.')) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  String _evalCssField(Object node, String rule) {
    var r = rule.trim();
    if (r.startsWith('@xpath:') || r.startsWith('xpath:')) return '';
    if (r.startsWith('@css:')) r = r.substring(5).trim();
    if (r.startsWith('@css ')) r = r.substring(5).trim();
    if (r.isEmpty) {
      return node is dom.Element ? LegadoDom.extract(node, '') : '';
    }
    final (els, attr) = LegadoDom.fieldElements(node, r);
    if (els.isEmpty) return '';
    return LegadoDom.extract(els.first, attr);
  }

  /// Evaluate a list rule (bookList / chapterList) into item
  /// contexts.
  Future<List<_Ctx>> _evalList(_Ctx ctx, String rule, _Page page) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.contains('<js>') || trimmed.startsWith('@js:')) {
      final out = await _js.run(
        code: _jsCodeOf(trimmed),
        result: _defaultSeed(ctx, page),
        domJson: page.domJson,
        baseUrl: page.requestUrl,
        sourceHeaders: def.headers,
      );
      return _contextsFromJs(out);
    }
    switch (ctx) {
      case _JsonCtx(:final value):
        final result = _evalJsonPath(value, trimmed);
        if (result is List) {
          return [for (final e in result) _Ctx.fromValue(e)];
        }
        if (result != null) return [_Ctx.fromValue(result)];
        return const [];
      case _DomCtx(:final node):
        var r = trimmed;
        if (r.startsWith('@css:')) r = r.substring(5).trim();
        if (r.startsWith('@css ')) r = r.substring(5).trim();
        return [
          for (final el in LegadoDom.selectChain(node, r)) _DomCtx(el),
        ];
      case _TextCtx():
        return const [];
    }
  }

  List<_Ctx> _contextsFromJs(dynamic out) {
    if (out is! List) return const [];
    final contexts = <_Ctx>[];
    for (final entry in out) {
      if (entry is Map && entry.containsKey('__elHtml')) {
        final fragment = html_parser.parseFragment(
          entry['__elHtml']?.toString() ?? '',
        );
        for (final el in fragment.children) {
          contexts.add(_DomCtx(el));
        }
      } else {
        contexts.add(_Ctx.fromValue(entry));
      }
    }
    return contexts;
  }

  static String _stringify(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is List) {
      return value.isEmpty ? '' : _stringify(value.first);
    }
    if (value is Map) return jsonEncode(value);
    return value.toString();
  }
}

/// Rule evaluation context: a JSON value, a DOM node, or raw
/// text.
sealed class _Ctx {
  const _Ctx();

  factory _Ctx.fromValue(dynamic value) {
    if (value is String) return _TextCtx(value);
    return _JsonCtx(value);
  }
}

class _JsonCtx extends _Ctx {
  const _JsonCtx(this.value);
  final dynamic value;
}

class _DomCtx extends _Ctx {
  const _DomCtx(this.node);
  final Object node; // dom.Document or dom.Element
}

class _TextCtx extends _Ctx {
  const _TextCtx(this.text);
  final String text;
}

/// A fetched page: raw body, decoded JSON (when the body is
/// JSON), parsed DOM (when it is not), final URL, and the
/// serialized DOM for the JS bridge (computed lazily).
class _Page {
  _Page({
    required this.body,
    required this.url,
    required this.requestUrl,
    required this.json,
    required this.doc,
  });

  final String body;

  /// Final URL after redirects — relative links resolve
  /// against this.
  final String url;

  /// The URL spec the page was requested with, Legado
  /// options suffix included. Rule JS sees THIS as
  /// `baseUrl` (Legado semantics — bilinovel's next-page
  /// logic parses the suffix off it, dumanwu's TOC splits
  /// an id out of it).
  final String requestUrl;
  final dynamic json;
  final dom.Document? doc;

  _Ctx get rootContext =>
      json != null ? _JsonCtx(json) : _DomCtx(doc ?? LegadoDom.parseHtml(''));

  Map<String, dynamic>? _domJson;

  Map<String, dynamic>? get domJson {
    if (json != null) return null;
    return _domJson ??= LegadoDom.serializeDocument(
      doc ?? LegadoDom.parseHtml(body),
    );
  }
}
