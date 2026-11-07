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
    final shorthand =
        RegExp(r'^(class|tag|id)\.([^.]+)(?:\.(-?\d+))?$').firstMatch(step);
    if (shorthand != null) {
      final kind = shorthand.group(1)!;
      final name = shorthand.group(2)!;
      final all = _descendants(context).where((el) {
        return switch (kind) {
          'class' => el.classes.contains(name),
          'id' => el.id == name,
          _ => el.localName == name,
        };
      }).toList();
      return _applyIndex(all, shorthand.group(3));
    }
    if (step == 'children') {
      if (context is dom.Element) return context.children;
      if (context is dom.Document) {
        return context.documentElement?.children ?? const [];
      }
      return const [];
    }
    // Plain CSS, with an optional trailing '.IDX' step index
    // (only when the final dot-segment is purely numeric).
    var css = step;
    String? index;
    final indexed = RegExp(r'^(.+)\.(-?\d+)$').firstMatch(step);
    if (indexed != null && !step.contains(' ')) {
      css = indexed.group(1)!;
      index = indexed.group(2);
    }
    return _applyIndex(queryAll(context, css), index);
  }

  /// Resolve a '@'-joined selector chain against [context].
  static List<dom.Element> selectChain(Object context, String chainSpec) {
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
    final segments = rule.split('@');
    if (segments.length == 1) return (selectChain(context, rule), '');
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
    const knownAttrs = {'text', 'ownText', 'html', 'outerHtml', 'textNodes'};
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
