import 'dart:convert';

import '../../models/novel_item.dart';
import 'legado_parse.dart';

/// A parsed Legado book-source definition (one entry of a
/// book-source JSON array).
class LegadoSourceDef {
  LegadoSourceDef._({
    required this.raw,
    required this.name,
    required this.url,
    required this.type,
    required this.group,
    required this.searchUrl,
    required this.exploreUrlRaw,
    required this.headers,
    required this.jsLib,
    required this.ruleSearch,
    required this.ruleExplore,
    required this.ruleBookInfo,
    required this.ruleToc,
    required this.ruleContent,
    required this.builtin,
  });

  final Map<String, dynamic> raw;
  final String name;

  /// bookSourceUrl — doubles as the source id.
  final String url;
  final int type;
  final String group;
  final String searchUrl;
  final String exploreUrlRaw;
  final Map<String, String> headers;
  final String? jsLib;
  final Map<String, String> ruleSearch;
  final Map<String, String> ruleExplore;
  final Map<String, String> ruleBookInfo;
  final Map<String, String> ruleToc;
  final Map<String, String> ruleContent;

  /// True for the two sources bundled from the
  /// liruohrh/legado-booksource library.
  final bool builtin;

  String get id => url;

  bool get enabled => raw['enabled'] != false;

  static Map<String, String> _ruleMap(dynamic value) {
    // Batch 66: some exports stringify a rule section
    // (the whole map as one JSON string) — parse it back
    // instead of silently dropping every rule in it
    // (a dropped ruleToc is exactly "imported fine, but
    // the book has no chapters").
    if (value is String) {
      value = LegadoParse.parseLooseObject(value);
    }
    if (value is! Map) return const {};
    return {
      for (final e in value.entries)
        if (e.value != null && e.value.toString().isNotEmpty)
          e.key.toString(): e.value.toString(),
    };
  }

  /// Batch 66: normalize a foreign source shape into the
  /// Legado 3.0 shape this class reads. The big one is the
  /// classic 阅读 (YueDu) format: FLAT rule keys
  /// (ruleSearchList / ruleChapterList / ruleBookContent…),
  /// the search URL inside ruleSearchUrl with literal
  /// `searchKey` / `searchPage` placeholders, the TOC-page
  /// rule inside ruleContentUrl, `enable` instead of
  /// `enabled`, `httpUserAgent` instead of a header map,
  /// and bookSourceType as a Chinese word （漫画/小说/音频）.
  /// Only missing pieces are synthesized; a source that
  /// already carries Legado-shaped sections keeps them.
  static Map<String, dynamic> _normalizeForeign(
    Map<String, dynamic> json,
  ) {
    String s(String key) => json[key]?.toString() ?? '';
    final typeText = s('bookSourceType');
    final typeValue = switch (typeText) {
      '漫画' => 2,
      '音频' || '听书' => 1,
      '小说' => 0,
      _ => null,
    };
    final isYuedu = json.containsKey('ruleSearchList') ||
        json.containsKey('ruleSearchUrl') ||
        json.containsKey('ruleChapterList');
    if (!isYuedu && typeValue == null) return json;
    final out = Map<String, dynamic>.of(json);
    if (typeValue != null) out['bookSourceType'] = typeValue;
    if (!isYuedu) return out;

    Map<String, String> pick(Map<String, String> fields) => {
          for (final e in fields.entries)
            if (e.value.isNotEmpty) e.key: e.value,
        };
    Map<String, String> searchRules() => pick({
          'bookList': s('ruleSearchList'),
          'name': s('ruleSearchName'),
          'author': s('ruleSearchAuthor'),
          'coverUrl': s('ruleSearchCoverUrl'),
          'kind': s('ruleSearchKind'),
          'lastChapter': s('ruleSearchLastChapter'),
          'bookUrl': s('ruleSearchNoteUrl'),
        });

    if (json.containsKey('enable')) out['enabled'] = json['enable'];
    if (!out.containsKey('header') && s('httpUserAgent').isNotEmpty) {
      out['header'] = jsonEncode({'User-Agent': s('httpUserAgent')});
    }
    if (out['searchUrl'] == null && s('ruleSearchUrl').isNotEmpty) {
      out['searchUrl'] = s('ruleSearchUrl')
          .replaceAll('searchKey', '{{key}}')
          .replaceAll('searchPage', '{{page}}');
    }
    if (out['exploreUrl'] == null && s('ruleFindUrl').isNotEmpty) {
      // YueDu separates find entries with \r (\n works too).
      out['exploreUrl'] =
          s('ruleFindUrl').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    }
    if (out['ruleSearch'] is! Map && s('ruleSearchList').isNotEmpty) {
      out['ruleSearch'] = searchRules();
    }
    if (out['ruleExplore'] is! Map) {
      if (s('ruleFindList').isNotEmpty) {
        out['ruleExplore'] = pick({
          'bookList': s('ruleFindList'),
          'name': s('ruleFindName'),
          'author': s('ruleFindAuthor'),
          'coverUrl': s('ruleFindCoverUrl'),
          'kind': s('ruleFindKind'),
          'lastChapter': s('ruleFindLastChapter'),
          'bookUrl': s('ruleFindNoteUrl'),
          'intro': s('ruleFindIntroduce'),
        });
      } else if (s('ruleSearchList').isNotEmpty) {
        // YueDu parses find pages with the search rules.
        out['ruleExplore'] = searchRules();
      }
    }
    if (out['ruleBookInfo'] is! Map) {
      out['ruleBookInfo'] = pick({
        'name': s('ruleBookName'),
        'author': s('ruleBookAuthor'),
        'coverUrl': s('ruleCoverUrl'),
        'intro': s('ruleIntroduce'),
        'kind': s('ruleBookKind'),
        'lastChapter': s('ruleBookLastChapter'),
        'tocUrl': s('ruleContentUrl'),
      });
    }
    if (out['ruleToc'] is! Map) {
      out['ruleToc'] = pick({
        'chapterList': s('ruleChapterList'),
        'chapterName': s('ruleChapterName'),
        'chapterUrl': s('ruleChapterUrl'),
        'nextTocUrl': s('ruleChapterUrlNext'),
      });
    }
    if (out['ruleContent'] is! Map) {
      out['ruleContent'] = pick({
        'content': s('ruleBookContent'),
        'nextContentUrl': s('ruleContentUrlNext'),
      });
    }
    if (out['bookUrlPattern'] == null &&
        s('ruleBookUrlPattern').isNotEmpty) {
      out['bookUrlPattern'] = s('ruleBookUrlPattern');
    }
    return out;
  }

