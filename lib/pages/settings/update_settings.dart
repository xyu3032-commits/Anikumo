import 'package:flutter/material.dart';

import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/update/auto_updater.dart';

class UpdateSettingsPage extends StatefulWidget {
  const UpdateSettingsPage({super.key});

  @override
  State<UpdateSettingsPage> createState() => _UpdateSettingsPageState();
}

class _UpdateSettingsPageState extends State<UpdateSettingsPage> {
  bool _autoUpdate = GStorage.getSetting(SettingsKeys.autoUpdate);
  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('更新设置'),
        body: SettingsList(
          sections: [
            SettingsSection(
              title: const Text('启动时检查更新'),
              tiles: [
                SettingsTile.switchTile(
                  leading: Icons.update_rounded,
                  title: const Text('应用更新'),
                  initialValue: _autoUpdate,
                  onToggle: (value) {
                    setState(() => _autoUpdate = value ?? !_autoUpdate);
                    GStorage.putSetting(SettingsKeys.autoUpdate, _autoUpdate);
                  },
                ),
              ],
            ),
            SettingsSection(
              title: const Text('手动检查'),
              bottomInfo: const Text(
                '更新来源：GitHub 仓库 xyu3032-commits/Anikumo 的 Releases',
              ),
              tiles: [
                SettingsTile(
                  leading: Icons.system_update_rounded,
                  title: const Text('检查更新'),
                  description: const Text('查看 GitHub 上有没有新版本'),
                  onPressed: (_) {
                    AutoUpdater().manualCheckForUpdates();
                  },
                ),
              ],
            ),
          ],
        ),
      );
}
