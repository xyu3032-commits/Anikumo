import 'dart:io';

import 'package:flutter/material.dart';

import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/settings/settings_dropdown_tile.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/services/download/download_directory_service.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/file_system.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  final _directoryService = DownloadDirectoryService();
  late int parallelEpisodes;
  late int parallelSegments;
  late bool downloadDanmaku;
  late bool wifiOnlyDownloads;
  late int rateLimitKbps;
  String downloadDirectory = '';
  String defaultDownloadDirectory = '';
  bool isSelectingDirectory = false;

  @override
  void initState() {
    super.initState();
    parallelEpisodes =
        GStorage.getSetting(SettingsKeys.downloadParallelEpisodes);
    parallelSegments =
        GStorage.getSetting(SettingsKeys.downloadParallelSegments);
    downloadDanmaku = GStorage.getSetting(SettingsKeys.downloadDanmaku);
    wifiOnlyDownloads = GStorage.getSetting(SettingsKeys.wifiOnlyDownloads);
    rateLimitKbps = GStorage.getSetting(SettingsKeys.downloadRateLimitKbps);
    downloadDirectory = _directoryService.customDirectory;
    _loadDefaultDownloadDirectory();
  }

  bool get _hasCustomDirectory => downloadDirectory.isNotEmpty;

  String get _effectiveDownloadDirectory =>
      _hasCustomDirectory ? downloadDirectory : defaultDownloadDirectory;

  Future<void> _loadDefaultDownloadDirectory() async {
    final directory = await getDefaultDownloadDirectory();
    if (!mounted) return;
    setState(() {
      defaultDownloadDirectory = directory;
    });
  }

  Future<void> _selectDownloadDirectory() async {
    if (isSelectingDirectory) return;

    setState(() => isSelectingDirectory = true);
    try {
      final selectedPath = await _directoryService.selectDirectory();
      if (selectedPath == null) return;
      if (mounted) {
        setState(() => downloadDirectory = selectedPath);
      }
      AnikumoDialog.showToast(message: S.t('下载位置已更新，仅对新下载生效'));
    } on DownloadDirectoryException catch (e) {
      AnikumoDialog.showToast(message: e.message);
    } on FileSystemException catch (e) {
      AnikumoDialog.showToast(message: S.f('无法写入该目录: {}', [e.message]));
    } catch (e) {
      AnikumoDialog.showToast(message: S.f('选择下载位置失败: {}', [e]));
    } finally {
      if (mounted) {
        setState(() => isSelectingDirectory = false);
      }
    }
  }

  Future<void> _resetDownloadDirectory() async {
    await _directoryService.resetDirectory();
    if (mounted) {
      setState(() => downloadDirectory = '');
    }
    AnikumoDialog.showToast(message: S.t('已恢复默认下载位置，仅对新下载生效'));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: Text(S.t('下载设置')),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text(S.t('并发设置')),
            tiles: [
              SettingsSliderTile(
                leading: AnikumoIcons.video_library_rounded,
                title: Text(S.t('同时下载集数')),
                description: Text(S.t('并行下载的剧集数量')),
                value: parallelEpisodes.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                valueLabel: S.f('{} 集', [parallelEpisodes]),
                onChanged: (value) {
                  setState(() => parallelEpisodes = value.toInt());
                  GStorage.putSetting(
                    SettingsKeys.downloadParallelEpisodes,
                    parallelEpisodes,
                  );
                },
              ),
              SettingsSliderTile(
                leading: AnikumoIcons.call_split_rounded,
                title: Text(S.t('分片并发数')),
                description: Text(S.t('每集同时下载的分片数量')),
                value: parallelSegments.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                valueLabel: S.f('{} 个', [parallelSegments]),
                onChanged: (value) {
                  setState(() => parallelSegments = value.toInt());
                  GStorage.putSetting(
                    SettingsKeys.downloadParallelSegments,
                    parallelSegments,
                  );
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text(S.t('缓存设置')),
            tiles: [
              SettingsTile(
                leading: AnikumoIcons.folder_rounded,
                title: Text(S.t('下载位置')),
                description: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _effectiveDownloadDirectory.isEmpty
                          ? S.t('正在读取默认位置...')
                          : _effectiveDownloadDirectory,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hasCustomDirectory
                          ? S.t('当前使用自定义下载位置，修改后仅对新下载生效')
                          : S.t('当前使用默认下载位置，修改后仅对新下载生效'),
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
                trailing: isSelectingDirectory
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: LoadingIndicator(),
                      )
                    : _hasCustomDirectory
                        ? IconButton(
                            tooltip: S.t('恢复默认'),
                            icon: const Icon(AnikumoIcons.restore_rounded),
                            onPressed: _resetDownloadDirectory,
                          )
                        : null,
                onPressed: (_) => _selectDownloadDirectory(),
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.subtitles_rounded,
                onToggle: (value) {
                  setState(() => downloadDanmaku = value ?? !downloadDanmaku);
                  GStorage.putSetting(
                      SettingsKeys.downloadDanmaku, downloadDanmaku);
                },
                title: Text(S.t('缓存弹幕')),
                description: Text(
                  S.t('下载视频时同时缓存弹幕数据'),
                ),
                initialValue: downloadDanmaku,
              ),
            ],
          ),
          SettingsSection(
            title: Text(S.t('网络')),
            tiles: [
              SettingsTile.switchTile(
                leading: AnikumoIcons.network_ping_rounded,
                onToggle: (value) {
                  setState(
                      () => wifiOnlyDownloads = value ?? !wifiOnlyDownloads);
                  GStorage.putSetting(
                      SettingsKeys.wifiOnlyDownloads, wifiOnlyDownloads);
                },
                title: Text(S.t('仅在 Wi-Fi 下下载')),
                description: Text(
                  S.t('开启后，移动网络下不启动新的动漫/漫画下载与自动同步，已排队的任务等到 Wi-Fi 时继续'),
                ),
                initialValue: wifiOnlyDownloads,
              ),
              SettingsDropdownTile<int>(
                leading: AnikumoIcons.speed_rounded,
                title: Text(S.t('下载限速')),
                description: Text(S.t('动漫与漫画下载共用一个总限速，只作用于下载，不影响在线播放')),
                value: rateLimitKbps,
                options: {
                  0: S.t('不限速'),
                  256: '256 KB/s',
                  512: '512 KB/s',
                  1024: '1 MB/s',
                  2048: '2 MB/s',
                  5120: '5 MB/s',
                },
                fallbackLabel: S.t('不限速'),
                onChanged: (value) {
                  setState(() => rateLimitKbps = value);
                  GStorage.putSetting(
                      SettingsKeys.downloadRateLimitKbps, rateLimitKbps);
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text(S.t('说明')),
            tiles: [
              SettingsTile(
                leading: AnikumoIcons.info_outline_rounded,
                title: Text(S.t('关于并发设置')),
                description: Text(
                  S.t('• 集数并发：同时下载多少集视频\n'
                      '• 分片并发：每集内同时下载多少个视频片段\n'
                      '• 较高的并发可提升速度，但可能被服务器限制\n'
                      '• 修改后对新开始的下载生效'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
