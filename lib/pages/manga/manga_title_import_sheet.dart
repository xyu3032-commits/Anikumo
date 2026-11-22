import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/manga/manga_api.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/manga/manga_title_import.dart';

/// Batch 279 (#11): title-list import for the favorites
/// tab — the film zone's 片单导入 flow (batch 272) on
/// manga seams. One dialog walks three steps: paste a
/// list (or pick a .txt/.json file), watch the per-title
/// searches run against the enabled sources, then tick
/// the matches to add. At most 30 titles are processed;
/// anything beyond the cap counts as not imported.
Future<void> runMangaTitleImport(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await showDialog<({int added, int notFound})>(
    context: context,
    builder: (_) => const _MangaTitleImportDialog(),
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
  final MangaItem? match;
  bool selected = true;
}

class _MangaTitleImportDialog extends StatefulWidget {
  const _MangaTitleImportDialog();

  @override
  State<_MangaTitleImportDialog> createState() =>
      _MangaTitleImportDialogState();
}

class _MangaTitleImportDialogState extends State<_MangaTitleImportDialog> {
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

  Future<List<MangaItem>> _searchAllSources(String title) async {
    var results = await MangaApi.searchMangaMulti(title);
    if (results.isEmpty) {
      // The cross-search trio came back dry — widen to
      // every remaining installed source before giving up
      // on the title (the search page's 「更多搜索」 move).
      final trio = {for (final s in MangaApi.crossSearchSources()) s.id};
      results = await MangaApi.searchMangaRest(title, excludeIds: trio);
    }
    return results;
  }

  Future<void> _startSearch() async {
    final titles = parseMangaTitleList(_textController.text);
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
      MangaItem? match;
      try {
        match = pickMangaImportMatch(await _searchAllSources(title), title);
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
    final favorites = <MangaFavorite>[];
    for (final candidate in _candidates) {
      final match = candidate.match;
      if (match == null || !candidate.selected) continue;
      favorites.add(
        MangaFavorite(
          id: match.id,
          title: match.title,
          coverUrl: match.coverUrl,
          source: match.source,
        ),
      );
    }
    final added = await MangaLibraryStore.addFavorites(favorites);
    final notFound = _overflow +
        _candidates.where((c) => c.match == null).length +
        (favorites.length - added);
    if (!mounted) return;
    Navigator.of(context).pop((added: added, notFound: notFound));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t('导入漫画清单')),
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
          Text(S.t('选择要导入的漫画')),
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
                final already = MangaLibraryStore.isFavorite(
                  match.source,
                  match.id,
                );
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
                        : '${match.source} · ${candidate.title}',
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
