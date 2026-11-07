import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/violet_components.dart';

import '../../models/novel_item.dart';
import '../../services/novel/novel_api.dart';
import '../../services/novel/novel_sources.dart';
import 'novel_widgets.dart';

/// Novel search: the active source, or every source with
/// relevance ranking.
class NovelSearchPage extends StatefulWidget {
  const NovelSearchPage({super.key, this.initialQuery = ''});

  /// Batch 32: companion sections deep-link here with a title.
  final String initialQuery;

  @override
  State<NovelSearchPage> createState() => _NovelSearchPageState();
}

class _NovelSearchPageState extends State<NovelSearchPage> {
  final _controller = TextEditingController();
  bool _allSources = false;
  bool _loading = false;
  bool _searched = false;
  String _lastQuery = '';
  String? _errorText;
  List<NovelItem> _results = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      _controller.text = widget.initialQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _errorText = null;
      _lastQuery = query;
    });
    try {
      final results = _allSources
          ? rankNovels(query, await NovelApi.searchAll(query))
          : await NovelApi.searchActive(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _searched = true;
        _errorText = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          // ── Glass search header (batch 39, Violet Glass),
          // same pattern as the manga search page.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 2),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: VioletGlassCard(
                      radius: 999,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                hintText: '搜索书名或作者',
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _search(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '搜索',
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('当前源')),
                    ButtonSegment(value: true, label: Text('全部源')),
                  ],
                  selected: {_allSources},
                  onSelectionChanged: (selection) {
                    setState(() => _allSources = selection.first);
                    if (_lastQuery.isNotEmpty) _search();
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _allSources
                        ? '共 ${NovelSources.all().length} 个源'
                        : '源：${NovelSources.all().isEmpty ? '—' : NovelSources.active().name}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_searched
                    ? const GeneralEmptyState(
                        icon: Icons.menu_book_outlined,
                        title: '输入关键词开始搜索',
                      )
                    : _errorText != null
                        ? NovelErrorState(
                            message: _errorText!,
                            onRetry: _search,
                          )
                        : _results.isEmpty
                            ? const GeneralEmptyState(
                                icon: Icons.search_off_rounded,
                                title: '没有找到相关的书',
                              )
                            : ListView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                                itemCount: _results.length,
                                itemBuilder: (context, index) =>
                                    NovelBookTile(item: _results[index]),
                              ),
          ),
        ],
      ),
    );
  }
}
