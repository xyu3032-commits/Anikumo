import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../bean/dialog/dialog.dart';
import '../../models/novel_item.dart';
import '../../services/novel/novel_downloads.dart';
import 'novel_widgets.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Downloaded novel chapters (batch 31, mirroring the manga
/// zone's download management): size summary, per-entry
/// delete, clear-all, and tap-to-read offline.
class NovelDownloadsPage extends StatefulWidget {
  const NovelDownloadsPage({super.key});

  @override
  State<NovelDownloadsPage> createState() => _NovelDownloadsPageState();
}

class _NovelDownloadsPageState extends State<NovelDownloadsPage> {
  List<NovelDownloadEntry> _entries = const [];
  int _sizeBytes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await NovelDownloadStore.loadIndex();
    final size = await NovelDownloadStore.totalSizeBytes();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _sizeBytes = size;
      _loading = false;
    });
  }

  String get _sizeLabel {
    final mb = _sizeBytes / (1024 * 1024);
    return mb >= 100
        ? '${mb.toStringAsFixed(0)} MB'
        : '${mb.toStringAsFixed(1)} MB';
  }

  void _openEntry(NovelDownloadEntry entry) {
    final item = NovelItem(
      bookUrl: entry.bookUrl,
      title: entry.bookTitle,
      coverUrl: entry.coverUrl,
      source: entry.source,
    );
    context.pushNamed(
      '/novel/reader',
      arguments: (
        item: item,
        chapters: [
          NovelChapter(title: entry.chapterTitle, url: entry.chapterUrl),
        ],
        chapterIndex: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(AnikumoIcons.delete_sweep_outlined),
              tooltip: '清空全部下载',
              onPressed: () async {
                await NovelDownloadStore.clearAll();
                await _load();
                if (context.mounted) {
                  AnikumoDialog.showToast(message: '已清空全部下载');
                }
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Text(
                    '还没有下载的章节\n在小说详情页点章节旁的下载按钮',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        '共 ${_entries.length} 章 · 占用 $_sizeLabel',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final entry in _entries)
                      ListTile(
                        leading: NovelCover(
                          url: entry.coverUrl,
                          width: 40,
                          height: 56,
                          radius: 6,
                        ),
                        title: Text(
                          '${entry.bookTitle} · ${entry.chapterTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${entry.blockCount} 段 · 离线可读'),
                        trailing: IconButton(
                          icon: const Icon(AnikumoIcons.delete_outline),
                          tooltip: '删除这一章',
                          onPressed: () async {
                            await NovelDownloadStore.remove(entry);
                            await _load();
                          },
                        ),
                        onTap: () => _openEntry(entry),
                      ),
                  ],
                ),
    );
  }
}
