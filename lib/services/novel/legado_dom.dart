import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// DOM + JSONPath evaluation for Legado rules (Dart side).
///
/// HTML rules are jsoup-style CSS selectors, evaluated with
/// package:html's selector engine; extraction follows the
/// Legado `@selector@attr` convention where attr is `text`,
/// `ownText`, `html`, or an attribute name.
class LegadoDom {
  LegadoDom._();

  static dom.Document parseHtml(String html) => html_parser.parse(html);

  static List<dom.Element> queryAll(Object context, String selector) {
    final sel = selector.trim();
    if (sel.isEmpty) return const [];
    try {
      if (context is dom.Document) return context.querySelectorAll(sel);
      if (context is dom.Element) return context.querySelectorAll(sel);
    } catch (_) {
      // Unsupported selector dialect in this engine subset.
    }
    return const [];
  }

  // ---- Legado selector chains (batch 31) -------------------
  // Real-world sources mostly write jsoup-style shorthand
  // chains, not raw CSS: steps joined by '@', each step
  // 'class.NAME[.IDX]' / 'tag.NAME[.IDX]' / 'id.NAME[.IDX]' /
  // 'children' / a plain CSS selector (optionally with a
  // trailing '.IDX'). Before this, those rules silently
  // matched nothing and whole sources returned empty lists.

  static List<dom.Element> _descendants(Object context) {
    if (context is dom.Document) return context.querySelectorAll('*');
    if (context is dom.Element) return context.querySelectorAll('*');
    return const [];
  }

  static List<dom.Element> _applyIndex(
    List<dom.Element> all,
    String? index,
  ) {
    if (index == null) return all;
    final idx = int.tryParse(index);
    if (idx == null) return all;
    final pos = idx >= 0 ? idx : all.length + idx;
    if (pos < 0 || pos >= all.length) return const [];
    return [all[pos]];
  }

  static List<dom.Element> _selectStep(Object context, String step) {
    var head = step.trim();
    // Batch 172: the reference's step grammar (ElementsSingle)
    // — a step is a kind head plus an optional index spec:
    // trailing '[...]' lists, a '!a:b' exclusion, or a dot
    // suffix that is a single index or an 'a:b[:c]' range.
    String? bracketSpec;
    var bracketExclude = false;
    if (head.endsWith(']')) {
      final open = head.indexOf('[');
      if (open >= 0) {
        var inner = head.substring(open + 1, head.length - 1).trim();
        head = head.substring(0, open).trim();
        if (inner.startsWith('!')) {
          bracketExclude = true;
          inner = inner.substring(1).trim();
        }
        bracketSpec = inner;
      }
    }
    String? bangSpec;
    if (bracketSpec == null) {
      final bang = head.indexOf('!');
      if (bang >= 0) {
        bangSpec = head.substring(bang + 1).trim();
        head = head.substring(0, bang).trim();
      }
    }

    List<dom.Element> base;
    String? dotSpec;
    if (head == 'children' || head.isEmpty && bracketSpec != null) {
      base = context is dom.Element
          ? context.children
          : context is dom.Document
              ? (context.documentElement?.children ?? const [])
              : const [];
    } else if (head.startsWith('children.')) {
      dotSpec = head.substring('children.'.length);
      base = context is dom.Element
          ? context.children
          : context is dom.Document
              ? (context.documentElement?.children ?? const [])
              : const [];
    } else {
      final shorthand =
          RegExp(r'^(class|tag|id|text)\.([^.]+)(?:\.(.+))?$')
              .firstMatch(head);
      if (shorthand != null) {
        final kind = shorthand.group(1)!;
        final name = shorthand.group(2)!;
        dotSpec = shorthand.group(3);
        base = _descendants(context).where((el) {
          return switch (kind) {
            'class' => el.classes.contains(name),
            'id' => el.id == name,
            // 'text.x' = elements whose OWN text contains x
            // (the reference's getElementsContainingOwnText).
            'text' => elementOwnText(el)
                .toLowerCase()
                .contains(name.toLowerCase()),
            _ => el.localName == name,
          };
        }).toList();
      } else {
        // Plain CSS, with an optional trailing '.IDX' step
        // index (only when the final dot-segment is purely
        // numeric).
        var css = head;
        String? index;
        final indexed = RegExp(r'^(.+)\.(-?\d+)$').firstMatch(head);
        if (indexed != null && !head.contains(' ')) {
          css = indexed.group(1)!;
          index = indexed.group(2);
        }
        base = _applyIndex(queryAll(context, css), index);
      }
    }

    if (bracketSpec != null) {
      return _applyIndexSpec(base, bracketSpec, exclude: bracketExclude);
    }
    if (bangSpec != null) {
      return _applyIndexSpec(
        base,
        bangSpec.replaceAll(':', ','),
        exclude: true,
      );
    }
    if (dotSpec != null) {
      return _applyIndexSpec(base, dotSpec, exclude: false);
    }
    return base;
  }

