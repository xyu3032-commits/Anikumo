import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:anikumo/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/services/player/mini_player_session.dart';
import 'package:anikumo/services/player/pip_utils.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// The picture-in-picture settings, shared by the player settings
/// page, the long-press shortcut on the player's PiP button, and a
/// long-press on the mini window itself. Plain wording only: modes
/// are described by where the small window lives, nothing else.
///
/// Batch 117 adds the personalisation sections (appearance,
/// controls, gestures) for the in-app mini player.
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
  late bool _autoSystemOnLeave;
  late int _theme;
  late int _controlMode;
  late double _controlsOpacity;
  late int _autoHideSeconds;
  late int _seekSeconds;
  late int _doubleTapAction;
  late bool _sideGestures;
  late bool _haptics;
  late bool _animations;
  late int _defaultSize;
  late int _catStyle;
  late int _catCount;

  @override
  void initState() {
    super.initState();
    _inAppMode = GStorage.getSetting(SettingsKeys.pipInAppMode);
    _hideInOtherZones = GStorage.getSetting(SettingsKeys.pipHideInOtherZones);
    _muteWhenHidden = GStorage.getSetting(SettingsKeys.pipMuteWhenHidden);
    _autoSystemOnLeave =
        GStorage.getSetting(SettingsKeys.pipAutoSystemOnLeave);
    _theme = GStorage.getSetting(SettingsKeys.pipTheme);
    _controlMode = GStorage.getSetting(SettingsKeys.pipControlMode);
    _controlsOpacity = GStorage.getSetting(SettingsKeys.pipControlsOpacity);
    _autoHideSeconds = GStorage.getSetting(SettingsKeys.pipAutoHideSeconds);
    _seekSeconds = GStorage.getSetting(SettingsKeys.pipSeekSeconds);
    _doubleTapAction = GStorage.getSetting(SettingsKeys.pipDoubleTapAction);
    _sideGestures = GStorage.getSetting(SettingsKeys.pipSideGestures);
    _haptics = GStorage.getSetting(SettingsKeys.pipHaptics);
    _animations = GStorage.getSetting(SettingsKeys.pipAnimations);
    _defaultSize = GStorage.getSetting(SettingsKeys.pipDefaultSize);
    _catStyle = GStorage.getSetting(SettingsKeys.pipCatStyle);
    _catCount = _savedCatPaths().length;
  }

  List<String> _savedCatPaths() {
    final raw = GStorage.getSetting(SettingsKeys.pipCatImages);
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final entry in decoded)
            if (entry is String && entry.isNotEmpty) entry,
        ];
      }
    } catch (_) {}
    return const [];
  }

  /// Batch 126: upload custom dock-face images. The picks are
  /// copied into app storage (the picker cache can be cleaned
  /// by the OS); several images play as a flipbook in the
  /// docked bubble.
  Future<void> _uploadCatImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    final files = result?.files ?? const [];
    final picked = [for (final f in files) if (f.path != null) f.path!];
    if (picked.isEmpty) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/pip_cat');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);
      final saved = <String>[];
      for (var i = 0; i < picked.length; i++) {
        final source = File(picked[i]);
        final ext = picked[i].split('.').last.toLowerCase();
        final target = File(
          '${dir.path}/cat_${i}_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );
        await source.copy(target.path);
        saved.add(target.path);
      }
      await GStorage.putSetting(
        SettingsKeys.pipCatImages,
        jsonEncode(saved),
      );
      await GStorage.putSetting(SettingsKeys.pipCatStyle, 1);
      if (!mounted) return;
      setState(() {
        _catStyle = 1;
        _catCount = saved.length;
      });
      MiniPlayerSession.instance.refreshFromSettings();
      AnikumoDialog.showToast(
        message: saved.length > 1
            ? '已设置 ${saved.length} 张自定义图片（会轮播）'
            : '已设置自定义图片',
      );
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(message: '图片保存失败，请重试');
      }
    }
  }

  Future<void> _clearCatImages() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/pip_cat');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Clearing the setting below is enough either way.
    }
    await GStorage.putSetting(SettingsKeys.pipCatImages, '');
    await GStorage.putSetting(SettingsKeys.pipCatStyle, 0);
    if (!mounted) return;
    setState(() {
      _catStyle = 0;
      _catCount = 0;
    });
    MiniPlayerSession.instance.refreshFromSettings();
  }

  Future<void> _setInAppMode(bool inApp) async {
    setState(() => _inAppMode = inApp);
    await GStorage.putSetting(SettingsKeys.pipInAppMode, inApp);
    // The two modes exclude each other natively: in-app mode turns
    // the system's auto-enter off; external mode restores whatever
    // the "自动进入画中画" switch says. Routed through the one
    // effective-value sync every surface shares (batch 116).
    await PipUtils.syncAndroidAutoEnterPIP();
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

  Future<void> _setAutoSystemOnLeave(bool value) async {
    setState(() => _autoSystemOnLeave = value);
    await GStorage.putSetting(SettingsKeys.pipAutoSystemOnLeave, value);
    MiniPlayerSession.instance.refreshFromSettings();
  }

  Future<void> _setInt(
    SettingKey<int> key,
    int value,
    void Function(int) apply,
  ) async {
    setState(() => apply(value));
    await GStorage.putSetting(key, value);
    MiniPlayerSession.instance.refreshFromSettings();
  }

  Future<void> _setBool(
    SettingKey<bool> key,
    bool value,
    void Function(bool) apply,
  ) async {
    setState(() => apply(value));
    await GStorage.putSetting(key, value);
    MiniPlayerSession.instance.refreshFromSettings();
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }

  Widget _chips<T>(
    List<(T, String)> options,
    T selected,
    void Function(T) onSelected,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          ChoiceChip(
            label: Text(label),
            selected: selected == value,
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
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
                  icon: Icon(AnikumoIcons.web_asset_rounded),
                  label: Text('应用内小窗'),
                ),
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(AnikumoIcons.picture_in_picture_alt_rounded),
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
            if (_inAppMode) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('退出软件时切到系统画中画'),
                subtitle: const Text(
                    '小窗播放时按 Home 离开软件，自动把视频送到系统画中画继续播放，而不是留在后台'),
                value: _autoSystemOnLeave,
                onChanged: _setAutoSystemOnLeave,
              ),
              _sectionLabel(context, '外观'),
              _chips<int>(
                const [
                  (0, '深色玻璃'),
                  (1, '月白'),
                  (2, '雾蓝'),
                  (3, '淡紫'),
                ],
                _theme,
                (v) => _setInt(SettingsKeys.pipTheme, v, (x) => _theme = x),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('控制栏透明度'),
                  Expanded(
                    child: Slider(
                      value: _controlsOpacity,
                      min: 0.4,
                      max: 1.0,
                      onChanged: (v) async {
                        setState(() => _controlsOpacity = v);
                        await GStorage.putSetting(
                            SettingsKeys.pipControlsOpacity, v);
                        MiniPlayerSession.instance.refreshFromSettings();
                      },
                    ),
                  ),
                  Text('${(_controlsOpacity * 100).round()}%'),
                ],
              ),
              _sectionLabel(context, '控制'),
              Text(
                '控制栏模式',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              _chips<int>(
                const [(0, '简洁'), (1, '标准'), (2, '完整')],
                _controlMode,
                (v) => _setInt(
                    SettingsKeys.pipControlMode, v, (x) => _controlMode = x),
              ),
              const SizedBox(height: 12),
              Text(
                '控制栏自动隐藏',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              _chips<int>(
                const [(0, '常显'), (2, '2 秒'), (3, '3 秒'), (5, '5 秒')],
                _autoHideSeconds,
                (v) => _setInt(SettingsKeys.pipAutoHideSeconds, v,
                    (x) => _autoHideSeconds = x),
              ),
              const SizedBox(height: 12),
              Text(
                '快退 / 快进秒数',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              _chips<int>(
                const [(5, '5 秒'), (10, '10 秒'), (15, '15 秒'), (30, '30 秒')],
                _seekSeconds,
                (v) => _setInt(
                    SettingsKeys.pipSeekSeconds, v, (x) => _seekSeconds = x),
              ),
              const SizedBox(height: 12),
              Text(
                '默认窗口大小',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              _chips<int>(
                const [(0, '小'), (1, '标准'), (2, '大')],
                _defaultSize,
                (v) async {
                  await _setInt(SettingsKeys.pipDefaultSize, v,
                      (x) => _defaultSize = x);
                  // Batch 119: a remembered pinch scale outranks
                  // the default forever, which made this setting
                  // feel dead after the first drag. Choosing a
                  // default clears the remembered scale so the
                  // choice takes effect from the next window.
                  await GStorage.putSetting(SettingsKeys.pipScale, 0.0);
                  MiniPlayerSession.instance.refreshFromSettings();
                },
              ),
              _sectionLabel(context, '手势'),
              Text(
                '双击操作',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              _chips<int>(
                const [(0, '播放 / 暂停'), (1, '两侧快退 / 快进')],
                _doubleTapAction,
                (v) => _setInt(SettingsKeys.pipDoubleTapAction, v,
                    (x) => _doubleTapAction = x),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('侧边滑动调节'),
                subtitle: const Text('在小窗左侧上下滑调亮度、右侧上下滑调音量'),
                value: _sideGestures,
                onChanged: (v) => _setBool(
                    SettingsKeys.pipSideGestures, v, (x) => _sideGestures = x),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('触觉反馈'),
                subtitle: const Text('点按小窗按钮与快进快退时轻震'),
                value: _haptics,
                onChanged: (v) => _setBool(
                    SettingsKeys.pipHaptics, v, (x) => _haptics = x),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('动画'),
                subtitle: const Text('小窗出现、隐藏与控制栏的过渡动画'),
                value: _animations,
                onChanged: (v) => _setBool(
                    SettingsKeys.pipAnimations, v, (x) => _animations = x),
              ),
              _sectionLabel(context, '停靠小猫'),
              Text(
                '小窗缩小停靠后的样子',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              _chips<int>(
                const [(0, '软件图标'), (1, '自定义图片')],
                _catStyle,
                (v) => _setInt(
                    SettingsKeys.pipCatStyle, v, (x) => _catStyle = x),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _uploadCatImages,
                    icon: const Icon(AnikumoIcons.upload_rounded, size: 18),
                    label: const Text('上传图片'),
                  ),
                  const SizedBox(width: 10),
                  if (_catCount > 0) ...[
                    Text(
                      _catCount > 1 ? '已存 $_catCount 张（轮播）' : '已存 1 张',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: _clearCatImages,
                      child: const Text('清除'),
                    ),
                  ] else
                    Expanded(
                      child: Text(
                        '可一次选多张，小猫会轮流播放',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
