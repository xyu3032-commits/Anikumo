import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/modules/download/download_module.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/pages/download/download_controller.dart';
import 'package:anikumo/pages/download/download_widgets.dart';
import 'package:anikumo/pages/video/video_playback_args.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/utils/format.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/download/download_gate.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/network/metered_network_service.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({
    super.key,
    required this.controller,
  });

  final DownloadController controller;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  DownloadController get downloadController => widget.controller;

  // Keep expansion state across controller snapshot replacements.
  final Map<String, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    downloadController.refreshRecords();
  }

  bool _isExpanded(String recordKey, DownloadRecord record) {
    return _expanded.putIfAbsent(
      recordKey,
      () => record.episodes.values
          .any((e) => e.status != DownloadStatus.completed),
    );
  }

  /// Batch 282 (#25): shown while the Wi-Fi-only gate
  /// holds queued episodes on a metered network.
  Widget _wifiGateBanner(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            AnikumoIcons.network_ping_rounded,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              S.t('仅 Wi-Fi 下载已开启：当前是移动网络，排队中的下载将在 Wi-Fi 下继续'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(title: Text(S.t('下载管理'))),
      body: ValueListenableBuilder<bool>(
        valueListenable: MeteredNetworkService.listenable,
        builder: (context, _, _) => Observer(builder: (context) {
          final recordKeys = downloadController.recordKeys.toList();
          _expanded.removeWhere((key, _) => !recordKeys.contains(key));
          if (recordKeys.isEmpty) {
            return GeneralEmptyState(
              icon: AnikumoIcons.download_rounded,
              title: S.t('还没有下载记录'),
            );
          }
          final hasPending = recordKeys.any((key) =>
              downloadController
                  .getRecordSnapshot(key)
                  ?.episodes
                  .values
                  .any((e) => e.status == DownloadStatus.pending) ??
              false);
          final list = ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: recordKeys.length,
            itemBuilder: (context, index) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: _buildRecordCard(recordKeys[index]),
                ),
              );
            },
          );
          if (hasPending && DownloadGate.blockedNow()) {
            return Column(
              children: [
                _wifiGateBanner(context),
                Expanded(child: list),
              ],
            );
          }
          return list;
        }),
      ),
    );
  }

  Widget _buildRecordCard(String recordKey) {
    return Observer(builder: (context) {
      final record = downloadController.getRecordSnapshot(recordKey);
      if (record == null) {
        return const SizedBox.shrink();
      }

      var totalSpeed = 0.0;
      for (final e in record.episodes.values) {
        if (e.status == DownloadStatus.downloading) {
          totalSpeed += downloadController.getSpeed(
            record.bangumiId,
            record.pluginName,
            e.episodeNumber,
          );
        }
      }
      final expanded = _isExpanded(recordKey, record);

      return DownloadRecordCard(
        record: record,
        expanded: expanded,
        onToggle: () {
          setState(() => _expanded[recordKey] = !expanded);
        },
        onResumeAll: () {
          downloadController.resumeAllDownloads(
            record.bangumiId,
            record.pluginName,
          );
          AnikumoDialog.showToast(message: S.t('已开始恢复下载'));
        },
        onDeleteAll: () => _confirmDeleteRecord(record),
        totalSpeed: totalSpeed,
        episodeTileBuilder: () {
          final episodes = record.episodes.values.toList()
            ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
          return episodes.map((ep) => _buildEpisodeTile(record, ep)).toList();
        },
      );
    });
  }

  Widget _buildEpisodeTile(DownloadRecord record, DownloadEpisode episode) {
    return DownloadEpisodeTile(
      episode: episode,
      statusText: _getStatusText(record, episode),
      actions: _getActionButtons(record, episode),
      onPlay: episode.status == DownloadStatus.completed
          ? () => _playEpisode(record, episode)
          : null,
    );
  }

  String _getStatusText(DownloadRecord record, DownloadEpisode episode) {
    switch (episode.status) {
      case DownloadStatus.completed:
        return S.f('已完成 · {}', [formatBytes(episode.totalBytes)]);
      case DownloadStatus.downloading:
        final speed = downloadController.getSpeed(
          record.bangumiId,
          record.pluginName,
          episode.episodeNumber,
        );
        final speedText = speed > 0 ? ' · ${formatSpeed(speed)}' : '';
        return S.f('{}% · {}/{} 分片{}', [
          (episode.progressPercent * 100).toStringAsFixed(0),
          episode.downloadedSegments,
          episode.totalSegments,
          speedText,
        ]);
      case DownloadStatus.failed:
        return episode.errorMessage.isNotEmpty ? episode.errorMessage : S.t('下载失败');
      case DownloadStatus.paused:
        return S.f('已暂停 · {}%', [(episode.progressPercent * 100).toStringAsFixed(0)]);
      case DownloadStatus.pending:
        return S.t('排队中');
      case DownloadStatus.resolving:
        return S.t('正在解析视频源');
      default:
        return '';
    }
  }

  List<Widget> _getActionButtons(
      DownloadRecord record, DownloadEpisode episode) {
    final colorScheme = Theme.of(context).colorScheme;
    final buttons = <Widget>[];

    switch (episode.status) {
      case DownloadStatus.completed:
        buttons.add(IconButton(
          icon: Icon(AnikumoIcons.play_circle_outline,
              size: 20, color: colorScheme.primary),
          onPressed: () => _playEpisode(record, episode),
          tooltip: S.t('播放'),
          visualDensity: VisualDensity.compact,
        ));
        break;
      case DownloadStatus.downloading:
        buttons.add(IconButton(
          icon: const Icon(AnikumoIcons.pause_rounded, size: 20),
          onPressed: () => downloadController.pauseDownload(
            record.bangumiId,
            record.pluginName,
            episode.episodeNumber,
          ),
          tooltip: S.t('暂停'),
          visualDensity: VisualDensity.compact,
        ));
        break;
      case DownloadStatus.paused:
        buttons.add(IconButton(
          icon: const Icon(AnikumoIcons.play_arrow_rounded, size: 20),
          onPressed: () => downloadController.retryDownload(
            bangumiId: record.bangumiId,
            pluginName: record.pluginName,
            episodeNumber: episode.episodeNumber,
          ),
          tooltip: S.t('继续'),
          visualDensity: VisualDensity.compact,
        ));
        break;
      case DownloadStatus.failed:
        buttons.add(IconButton(
          icon: const Icon(AnikumoIcons.refresh_rounded, size: 20),
          onPressed: () => downloadController.retryDownload(
            bangumiId: record.bangumiId,
            pluginName: record.pluginName,
            episodeNumber: episode.episodeNumber,
          ),
          tooltip: S.t('重试'),
          visualDensity: VisualDensity.compact,
        ));
        break;
      case DownloadStatus.pending:
        buttons.add(IconButton(
          icon: Icon(AnikumoIcons.priority_high, size: 20, color: colorScheme.primary),
          onPressed: () {
            downloadController.priorityDownload(
              bangumiId: record.bangumiId,
              pluginName: record.pluginName,
              episodeNumber: episode.episodeNumber,
            );
            AnikumoDialog.showToast(message: S.t('已插队优先下载'));
          },
          tooltip: S.t('优先下载'),
          visualDensity: VisualDensity.compact,
        ));
        break;
      default:
        break;
    }

    buttons.add(IconButton(
      icon: Icon(AnikumoIcons.delete_outline,
          size: 20, color: colorScheme.onSurfaceVariant),
      onPressed: () => _confirmDeleteEpisode(record, episode),
      tooltip: S.t('删除'),
      visualDensity: VisualDensity.compact,
    ));

    return buttons;
  }

  void _playEpisode(DownloadRecord record, DownloadEpisode episode) {
    final localPath = downloadController.getLocalVideoPath(
      record.bangumiId,
      record.pluginName,
      episode.episodeNumber,
    );
    if (localPath == null) {
      AnikumoDialog.showToast(message: S.t('本地文件不存在'));
      return;
    }

    final bangumiItem = BangumiItem(
      id: record.bangumiId,
      type: 2,
      name: record.bangumiName,
      nameCn: record.bangumiName,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {'large': record.bangumiCover},
      tags: [],
      alias: [],
      ratingScore: 0.0,
      votes: 0,
      votesCount: [],
      info: '',
    );

    final downloadedEpisodes = downloadController.getCompletedEpisodes(
      record.bangumiId,
      record.pluginName,
    );

    context.pushNamed(
      '/video/',
      arguments: OfflineVideoPlaybackArgs(
        bangumiItem: bangumiItem,
        pluginName: record.pluginName,
        episodeNumber: episode.episodeNumber,
        road: episode.road,
        downloadedEpisodes: downloadedEpisodes,
      ),
    );
  }

  void _confirmDeleteEpisode(DownloadRecord record, DownloadEpisode episode) {
    AnikumoDialog.show(
      builder: (context) => AlertDialog(
        title: Text(S.t('删除下载')),
        content: Text(S.f('确定要删除「{}」的下载文件吗？', [
          episode.episodeName.isNotEmpty
              ? episode.episodeName
              : S.f('第{}集', [episode.episodeNumber])
        ])),
        actions: [
          TextButton(
            onPressed: () => AnikumoDialog.dismiss(),
            child: Text(
              S.t('取消'),
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () async {
              AnikumoDialog.dismiss();
              await _deleteDownload(
                () => downloadController.deleteEpisode(
                  record.bangumiId,
                  record.pluginName,
                  episode.episodeNumber,
                ),
              );
            },
            child: Text(
              S.t('删除'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteRecord(DownloadRecord record) {
    AnikumoDialog.show(
      builder: (context) => AlertDialog(
        title: Text(S.t('删除全部下载')),
        content: Text(S.f('确定要删除「{}」的所有下载文件吗？', [record.bangumiName])),
        actions: [
          TextButton(
            onPressed: () => AnikumoDialog.dismiss(),
            child: Text(
              S.t('取消'),
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () async {
              AnikumoDialog.dismiss();
              await _deleteDownload(
                () => downloadController.deleteRecord(
                  record.bangumiId,
                  record.pluginName,
                ),
              );
            },
            child: Text(
              S.t('删除'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDownload(Future<void> Function() delete) async {
    try {
      await delete();
    } catch (e) {
      AnikumoLogger().w('DownloadPage: failed to delete download', error: e);
      if (!mounted) return;
      AnikumoDialog.show(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(S.t('删除失败')),
          content: Text(S.t('删除下载文件失败，请稍后重试')),
          actions: [
            TextButton(
              onPressed: () => AnikumoDialog.dismiss(context: context),
              child: Text(S.t('确定')),
            ),
          ],
        ),
      );
    }
  }
}
