import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'legado_dom.dart';
import 'legado_http.dart';
import 'legado_js.dart';
import 'legado_parse.dart';
import 'rss_sources.dart';

/// Batch 167: the subscription reader engine. Subscription
/// sources speak the same rule language as book sources
/// (selector chains, JsonPath, @js blocks), so this reuses
/// the book engine's DOM/JS/HTTP machinery with a small
/// evaluator shaped for article lists instead of books.
///
/// Honest v1 limits: no list pagination (first page only),
/// no login flows (a source whose rules need a signed-in
/// session will come back empty), and item-level @js rules
/// get the item element as their seed — sources that lean
/// on app-only bridges beyond that subset may still fail,
/// per rule, without taking the whole list down.
class RssArticle {
  const RssArticle({
    required this.title,
    required this.link,
    this.pubDate = '',
    this.description = '',
    this.image = '',
  });

  final String title;
  final String link;
  final String pubDate;
  final String description;
  final String image;
}

class _Item {
  _Item.dom(this.el) : json = null, text = null;
  _Item.json(this.json) : el = null, text = null;
  _Item.text(this.text) : el = null, json = null;

  final dom.Element? el;
  final dynamic json;
  final String? text;
}

class RssEngine {
  RssEngine._();

  static LegadoJsHost _hostFor(RssSourceDef def) =>
      LegadoJsHost.forSource(
        'rss:${def.id}',
        def.raw['jsLib']?.toString(),
        sourceName: def.name,
        loginUrl: def.rule('loginUrl'),
        loginUi: def.raw['loginUi'],
      );

