import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/services/danmaku/local_danmaku.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/pages/settings/danmaku/danmaku_ch_convert_tile.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class DanmakuSettingsPage extends StatefulWidget {
  const DanmakuSettingsPage({super.key});

  @override
  State<DanmakuSettingsPage> createState() => _DanmakuSettingsPageState();
}

class _DanmakuSettingsPageState extends State<DanmakuSettingsPage> {
  late double defaultDanmakuArea;
  late double defaultDanmakuOpacity;
  late double defaultDanmakuFontSize;
  late int defaultDanmakuFontWeight;
  late double defaultDanmakuDuration;
  late double defaultDanmakuLineHeight;
  late double defaultdanmakuBorderSize;
  late bool danmakuBorder;
  late bool danmakuTop;
  late bool danmakuBottom;
  late bool danmakuScroll;
  late bool danmakuColor;
  late bool danmakuMassive;
  late bool danmakuDeduplication;
  late bool pauseOnDanmakuEdit;
  late bool danmakuBiliBiliSource;
  late bool danmakuGamerSource;
  late bool danmakuDanDanSource;
  late bool danmakuFollowSpeed;
  late bool danmakuBuiltinEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSettingsFromStorage();
  }

  void _loadSettingsFromStorage() {
    final settingContext = SettingContext(
      compactLayout: MediaQuery.sizeOf(context).shortestSide < 600,
    );
    defaultDanmakuArea = GStorage.getSetting(SettingsKeys.danmakuArea);
    defaultDanmakuOpacity = GStorage.getSetting(SettingsKeys.danmakuOpacity);
    defaultDanmakuFontSize = GStorage.getSetting<double>(
        SettingsKeys.danmakuFontSize,
        context: settingContext);
    defaultDanmakuFontWeight =
        GStorage.getSetting(SettingsKeys.danmakuFontWeight);
    defaultDanmakuDuration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    defaultDanmakuLineHeight =
        GStorage.getSetting(SettingsKeys.danmakuLineHeight);
    danmakuBorder = GStorage.getSetting(SettingsKeys.danmakuBorder);
    defaultdanmakuBorderSize =
        GStorage.getSetting(SettingsKeys.danmakuBorderSize);
    danmakuTop = GStorage.getSetting(SettingsKeys.danmakuTop);
    danmakuBottom = GStorage.getSetting(SettingsKeys.danmakuBottom);
    danmakuScroll = GStorage.getSetting(SettingsKeys.danmakuScroll);
    danmakuColor = GStorage.getSetting(SettingsKeys.danmakuColor);
    danmakuMassive = GStorage.getSetting(SettingsKeys.danmakuMassive);
    danmakuDeduplication =
        GStorage.getSetting<bool>(SettingsKeys.danmakuDeduplication);
    pauseOnDanmakuEdit =
        GStorage.getSetting<bool>(SettingsKeys.pauseOnDanmakuEdit);
    danmakuBiliBiliSource =
        GStorage.getSetting<bool>(SettingsKeys.danmakuBiliBiliSource);
    danmakuGamerSource =
        GStorage.getSetting<bool>(SettingsKeys.danmakuGamerSource);
    danmakuDanDanSource =
        GStorage.getSetting<bool>(SettingsKeys.danmakuDanDanSource);
    danmakuFollowSpeed =
        GStorage.getSetting<bool>(SettingsKeys.danmakuFollowSpeed);
    danmakuBuiltinEnabled =
        GStorage.getSetting<bool>(SettingsKeys.danmakuBuiltinEnabled);
  }

  Future<void> resetDanmakuSettings() async {
    final bool shouldReset = await AnikumoDialog.show<bool>(
          builder: (context) => AlertDialog(
            title: const Text('恢复默认弹幕设置'),
            content: const Text('弹幕来源、显示和样式设置将恢复为默认值，关键词屏蔽列表不会被清空。'),
            actions: [
              TextButton(
                onPressed: () => AnikumoDialog.dismiss(popWith: false),
                child: Text('取消'),
              ),
              TextButton(
                onPressed: () => AnikumoDialog.dismiss(popWith: true),
                child: Text('恢复默认'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldReset) return;

    await GStorage.resetDanmakuSettings();
    if (!mounted) return;
    setState(_loadSettingsFromStorage);
    AnikumoDialog.showToast(message: '已恢复默认弹幕设置');
  }

  void updateDanmakuArea(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuArea, i);
    setState(() {
      defaultDanmakuArea = i;
    });
  }

  void updateDanmakuOpacity(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuOpacity, i);
    setState(() {
      defaultDanmakuOpacity = i;
    });
  }

  void updateDanmakuFontSize(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuFontSize, i);
    setState(() {
      defaultDanmakuFontSize = i;
    });
  }

  void updateDanmakuDuration(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuDuration, i);
    setState(() {
      defaultDanmakuDuration = i;
    });
  }

  void updateDanmakuLineHeight(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuLineHeight, i);
    setState(() {
      defaultDanmakuLineHeight = i;
    });
  }

  void updateDanmakuFontWeight(int i) async {
    await GStorage.putSetting<int>(SettingsKeys.danmakuFontWeight, i);
    setState(() {
      defaultDanmakuFontWeight = i;
    });
  }

  void updateDanmakuBorderSize(double i) async {
    await GStorage.putSetting<double>(SettingsKeys.danmakuBorderSize, i);
    setState(() {
      defaultdanmakuBorderSize = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('弹幕设置'),
      body: SettingsList(
        sections: [
          // Batch 193: the credential entry is gone — the
          // build carries the pair (obfuscated, injected at
          // packaging time) and a pair stored by an earlier
          // version keeps working silently underneath.
          // Nothing about credentials appears here anymore.
          SettingsSection(
            title: Text('弹幕服务'),
            tiles: [
              // Batch 163: the built-in service's only UI —
              // a switch. No address, no key, nothing else
              // about it appears anywhere in the app.
              SettingsTile.switchTile(
                leading: AnikumoIcons.cloud_rounded,
                title: Text('内置弹幕服务'),
                description: Text('主线路不可用时自动切换使用'),
                initialValue: danmakuBuiltinEnabled,
                onToggle: (value) async {
                  danmakuBuiltinEnabled = value ?? !danmakuBuiltinEnabled;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuBuiltinEnabled,
                      danmakuBuiltinEnabled);
                  setState(() {});
                },
              ),
              // Batch 182: sent danmaku live only on this
              // device (no provider send API) — show the
              // count and offer a wipe.
              SettingsTile(
                leading: AnikumoIcons.delete_outline_rounded,
                title: Text('本机弹幕记录'),
                description: Text('你发送的弹幕只保存在这台设备上'),
                trailing: Text('${LocalDanmakuStore.totalCount} 条'),
                onPressed: (_) {
                  if (LocalDanmakuStore.totalCount == 0) return;
                  LocalDanmakuStore.clearAll();
                  setState(() {});
                  AnikumoDialog.showToast(message: '已清除本机弹幕记录');
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text('弹幕来源'),
            tiles: [
              SettingsTile.switchTile(
                leading: AnikumoIcons.live_tv_rounded,
                onToggle: (value) async {
                  danmakuBiliBiliSource = value ?? !danmakuBiliBiliSource;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuBiliBiliSource,
                      danmakuBiliBiliSource);
                  setState(() {});
                },
                title: Text('BiliBili'),
                initialValue: danmakuBiliBiliSource,
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.sports_esports_rounded,
                onToggle: (value) async {
                  danmakuGamerSource = value ?? !danmakuGamerSource;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuGamerSource, danmakuGamerSource);
                  setState(() {});
                },
                title: Text('Gamer'),
                initialValue: danmakuGamerSource,
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.forum_rounded,
                onToggle: (value) async {
                  danmakuDanDanSource = value ?? !danmakuDanDanSource;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuDanDanSource, danmakuDanDanSource);
                  setState(() {});
                },
                title: Text('弹弹play'),
                initialValue: danmakuDanDanSource,
              ),
            ],
          ),
          SettingsSection(
            title: Text('弹幕屏蔽'),
            tiles: [
              SettingsTile(
                leading: AnikumoIcons.block_rounded,
                onPressed: (_) {
                  context.pushNamed('/settings/danmaku/shield');
                },
                title: Text('关键词屏蔽'),
              ),
            ],
          ),
          SettingsSection(
            title: Text('弹幕显示'),
            tiles: [
              const DanmakuChConvertTile(),
              SettingsSliderTile(
                leading: AnikumoIcons.crop_free_rounded,
                title: Text('弹幕区域'),
                value: defaultDanmakuArea,
                min: 0,
                max: 1,
                divisions: 8,
                valueLabel: '${(defaultDanmakuArea * 100).round()}%',
                onChanged: updateDanmakuArea,
              ),
              SettingsSliderTile(
                leading: AnikumoIcons.timer_rounded,
                title: Text('弹幕持续时间'),
                value: defaultDanmakuDuration,
                min: 2,
                max: 16,
                divisions: 14,
                valueLabel: '${defaultDanmakuDuration.round()} 秒',
                onChanged: (value) =>
                    updateDanmakuDuration(value.roundToDouble()),
              ),
              SettingsSliderTile(
                leading: AnikumoIcons.format_line_spacing_rounded,
                title: Text('弹幕行高'),
                value: defaultDanmakuLineHeight,
                min: 0,
                max: 3,
                divisions: 30,
                valueLabel: defaultDanmakuLineHeight.toStringAsFixed(1),
                onChanged: (value) => updateDanmakuLineHeight(
                    double.parse(value.toStringAsFixed(1))),
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.speed_rounded,
                onToggle: (value) async {
                  danmakuFollowSpeed = value ?? !danmakuFollowSpeed;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuFollowSpeed, danmakuFollowSpeed);
                  setState(() {});
                },
                title: Text('弹幕跟随视频倍速'),
                description: Text('开启后弹幕速度会随视频倍速而改变'),
                initialValue: danmakuFollowSpeed,
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.vertical_align_top_rounded,
                onToggle: (value) async {
                  danmakuTop = value ?? !danmakuTop;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuTop, danmakuTop);
                  setState(() {});
                },
                title: Text('顶部弹幕'),
                initialValue: danmakuTop,
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.vertical_align_bottom_rounded,
                onToggle: (value) async {
                  danmakuBottom = value ?? !danmakuBottom;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuBottom, danmakuBottom);
                  setState(() {});
                },
                title: Text('底部弹幕'),
                initialValue: danmakuBottom,
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.swap_horiz_rounded,
                onToggle: (value) async {
                  danmakuScroll = value ?? !danmakuScroll;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuScroll, danmakuScroll);
                  setState(() {});
                },
                title: Text('滚动弹幕'),
                initialValue: danmakuScroll,
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.layers_rounded,
                onToggle: (value) async {
                  danmakuMassive = value ?? !danmakuMassive;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuMassive, danmakuMassive);
                  setState(() {});
                },
                title: Text('海量弹幕'),
                description: Text('弹幕过多时进行叠加绘制'),
                initialValue: danmakuMassive,
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.filter_alt_rounded,
                onToggle: (value) async {
                  danmakuDeduplication = value ?? !danmakuDeduplication;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuDeduplication, danmakuDeduplication);
                  setState(() {});
                },
                title: Text('弹幕去重'),
                description: Text('相同内容弹幕过多时合并为一条弹幕'),
                initialValue: danmakuDeduplication,
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.pause_circle_outline_rounded,
                onToggle: (value) async {
                  pauseOnDanmakuEdit = value ?? !pauseOnDanmakuEdit;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.pauseOnDanmakuEdit, pauseOnDanmakuEdit);
                  setState(() {});
                },
                title: Text('编辑弹幕时暂停播放'),
                description: Text('聚焦弹幕输入框时暂停，输入结束后继续；一起看房间内不生效'),
                initialValue: pauseOnDanmakuEdit,
              ),
            ],
          ),
          SettingsSection(
            title: Text('弹幕样式'),
            tiles: [
              SettingsTile.switchTile(
                leading: AnikumoIcons.border_color_rounded,
                onToggle: (value) async {
                  danmakuBorder = value ?? !danmakuBorder;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuBorder, danmakuBorder);
                  setState(() {});
                },
                title: Text('弹幕描边'),
                initialValue: danmakuBorder,
              ),
              SettingsSliderTile(
                leading: AnikumoIcons.line_weight_rounded,
                title: Text('弹幕描边粗细'),
                value: defaultdanmakuBorderSize,
                min: 0.1,
                max: 3,
                divisions: 29,
                valueLabel: defaultdanmakuBorderSize.toStringAsFixed(1),
                onChanged: (value) => updateDanmakuBorderSize(
                    double.parse(value.toStringAsFixed(1))),
              ),
              SettingsTile.switchTile(
                leading: AnikumoIcons.palette_rounded,
                onToggle: (value) async {
                  danmakuColor = value ?? !danmakuColor;
                  await GStorage.putSetting<bool>(
                      SettingsKeys.danmakuColor, danmakuColor);
                  setState(() {});
                },
                title: Text('弹幕颜色'),
                initialValue: danmakuColor,
              ),
              SettingsSliderTile(
                leading: AnikumoIcons.format_size_rounded,
                title: Text('字体大小'),
                value: defaultDanmakuFontSize,
                min: 10,
                max: 48,
                valueLabel: '${defaultDanmakuFontSize.floor()}',
                onChanged: (value) =>
                    updateDanmakuFontSize(value.floorToDouble()),
              ),
              SettingsSliderTile(
                leading: AnikumoIcons.format_bold_rounded,
                title: Text('字体字重'),
                value: defaultDanmakuFontWeight.toDouble(),
                min: 1,
                max: 9,
                divisions: 8,
                valueLabel: '$defaultDanmakuFontWeight',
                onChanged: (value) => updateDanmakuFontWeight(value.toInt()),
              ),
              SettingsSliderTile(
                leading: AnikumoIcons.opacity_rounded,
                title: Text('弹幕不透明度'),
                value: defaultDanmakuOpacity,
                min: 0.1,
                max: 1,
                valueLabel: '${(defaultDanmakuOpacity * 100).round()}%',
                onChanged: (value) => updateDanmakuOpacity(
                    double.parse(value.toStringAsFixed(2))),
              ),
            ],
          ),
          SettingsSection(
            tiles: [
              SettingsTile(
                leading: AnikumoIcons.settings_backup_restore_rounded,
                onPressed: (_) => resetDanmakuSettings(),
                title: Text('恢复默认设置'),
                description: Text('将弹幕相关设置恢复为默认值'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
