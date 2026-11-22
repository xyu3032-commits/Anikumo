import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/subtitle/online_subtitle_service.dart';

/// Batch 278: the online subtitle search sheet.
///
/// Searches by the playing work's name + episode (both
/// editable before searching), lists hits with their
/// language / format / download count, and on tap
/// downloads + stages the file, popping with its path
/// so the subtitle sheet can mount it through the
/// player's normal external-subtitle path. All failures
/// stay inside the sheet as inline text or a toast —
/// nothing here can break playback.
Future<String?> showOnlineSubtitleSheet(
  BuildContext context, {
  required String initialQuery,
  required int episode,
}) async {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _OnlineSubtitleSheet(
      initialQuery: initialQuery,
      episode: episode,
    ),
  );
}

class _OnlineSubtitleSheet extends StatefulWidget {
  const _OnlineSubtitleSheet({
    required this.initialQuery,
    required this.episode,
  });

  final String initialQuery;
  final int episode;

  @override
  State<_OnlineSubtitleSheet> createState() => _OnlineSubtitleSheetState();
}

class _OnlineSubtitleSheetState extends State<_OnlineSubtitleSheet> {
  late final TextEditingController _queryController =
      TextEditingController(text: widget.initialQuery);
  List<OnlineSubtitleResult> _results = const [];
  bool _searching = false;
  bool _searched = false;
  String? _error;
  int? _downloadingFileId;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await OnlineSubtitleService.search(
        query: query,
        episode: widget.episode > 0 ? widget.episode : null,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (e) {
      AnikumoLogger().w('OnlineSubtitle: search failed', error: e);
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searched = true;
        _error = S.t('搜索失败，请检查网络后重试');
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _download(OnlineSubtitleResult result) async {
    if (_downloadingFileId != null) return;
    setState(() => _downloadingFileId = result.fileId);
    try {
      final dir = await getTemporaryDirectory();
      final file = await OnlineSubtitleService.download(result, dir: dir);
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (e) {
      AnikumoLogger().w('OnlineSubtitle: download failed', error: e);
      if (!mounted) return;
      AnikumoDialog.showToast(message: S.t('字幕下载失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _downloadingFileId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.t('在线字幕'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: InputDecoration(
                      hintText: S.t('输入作品名搜索字幕'),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _searching ? null : _search,
                  child: Text(S.t('搜索')),
                ),
              ],
            ),
            if (widget.episode > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  S.f('按第 {} 集搜索', [widget.episode]),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            const SizedBox(height: 8),
            if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_error!),
              )
            else if (_searched && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  S.t('没有找到字幕，换个关键词试试'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final result in _results)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.subtitles_outlined),
                        title: Text(
                          result.release.isNotEmpty
                              ? result.release
                              : result.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (result.language.isNotEmpty) result.language,
                            result.effectiveFormat,
                            S.f('下载 {} 次', [result.downloadCount]),
                          ].join(' · '),
                        ),
                        trailing: _downloadingFileId == result.fileId
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_outlined),
                        onTap: () => _download(result),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
