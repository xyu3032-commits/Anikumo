import 'package:flutter/material.dart';

import 'package:anikumo/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:anikumo/services/player/mini_player_session.dart';
import 'package:anikumo/services/player/pip_utils.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 113: the picture-in-picture settings, shared by the player
/// settings page and the long-press shortcut on the player's PiP
/// button. Plain wording only: the two modes are described by where
/// the small window lives, nothing else.
Future<void> showPipSettingsSheet(BuildContext context) {
  return showAdaptiveBottomSheet<void>(
    context: context,
    builder: (context) => const PipSettingsSheet(),
  );
}

class PipSettingsSheet extends StatefulWidget {
  const PipSettingsSheet({super.key});

  @override
  State<PipSettingsSheet> createState() => _PipSettingsSheetState();
}

class _PipSettingsSheetState extends State<PipSettingsSheet> {
  late bool _inAppMode;
  late bool _hideInOtherZones;
  late bool _muteWhenHidden;

  @override
  void initState() {
    super.initState();
    _inAppMode = GStorage.getSetting(SettingsKeys.pipInAppMode);
    _hideInOtherZones = GStorage.getSetting(SettingsKeys.pipHideInOtherZones);
    _muteWhenHidden = GStorage.getSetting(SettingsKeys.pipMuteWhenHidden);
  }

  Future<void> _setInAppMode(bool inApp) async {
    setState(() => _inAppMode = inApp);
    await GStorage.putSetting(SettingsKeys.pipInAppMode, inApp);
    // The two modes exclude each other natively: in-app mode turns
    // the system's auto-enter off; external mode restores whatever
    // the "自动进入画中画" switch says.
    await PipUtils.setAndroidAutoEnterPIPEnabled(
      inApp ? false : GStorage.getSetting(SettingsKeys.androidAutoEnterPIP),
    );
    MiniPlayerSession.instance.refreshFromSettings();
  }

  Future<void> _setHideInOtherZones(bool value) async {
    setState(() => _hideInOtherZones = value);
    await GStorage.putSetting(SettingsKeys.pipHideInOtherZones, value);
    MiniPlayerSession.instance.refreshFromSettings();
  }

  Future<void> _setMuteWhenHidden(bool value) async {
    setState(() => _muteWhenHidden = value);
    await GStorage.putSetting(SettingsKeys.pipMuteWhenHidden, value);
    MiniPlayerSession.instance.refreshFromSettings();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '画中画设置',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text(
              '画中画模式',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(Icons.web_asset_rounded),
                  label: Text('应用内小窗'),
                ),
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(Icons.picture_in_picture_alt_rounded),
                  label: Text('应用外'),
                ),
              ],
              selected: {_inAppMode},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  _setInAppMode(selection.first);
                }
              },
            ),
            const SizedBox(height: 6),
            Text(
              _inAppMode
                  ? '退出播放页后回到应用主页，视频在应用内小窗继续播放。'
                  : '使用系统画中画：切到桌面或其他应用时，视频悬浮在最上层。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('进入漫画 / 小说时隐藏小窗'),
              subtitle: const Text('退出漫画 / 小说后，小窗自动恢复显示'),
              value: _hideInOtherZones,
              onChanged: _setHideInOtherZones,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('隐藏小窗时静音'),
              subtitle: const Text('小窗隐藏期间不播放声音，恢复显示后还原音量'),
              value: _muteWhenHidden,
              onChanged: _hideInOtherZones ? _setMuteWhenHidden : null,
            ),
          ],
        ),
      ),
    );
  }
}