  /// Batch 172: apply a Legado index spec to [all] —
  /// comma-separated singles and 'start:end[:step]' ranges
  /// (either end may be omitted or negative; a descending
  /// range reverses). With [exclude], the picked positions
  /// are REMOVED instead of selected. Picks are deduped,
  /// order-preserving.
  static List<dom.Element> _applyIndexSpec(
    List<dom.Element> all,
    String spec, {
    required bool exclude,
  }) {
    final len = all.length;
    if (len == 0) return const [];
    final picked = <int>[];
    void addSingle(int raw) {
      final pos = raw >= 0 ? raw : len + raw;
      if (pos >= 0 && pos < len && !picked.contains(pos)) {
        picked.add(pos);
      }
    }

    void addRange(String a, String b, String c) {
      var start = a.isEmpty ? 0 : (int.tryParse(a) ?? 0);
      if (start < 0) start += len;
      var end = b.isEmpty ? len - 1 : (int.tryParse(b) ?? len - 1);
      if (end < 0) end += len;
      start = start.clamp(0, len - 1);
      end = end.clamp(0, len - 1);
      var step = c.isEmpty ? 0 : (int.tryParse(c) ?? 0);
      if (step == 0) step = end >= start ? 1 : -1;
      if (step > 0) {
        for (var i = start; i <= end; i += step) {
          if (!picked.contains(i)) picked.add(i);
        }
      } else {
        for (var i = start; i >= end; i += step) {
          if (!picked.contains(i)) picked.add(i);
        }
      }
    }

    for (final token in spec.split(',')) {
      final t = token.trim();
      if (t.isEmpty) continue;
      final parts = t.split(':');
      if (parts.length == 1) {
        final n = int.tryParse(t);
        if (n != null) addSingle(n);
      } else {
        addRange(
          parts[0].trim(),
          parts.length > 1 ? parts[1].trim() : '',
          parts.length > 2 ? parts[2].trim() : '',
        );
      }
    }
    if (exclude) {
      final drop = picked.toSet();
      return [
        for (var i = 0; i < len; i++)
          if (!drop.contains(i)) all[i],
      ];
    }
    return [for (final i in picked) all[i]];
  }

  /// Split [rule] on a top-level [separator], ignoring
  /// separators nested in [] / () or inside quotes (the
  /// same protection the scalar '||' splitter uses).
  static List<String> _splitCombinator(String rule, String separator) {
    final parts = <String>[];
    var depth = 0;
    String? quote;
    var start = 0;
    var i = 0;
    while (i < rule.length) {
      final ch = rule[i];
      if (quote != null) {
        if (ch == quote) quote = null;
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '[' || ch == '(') {
        depth++;
      } else if (ch == ']' || ch == ')') {
        if (depth > 0) depth--;
      } else if (depth == 0 && rule.startsWith(separator, i)) {
        parts.add(rule.substring(start, i));
        i += separator.length;
        start = i;
        continue;
      }
      i++;
    }
    parts.add(rule.substring(start));
    return parts;
  }

  static List<dom.Element> _concatDedup(List<List<dom.Element>> lists) {
    final seen = <dom.Element>{};
    final out = <dom.Element>[];
    for (final list in lists) {
      for (final el in list) {
        if (seen.add(el)) out.add(el);
      }
    }
    return out;
  }

  static List<dom.Element> _interleave(List<List<dom.Element>> lists) {
    final out = <dom.Element>[];
    var i = 0;
    var added = true;
    while (added) {
      added = false;
      for (final list in lists) {
        if (i < list.length) {
          out.add(list[i]);
          added = true;
        }
      }
      i++;
    }
    return out;
  }

