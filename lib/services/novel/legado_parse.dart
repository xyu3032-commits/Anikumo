import 'dart:convert';
import 'dart:io';

/// Parsing helpers for Legado book-source definitions.
///
/// Legado sources are permissive: headers and URL options are
/// written as JS object literals (single quotes, bare keys),
/// content may arrive hex-encoded (base16), and URLs carry
/// `{{key}}` / `{{page}}` templates. These helpers normalize
/// all of that without ever throwing on shape surprises —
/// a malformed piece yields an empty result, not a crash.
class LegadoParse {
  LegadoParse._();

  /// Batch 66: decode a source payload in whatever wrapper
  /// the file or subscription used: plain JSON text, base16
  /// (hex), base64, or base64 of zlib/gzip-compressed JSON
  /// (the classic 阅读 (YueDu) shuyuan distribution format
  /// is base64(zlib(JSON))). A leading BOM is stripped.
  /// Returns the input unchanged when nothing matches.
  static String decodePayload(String text) {
    var t = text.trim();
    if (t.startsWith('\uFEFF')) t = t.substring(1).trim();
    if (t.isEmpty || t.startsWith('{') || t.startsWith('[')) return t;
    final hex = decodePossibleBase16(t);
    if (hex != t) return hex;
    final compact = t.replaceAll(RegExp(r'\s+'), '');
    if (compact.length >= 40 &&
        compact.length % 4 == 0 &&
        RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(compact)) {
      try {
        final bytes = base64Decode(compact);
        try {
          return utf8.decode(bytes);
        } catch (_) {
          // Compressed payload: zlib (78 9c/da) or gzip.
          for (final codec in [ZLibCodec(), GZipCodec()]) {
            try {
              return utf8.decode(codec.decode(bytes));
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return t;
  }

  /// Decode text that may be base16 (hex) encoded. Returns
  /// the input unchanged when it does not look like hex.
  static String decodePossibleBase16(String text) {
    final t = text.trim();
    if (t.length < 40 || t.length.isOdd) return text;
    if (t.startsWith('{') || t.startsWith('[')) return text;
    if (!RegExp(r'^[0-9a-fA-F\s]+$').hasMatch(t)) return text;
    try {
      final clean = t.replaceAll(RegExp(r'\s+'), '');
      final bytes = <int>[];
      for (var i = 0; i < clean.length; i += 2) {
        bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
      return utf8.decode(bytes);
    } catch (_) {
      return text;
    }
  }

  /// Parse a source payload (single object or array, possibly
  /// base16) into a list of source definition maps.
  static List<Map<String, dynamic>> parseSourceArray(String text) {
    final decoded = decodePayload(text);
    // Batch 66: shape tolerance for the wild — strict JSON
    // first, then a JSONC pass (comments / trailing commas),
    // then the JS-literal pass, then JSONL (one source per
    // line). Wrapper objects ({"sources": [...]}) unwrap.
    for (final candidate in <String>[
      decoded,
      _stripJsonComments(decoded),
    ]) {
      try {
        final out = _sourcesFromDecoded(jsonDecode(candidate));
        if (out != null) return out;
      } catch (_) {}
    }
    try {
      final out = _sourcesFromDecoded(
        jsonDecode(_literalToJson(decoded.trim())),
      );
      if (out != null) return out;
    } catch (_) {}
    final lines = <Map<String, dynamic>>[];
    for (final line in decoded.split('\n')) {
      final t = line.trim();
      if (!t.startsWith('{')) continue;
      try {
        final v = jsonDecode(t);
        if (v is Map) lines.add(v.cast<String, dynamic>());
      } catch (_) {}
    }
    if (lines.isNotEmpty) return lines;
    // Batch 35: growable, never const — callers mutate the
    // result (the source registry adds imported sources to
    // it), and a const [] here made every first-time import
    // on a fresh install die with "Cannot add to an
    // unmodifiable list".
    return <Map<String, dynamic>>[];
  }

  /// One decoded JSON value → source maps, or null when the
  /// shape is unusable. A bare object is a single source,
  /// unless it wraps the array under a well-known key.
  static List<Map<String, dynamic>>? _sourcesFromDecoded(dynamic value) {
    if (value is List) {
      return [
        for (final e in value)
          if (e is Map) e.cast<String, dynamic>(),
      ];
    }
    if (value is Map) {
      final map = value.cast<String, dynamic>();
      for (final key in ['sources', 'bookSources', 'data', 'list', 'items']) {
        final inner = map[key];
        if (inner is List && inner.any((e) => e is Map)) {
          return [
            for (final e in inner)
              if (e is Map) e.cast<String, dynamic>(),
          ];
        }
      }
      return [map];
    }
    return null;
  }

  /// Removes // and /* */ comments and trailing commas
  /// outside string literals (JSONC, as several source
  /// repos publish). String contents are preserved exactly.
  static String _stripJsonComments(String input) {
    final out = StringBuffer();
    var inString = false;
    var escaped = false;
    var i = 0;
    while (i < input.length) {
      final ch = input[i];
      if (inString) {
        out.write(ch);
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        i++;
        continue;
      }
      if (ch == '"') {
        inString = true;
        out.write(ch);
        i++;
        continue;
      }
      if (ch == '/' && i + 1 < input.length && input[i + 1] == '/') {
        while (i < input.length && input[i] != '\n') i++;
        continue;
      }
      if (ch == '/' && i + 1 < input.length && input[i + 1] == '*') {
        i += 2;
        while (i + 1 < input.length &&
            !(input[i] == '*' && input[i + 1] == '/')) i++;
        i += 2;
        continue;
      }
      if (ch == ',') {
        var j = i + 1;
        while (j < input.length && ' \t\r\n'.contains(input[j])) j++;
        if (j < input.length && (input[j] == ']' || input[j] == '}')) {
          i++;
          continue;
        }
      }
      out.write(ch);
      i++;
    }
    return out.toString();
  }

  /// Parse a JS-object-literal-ish string into a map: strict
  /// JSON first, then a tolerant tokenizer pass that accepts
  /// single-quoted strings, bare keys and trailing commas.
  static Map<String, dynamic> parseLooseObject(String? text) {
    if (text == null) return const {};
    final t = text.trim();
    if (t.isEmpty) return const {};
    try {
      final v = jsonDecode(t);
      if (v is Map) return v.cast<String, dynamic>();
    } catch (_) {}
    try {
      final v = jsonDecode(_literalToJson(t));
      if (v is Map) return v.cast<String, dynamic>();
    } catch (_) {}
    return const {};
  }

  /// Convert a JS object literal to JSON text: quote bare
  /// keys, turn single-quoted strings into double-quoted
  /// ones (escaping embedded double quotes), drop trailing
  /// commas. Strings are scanned properly so apostrophes
  /// inside double-quoted strings survive.
  static String _literalToJson(String input) {
    final out = StringBuffer();
    var i = 0;
    var expectKey = false;
    final stack = <String>[];
    while (i < input.length) {
      final ch = input[i];
      if (ch == '{') {
        stack.add('{');
        expectKey = true;
        out.write(ch);
        i++;
      } else if (ch == '[') {
        stack.add('[');
        expectKey = false;
        out.write(ch);
        i++;
      } else if (ch == '}' || ch == ']') {
        if (stack.isNotEmpty) stack.removeLast();
        // Remove a trailing comma we may have just written.
        var s = out.toString();
        if (s.trimRight().endsWith(',')) {
          s = s.trimRight();
          s = s.substring(0, s.length - 1);
          out.clear();
          out.write(s);
        }
        out.write(ch);
        i++;
      } else if (ch == "'") {
        // Single-quoted string → JSON string.
        final sb = StringBuffer('"');
        i++;
        while (i < input.length && input[i] != "'") {
          if (input[i] == '\\' && i + 1 < input.length) {
            sb.write(input[i]);
            sb.write(input[i + 1]);
            i += 2;
          } else if (input[i] == '"') {
            sb.write('\\"');
            i++;
          } else {
            sb.write(input[i]);
            i++;
          }
        }
        i++; // closing quote
        sb.write('"');
        out.write(sb);
        if (expectKey) {
          // key position: colon follows separately.
        }
        expectKey = false;
      } else if (ch == '"') {
        // Copy a JSON string verbatim.
        final start = i;
        i++;
        while (i < input.length && input[i] != '"') {
          if (input[i] == '\\') i++;
          i++;
        }
        i++;
        out.write(input.substring(start, i));
        expectKey = false;
      } else if (ch == ':') {
        out.write(ch);
        expectKey = false;
        i++;
      } else if (ch == ',') {
        out.write(ch);
        expectKey = stack.isNotEmpty && stack.last == '{';
        i++;
      } else if (RegExp(r'[A-Za-z_$]').hasMatch(ch) && expectKey) {
        // Bare key.
        final start = i;
        while (i < input.length && RegExp(r'[A-Za-z0-9_$]').hasMatch(input[i])) {
          i++;
        }
        out.write('"${input.substring(start, i)}"');
        expectKey = false;
      } else {
        out.write(ch);
        i++;
      }
    }
    return out.toString();
  }

  /// Decode a JSON array text, or return an empty list.
  static List<dynamic> decodeJsonArray(String text) {
    try {
      final v = jsonDecode(text);
      if (v is List) return v;
    } catch (_) {}
    return const [];
  }

  /// Parse any JS-literal value (objects/arrays with bare
  /// keys or single quotes) into Dart values.
  static dynamic parseLooseValue(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {}
    try {
      return jsonDecode(_literalToJson(text.trim()));
    } catch (_) {
      return null;
    }
  }

  /// Split a Legado URL spec into its URL and trailing
  /// options object: `https://x/s, {"method":"POST",...}`.
  static (String, Map<String, dynamic>) splitUrlOptions(String spec) {
    final m = RegExp(r',\s*\{').firstMatch(spec);
    if (m == null) return (spec.trim(), const {});
    final url = spec.substring(0, m.start).trim();
    final options = parseLooseObject(spec.substring(m.start + 1));
    return (url, options);
  }

  /// Classify a Legado URL field (searchUrl / explore
  /// entries). Three shapes occur in the wild:
  /// - literal: a plain URL spec, possibly relative, possibly
  ///   with an options suffix;
  /// - js: '@js:...' or a whole-field '<js>...</js>' whose
  ///   evaluation yields the URL spec;
  /// - the embedded-literal idiom: '<js>URLSPEC;result...'
  ///   where the URL spec itself rides inside the tags and
  ///   the trailing JS only massages a result variable —
  ///   recognized when the inner text starts like a URL spec
  ///   and its first statement has balanced braces.
  static ({String kind, String body}) classifyUrlSpec(String raw) {
    final spec = raw.trim();
    if (spec.startsWith('@js:')) {
      return (kind: 'js', body: spec.substring(4).trim());
    }
    if (spec.startsWith('<js>') && spec.endsWith('</js>')) {
      final inner = spec.substring(4, spec.length - 5).trim();
      if (inner.startsWith('/') || inner.startsWith('http')) {
        final semi = inner.indexOf(';');
        final candidate = semi == -1 ? inner : inner.substring(0, semi);
        var depth = 0;
        var balanced = true;
        for (final ch in candidate.codeUnits) {
          if (ch == 0x7B) depth++;
          if (ch == 0x7D) depth--;
          if (depth < 0) balanced = false;
        }
        if (balanced && depth == 0 && !candidate.contains('(')) {
          return (kind: 'literal', body: candidate);
        }
      }
      return (kind: 'js', body: inner);
    }
    return (kind: 'literal', body: spec);
  }

  /// Whether a URL spec asks for WebView rendering
  /// (`{"webView": true}` in its options suffix) — Legado's
  /// signal that the page only yields its content to a real
  /// browser (script-injected images, typically).
  static bool urlRequestsWebView(String spec) {
    return splitUrlOptions(spec).$2['webView'] == true;
  }

  /// Fill `{{key}}`, `{{page}}` and simple `{{page±n}}` /
  /// `{{(page-1)*20}}` arithmetic templates in a URL.
  static String fillTemplate(String template,
      {required String key, required int page}) {
    return template.replaceAllMapped(RegExp(r'\{\{(.*?)\}\}'), (m) {
      final expr = (m.group(1) ?? '').trim();
      if (expr == 'key') return Uri.encodeComponent(key);
      final value = _evalPageExpr(expr, page);
      if (value != null) return value.toString();
      if (expr == 'key_') return key;
      return m.group(0) ?? '';
    });
  }

  static int? _evalPageExpr(String expr, int page) {
    if (!RegExp(r'^[0-9page\s+\-*/()]+$').hasMatch(expr)) return null;
    try {
      final tokens = RegExp(r'\d+|page|[+\-*/()]')
          .allMatches(expr.replaceAll(' ', ''))
          .map((m) => m.group(0)!)
          .toList();
      final parser = _PageExprParser(tokens, page);
      final value = parser.parseExpr();
      return parser.atEnd ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// Split off the `##pattern##replacement##...` tail of a
  /// rule. Returns the base rule and the replacement pairs.
  static (String, List<(String, String)>) splitReplacements(String rule) {
    if (!rule.contains('##')) return (rule, const []);
    final parts = rule.split('##');
    final pairs = <(String, String)>[];
    for (var i = 1; i < parts.length; i += 2) {
      pairs.add((parts[i], i + 1 < parts.length ? parts[i + 1] : ''));
    }
    return (parts.first, pairs);
  }

  /// Apply Legado `##` replacements: regex replace where the
  /// replacement may reference $1..$9 capture groups.
  static String applyReplacements(
      String value, List<(String, String)> pairs) {
    var out = value;
    for (final (pattern, replacement) in pairs) {
      try {
        final re = RegExp(pattern);
        out = out.replaceAllMapped(re, (m) {
          var r = replacement;
          for (var g = m.groupCount; g >= 1; g--) {
            r = r.replaceAll('\$$g', m.group(g) ?? '');
          }
          return r.replaceAll(r'$0', m.group(0) ?? '');
        });
      } catch (_) {
        // A bad regex in a source must not kill the value.
      }
    }
    return out;
  }

  /// Resolve a possibly-relative URL against a base.
  static String resolveUrl(String base, String url) {
    final u = url.trim();
    if (u.isEmpty) return u;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    try {
      return Uri.parse(base).resolve(u).toString();
    } catch (_) {
      return u;
    }
  }
}

/// Tiny recursive-descent evaluator for {{page}} arithmetic.
class _PageExprParser {
  _PageExprParser(this.tokens, this.page);

  final List<String> tokens;
  final int page;
  var pos = 0;

  bool get atEnd => pos == tokens.length;

  int parseExpr() {
    var v = parseTerm();
    while (pos < tokens.length && (tokens[pos] == '+' || tokens[pos] == '-')) {
      final op = tokens[pos++];
      final rhs = parseTerm();
      v = op == '+' ? v + rhs : v - rhs;
    }
    return v;
  }

  int parseTerm() {
    var v = parseFactor();
    while (pos < tokens.length && (tokens[pos] == '*' || tokens[pos] == '/')) {
      final op = tokens[pos++];
      final rhs = parseFactor();
      v = op == '*' ? v * rhs : (rhs == 0 ? v : v ~/ rhs);
    }
    return v;
  }

  int parseFactor() {
    if (pos >= tokens.length) return 0;
    final t = tokens[pos++];
    if (t == '(') {
      final v = parseExpr();
      pos++; // ')'
      return v;
    }
    if (t == '-') return -parseFactor();
    if (t == 'page') return page;
    return int.tryParse(t) ?? 0;
  }
}
