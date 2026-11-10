import 'dart:convert';

import 'moyuan_host.dart';
import 'rss_engine.dart' show RssArticle;
import 'rss_sources.dart';

/// Batch 174: the subscription reader on the MoYuan
/// engine. Same surface the subscription page has always
/// consumed (categories / articles / contentParagraphs),
/// served by the engine's own subscription registry —
/// which, unlike the Dart reader it replaces, also
/// follows nextPageUrl (up to 5 pages) and runs each
/// source's loginCheckJs. The Dart RssEngine stays in
/// the tree for its fixture tests; nothing at runtime
/// calls it anymore.
class MoyuanRssEngine {
  MoyuanRssEngine._();

  static MoyuanHost get _host => MoyuanHost.instance;

  static Future<List<(String, String)>> categories(
    RssSourceDef def,
  ) async {
    await _host.syncSourcesIfChanged();
    final out = await _host.callWithReplay(
      def.id,
      '__moyuanEngine.rss.categories(${jsonEncode(def.id)})',
    );
    return [
      for (final e in (out as List? ?? const []))
        if (e is Map &&
            (e['url']?.toString().trim() ?? '').isNotEmpty)
          (
            (e['title'] ?? e['name'] ?? '').toString(),
            e['url'].toString(),
          ),
    ];
  }

  static Future<List<RssArticle>> articles(
    RssSourceDef def,
    String categoryUrl,
  ) async {
    await _host.syncSourcesIfChanged();
    final out = await _host.callWithReplay(
      def.id,
      '__moyuanEngine.rss.articles(${jsonEncode(def.id)}, '
      '{"category": ${jsonEncode(categoryUrl)}})',
    );
    return [
      for (final e in (out as List? ?? const []))
        if (e is Map) _article(e.cast<String, dynamic>()),
    ];
  }

  static RssArticle _article(Map<String, dynamic> e) {
    final title = e['title']?.toString() ?? '';
    return RssArticle(
      title: title.isEmpty ? '(无标题)' : title,
      link: e['link']?.toString() ?? '',
      pubDate: e['pubDate']?.toString() ?? '',
      description: e['description']?.toString() ?? '',
      image: e['image']?.toString() ?? '',
    );
  }

  /// Article body paragraphs, or null when the source
  /// has no content rule (the caller then offers the
  /// link) — the same contract as before.
  static Future<List<String>?> contentParagraphs(
    RssSourceDef def,
    RssArticle article,
  ) async {
    if (def.ruleContent.isEmpty || article.link.isEmpty) return null;
    await _host.syncSourcesIfChanged();
    final out = await _host.callWithReplay(
      def.id,
      '__moyuanEngine.rss.articleContent('
      '{"title": ${jsonEncode(article.title)}, '
      '"link": ${jsonEncode(article.link)}, '
      '"sourceId": ${jsonEncode(def.id)}})',
    );
    if (out is! Map) return const [];
    return [
      for (final p in (out['paragraphs'] as List? ?? const []))
        p.toString(),
    ];
  }
}
