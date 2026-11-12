import 'dart:typed_data';
import 'dart:io';
import 'package:anikumo/utils/tap_debouncer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/widget/motion_kit.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/services/manga/manga_cbz_export.dart';
import 'package:anikumo/services/manga/manga_features.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_extras.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Downloaded chapters (batch 15, M1): list, open, delete.
class MangaDownloadsPage extends StatefulWidget {
  const MangaDownloadsPage({super.key});

  @override
  State<MangaDownloadsPage> createState() => _MangaDownloadsPageState();
}

class _MangaDownloadsPageState extends State<MangaDownloadsPage> {
  List<MangaDownloadEntry> _entries = const [];
  int _sizeBytes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await MangaDownloadStore.loadIndex();
    final size = await MangaDownloadStore.totalSizeBytes();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _sizeBytes = size;
      _loading = false;
    });
  }

  String get _sizeLabel {
    final mb = _sizeBytes / (1024 * 1024);
    return mb >= 100 ? '${mb.toStringAsFixed(0)} MB' : '${mb.toStringAsFixed(1)} MB';
  }

  /// Batch 234 （章节导出 pack): pack one downloaded
  /// chapter into a CBZ and let the user save it.
  Future<void> _exportEntry(MangaDownloadEntry entry) async {
    final pages = await MangaDownloadStore.localPages(
      entry.source,
      entry.mangaId,
      entry.chapterId,
    );
    if (pages == null || pages.isEmpty) {
      if (mounted) {
        AnikumoDialog.showToast(message: '这一话的本地文件不完整，无法导出');
      }
      return;
    }
    final bytesList = <Uint8List>[];
    for (final page in pages) {
      final path = Uri.parse(page.url).toFilePath();
      bytesList.add(await File(path).readAsBytes());
    }
    final cbz = buildCbzBytes(bytesList);
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: '保存 CBZ',
      fileName: cbzFileName(entry.mangaTitle, entry.chapterLabel),
      bytes: cbz,
    );
    if (mounted && saved != null) {
      AnikumoDialog.showToast(message: '已导出 ${bytesList.length} 页');
    }
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
                await MangaDownloadStore.clearAll();
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
              ? const Center(child: Text('还没有下载的章节\n在漫画详情页点章节旁的下载按钮', textAlign: TextAlign.center))
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        '共 ${_entries.length} 话 · 占用 $_sizeLabel',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (var i = 0; i < _entries.length; i++)
                      SlideInX(
                        delay: Duration(milliseconds: i * 40),
                        child: ListTile(
                        leading: MangaCover(
                          url: _entries[i].coverUrl,
                          width: 40,
                          height: 56,
                        ),
                        title: Text(
                          '${_entries[i].mangaTitle} · ${_entries[i].chapterLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_entries[i].pageCount} 页 · ${_entries[i].source}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Batch 234 （章节导出 pack).
                            if (MangaFeatures.isInstalled(
                                MangaFeatures.cbzExportId))
                              IconButton(
                                icon: const Icon(
                                    AnikumoIcons.folder_zip_outlined),
                                tooltip: '导出 CBZ',
                                onPressed: () => _exportEntry(_entries[i]),
                              ),
                            IconButton(
                              icon: const Icon(AnikumoIcons.delete_outline),
                              tooltip: '删除这一话',
                              onPressed: () async {
                                await MangaDownloadStore.deleteEntry(
                                    _entries[i]);
                                await _load();
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          if (TapDebouncer.accept(
                              'manga:${_entries[i].source}:${_entries[i].mangaId}')) {
                            context.pushNamed(
                              '/manga/detail',
                              arguments: MangaItem(
                                id: _entries[i].mangaId,
                                title: _entries[i].mangaTitle,
                                description: '',
                                coverUrl: _entries[i].coverUrl,
                                author: '',
                                status: '',
                                year: null,
                                tags: const [],
                                source: _entries[i].source,
                              ),
                            );
                          }
                        },
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// Reading statistics (batch 15, M6).
class MangaStatsPage extends StatelessWidget {
  const MangaStatsPage({super.key});

  String _duration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '$hours 小时 $minutes 分';
    if (minutes > 0) return '$minutes 分钟';
    return '$seconds 秒';
  }

  @override
  Widget build(BuildContext context) {
    final stats = MangaStatsStore.load();
    final now = DateTime.now();
    final numberStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );
    Widget textRow(String label, String value) => ListTile(
          title: Text(label),
          trailing: Text(value, style: numberStyle),
        );
    Widget countRow(String label, int value, String unit) => ListTile(
          title: Text(label),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountUpNumber(value: value, style: numberStyle),
              Text(unit, style: numberStyle),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('阅读数据')),
      body: ListView(
        children: [
          textRow('累计阅读时长', _duration(stats.secondsRead)),
          textRow('今日阅读', _duration(stats.secondsOn(now))),
          textRow('近 7 天阅读', _duration(stats.secondsInLastWeek(now))),
          countRow('读完话数', stats.chaptersFinished, ' 话'),
          countRow('翻页总数', stats.pagesRead, ' 页'),
        ],
      ),
    );
  }
}
