import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/settings/settings_dropdown_tile.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/pages/manga/manga_downloads_page.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/manga/manga_image_pipeline.dart';
import 'package:anikumo/services/manga/manga_page_cache.dart';
import 'package:anikumo/services/storage/image_cache_service.dart';
import 'package:anikumo/services/storage/library_housekeeping.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/storage/storage_analysis.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// The storage page: originally a single image-cache
/// row, Batch 283 (#29) grows it into the full
/// analysis surface — every on-disk consumer measured
/// (StorageAnalysis), cache rows clearable through
/// their own managers, downloads and backups shown
/// with jump entries but never a one-tap delete. The
/// same page hosts the #27 cache cap and the #28
/// history retention settings, which the startup
/// housekeeping passes honor.
class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  late Future<List<StorageRowData>> _rows = StorageAnalysis.measure();
  final Set<String> _clearing = {};

  void _refresh() => setState(() => _rows = StorageAnalysis.measure());

  void _message(String message) {
    AnikumoDialog.showToast(context: context, message: message);
  }

  static String _labelFor(String id) => switch (id) {
        'animeDownloads' => '动漫下载',
        'mangaDownloads' => '漫画下载',
        'filmDownloads' => '影视下载',
        'imageCache' => '图片缓存',
        'playbackScratch' => '播放与临时缓存',
        'subtitleCache' => '字幕译文缓存',
        'backups' => '自动备份',
        'logs' => '日志',
        _ => id,
      };

  static IconData _iconFor(String id) => switch (id) {
        'animeDownloads' => AnikumoIcons.smart_display_rounded,
        'mangaDownloads' => AnikumoIcons.auto_stories_rounded,
        'filmDownloads' => AnikumoIcons.movie_rounded,
        'imageCache' => AnikumoIcons.image_outlined,
        'playbackScratch' => AnikumoIcons.play_circle_outline_rounded,
        'subtitleCache' => AnikumoIcons.subtitles_outlined,
        'backups' => AnikumoIcons.settings_backup_restore_rounded,
        'logs' => AnikumoIcons.receipt_long_rounded,
        _ => AnikumoIcons.folder_rounded,
      };

  Future<void> _clearRow(StorageRowData row) async {
    if (_clearing.contains(row.id)) return;
    final confirmed = await AnikumoDialog.show<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(AnikumoIcons.cleaning_services_rounded),
        title: Text(S.f('清除{}？', [S.t(_labelFor(row.id))])),
        content: Text(S.t('缓存会在下次使用时重新下载。下载、记录和设置不会删除。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(S.t('清除缓存')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing.add(row.id));
    try {
      switch (row.id) {
        case 'imageCache':
          await ImageCacheService().clear();
          await mangaPageCacheManager.emptyCache();
          await mangaCoverCacheManager.emptyCache();
          await filmCoverCacheManager.emptyCache();
        case 'subtitleCache':
          final support = await getApplicationSupportDirectory();
          final dir =
              Directory(p.join(support.path, 'subtitle_translations'));
          if (await dir.exists()) {
            await for (final entity in dir.list(followLinks: false)) {
              try {
                await entity.delete(recursive: true);
              } catch (_) {}
            }
          }
      }
      if (!mounted) return;
      _message(S.t('缓存已清除'));
      _refresh();
    } catch (_) {
      if (mounted) _message(S.t('清除失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _clearing.remove(row.id));
    }
  }

  void _jump(StorageRowData row) {
    switch (row.id) {
      case 'animeDownloads':
        context.pushNamed('/download');
      case 'mangaDownloads':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MangaDownloadsPage()),
        );
      case 'filmDownloads':
        context.pushNamed('/film/downloads');
      case 'backups':
        context.pushNamed('/settings/toolbox/backup');
      case 'logs':
        context.pushNamed('/settings/storage/logs');
    }
  }

  Widget _rowTile(StorageRowData row) {
    final clearing = _clearing.contains(row.id);
    final description = switch (row.kind) {
      StorageRowKind.scratch =>
        S.f('{} · 由系统回收，无需手动清理', [formatBytes(row.bytes)]),
      _ => formatBytes(row.bytes),
    };
    return SettingsTile(
      leading: _iconFor(row.id),
      title: Text(S.t(_labelFor(row.id))),
      description: Text(clearing ? S.t('正在清除…') : description),
      enabled: !clearing,
      trailing: switch (row.kind) {
        StorageRowKind.cache => IconButton(
            tooltip: S.t('清除缓存'),
            onPressed: clearing ? null : () => _clearRow(row),
            icon: const Icon(AnikumoIcons.cleaning_services_rounded),
          ),
        StorageRowKind.download ||
        StorageRowKind.backup ||
        StorageRowKind.log =>
          const Icon(AnikumoIcons.chevron_right_rounded),
        StorageRowKind.scratch => null,
      },
      onPressed: switch (row.kind) {
        StorageRowKind.download ||
        StorageRowKind.backup ||
        StorageRowKind.log =>
          (_) => _jump(row),
        _ => null,
      },
    );
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: Text(S.t('存储与日志')),
        body: FutureBuilder<List<StorageRowData>>(
          future: _rows,
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <StorageRowData>[];
            final loading =
                snapshot.connectionState != ConnectionState.done;
            return SettingsList(
              sections: [
                SettingsSection(
                  title: Text(S.t('空间占用')),
                  tiles: [
                    SettingsTile(
                      leading: AnikumoIcons.pie_chart_rounded,
                      title: Text(S.t('合计')),
                      description: Text(
                        loading
                            ? S.t('正在统计…')
                            : formatBytes(totalBytesOf(rows)),
                      ),
                      trailing: loading
                          ? null
                          : IconButton(
                              tooltip: S.t('重新统计'),
                              onPressed: _refresh,
                              icon: const Icon(AnikumoIcons.refresh_rounded),
                            ),
                    ),
                    for (final row in rows) _rowTile(row),
                  ],
                ),
                SettingsSection(
                  title: Text(S.t('自动管理')),
                  tiles: [
                    SettingsDropdownTile<int>(
                      leading: AnikumoIcons.cleaning_services_rounded,
                      title: Text(S.t('缓存上限')),
                      description:
                          Text(S.t('图片与播放缓存的总上限，超出后启动时自动清理最旧的缓存')),
                      value: GStorage.getSetting(SettingsKeys.cacheCapMb),
                      options: {
                        0: S.t('不限'),
                        512: '512 MB',
                        1024: '1 GB',
                        2048: '2 GB',
                      },
                      onChanged: (value) async {
                        await GStorage.putSetting(
                          SettingsKeys.cacheCapMb,
                          value,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                    SettingsDropdownTile<int>(
                      leading: AnikumoIcons.history_rounded,
                      title: Text(S.t('历史保留时长')),
                      description:
                          Text(S.t('超过时长的动漫与影视观看历史会在启动时自动删除，收藏不受影响')),
                      value: GStorage.getSetting(
                          SettingsKeys.historyRetentionDays),
                      options: {
                        0: S.t('永久'),
                        90: S.f('{} 天', [90]),
                        30: S.f('{} 天', [30]),
                      },
                      onChanged: (value) async {
                        await GStorage.putSetting(
                          SettingsKeys.historyRetentionDays,
                          value,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
}