  static LegadoSourceDef? fromJson(
    Map<String, dynamic> sourceJson, {
    bool builtin = false,
  }) {
    final json = _normalizeForeign(sourceJson);
    final url = (json['bookSourceUrl'] ?? json['sourceUrl'] ?? json['url'])
            ?.toString()
            .trim() ??
        '';
    final name =
        (json['bookSourceName'] ?? json['sourceName'] ?? json['name'])
                ?.toString()
                .trim() ??
            '';
    if (url.isEmpty || name.isEmpty) return null;
    final headerObj = LegadoParse.parseLooseObject(
      json['header']?.toString(),
    );
    return LegadoSourceDef._(
      raw: json,
      name: name,
      url: url,
      type: int.tryParse(json['bookSourceType']?.toString() ?? '') ?? 0,
      group: json['bookSourceGroup']?.toString() ?? '',
      searchUrl: json['searchUrl']?.toString() ?? '',
      exploreUrlRaw: switch (json['exploreUrl']) {
        final String v => v,
        final List v => jsonEncode(v),
        _ => '',
      },
      headers: {
        for (final e in headerObj.entries)
          e.key: e.value.toString(),
      },
      jsLib: json['jsLib']?.toString(),
      ruleSearch: _ruleMap(json['ruleSearch']),
      ruleExplore: _ruleMap(json['ruleExplore']),
      ruleBookInfo: _ruleMap(json['ruleBookInfo']),
      ruleToc: _ruleMap(json['ruleToc']),
      ruleContent: _ruleMap(json['ruleContent']),
      builtin: builtin,
    );
  }

  /// Explore categories declared by exploreUrl. Two shapes
  /// in the wild: a JSON array of {title, url} (entries with
  /// an empty URL are section headers in Legado and are
  /// skipped as categories), and the line format — one
  /// `标题::地址` per line.
  List<NovelExploreCategory> get exploreCategories {
    final rawText = exploreUrlRaw.trim();
    if (rawText.isEmpty) return const [];
    if (!rawText.startsWith('[')) {
      // Batch 36: the line format was not parsed at all —
      // the whole multi-line blob became ONE category whose
      // "url" was the blob itself, so every such source
      // (69书吧/铅笔/和图书/速读谷/得奇/快书网…) died on
      // its explore fetch with a URI scheme FormatException.
      final lines = [
        for (final line in rawText.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
      final out = <NovelExploreCategory>[];
      for (final line in lines) {
        final sep = line.indexOf('::');
        if (sep <= 0) continue;
        final title = line.substring(0, sep).trim();
        final url = line.substring(sep + 2).trim();
        if (title.isNotEmpty && url.isNotEmpty) {
          out.add(NovelExploreCategory(title: title, url: url));
        }
      }
      if (out.isNotEmpty) return out;
      return [NovelExploreCategory(title: '发现', url: rawText)];
    }
    var decoded = LegadoParse.decodeJsonArray(rawText);
    if (decoded.isEmpty) {
      final loose = LegadoParse.parseLooseValue(rawText);
      if (loose is List) decoded = loose;
    }
    final out = <NovelExploreCategory>[];
    for (final e in decoded) {
      if (e is Map) {
        final title = e['title']?.toString() ?? '';
        final url = e['url']?.toString() ?? '';
        if (title.isNotEmpty && url.isNotEmpty) {
          out.add(NovelExploreCategory(title: title, url: url));
        }
      }
    }
    return out;
  }
}
