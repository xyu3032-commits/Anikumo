import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/services/backup/local_backup.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// 本地备份/恢复 (hub 区三）: export the user's own data to one JSON
/// file, or merge a previously exported file back in. Complements —
/// does not replace — the WebDAV sync: no account, no server.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  // Batch 83: the manga download index lives in a file, so
  // its count loads asynchronously.
  int? _mangaDownloadCount;

  @override
  void initState() {
    super.initState();
    MangaDownloadStore.loadIndex().then((entries) {
      if (mounted) setState(() => _mangaDownloadCount = entries.length);
    });
  }

  String get _fileName {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'anikumo-backup-$stamp.json';
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final bytes = utf8.encode(await LocalBackup.exportJson());
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存备份文件',
        fileName: _fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (!mounted) return;
      AnikumoDialog.showToast(
        context: context,
        message: path == null ? '已取消导出' : '备份已保存',
      );
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: '导出失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FileSystemException('无法读取所选文件');
      if (!mounted) return;
      final data = LocalBackup.parse(utf8.decode(bytes));
      if (data == null) {
        AnikumoDialog.showToast(
          context: context,
          message: '这不是有效的 anikumo 备份文件',
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('恢复这份备份？'),
          content: Text(
            '将合并：观看历史 ${data.histories.length} 条 · '
            '追番 ${data.collectibles.length} 部 · '
            '搜索记录 ${data.searchHistories.length} 条 · '
            '榜单 ${data.userLists.length} 个 · '
            '笔记 ${data.notes.length} 条 · '
            '漫画收藏 ${data.mangaFavorites.length} 部 · '
            '漫画进度 ${data.mangaProgress.length} 条 · '
            '小说收藏 ${data.novelFavorites.length} 部 · '
            '小说进度 ${data.novelProgress.length} 条 · '
            '下载记录 ${data.mangaDownloads.length + data.animeDownloads.length} 条。\n\n'
            '恢复只会覆盖同名记录，不会删除现有数据。'
            '下载只恢复记录：文件已不在本机的记录会被跳过。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final report = await LocalBackup.apply(data);
      if (!mounted) return;
      AnikumoDialog.showToast(
        context: context,
        message: report.downloadsSkipped > 0
            ? '恢复完成；${report.downloadsSkipped} 条下载记录因文件不在本机已跳过'
            : '恢复完成',
      );
      setState(() {});
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: '导入失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = <(IconData, String, String)>[
      (AnikumoIcons.history_rounded, '${GStorage.histories.length}', '观看历史'),
      (AnikumoIcons.favorite_rounded, '${GStorage.collectibles.length}', '追番收藏'),
      (
        AnikumoIcons.manage_search_rounded,
        '${GStorage.searchHistory.length}',
        '搜索记录',
      ),
      (AnikumoIcons.list_alt_rounded, '${UserListsStore.load().length}', '自建榜单'),
      (AnikumoIcons.sticky_note_2_outlined, '${BangumiNotesStore.load().length}', '番剧笔记'),
      (
        AnikumoIcons.menu_book_rounded,
        '${MangaLibraryStore.loadFavorites().length}',
        '漫画收藏',
      ),
      (
        AnikumoIcons.bookmark_rounded,
        '${MangaLibraryStore.loadProgressList().length}',
        '漫画进度',
      ),
      (
        AnikumoIcons.library_books_rounded,
        '${NovelLibraryStore.loadFavorites().length}',
        '小说收藏',
      ),
      (
        AnikumoIcons.auto_stories_rounded,
        '${NovelLibraryStore.loadProgressList().length}',
        '小说进度',
      ),
      (AnikumoIcons.download_rounded, '${GStorage.downloads.length}', '动漫下载'),
      (
        AnikumoIcons.download_for_offline_rounded,
        _mangaDownloadCount?.toString() ?? '—',
        '漫画下载',
      ),
    ];
    return Scaffold(
      appBar: const SysAppBar(title: Text('本地备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(StyleString.pagePadding),
        children: [
          GlassSurface(
            padding: const EdgeInsets.all(StyleString.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前设备上的数据',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                for (final (icon, value, label) in counts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(icon, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(label)),
                        Text(
                          value,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: StyleString.sectionSpace),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(AnikumoIcons.upload_file_outlined),
            label: const Text('导出备份文件'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(AnikumoIcons.file_download_outlined),
            label: const Text('从文件恢复'),
          ),
          const SizedBox(height: StyleString.sectionSpace),
          Text(
            '备份文件包含你的观看历史、三区收藏与进度、榜单、笔记、已装内容源和下载记录，'
            '请像对待其他私人文件一样保管。下载的视频与漫画图片文件本身不在备份内，'
            '恢复时文件还在本机的下载会一并复活。'
            '换手机或重装前先导出一份，装好后在这里恢复即可。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