  /// The source's request headers. The header field may be
  /// a map, a JSON string, or a js block that builds one.
  static Future<Map<String, String>> headersOf(RssSourceDef def) async {
    final raw = def.raw['header'];
    if (raw is Map) {
      return {
        for (final e in raw.entries) e.key.toString(): e.value.toString(),
      };
    }
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return const {};
      if (s.startsWith('<js>') || s.startsWith('@js:')) {
        try {
          final out = await _hostFor(def).run(
            code: _jsCodeOf(s),
            result: '',
            baseUrl: def.url,
            sourceHeaders: const {},
          );
          if (out is Map) {
            return {
              for (final e in out.entries)
                e.key.toString(): e.value.toString(),
            };
          }
          if (out is String && out.trim().startsWith('{')) {
            final decoded = jsonDecode(out);
            if (decoded is Map) {
              return {
                for (final e in decoded.entries)
                  e.key.toString(): e.value.toString(),
              };
            }
          }
        } catch (_) {
          return const {};
        }
        return const {};
      }
      if (s.startsWith('{')) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is Map) {
            return {
              for (final e in decoded.entries)
                e.key.toString(): e.value.toString(),
            };
          }
        } catch (_) {
          return const {};
        }
      }
    }
    return const {};
  }

  /// Category tabs from the sortUrl field: "name::url"
  /// lines, or an @js block returning [{name, url}].
  static Future<List<(String, String)>> categories(
    RssSourceDef def,
  ) async {
    final sort = def.sortUrl;
    if (sort.isEmpty) return const [];
    if (sort.startsWith('@js:') || sort.contains('<js>')) {
      try {
        final headers = await headersOf(def);
        final out = await _hostFor(def).run(
          code: _jsCodeOf(sort),
          result: '',
          baseUrl: def.url,
          sourceHeaders: headers,
        );
        // Batch 168: in the reference implementation the
        // @js sortUrl returns "name::url" TEXT, not JSON —
        // parse it the same way as a literal sortUrl.
        if (out is String) {
          return parseSortUrlText(out, def.url);
        }
        if (out is List) {
          return [
            for (final entry in out)
              if (entry is Map &&
                  (entry['url']?.toString().trim() ?? '').isNotEmpty)
                (
                  (entry['name'] ?? entry['title'] ?? '').toString(),
                  LegadoParse.resolveUrl(
                    def.url,
                    entry['url'].toString(),
                  ),
                ),
          ];
        }
      } catch (_) {
        return const [];
      }
      return const [];
    }
    return parseSortUrlText(sort, def.url);
  }

  static List<(String, String)> parseSortUrlText(
    String sortUrl,
    String baseUrl,
  ) {
    final out = <(String, String)>[];
    for (final chunk in sortUrl.split('\n')) {
      for (final part in chunk.split('&&')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final sep = trimmed.indexOf('::');
        if (sep < 0) continue;
        final name = trimmed.substring(0, sep).trim();
        final url = trimmed.substring(sep + 2).trim();
        if (name.isEmpty || url.isEmpty) continue;
        out.add((name, LegadoParse.resolveUrl(baseUrl, url)));
      }
    }
    return out;
  }

  /// Batch 170: the source's loginCheckJs, run on every
  /// response with the response object bound as `result`
  /// (same contract as the book engine's fetch path); a
  /// string or response-shaped return replaces the body.
  static Future<String> _applyLoginCheck(
    RssSourceDef def,
    String body,
    String url,
    int statusCode,
    Map<String, String> headers,
  ) async {
    final checkJs = def.raw['loginCheckJs']?.toString().trim() ?? '';
    if (checkJs.isEmpty) return body;
    final out = await _hostFor(def).run(
      code: _jsCodeOf(checkJs),
      strResponse: (body: body, url: url, code: statusCode),
      baseUrl: url,
      sourceHeaders: headers,
    );
    if (out is String && out.isNotEmpty) return out;
    if (out is Map && out['__strResp'] == true) {
      final checked = out['_body']?.toString() ?? '';
      if (checked.isNotEmpty) return checked;
    }
    return body;
  }

  static Future<List<RssArticle>> articles(
    RssSourceDef def,
    String categoryUrl,
  ) async {
    final headers = await headersOf(def);
    final response = await LegadoHttp.fetch(
      categoryUrl,
      sourceHeaders: headers,
    );
    if (response.statusCode >= 400) {
      throw StateError('源站返回 ${response.statusCode}');
    }
    final body = await _applyLoginCheck(
      def,
      response.body,
      response.url,
      response.statusCode,
      headers,
    );
    return articlesFromBody(def, body, response.url, headers);
  }

  /// The list half of [articles], split out so tests can
  /// drive it with fixture pages and no network.
  static Future<List<RssArticle>> articlesFromBody(
    RssSourceDef def,
    String body,
    String pageUrl,
    Map<String, String> headers,
  ) async {
    final items = await _listItems(def, body, pageUrl, headers);
    // Batch 168: when the rules produce nothing and the
    // body is a real feed document, fall back to parsing
    // its items directly — the reference does the same
    // (its rule-less path reads standard feed XML).
    if (items.isEmpty && body.contains('<item')) {
      return _feedArticles(body, pageUrl);
    }
    final out = <RssArticle>[];
    for (final item in items) {
      final title = await _field(def, item, def.ruleTitle, body, pageUrl, headers);
      var link = await _field(def, item, def.ruleLink, body, pageUrl, headers);
      if (link.isNotEmpty) {
        link = LegadoParse.resolveUrl(pageUrl, link);
      }
      final image = await _field(def, item, def.ruleImage, body, pageUrl, headers);
      out.add(
        RssArticle(
          title: title.isEmpty ? '(无标题)' : title,
          link: link,
          pubDate:
              await _field(def, item, def.rulePubDate, body, pageUrl, headers),
          description: await _field(
            def,
            item,
            def.ruleDescription,
            body,
            pageUrl,
            headers,
          ),
          image: image.isEmpty
              ? ''
              : LegadoParse.resolveUrl(pageUrl, image),
        ),
      );
    }
    return out;
  }

  static Future<List<_Item>> _listItems(
    RssSourceDef def,
    String body,
    String pageUrl,
    Map<String, String> headers,
  ) async {
    // Batch 170: '-' declares the article list descending,
    // '+' is a no-op marker (same convention as book lists).
    var rawRule = def.ruleArticles.trim();
    var reversed = false;
    if (rawRule.startsWith('-')) {
      reversed = true;
      rawRule = rawRule.substring(1).trim();
    } else if (rawRule.startsWith('+')) {
      rawRule = rawRule.substring(1).trim();
    }
    final items =
        await _listItemsInner(def, rawRule, body, pageUrl, headers);
    return reversed ? items.reversed.toList() : items;
  }

  static Future<List<_Item>> _listItemsInner(
    RssSourceDef def,
    String rule,
    String body,
    String pageUrl,
    Map<String, String> headers,
  ) async {
    if (rule.isEmpty) return const [];
    final trimmed = rule.trim();
    if (trimmed.startsWith('@js:') || trimmed.contains('<js>')) {
      final doc = LegadoDom.parseHtml(body);
      final out = await _hostFor(def).run(
        code: _jsCodeOf(trimmed),
        result: body,
        domJson: LegadoDom.serializeDocument(doc),
        baseUrl: pageUrl,
        sourceHeaders: headers,
      );
      return _itemsFromJs(out);
    }
    if (trimmed.startsWith(r'$.')) {
      try {
        final decoded = jsonDecode(body);
        final result = JsonPathLite.eval(decoded, trimmed);
        if (result is List) {
          return [for (final e in result) _Item.json(e)];
        }
        if (result != null) return [_Item.json(result)];
      } catch (_) {
        return const [];
      }
      return const [];
    }
    var chain = trimmed;
    if (chain.startsWith('@css:')) chain = chain.substring(5).trim();
    if (chain.startsWith('@css ')) chain = chain.substring(5).trim();
    final doc = LegadoDom.parseHtml(body);
    return [
      for (final el in LegadoDom.selectChain(doc, chain)) _Item.dom(el),
    ];
  }

  /// Standard feed items (RSS item / Atom entry) read
  /// straight off the raw text — deliberately NOT through
  /// the HTML parser, which treats link as a void head
  /// element and mangles feed documents. Feed XML is
  /// regular enough for tag-level extraction (CDATA
  /// unwrapped, inner markup stripped).
  static List<RssArticle> _feedArticles(String body, String pageUrl) {
    String field(String chunk, List<String> tags) {
      for (final tag in tags) {
        final m = RegExp(
          '<$tag[^>]*>([\\s\\S]*?)</$tag>',
          caseSensitive: false,
        ).firstMatch(chunk);
        if (m != null) {
          var text = (m.group(1) ?? '').trim();
          if (text.startsWith('<![CDATA[') && text.endsWith(']]>')) {
            text = text.substring(9, text.length - 3).trim();
          }
          text = text.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
          if (text.isNotEmpty) return text;
        }
      }
      return '';
    }

    var chunks = RegExp(
      r'<item[\s>][\s\S]*?</item>',
      caseSensitive: false,
    ).allMatches(body).map((m) => m.group(0)!).toList();
    if (chunks.isEmpty) {
      chunks = RegExp(
        r'<entry[\s>][\s\S]*?</entry>',
        caseSensitive: false,
      ).allMatches(body).map((m) => m.group(0)!).toList();
    }
    final out = <RssArticle>[];
    for (final chunk in chunks) {
      var link = field(chunk, ['link']);
      if (link.isEmpty) {
        final href = RegExp(
          r'''<link[^>]*href=["']([^"']+)["']''',
          caseSensitive: false,
        ).firstMatch(chunk);
        link = href?.group(1) ?? field(chunk, ['guid']);
      }
      out.add(
        RssArticle(
          title: field(chunk, ['title']),
          link: link.isEmpty ? '' : LegadoParse.resolveUrl(pageUrl, link),
          pubDate: field(chunk, ['pubDate', 'published', 'updated', 'date']),
          description: field(chunk, ['description', 'summary', 'content']),
        ),
      );
    }
    return out;
  }

  static List<_Item> _itemsFromJs(dynamic out) {
    if (out is! List) return const [];
    final items = <_Item>[];
    for (final entry in out) {
      if (entry is Map && entry.containsKey('__elHtml')) {
        final fragment = html_parser.parseFragment(
          entry['__elHtml']?.toString() ?? '',
        );
        for (final el in fragment.children) {
          items.add(_Item.dom(el));
        }
      } else if (entry is String) {
        items.add(_Item.text(entry));
      } else {
        items.add(_Item.json(entry));
      }
    }
    return items;
  }

  static Future<String> _field(
    RssSourceDef def,
    _Item item,
    String rule,
    String body,
    String pageUrl,
    Map<String, String> headers,
  ) async {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return '';
    final (base, pairs) = LegadoParse.splitReplacements(trimmed);
    final r = base.trim();
    String out = '';
    if (r.startsWith('@js:') || r.contains('<js>')) {
      final seed = item.el != null
          ? {'__elHtml': item.el!.outerHtml}
          : (item.json ?? item.text ?? body);
      try {
        final value = await _hostFor(def).run(
          code: _jsCodeOf(r),
          result: seed,
          baseUrl: pageUrl,
          sourceHeaders: headers,
        );
        out = _stringify(value);
      } catch (_) {
        out = '';
      }
    } else if (item.el != null) {
      var chain = r;
      if (chain.startsWith('@css:')) chain = chain.substring(5).trim();
      if (chain.startsWith('@css ')) chain = chain.substring(5).trim();
      if (chain.isEmpty) {
        out = LegadoDom.extract(item.el!, '');
      } else {
        final (els, attr) = LegadoDom.fieldElements(item.el!, chain);
        out = els.isEmpty ? '' : LegadoDom.extract(els.first, attr);
      }
    } else if (item.json != null) {
      out = _jsonField(item.json, r);
    } else if (item.text != null) {
      out = item.text!;
    }
    return LegadoParse.applyReplacements(out.trim(), pairs);
  }

  static String _jsonField(dynamic value, String rule) {
    var r = rule.trim();
    if (r.startsWith('@css:')) r = r.substring(5).trim();
    if (r.isEmpty) return _stringify(value);
    if (r.startsWith(r'$.')) {
      return _stringify(JsonPathLite.eval(value, r));
    }
    // Bare key or dotted path ("name", "data.title").
    dynamic current = value;
    for (final part in r.split('.')) {
      if (current is Map) {
        current = current[part];
      } else {
        return '';
      }
    }
    return _stringify(current);
  }

  /// Article body paragraphs, or null when the source has
  /// no content rule (the caller then offers the link).
  static Future<List<String>?> contentParagraphs(
    RssSourceDef def,
    RssArticle article,
  ) async {
    if (def.ruleContent.isEmpty || article.link.isEmpty) return null;
    final headers = await headersOf(def);
    final response = await LegadoHttp.fetch(
      article.link,
      sourceHeaders: headers,
    );
    if (response.statusCode >= 400) {
      throw StateError('源站返回 ${response.statusCode}');
    }
    final body = await _applyLoginCheck(
      def,
      response.body,
      response.url,
      response.statusCode,
      headers,
    );
    return contentFromBody(def, body, response.url, headers);
  }

  static Future<List<String>> contentFromBody(
    RssSourceDef def,
    String body,
    String pageUrl,
    Map<String, String> headers,
  ) async {
    final rule = def.ruleContent.trim();
    if (rule.startsWith('@js:') || rule.contains('<js>')) {
      final doc = LegadoDom.parseHtml(body);
      final out = await _hostFor(def).run(
        code: _jsCodeOf(rule),
        result: body,
        domJson: LegadoDom.serializeDocument(doc),
        baseUrl: pageUrl,
        sourceHeaders: headers,
      );
      return _paragraphsOfText(_stringify(out));
    }
    var chain = rule;
    if (chain.startsWith('@css:')) chain = chain.substring(5).trim();
    if (chain.startsWith('@css ')) chain = chain.substring(5).trim();
    final doc = LegadoDom.parseHtml(body);
    final (els, _) = LegadoDom.fieldElements(doc, chain);
    if (els.isEmpty) return const [];
    return _paragraphsOfElement(els.first);
  }

  static List<String> _paragraphsOfElement(dom.Element el) {
    var html = el.innerHtml;
    html = html.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      '\n',
    );
    html = html.replaceAll(
      RegExp(r'</(p|div|li|h[1-6])\s*>', caseSensitive: false),
      '\n',
    );
    final text = html_parser.parseFragment(html).text ?? '';
    return _paragraphsOfText(text);
  }

  static List<String> _paragraphsOfText(String text) {
    return [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
  }

  static String _jsCodeOf(String rule) {
    final trimmed = rule.trim();
    if (trimmed.startsWith('@js:')) return trimmed.substring(4);
    final start = trimmed.indexOf('<js>');
    final end = trimmed.lastIndexOf('</js>');
    if (start >= 0 && end > start) {
      return trimmed.substring(start + 4, end);
    }
    return trimmed;
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
