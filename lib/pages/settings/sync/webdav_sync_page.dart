import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/settings/settings_dropdown_tile.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/bean/widget/state_presentation.dart';
import 'package:anikumo/pages/settings/sync/sync_settings_widgets.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/sync/webdav.dart';
import 'package:anikumo/services/sync/zone_sync.dart';
import 'package:anikumo/services/sync/danmaku_shield_sync_service.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class WebDavSyncPage extends StatefulWidget {
  const WebDavSyncPage({super.key, required this.danmakuShieldSync});

  final DanmakuShieldSyncService danmakuShieldSync;

  @override
  State<WebDavSyncPage> createState() => _WebDavSyncPageState();
}

class _WebDavSyncPageState extends State<WebDavSyncPage> {
  bool _busy = false;
  bool _failed = false;
  String? _message;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
      _message = S.t('正在连接 WebDAV…');
    });
    try {
      await action();
    } catch (e) {
      AnikumoLogger().w('WebDAV settings operation failed', error: e);
      if (mounted) {
        _failed = true;
        _message = S.t('未能完成，请检查网络或服务器配置后重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setEnabled(bool enabled) => _run(() async {
        await WebDav().setEnabled(enabled);
        _message = null;
      });

  Future<void> _syncHistory() => _run(() async {
        final webDav = WebDav();
        if (!webDav.initialized) {
          await webDav.init();
        } else if (!webDav.isHistorySyncing) {
          await webDav.ping();
        }
        if (mounted) setState(() => _message = S.t('正在同步观看记录…'));
        await webDav.syncHistory();
        _message = S.t('观看记录已同步');
      });

  Future<void> _configure() async {
    await context.pushNamed('/settings/webdav/editor');
    if (mounted) {
      setState(() {
        _message = null;
        _failed = false;
      });
    }
  }

  Future<void> _syncDanmakuShield() => _run(() async {
        if (mounted) setState(() => _message = S.t('正在同步弹幕屏蔽词…'));
        await widget.danmakuShieldSync.sync();
        _message = S.t('弹幕屏蔽词已同步');
      });

  /// Batch 274 (#36–#38): one zone bundle sync, with
  /// the outcome surfaced in the page feedback line.
  Future<void> _syncZone(String zone, String label) => _run(() async {
        final webDav = WebDav();
        if (!webDav.initialized) {
          await webDav.init();
        }
        if (mounted) {
          setState(() => _message = S.f('正在同步{}…', [label]));
        }
        final outcome = await webDav.syncZoneData(zone);
        _message = switch (outcome) {
          'uploaded' => S.f('{}已上传', [label]),
          'downloaded' => S.f('{}已从服务器更新', [label]),
          'conflict' => S.f('{}出现同步冲突，请到冲突页处理', [label]),
          _ => S.f('{}已是最新', [label]),
        };
        if (mounted) setState(() {});
      });

  @override
  Widget build(BuildContext context) {
    final enabled = GStorage.getSetting(SettingsKeys.webDavEnable);
    final history = GStorage.getSetting(SettingsKeys.webDavEnableHistory);
    final collect = GStorage.getSetting(SettingsKeys.webDavEnableCollect);
    final shield = GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield);
    final url = GStorage.getSetting(SettingsKeys.webDavURL).trim();
    final configured = url.isNotEmpty;
    final host = Uri.tryParse(url)?.host;
    return PopScope(
      canPop: !_busy,
      child: SettingsDetailScaffold(
        title: Text(S.t('多设备同步')),
        body: SyncPageBody(
          maxWidth: 720,
          children: [
            SyncPageIntro(
              icon: AnikumoIcons.devices_rounded,
              title: 'WebDAV',
              description: S.t('连接自己的云盘，同步观看记录、收藏与弹幕屏蔽词。'),
            ),
            SettingsSection(
              margin: EdgeInsets.zero,
              tiles: [
                SettingsTile(
                  leading: AnikumoIcons.dns_rounded,
                  title: Text(configured ? S.t('同步服务器') : S.t('连接你的云盘')),
                  description: Text(configured
                      ? (host == null || host.isEmpty ? S.t('已保存服务器地址') : host)
                      : S.t('需要支持 WebDAV 的云盘或服务器')),
                  trailing: const Icon(AnikumoIcons.chevron_right_rounded),
                  enabled: !_busy,
                  onPressed: (_) => _configure(),
                ),
                SettingsTile.switchTile(
                  leading: AnikumoIcons.cloud_sync_rounded,
                  title: Text(S.t('启用 WebDAV')),
                  description: Text(configured
                      ? (enabled
                          ? S.t('已开启，选择下方要同步的内容')
                          : S.t('开启后选择要同步的内容'))
                      : S.t('请先配置服务器')),
                  initialValue: enabled,
                  enabled: configured && !_busy,
                  onToggle: (value) => _setEnabled(value ?? !enabled),
                ),
              ],
            ),
            SettingsSection(
              title: Text(S.t('同步内容')),
              margin: EdgeInsets.zero,
              tiles: [
                SettingsTile.switchTile(
                  leading: AnikumoIcons.history_rounded,
                  title: Text(S.t('观看记录')),
                  description: Text(S.t('自动同步播放进度与历史记录')),
                  initialValue: history,
                  enabled: enabled && !_busy,
                  onToggle: (value) async {
                    await GStorage.putSetting(
                        SettingsKeys.webDavEnableHistory, value ?? !history);
                    if (mounted) setState(() {});
                  },
                ),
                SettingsTile.switchTile(
                  leading: AnikumoIcons.favorite_rounded,
                  title: Text(S.t('收藏')),
                  description: Text(S.t('在收藏页同步所有追番分类')),
                  initialValue: collect,
                  enabled: enabled && !_busy,
                  onToggle: (value) async {
                    await GStorage.putSetting(
                        SettingsKeys.webDavEnableCollect, value ?? !collect);
                    if (mounted) setState(() {});
                  },
                ),
                SettingsTile.switchTile(
                  leading: AnikumoIcons.filter_alt_rounded,
                  title: Text(S.t('弹幕屏蔽词')),
                  description: Text(S.t('启动和修改规则后自动同步，包含关键词与正则表达式')),
                  initialValue: shield,
                  enabled: enabled && !_busy,
                  onToggle: (value) async {
                    final syncEnabled = value ?? !shield;
                    await GStorage.putSetting(
                        SettingsKeys.webDavEnableDanmakuShield, syncEnabled);
                    if (!mounted) return;
                    setState(() {});
                    if (syncEnabled) await _syncDanmakuShield();
                  },
                ),
              ],
            ),
            // Batch 274 (#36–#39): zone data bundles and
            // the conflicts inbox.
            SettingsSection(
              title: Text(S.t('分区数据')),
              margin: EdgeInsets.zero,
              tiles: [
                for (final (zone, label) in [
                  ('manga', S.t('漫画区')),
                  ('novel', S.t('小说区')),
                  ('film', S.t('影视区')),
                ])
                  SettingsTile(
                    leading: AnikumoIcons.cloud_sync_rounded,
                    title: Text(S.f('同步{}', [label])),
                    description: Text(S.t('收藏与阅读进度')),
                    trailing: const Icon(AnikumoIcons.sync_rounded),
                    enabled: enabled && !_busy,
                    onPressed: (_) => _syncZone(zone, label),
                  ),
                SettingsTile(
                  leading: AnikumoIcons.sync_problem_rounded,
                  title: Text(S.t('同步冲突')),
                  description: Text(
                    SyncConflicts.load().isEmpty
                        ? S.t('没有待处理的同步冲突')
                        : S.f('{} 个冲突待处理', [
                            SyncConflicts.load().length,
                          ]),
                  ),
                  trailing: const Icon(AnikumoIcons.chevron_right_rounded),
                  enabled: !_busy,
                  onPressed: (_) async {
                    await context.pushNamed('/settings/webdav/conflicts');
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            // Batch 282 (#24): timed auto sync of the
            // zone bundles (+ GitHub when signed in).
            SettingsSection(
              title: Text(S.t('自动同步')),
              margin: EdgeInsets.zero,
              tiles: [
                SettingsTile.switchTile(
                  leading: AnikumoIcons.schedule_rounded,
                  title: Text(S.t('自动同步分区数据')),
                  description: Text(
                    S.t('打开 App 时与运行期间按间隔自动同步漫画、小说、影视分区数据；已登录 GitHub 同步时也会一并同步。冲突不会自动处理，会记录到通知中心。'),
                  ),
                  initialValue:
                      GStorage.getSetting(SettingsKeys.autoSyncEnabled),
                  enabled: !_busy,
                  onToggle: (value) async {
                    await GStorage.putSetting(
                      SettingsKeys.autoSyncEnabled,
                      value ??
                          !GStorage.getSetting(SettingsKeys.autoSyncEnabled),
                    );
                    if (mounted) setState(() {});
                  },
                ),
                SettingsDropdownTile<int>(
                  leading: AnikumoIcons.schedule_rounded,
                  title: Text(S.t('同步间隔')),
                  value:
                      GStorage.getSetting(SettingsKeys.autoSyncIntervalHours),
                  options: {
                    6: S.t('每 6 小时'),
                    12: S.t('每 12 小时'),
                    24: S.t('每 24 小时'),
                  },
                  fallbackLabel: S.t('每 24 小时'),
                  enabled: !_busy &&
                      GStorage.getSetting(SettingsKeys.autoSyncEnabled),
                  onChanged: (value) async {
                    await GStorage.putSetting(
                      SettingsKeys.autoSyncIntervalHours,
                      value,
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            StateActionButton(
              onPressed: enabled && !_busy ? _syncHistory : null,
              text: _busy ? S.t('请稍候…') : S.t('立即同步观看记录'),
              icon: AnikumoIcons.sync_rounded,
            ),
            StateActionButton.tonal(
              onPressed:
                  enabled && shield && !_busy ? _syncDanmakuShield : null,
              text: S.t('立即同步弹幕屏蔽词'),
              icon: AnikumoIcons.sync_rounded,
            ),
            if (_message != null)
              SyncFeedback(message: _message!, error: _failed, busy: _busy),
          ],
        ),
      ),
    );
  }
}
