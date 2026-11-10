import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../bean/dialog/dialog.dart';
import '../../bean/widget/anikumo_icons.dart';
import '../../services/novel/moyuan_rss.dart';
import '../../services/novel/rss_engine.dart' show RssArticle;
import '../../services/novel/rss_sources.dart';

/// Batch 167: subscription (RSS-format) source pages — an
/// article list per source (with category chips when the
/// source declares a sortUrl) and a plain-text reader for
/// articles whose source carries a content rule. Articles
/// without a content rule, and rule-less directory
/// sources, open in the browser instead: that mirrors how
/// the original apps treat them (as web pages).

class RssReaderArgs {
  const RssReaderArgs({required this.sourceId, required this.article});

  final String sourceId;
  final RssArticle article;
}

Future<void> openRssExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    AnikumoDialog.showToast(message: '打不开这个链接');
  }
}

class RssArticlesPage extends StatefulWidget {
  const RssArticlesPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  State<RssArticlesPage> createState() => _RssArticlesPageState();
}

class _RssArticlesPageState extends State<RssArticlesPage> {
  late final RssSourceDef? _def;
  List<(String, String)> _categories = const [];
  String? _categoryUrl;
  Future<List<RssArticle>>? _articlesFuture;
  Object? _categoriesError;

  @override
  void initState() {
    super.initState();
    _def = RssSources.byId(widget.sourceId);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final def = _def;
    if (def == null) return;
    try {
      final categories = await MoyuanRssEngine.categories(def);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _categoryUrl = categories.isEmpty ? def.url : categories.first.$2;
        _articlesFuture = MoyuanRssEngine.articles(def, _categoryUrl!);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _categoriesError = e);
    }
  }

  void _selectCategory(String url) {
    final def = _def;
    if (def == null || url == _categoryUrl) return;
    setState(() {
      _categoryUrl = url;
      _articlesFuture = MoyuanRssEngine.articles(def, url);
    });
  }

  void _openArticle(RssArticle article) {
    final def = _def;
    if (def == null) return;
    if (article.link.isEmpty) return;
    if (def.ruleContent.isNotEmpty) {
      context.pushNamed(
        '/novel/rss-reader',
        arguments: RssReaderArgs(sourceId: def.id, article: article),
      );
    } else {
      openRssExternal(article.link);
    }
  }

  @override
  Widget build(BuildContext context) {
    final def = _def;
    if (def == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('订阅源')),
        body: const Center(child: Text('这个订阅源已不存在')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(def.name, maxLines: 1)),
      body: Column(
        children: [
          if (_categories.length > 1)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final (name, url) in _categories)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: ChoiceChip(
                        label: Text(name),
                        selected: url == _categoryUrl,
                        onSelected: (_) => _selectCategory(url),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: _buildList(def)),
        ],
      ),
    );
  }

  Widget _buildList(RssSourceDef def) {
    if (_categoriesError != null) {
      return Center(child: Text('加载失败：$_categoriesError'));
    }
    final future = _articlesFuture;
    if (future == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return FutureBuilder<List<RssArticle>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('加载失败：${snapshot.error}'));
        }
        final articles = snapshot.data ?? const [];
        if (articles.isEmpty) {
          return const Center(
            child: Text('没有取到文章（源站无结果，或这个源需要登录）'),
          );
        }
        return ListView.separated(
          itemCount: articles.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final article = articles[index];
            return ListTile(
              leading: article.image.isEmpty
                  ? const Icon(AnikumoIcons.description_outlined)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        article.image,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(AnikumoIcons.description_outlined),
                      ),
                    ),
              title: Text(
                article.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: (article.pubDate.isNotEmpty ||
                      article.description.isNotEmpty)
                  ? Text(
                      [
                        if (article.pubDate.isNotEmpty) article.pubDate,
                        if (article.description.isNotEmpty)
                          article.description,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: def.ruleContent.isEmpty
                  ? const Icon(AnikumoIcons.open_in_new_rounded)
                  : null,
              onTap: () => _openArticle(article),
            );
          },
        );
      },
    );
  }
}

class RssReaderPage extends StatelessWidget {
  const RssReaderPage({super.key, required this.args});

  final RssReaderArgs args;

  @override
  Widget build(BuildContext context) {
    final def = RssSources.byId(args.sourceId);
    return Scaffold(
      appBar: AppBar(
        title: Text(args.article.title, maxLines: 1),
        actions: [
          IconButton(
            icon: const Icon(AnikumoIcons.open_in_new_rounded),
            tooltip: '打开原文',
            onPressed: () => openRssExternal(args.article.link),
          ),
        ],
      ),
      body: def == null
          ? const Center(child: Text('这个订阅源已不存在'))
          : FutureBuilder<List<String>?>(
              future: MoyuanRssEngine.contentParagraphs(def, args.article),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('正文加载失败：${snapshot.error}'));
                }
                final paragraphs = snapshot.data;
                if (paragraphs == null || paragraphs.isEmpty) {
                  return const Center(child: Text('没有取到正文'));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    SelectableText(
                      args.article.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (args.article.pubDate.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        args.article.pubDate,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    for (final paragraph in paragraphs) ...[
                      SelectableText(
                        paragraph,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(height: 1.7),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
    );
  }
}