  /// Resolve a '@'-joined selector chain against [context].
  static List<dom.Element> selectChain(Object context, String chainSpec) {
    // Batch 172: list combinators — the reference's
    // getElements splits the rule on '&&' (concatenate),
    // '%%' (interleave) and '||' (first non-empty) before
    // evaluating each alternative chain.
    for (final sep in ['&&', '%%', '||']) {
      final parts = _splitCombinator(chainSpec, sep);
      if (parts.length > 1) {
        final lists = [
          for (final part in parts)
            if (part.trim().isNotEmpty) selectChain(context, part),
        ];
        return switch (sep) {
          '&&' => _concatDedup(lists),
          '%%' => _interleave(lists),
          _ => lists.firstWhere(
              (l) => l.isNotEmpty,
              orElse: () => const [],
            ),
        };
      }
    }
    final steps = [
      for (final part in chainSpec.split('@'))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    if (steps.isEmpty) return const [];
    var current = _selectStep(context, steps.first);
    for (final step in steps.skip(1)) {
      if (current.isEmpty) break;
      final next = <dom.Element>[];
      for (final el in current) {
        next.addAll(_selectStep(el, step));
      }
      current = next;
    }
    return current;
  }

  /// Field evaluation helper: resolve [rule] (a chain with
  /// an optional trailing '@attr') to the matched elements
  /// plus the attr to extract. A bare trailing token is
  /// ambiguous ('div@a' = tag step vs 'tag.a.0@href' =
  /// attr): the attr reading wins when it matches anything,
  /// otherwise the full chain is tried.
  static (List<dom.Element>, String) fieldElements(
    Object context,
    String rule,
  ) {
    const knownAttrs = {'text', 'ownText', 'html', 'outerHtml', 'textNodes'};
    final segments = rule.split('@');
    if (segments.length == 1) {
      // Batch 172: a BARE extraction token reads the
      // context element ITSELF — the reference splits the
      // rule on '@' and sends the lone last part straight
      // to extraction, so chapterName 'text' is the item's
      // own text and chapterUrl 'href' its own attribute.
      // Treating the token as a selector (the old reading)
      // starved both and emptied whole chapter lists
      // (UU看书). A lone SELECTOR ('class.bookbox') still
      // selects: the token only reads as extraction when
      // it is a known extraction name or an attribute the
      // element actually carries.
      final token = rule.trim();
      final self = context is dom.Element
          ? context
          : context is dom.Document
              ? context.documentElement
              : null;
      if (self != null &&
          (knownAttrs.contains(token) ||
              self.attributes.containsKey(token))) {
        return ([self], token);
      }
      return (selectChain(context, rule), '');
    }
    final last = segments.last.trim();
    final stepLike = last.contains('.') || last == 'children';
    if (stepLike) return (selectChain(context, rule), '');
    final chainPart = segments.sublist(0, segments.length - 1).join('@');
    // Batch 36: a bare '@attr' rule (empty selector part)
    // reads the context element's OWN attribute in Legado
    // ('@onclick@js:…' on a list item). selectChain('') is
    // empty by definition, which starved the attr branch
    // below and left the JS seed '' — sources died with
    // "cannot read property '1' of null" on a null match.
    final els = chainPart.trim().isEmpty
        ? (context is dom.Element ? [context] : selectChain(context, chainPart))
        : selectChain(context, chainPart);
    // The attr reading wins only when the trailing token is
    // a known extraction name or an attribute the matched
    // element actually carries — 'tag.tr.0@td' means a td
    // STEP, not an attribute named td.
    if (els.isNotEmpty &&
        (knownAttrs.contains(last) ||
            els.first.attributes.containsKey(last))) {
      return (els, last);
    }
    return (selectChain(context, rule), '');
  }

  static dom.Element? queryFirst(Object context, String selector) {
    final all = queryAll(context, selector);
    return all.isEmpty ? null : all.first;
  }

  /// jsoup-like text(): all descendant text, whitespace
  /// collapsed.
  static String elementText(dom.Element el) {
    final parts = <String>[];
    void walk(dom.Node node) {
      if (node is dom.Text) {
        final t = node.text.trim();
        if (t.isNotEmpty) parts.add(t);
      } else {
        for (final child in node.nodes) {
          walk(child);
        }
      }
    }

    walk(el);
    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// jsoup ownText(): only direct text children.
  static String elementOwnText(dom.Element el) {
    final parts = <String>[];
    for (final node in el.nodes) {
      if (node is dom.Text) {
        final t = node.text.trim();
        if (t.isNotEmpty) parts.add(t);
      }
    }
    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Extract a field from an element per the Legado attr
  /// convention. Empty attr means text.
  static String extract(dom.Element el, String attr) {
    switch (attr) {
      case '':
      case 'text':
        return elementText(el);
      case 'ownText':
        return elementOwnText(el);
      case 'html':
        return el.innerHtml;
      case 'outerHtml':
        return el.outerHtml;
      case 'textNodes':
        return elementOwnText(el);
      default:
        return el.attributes[attr]?.toString() ?? '';
    }
  }

  /// Split a CSS field rule `selector@attr` at its last '@'.
  /// A rule with no '@' tail selects text.
  static (String, String) splitSelectorAttr(String rule) {
    final idx = rule.lastIndexOf('@');
    if (idx <= 0) return (rule.trim(), '');
    final tail = rule.substring(idx + 1).trim();
    if (tail.isEmpty || tail.contains(RegExp(r'[\s>\[\],:]'))) {
      return (rule.trim(), '');
    }
    return (rule.substring(0, idx).trim(), tail);
  }

  /// Serialize a parsed document into the JSON DOM the JS
  /// bridge consumes: elements {t, a, c}, text nodes {x}.
  static Map<String, dynamic> serializeDocument(dom.Document doc) {
    Map<String, dynamic>? ser(dom.Node node) {
      if (node is dom.Text) return {'x': node.text};
      if (node is dom.Element) {
        final children = <Map<String, dynamic>>[];
        for (final child in node.nodes) {
          final serialized = ser(child);
          if (serialized != null) children.add(serialized);
        }
        return {
          't': node.localName ?? '',
          'a': {
            for (final e in node.attributes.entries)
              e.key.toString(): e.value.toString(),
          },
          'c': children,
        };
      }
      return null;
    }

    final roots = <Map<String, dynamic>>[];
    for (final child in doc.nodes) {
      final serialized = ser(child);
      if (serialized != null) roots.add(serialized);
    }
    return {'t': '#root', 'a': <String, String>{}, 'c': roots};
  }
}

/// Minimal JSONPath evaluator covering what Legado sources
/// actually use: $.a.b, $.a[0], $.a[*], $..a (recursive),
/// $.a.b[*].c. A path containing a wildcard or recursive
/// step returns a List; anything else returns the value.
class JsonPathLite {
  JsonPathLite._();

  static dynamic eval(dynamic root, String path) {
    var p = path.trim();
    if (!p.startsWith(r'$')) return null;
    p = p.substring(1);
    var multiple = false;
    dynamic current = root;
    var i = 0;
    List<dynamic> asList(dynamic v) =>
        v is List ? v.cast<dynamic>() : [?v];

    while (i < p.length) {
      if (p.startsWith('..', i)) {
        multiple = true;
        i += 2;
        final name = _readName(p, i);
        i += name.length;
        final found = <dynamic>[];
        void collect(dynamic v) {
          if (v is Map) {
            for (final e in v.entries) {
              if (e.key.toString() == name) found.add(e.value);
              collect(e.value);
            }
          } else if (v is List) {
            for (final e in v) {
              collect(e);
            }
          }
        }

        for (final v in asList(current)) {
          collect(v);
        }
        current = found;
      } else if (p[i] == '.') {
        i++;
        final name = _readName(p, i);
        i += name.length;
        if (multiple) {
          current = [
            for (final v in asList(current))
              if (v is Map) v[name],
          ];
        } else {
          current = current is Map ? current[name] : null;
        }
      } else if (p[i] == '[') {
        final close = p.indexOf(']', i);
        if (close < 0) break;
        final inner = p.substring(i + 1, close).trim();
        i = close + 1;
        if (inner == '*') {
          multiple = true;
          current = [
            for (final v in asList(current))
              if (v is List) ...v else ?v,
          ];
        } else if (inner.startsWith("'") || inner.startsWith('"')) {
          final name = inner.substring(1, inner.length - 1);
          if (multiple) {
            current = [
              for (final v in asList(current))
                if (v is Map) v[name],
            ];
          } else {
            current = current is Map ? current[name] : null;
          }
        } else {
          final idx = int.tryParse(inner) ?? -1;
          if (multiple) {
            current = [
              for (final v in asList(current))
                if (v is List && idx >= 0 && idx < v.length) v[idx],
            ];
          } else {
            current =
                current is List && idx >= 0 && idx < current.length
                    ? current[idx]
                    : null;
          }
        }
      } else {
        break;
      }
    }
    return current;
  }

  static String _readName(String p, int start) {
    var i = start;
    while (i < p.length && p[i] != '.' && p[i] != '[') {
      i++;
    }
    return p.substring(start, i);
  }
}
