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
/// and URL option objects, {{key}}/{{page}} templates plus
/// JS-evaluated {{...}} templates (batch 157: cookie.getKey,
/// jsLib functions, ternaries — the shapes mainstream
/// bundles use in search/explore URLs), @css selectors with
/// @text/@ownText/@html/@attr, $. JSON paths, key lookups
/// on JS-returned objects, JS with the java shim
/// (getElements/getElement/getString/getStringList/ajax/
/// ajaxAll/post/connect/md5/base64/put/get/log/timeFormat/
/// hex/timeFormatUTC plus no-op toast/browser calls), the
/// cookie and cache objects (batch 157), jsLib, cookie jar
/// (batch 68), GBK decoding (batch 31), next-content
/// pagination, content replaceRegex. NOT supported: XPath
/// rules, interactive login flows, WebView-rendered pages,
/// AES crypto helpers — sources needing those throw or
/// return empty and the UI says so per source.
class LegadoEngine {
  LegadoEngine(this.def);

  final LegadoSourceDef def;

  // Batch 171: diagnostics capture. When the diagnostics
  // page enables this, every fetched body (the exact text
  // the rules saw, after bodyJs / login-check rewrites) is
  // kept per final URL so a report can quote the raw
  // response behind a suspicious result — a chapter count
  // of 1, say, is undecidable from counts alone.
  static bool debugCapture = false;
  static final Map<String, String> debugBodies = {};

  LegadoJsHost get _js => LegadoJsHost.forSource(
        def.id,
        def.jsLib,
        sourceName: def.name,
        loginUrl: def.raw['loginUrl']?.toString() ?? '',
        loginUi: def.raw['loginUi'],
      );

  // Batch 170: per-flow JS context — the bindings (key /
  // page / title / src / nextChapterUrl) and book/chapter
  // snapshots the reference binds into every rule script.
  // Flows set these before evaluating; _runJs forwards
  // them into every run so field scripts see them.
  Map<String, dynamic> _flowBindings = const {};
  Map<String, dynamic>? _flowBook;
  Map<String, dynamic>? _flowChapter;

  Future<dynamic> _runJs({
    required String code,
    dynamic result,
    Map<String, dynamic>? domJson,
    required String baseUrl,
    Map<String, String> sourceHeaders = const {},
  }) {
    return _js.run(
      code: code,
      result: result,
      domJson: domJson,
      baseUrl: baseUrl,
      sourceHeaders: sourceHeaders,
      bindings: _flowBindings,
      book: _flowBook,
      chapter: _flowChapter,
    );
  }

  Map<String, dynamic> _bookSnapshot(NovelItem item, {String? tocUrl}) {
    final snapshot = <String, dynamic>{
      'name': item.title,
      'author': item.author,
      'bookUrl': item.bookUrl,
      'coverUrl': item.coverUrl,
      'intro': item.intro,
      'kind': item.kind,
      'lastChapter': item.lastChapter,
      'wordCount': item.wordCount,
      'origin': def.id,
      'originName': def.name,
    };
    if (tocUrl != null) snapshot['tocUrl'] = tocUrl;
    return snapshot;
  }

