import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/novel/novel_api.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/novel/novel_title_import.dart';

/// Batch 280 (#13): title-list import for the favorites
/// tab — the film zone's 片单导入 flow (batch 272) on
/// novel seams, mirroring the manga zone's batch-279
/// version. One dialog walks three steps: paste a list
/// (or pick a .txt/.json file), watch the per-title
/// searches run against the enabled sources, then tick
/// the matches to add. At most 30 titles are processed;
/// anything beyond the cap counts as not imported.
Future<void> runNovelTitleImport(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await showDialog<({int added, int notFound})>(
    context: context,
    builder: (_) => const _NovelTitleImportDialog(),
  );
  if (result == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        S.f('导入完成：成功 {} 本，未找到 {} 本', [result.added, result.notFound]),
      ),
    ),
  );
}

class _ImportCandidate {
  _ImportCandidate({required this.title, required this.match});

  final String title;
  final NovelItem? match;
  bool selected = true;
}

class _NovelTitleImportDialog extends StatefulWidget {
  const _NovelTitleImportDialog();

  @override
  State<_NovelTitleImportDialog> createState() =>
      _NovelTitleImportDialogState();
}

class _NovelTitleImportDialogState extends State<_NovelTitleImportDialog> {
  final TextEditingController _textController = TextEditingController();
  int _step = 0; // 0 paste, 1 searching, 2 confirm.
  String _currentTitle = '';
  int _overflow = 0;
  List<_ImportCandidate> _candidates = const [];

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'json'],
      withData: true,
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;
    _textController.text = utf8.decode(file!.bytes!, allowMalformed: true);
    if (mounted) setState(() {});
  }

  Future<List<NovelItem>> _searchAllSources(String title) async {
    var results = await NovelApi.searchCross(title);
    if (results.isEmpty) {
      // The cross-search trio came back dry — widen to
      // every remaining installed source before giving up
      // on the title (the search page's 「更多搜索」 move).
      final trio = {for (final s in NovelApi.crossSearchSources()) s.id};
      results = await NovelApi.searchCrossRest(title, excludeIds: trio);
    }
    return results;
  }

  Future<void> _startSearch() async {
    final titles = parseNovelTitleList(_textController.text);
    if (titles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('清单里没有可导入的标题'))),
      );
      return;
    }
    final capped = titles.take(30).toList();
    _overflow = titles.length - capped.length;
    setState(() => _step = 1);
    final candidates = <_ImportCandidate>[];
    for (final title in capped) {
      if (!mounted) return;
      setState(() => _currentTitle = title);
      NovelItem? match;
      try {
        match = pickNovelImportMatch(await _searchAllSources(title), title);
      } catch (_) {
        match = null; // One bad title never sinks the list.
      }
      candidates.add(_ImportCandidate(title: title, match: match));
    }
    if (!mounted) return;
    setState(() {
      _candidates = candidates;
      _step = 2;
    });
  }

  Future<void> _confirm() async {
    final picks = <NovelItem>[];
    for (final candidate in _candidates) {
      final match = candidate.match;
      if (match == null || !candidate.selected) continue;
      picks.add(match);
    }
    final added = await NovelLibraryStore.addFavorites(picks);
    final notFound = _overflow +
        _candidates.where((c) => c.match == null).length +
        (picks.length - added);
    if (!mounted) return;
    Navigator.of(context).pop((added: added, notFound: notFound));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t('导入小说清单')),
      content: switch (_step) {
        1 => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(S.t('正在搜索标题…')),
              if (_currentTitle.isNotEmpty)
                Text(
                  _currentTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        2 => _confirmContent(),
        _ => _pasteContent(),
      },
      actions: switch (_step) {
        1 => const [],
        2 => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.t('取消')),
            ),
            FilledButton(
              onPressed: _confirm,
              child: Text(
                S.f('确认导入 {} 本', [
                  _candidates
                      .where((c) => c.match != null && c.selected)
                      .length,
                ]),
              ),
            ),
          ],
        _ => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.t('取消')),
            ),
            TextButton(
              onPressed: _pickFile,
              child: Text(S.t('从文件选择')),
            ),
            FilledButton(
              onPressed: _startSearch,
              child: Text(S.t('开始导入')),
            ),
          ],
      },
    );
  }

  Widget _pasteContent() {
    return SizedBox(
      width: 420,
      child: TextField(
        controller: _textController,
        maxLines: 10,
        minLines: 5,
        decoration: InputDecoration(
          hintText: S.t('粘贴标题清单，一行一个标题（最多 30 条）'),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _confirmContent() {
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.t('选择要导入的小说')),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _candidates.length,
              itemBuilder: (context, index) {
                final candidate = _candidates[index];
                final match = candidate.match;
                if (match == null) {
                  return ListTile(
                    dense: true,
                    title: Text(candidate.title),
                    subtitle: Text(S.t('未找到')),
                    enabled: false,
                  );
                }
                final already = NovelLibraryStore.isFavorite(match);
                final sourceLabel = match.sourceName.isNotEmpty
                    ? match.sourceName
                    : match.source;
                return CheckboxListTile(
                  dense: true,
                  value: candidate.selected && !already,
                  onChanged: already
                      ? null
                      : (value) => setState(
                            () => candidate.selected = value ?? false,
                          ),
                  title: Text(
                    match.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    already
                        ? S.t('已在收藏中')
                        : '$sourceLabel · ${candidate.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
