import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:liuguang_download/liuguang_download.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/liuguang/film_downloads.dart';
import 'package:anikumo/services/liuguang/film_playback_bridge.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';

/// Batch 207: 下载 — the engine download manager's tasks:
/// live progress, pause / resume / cancel, delete (file +
/// record hidden once gone), and offline playback of
/// finished downloads through the film player.
class FilmDownloadsPage extends StatefulWidget {
  const FilmDownloadsPage({super.key});

  @override
  State<FilmDownloadsPage> createState() => _FilmDownloadsPageState();
}

class _FilmDownloadsPageState extends State<FilmDownloadsPage> {
  DownloadManager? _manager;
  StreamSubscription<DownloadTask>? _sub;
  List<DownloadTask> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final manager = await VideoEngineService.instance.downloads();
    _manager = manager;
    _sub = manager.updates.listen((_) => _refresh());
    _refresh();
    if (mounted) setState(() => _loading = false);
  }

  bool _visible(DownloadTask task) {
    // Deleted tasks linger as canceled records in the
    // store; once their file is gone they leave the list.
    if (task.status == DownloadStatus.canceled &&
        !File(task.targetPath).existsSync()) {
      return false;
    }
    return true;
  }

  void _refresh() {
    final manager = _manager;
    if (manager == null || !mounted) return;
    setState(() => _tasks = manager.tasks.where(_visible).toList());
  }

  String _sizeText(DownloadTask task) {
    String fmt(int bytes) {
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
      if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
      }
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    }

    if (task.totalBytes > 0) {
      return '${fmt(task.downloadedBytes)} / ${fmt(task.totalBytes)}';
    }
    return '已下载 ${fmt(task.downloadedBytes)}';
  }

  String _statusText(DownloadTask task) {
    return switch (task.status) {
      DownloadStatus.queued => '排队中',
      DownloadStatus.downloading => '下载中',
      DownloadStatus.paused => '已暂停',
      DownloadStatus.completed => '已完成',
      DownloadStatus.failed =>
        '失败${task.error == null ? '' : '：${task.error}'}',
      DownloadStatus.canceled => '已取消',
    };
  }

  Future<void> _delete(DownloadTask task) async {
    final manager = _manager;
    if (manager == null) return;
    if (task.status != DownloadStatus.canceled) {
      await manager.cancel(task.id);
    }
    final file = File(task.targetPath);
    if (await file.exists()) await file.delete();
    final part = File('${task.targetPath}.part');
    if (await part.exists()) await part.delete();
    _refresh();
  }

  /// Batch 208: finished downloads play through the shared
  /// player page's offline mode, with every completed
  /// episode of the same title queued alongside.
  Future<void> _play(DownloadTask task) async {
    final ref = decodeFilmDownloadId(task.id);
    if (ref == null) return;
    final files = <({FilmDownloadRef ref, String filePath})>[];
    for (final t in _tasks) {
      if (t.status != DownloadStatus.completed) continue;
      final r = decodeFilmDownloadId(t.id);
      if (r == null || r.mediaId != ref.mediaId) continue;
      if (!File(t.targetPath).existsSync()) continue;
      files.add((ref: r, filePath: t.targetPath));
    }
    if (files.isEmpty) return;
    final service = VideoEngineService.instance;
    var pluginName = '影视';
    for (final e in service.sources) {
      if (ref.mediaId.startsWith('${e.id}::')) {
        pluginName = e.name;
        break;
      }
    }
    final args = buildFilmOfflineArgs(
      mediaId: ref.mediaId,
      title: ref.title,
      pluginName: pluginName,
      files: files,
      startLineIndex: ref.lineIndex,
      startEpisodeIndex: ref.episodeIndex,
    );
    if (!mounted) return;
    context.pushNamed('/video/', arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
          ? const FilmEmptyState(
              icon: AnikumoIcons.download_rounded,
              title: '还没有下载',
              message: '在影片详情页选集下载后，任务会出现在这里。',
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _tasks.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _tile(context, _tasks[i]),
            ),
    );
  }

  Widget _tile(BuildContext context, DownloadTask task) {
    final ref = decodeFilmDownloadId(task.id);
    final manager = _manager!;
    final active =
        task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.queued;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref == null ? task.id : '${ref.title} · ${ref.episodeTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_statusText(task)} · ${_sizeText(task)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: task.progress < 0 ? null : task.progress,
                ),
              ],
            ),
          ),
          if (task.status == DownloadStatus.completed)
            IconButton(
              tooltip: '离线播放',
              icon: const Icon(AnikumoIcons.play_circle_rounded),
              onPressed: () => _play(task),
            ),
          if (active)
            IconButton(
              tooltip: '暂停',
              icon: const Icon(AnikumoIcons.pause_rounded),
              onPressed: () => manager.pause(task.id),
            ),
          if (task.status == DownloadStatus.paused ||
              task.status == DownloadStatus.failed)
            IconButton(
              tooltip: '继续下载',
              icon: const Icon(AnikumoIcons.play_arrow_rounded),
              onPressed: () => manager.resume(task.id),
            ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(AnikumoIcons.delete_outline_rounded),
            onPressed: () => _delete(task),
          ),
        ],
      ),
    );
  }
}