  Map<String, dynamic> _chapterSnapshot(NovelChapter chapter, int index) {
    return {
      'title': chapter.title,
      'url': chapter.url,
      'index': index,
      'isVip': false,
      'isPay': false,
      'isVolume': false,
    };
  }

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
      // Batch 165: name the address that was actually
      // answered — a bare status code cannot distinguish a
      // dead search path from a dead host (the 霹雳书屋
      // search 404 sat in exactly that blind spot).
      throw StateError(
          '源站返回 ${response.statusCode}（最终地址 ${response.url}）');
    }
    var body = response.body;
    // Batch 168: UrlOption bodyJs — the reference runs it
    // once per response with `result` bound to the raw
    // body, and the OUTPUT becomes the body every rule
    // then sees (Fanqie-style list-font decoding rides on
    // exactly this). It was silently ignored before.
    final (_, urlOptions) = LegadoParse.splitUrlOptions(urlSpec);
    final bodyJs = urlOptions['bodyJs']?.toString().trim() ?? '';
    if (bodyJs.isNotEmpty) {
      final out = await _runJs(
        code: bodyJs,
        result: body,
        baseUrl: response.url,
        sourceHeaders: def.headers,
      );
      body = _stringify(out);
    }
    // Batch 170: loginCheckJs — the reference runs it on
    // EVERY response (search/explore/info/toc/content)
    // with the response object bound as `result`; the
    // script inspects the body (login walls, redirects of
    // the soft kind), may open a browser login via the
    // browse suspension, and its return — a string or a
    // response-shaped value — replaces the body rules see.
    final checkJs = def.raw['loginCheckJs']?.toString().trim() ?? '';
    if (checkJs.isNotEmpty) {
      final out = await _js.run(
        code: _jsCodeOf(checkJs),
        strResponse: (
          body: body,
          url: response.url,
          code: response.statusCode,
        ),
        baseUrl: response.url,
        sourceHeaders: def.headers,
        bindings: _flowBindings,
        book: _flowBook,
        chapter: _flowChapter,
      );
      if (out is String && out.isNotEmpty) {
        body = out;
      } else if (out is Map && out['__strResp'] == true) {
        final checked = out['_body']?.toString() ?? '';
        if (checked.isNotEmpty) body = checked;
      }
    }
    if (debugCapture) {
      debugBodies[response.url] =
          body.length > 6000 ? body.substring(0, 6000) : body;
    }
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {}
    return _Page(
      body: body,
      url: response.url,
      requestUrl: urlSpec,
      json: json,
      doc: json == null ? LegadoDom.parseHtml(body) : null,
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
      final result = await _runJs(
        code: script,
        baseUrl: def.url,
        sourceHeaders: def.headers,
      );
      resolved = result?.toString() ?? '';
      if (resolved.isEmpty) {
        throw StateError('源的地址脚本没有返回地址');
      }
    }
    resolved = await _evalTemplates(
      resolved,
      key: key,
      page: page,
      baseUrl: def.url,
    );
    return _resolve(def.url, resolved);
  }

  /// Batch 157: fill a text's `{{...}}` templates the way
  /// Legado does. The cheap deterministic shapes ({{key}},
  /// {{page}}, page arithmetic) are filled by
  /// [LegadoParse.fillTemplate]; anything left over is a JS
  /// expression and is evaluated through the source's JS
  /// host with key/page bound and [seed] as `result` —
  /// `{{cookie.getKey(url, "_csrfToken")}}`,
  /// `{{cookie.removeCookie(url)}}` (a common searchUrl
  /// prefix that evaluates to ''), jsLib helpers like
  /// `{{bhost()}}`, ternaries like {{page==1?'':'_'+page}}.
  /// Before this, those braces went to the server verbatim
  /// and mainstream bundle sources errored or returned
  /// nothing. `$.` expressions resolve against [seed]
  /// without a JS round-trip.
  Future<String> _evalTemplates(
    String text, {
    required String key,
    required int page,
    required String baseUrl,
    dynamic seed,
    Map<String, dynamic>? domJson,
  }) async {
    final filled = LegadoParse.fillTemplate(text, key: key, page: page);
    if (!filled.contains('{{')) return filled;
    final matches = RegExp(r'\{\{(.*?)\}\}').allMatches(filled).toList();
    if (matches.isEmpty) return filled;
    final values = <String, String>{};
    for (final m in matches) {
      final expr = (m.group(1) ?? '').trim();
      if (expr.isEmpty || values.containsKey(expr)) continue;
      if (expr.startsWith(r'$')) {
        values[expr] = _stringify(_evalJsonPath(seed, expr));
        continue;
      }
      final code =
          'var key = ${jsonEncode(key)}; var page = $page;\n($expr)';
      final out = await _runJs(
        code: code,
        result: seed,
        domJson: domJson,
        baseUrl: baseUrl,
        sourceHeaders: def.headers,
      );
      values[expr] = _stringify(out);
    }
    return filled.replaceAllMapped(
      RegExp(r'\{\{(.*?)\}\}'),
      (m) => values[(m.group(1) ?? '').trim()] ?? '',
    );
  }

  Future<List<NovelItem>> search(String key, {int page = 1}) async {
    if (def.searchUrl.isEmpty) throw StateError('这个源没有搜索地址');
    _flowBindings = {'key': key, 'page': page};
    _flowBook = null;
    _flowChapter = null;
    final url = await _requestUrl(def.searchUrl, key: key, page: page);
    final fetched = await _fetchPage(url);
    return _extractBooks(fetched, def.ruleSearch);
  }

  /// Batch 173: resolve the source's explore categories.
  /// Static declarations parse from the definition; a
  /// script exploreUrl (`@js:` or a `<js>` block) is EVALUATED —
  /// the reference runs it per source and renders the
  /// returned kinds (group headers, layout styles and
  /// all). Treating the script as a category URL (the old
  /// static reading) fetched the kinds JSON as an address
  /// and died on its scheme.
  Future<List<NovelExploreCategory>> exploreKinds() async {
    final raw = def.exploreUrlRaw.trim();
    if (raw.startsWith('@js:') || raw.contains('<js>')) {
      _flowBindings = const {};
      _flowBook = null;
      _flowChapter = null;
      final out = await _js.run(
        code: _jsCodeOf(raw),
        result: null,
        baseUrl: def.id,
        sourceHeaders: def.headers,
      );
      dynamic decoded = out;
      if (out is String) {
        try {
          decoded = jsonDecode(out);
        } catch (_) {
          decoded = LegadoParse.parseLooseValue(out);
        }
      }
      if (decoded is List) {
        return NovelExploreCategory.listFromKinds(decoded);
      }
      return const [];
    }
    return def.exploreCategories;
  }

  Future<List<NovelItem>> explore(
    NovelExploreCategory category, {
    int page = 1,
  }) async {
    _flowBindings = {'key': '', 'page': page};
    _flowBook = null;
    _flowChapter = null;
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
    _flowBindings = const {};
    _flowBook = _bookSnapshot(item, tocUrl: item.bookUrl);
    _flowChapter = null;
    final bookDataBefore = _js.lastBookData;
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
    var tocUrl = _resolve(fetched.url, await field('tocUrl'));
    // Batch 170: a field script may rewrite book.tocUrl
    // directly; the reference adopts the rewrite. The
    // envelope always echoes the snapshot back, so only
    // a value a run in THIS call produced AND changed
    // (the snapshot seeds tocUrl with the book URL)
    // counts as a rewrite.
    final bookDataAfter = _js.lastBookData;
    if (!identical(bookDataAfter, bookDataBefore)) {
      final rewritten = bookDataAfter?['tocUrl']?.toString() ?? '';
      if (rewritten.isNotEmpty && rewritten != item.bookUrl) {
        tocUrl = _resolve(fetched.url, rewritten);
      }
    }
    return (enriched, tocUrl.isEmpty ? item.bookUrl : tocUrl);
  }

  Future<List<NovelChapter>> chapters(
    NovelItem item, {
    String? tocUrl,
  }) async {
    _flowBindings = const {};
    _flowBook = _bookSnapshot(item, tocUrl: tocUrl ?? item.bookUrl);
    _flowChapter = null;
    // Batch 170: a leading '-' on the chapterList rule
    // declares the source's list descending — strip it
    // here (not per page) and reverse the ASSEMBLED list;
    // '+' is a no-op marker.
    var listRule = (def.ruleToc['chapterList'] ?? '').trim();
    var descending = false;
    if (listRule.startsWith('-')) {
      descending = true;
      listRule = listRule.substring(1).trim();
    } else if (listRule.startsWith('+')) {
      listRule = listRule.substring(1).trim();
    }
    final nextTocRule = (def.ruleToc['nextTocUrl'] ?? '').trim();

    final chapters = <NovelChapter>[];
    var sawContexts = false;
    var page = await _fetchPage(tocUrl ?? item.bookUrl);
    final visited = <String>{page.url};
    for (var pageNo = 0; pageNo < 50; pageNo++) {
      final contexts = await _evalList(page.rootContext, listRule, page);
      // Batch 40: a real chapterList rule that matches
      // NOTHING on the FIRST page means the fetched page
      // is not the chapter list the rule expects (wrong
      // page, a block/challenge page, or the site
      // changed). Report it as an error so callers show
      // error + retry instead of the misleading "no
      // readable chapters" dead end. (Later pages may
      // legitimately come back empty — the chain just
      // ends.)
      if (pageNo == 0 && listRule.isNotEmpty && contexts.isEmpty) {
        throw StateError(
          '目录页没有匹配到章节（${def.name}）：${page.url}',
        );
      }
      if (contexts.isNotEmpty) sawContexts = true;
      for (final ctx in contexts) {
        final title =
            await _evalScalar(ctx, def.ruleToc['chapterName'] ?? '', page);
        var rawUrl =
            await _evalScalar(ctx, def.ruleToc['chapterUrl'] ?? '', page);
        // Batch 66: a BLANK chapterUrl rule means "the
        // list element itself is the link" (the classic
        // YueDu convention, and how plain <a> chapter
        // lists read). Falling back to the element's own
        // href — then a nested anchor — keeps those TOCs
        // from parsing to an empty chapter list.
        if (rawUrl.isEmpty &&
            (def.ruleToc['chapterUrl'] ?? '').trim().isEmpty) {
          rawUrl = await _evalScalar(ctx, '@href', page);
          if (rawUrl.isEmpty) {
            rawUrl = await _evalScalar(ctx, 'tag.a@href', page);
          }
        }
        final url = _resolve(page.url, rawUrl);
        if (title.isNotEmpty && url.isNotEmpty) {
          chapters.add(NovelChapter(
            title: title,
            url: url,
            webView: LegadoParse.urlRequestsWebView(url),
          ));
        }
      }
      // Batch 170: follow the TOC pagination chain.
      if (nextTocRule.isEmpty) break;
      final nextText =
          await _evalScalar(page.rootContext, nextTocRule, page);
      String? nextUrl;
      for (final line in nextText.split('\n')) {
        final candidate = _resolve(page.url, line.trim());
        if (candidate.isNotEmpty && !visited.contains(candidate)) {
          nextUrl = candidate;
          break;
        }
      }
      if (nextUrl == null) break;
      visited.add(nextUrl);
      page = await _fetchPage(nextUrl);
    }
    // Batch 40: the rule matched elements but none yielded
    // a usable title + URL — same failure shape as no match.
    if (chapters.isEmpty && sawContexts) {
      throw StateError(
        '目录页章节解析为空（${def.name}）：${page.url}',
      );
    }
    var out = descending ? chapters.reversed.toList() : chapters;
    // Batch 170: formatJs post-processing — each chapter's
    // title goes through the script with its final index
    // bound; a non-empty return replaces the title.
    final formatJs = (def.ruleToc['formatJs'] ?? '').trim();
    if (formatJs.isNotEmpty && out.isNotEmpty) {
      final formatted = <NovelChapter>[];
      for (var i = 0; i < out.length; i++) {
        final chapter = out[i];
        _flowChapter = _chapterSnapshot(chapter, i);
        _flowBindings = {'index': i, 'gInt': 0, 'title': chapter.title};
        final result = await _runJs(
          code: _jsCodeOf(formatJs),
          result: chapter.title,
          baseUrl: page.url,
        );
        final newTitle = _stringify(result).trim();
        formatted.add(
          newTitle.isEmpty
              ? chapter
              : NovelChapter(
                  title: newTitle,
                  url: chapter.url,
                  webView: chapter.webView,
                ),
        );
      }
      _flowChapter = null;
      _flowBindings = const {};
      out = formatted;
    }
    return out;
  }

  /// Fetch one chapter's content as blocks, following the
  /// source's next-page chain (capped) and applying its
  /// replaceRegex.
  Future<List<NovelBlock>> content(NovelChapter chapter) async {
    // Batch 170: content scripts read the chapter binding
    // plus title / src (the text gathered so far) /
    // nextChapterUrl (the following page once known).
    _flowChapter = _chapterSnapshot(chapter, -1);
    var url = chapter.url;
    var html = '';
    var nextChapterUrl = '';
    for (var hop = 0; hop < 8; hop++) {
      _flowBindings = {
        'title': chapter.title,
        'src': html,
        'nextChapterUrl': nextChapterUrl,
      };
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
      nextChapterUrl = nextUrl;
      url = nextUrl;
    }
    _flowChapter = null;
    _flowBindings = const {};
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
      // Batch 170: the remaining fields evaluate with this
      // book bound, as the reference binds it.
      _flowBook = _bookSnapshot(
        NovelItem(
          bookUrl: bookUrl,
          title: name,
          source: def.id,
          sourceName: def.name,
        ),
      );
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
      final out = await _runJs(
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
  ///
  /// Batch 168: the dispatch order now follows the
  /// reference implementation (its AnalyzeRule cuts JS
  /// segments first, greedily; the `||` fallback lives
  /// inside the sub-analyzers and never touches JS):
  ///   1. A rule STARTING with '@js:' is JS in its
  ///      entirety — a '||' inside is the script's own
  ///      operator. The old order split first and fed
  ///      half a script to the engine, which is what
  ///      killed Fanqie-style bookInfo/content rules
  ///      ("expecting ','" on 'd.categoryV2||'[]'').
  ///   2. An '@js:' suffix: the plain head evaluates
  ///      first (with its own top-level fallbacks), the
  ///      JS transforms the head's string.
  ///   3. Embedded js segments.
  ///   4. Plain rules: top-level '||' fallback chain,
  ///      split with group/quote awareness.
  Future<String> _evalScalar(_Ctx ctx, String rule, _Page page) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('@js:')) {
      return _runRuleJs(
        trimmed.substring(4),
        result: _defaultSeed(ctx, page),
        page: page,
      );
    }
    // '@js:' SUFFIX after a plain rule: the head evaluates
    // first, the JS transforms its string
    // ('{{$.a}},{{$.b}}@js:result.replace(...)').
    final jsSuffix = trimmed.indexOf('@js:');
    if (jsSuffix > 0 && !trimmed.contains('<js>')) {
      final head = trimmed.substring(0, jsSuffix);
      final code = trimmed.substring(jsSuffix + 4);
      var seed = '';
      for (final alt in LegadoParse.splitAlternatives(head)) {
        seed = await _evalScalarNoJs(ctx, alt, page);
        if (seed.isNotEmpty) break;
      }
      return _runRuleJs(code, result: seed, page: page);
    }
    // JS segments: prefix rule feeds `result`, JS transforms.
    if (trimmed.contains('<js>')) {
      final jsMatch = RegExp(r'<js>([\s\S]*?)</js>').allMatches(trimmed);
      dynamic seed;
      var rest = trimmed;
      final first = jsMatch.first;
      final prefix = trimmed.substring(0, first.start).trim();
      seed = prefix.isNotEmpty
          ? await _evalScalarNoJs(ctx, prefix, page)
          : _defaultSeed(ctx, page);
      for (final match in jsMatch) {
        seed = await _runJs(
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
    // Plain rule: top-level `||` fallback chain. Alts are
    // re-dispatched whole (an alt may itself be a JS form);
    // a single-part split means every `||` sat inside a
    // group and belongs to the sub-analyzer — fall through.
    if (trimmed.contains('||')) {
      final alts = LegadoParse.splitAlternatives(trimmed);
      if (alts.length > 1) {
        for (final alt in alts) {
          final value = await _evalScalar(ctx, alt, page);
          if (value.isNotEmpty) return value;
        }
        return '';
      }
    }
    return _evalScalarNoJs(ctx, trimmed, page);
  }

  /// Batch 162: run a rule's JS with any trailing
  /// `##regex##replacement` pairs split off first and
  /// applied to the result afterwards — the pairs are
  /// rule syntax, not JS. Feeding them into the script
  /// (the widely copied chapter-name cleaner ends with
  /// one) made the JS parser die on the leading '##'
  /// with "invalid first character of private name",
  /// which is what took out QQ阅读标签's chapter list.
  Future<String> _runRuleJs(
    String code, {
    required dynamic result,
    required _Page page,
  }) async {
    final (js, pairs) = LegadoParse.splitReplacements(code.trim());
    final out = await _runJs(
      code: js,
      result: result,
      domJson: page.domJson,
      baseUrl: page.requestUrl,
      sourceHeaders: def.headers,
    );
    var text = _stringify(out);
    if (pairs.isNotEmpty) {
      text = LegadoParse.applyReplacements(text, pairs);
    }
    return text;
  }

  dynamic _defaultSeed(_Ctx ctx, _Page page) {
    return switch (ctx) {
      _JsonCtx(:final value, :final jsSeed) => jsSeed ?? value,
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
          // template expressions into the literal text.
          // Batch 157: non-JSONPath expressions are JS,
          // evaluated with the value as `result` (before,
          // they were left in the output verbatim).
          result = await _evalTemplates(
            base,
            key: '',
            page: 1,
            baseUrl: page.requestUrl,
            seed: value,
            domJson: page.domJson,
          );
        } else {
          result = _stringify(_evalJsonPath(value, base));
        }
      case _DomCtx(:final node):
        var ruleText = base;
        if (ruleText.contains('{{')) {
          // Batch 157: templates inside a DOM rule are JS
          // too, seeded with the element's own HTML.
          ruleText = await _evalTemplates(
            ruleText,
            key: '',
            page: 1,
            baseUrl: page.requestUrl,
            seed: node is dom.Element ? node.outerHtml : page.body,
            domJson: page.domJson,
          );
        }
        result = _evalCssField(node, ruleText);
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
    var trimmed = rule.trim();
    if (trimmed.isEmpty) return const [];
    // Batch 170: a leading '-' declares the list
    // descending (reverse after evaluation), '+' is a
    // no-op marker. The TOC flow strips its own prefix
    // before calling (it reverses the assembled multi-page
    // list itself); search/explore lists reverse here.
    var reversed = false;
    if (trimmed.startsWith('-')) {
      reversed = true;
      trimmed = trimmed.substring(1).trim();
    } else if (trimmed.startsWith('+')) {
      trimmed = trimmed.substring(1).trim();
    }
    final items = await _evalListInner(ctx, trimmed, page);
    return reversed ? items.reversed.toList() : items;
  }

  Future<List<_Ctx>> _evalListInner(_Ctx ctx, String rule, _Page page) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return const [];
    // Batch 168: '@js:' SUFFIX on a list rule — the head
    // list evaluates first, the JS transforms the items
    // (the reference cuts its JS segments the same way).
    final jsAt = trimmed.indexOf('@js:');
    if (jsAt > 0 && !trimmed.contains('<js>')) {
      final headItems =
          await _evalList(ctx, trimmed.substring(0, jsAt), page);
      final seed = [
        for (final item in headItems)
          switch (item) {
            _JsonCtx(:final value) => value,
            _TextCtx(:final text) => text,
            _DomCtx(:final node) => {
                '__elHtml': node is dom.Element ? node.outerHtml : '',
              },
          },
      ];
      final out = await _runJs(
        code: trimmed.substring(jsAt + 4),
        result: seed,
        domJson: page.domJson,
        baseUrl: page.requestUrl,
        sourceHeaders: def.headers,
      );
      return _contextsFromJs(out);
    }
    if (trimmed.contains('<js>') || trimmed.startsWith('@js:')) {
      final out = await _runJs(
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
  const _JsonCtx(this.value, {this.jsSeed});
  final dynamic value;

  /// Batch 168: what a JS rule sees as `result` when this
  /// context is a whole PAGE. The reference binds the raw
  /// response text there — scripts do JSON.parse(
  /// String(result)) — while per-ITEM contexts bind the
  /// item object itself (null here → seed = value).
  final dynamic jsSeed;
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

  _Ctx get rootContext => json != null
      ? _JsonCtx(json, jsSeed: body)
      : _DomCtx(doc ?? LegadoDom.parseHtml(''));

  Map<String, dynamic>? _domJson;

  Map<String, dynamic>? get domJson {
    if (json != null) return null;
    return _domJson ??= LegadoDom.serializeDocument(
      doc ?? LegadoDom.parseHtml(body),
    );
  }
}
