import 'package:flutter/material.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/services/player/player_enhance.dart';

/// Batch 16: the playback enhancement profile UI — switches
/// and pickers for the 24 optimizations and 12 features in
/// [PlayerEnhance]. Everything is stored immediately and
/// applied to the next playback session at player init.
class PlayerEnhancePage extends StatefulWidget {
  const PlayerEnhancePage({super.key});

  @override
  State<PlayerEnhancePage> createState() => _PlayerEnhancePageState();
}

class _PlayerEnhancePageState extends State<PlayerEnhancePage> {
  final _flags = <String, bool>{};
  final _nums = <String, double>{};
  final _strs = <String, String>{};

  @override
  void initState() {
    super.initState();
    for (final key in PlayerEnhanceKeys.flagKeys) {
      _flags[key] = _read(key, false) as bool;
    }
    for (final key in PlayerEnhanceKeys.numKeys) {
      _nums[key] = (_read(key, PlayerEnhanceKeys.numDefaults[key] ?? 0)
              as num)
          .toDouble();
    }
    for (final key in PlayerEnhanceKeys.strKeys) {
      _strs[key] =
          _read(key, PlayerEnhanceKeys.strDefaults[key] ?? '') as String;
    }
  }

  Object? _read(String key, Object fallback) {
    if (fallback is bool) return PlayerEnhance.flagOf(key);
    if (fallback is num) {
      return PlayerEnhance.numOf(key, fallback.toDouble());
    }
    return PlayerEnhance.strOf(key, fallback.toString());
  }

  // Batch 57: same settings design system as the rest of
  // the settings area (was raw SwitchListTile/ListTile).
  // Controls, keys and storage behavior are unchanged.
  Widget _flagTile(String key, String title, String subtitle) {
    return SettingsTile.switchTile(
      title: Text(title),
      description: Text(subtitle),
      initialValue: _flags[key] ?? false,
      onToggle: (value) {
        final next = value ?? !(_flags[key] ?? false);
        setState(() => _flags[key] = next);
        PlayerEnhance.setFlag(key, next);
      },
    );
  }

  Widget _chips(
    String key,
    String title,
    List<(String, String)> options,
  ) {
    return SettingsTile(
      title: Text(title),
      description: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (value, label) in options)
              ChoiceChip(
                label: Text(label),
                selected: _strs[key] == value,
                onSelected: (_) {
                  setState(() => _strs[key] = value);
                  PlayerEnhance.setStr(key, value);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    String key,
    String title,
    double min,
    double max,
    int divisions,
    String Function(double) format,
  ) {
    final value = _nums[key] ?? 0;
    return SettingsTile(
      title: Row(
        children: [
          Expanded(child: Text(title)),
          Text(
            format(value),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      description: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (next) {
          setState(() => _nums[key] = next);
          PlayerEnhance.setNum(key, next);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('播放增强'),
      body: SettingsList(
        sections: [
          SettingsSection(tiles: [
            SettingsTile(
              title: const Text('全部设置在下次开始播放时生效'),
              description: const Text('默认全关 = 原版行为'),
            ),
          ]),
          SettingsSection(title: const Text('智能调优'), tiles: [
            SettingsTile.switchTile(
              title: const Text('自适应预读'),
              description:
                  const Text('播放中按缓冲余量自动加深/回收预读（30–240 秒）'),
              initialValue: PlayerEnhance.flagDefault(
                  PlayerEnhanceKeys.autoCacheSecs, true),
              onToggle: (value) async {
                await PlayerEnhance.setFlag(PlayerEnhanceKeys.autoCacheSecs,
                    value ?? !PlayerEnhance.flagDefault(PlayerEnhanceKeys.autoCacheSecs, true));
                setState(() {});
              },
            ),
            SettingsTile.switchTile(
              title: const Text('掉帧守护'),
              description: const Text(
                  '持续掉帧时自动分级降负：关插帧 → 降超分 → 关滤镜 → 快速解码'),
              initialValue: PlayerEnhance.flagDefault(
                  PlayerEnhanceKeys.autoDropGuard, true),
              onToggle: (value) async {
                await PlayerEnhance.setFlag(PlayerEnhanceKeys.autoDropGuard,
                    value ?? !PlayerEnhance.flagDefault(PlayerEnhanceKeys.autoDropGuard, true));
                setState(() {});
              },
            ),
          ]),
          SettingsSection(title: const Text('播放优化（21）'), tiles: [
            _flagTile(PlayerEnhanceKeys.optDisplaySync, '显示器帧率同步',
                '按屏幕刷新率重采样，60/90/120Hz 上更顺滑'),
            _flagTile(PlayerEnhanceKeys.optInterpolation, '运动插帧',
                '帧间插值补偿，低帧率片源更连贯（开启时自动启用显示同步）'),
            _flagTile(PlayerEnhanceKeys.optLowPowerDecode, '低功耗解码',
                '快速解码并跳过环路滤波，弱机型/省电'),
            _flagTile(PlayerEnhanceKeys.optPrebuffer, '起播预缓冲',
                '先缓冲约 1 秒再起播，减少开局卡顿'),
            _flagTile(PlayerEnhanceKeys.optReconnect, '断线自动重连',
                '网络流中断后自动重连（最多等 5 秒）'),
            _flagTile(PlayerEnhanceKeys.optSeekableCache, '可拖动缓存',
                '已缓存区间内任意拖动不重新请求'),
            _flagTile(PlayerEnhanceKeys.optDeband, '去色带',
                '消除暗场渐变里的色带断层'),
            _flagTile(PlayerEnhanceKeys.optSharpen, '画面锐化',
                '渲染级锐化，糊片源更清晰（耗性能）'),
            _flagTile(PlayerEnhanceKeys.optFullRange, '全范围色彩',
                '修正灰蒙蒙的有限范围输出'),
            _flagTile(PlayerEnhanceKeys.optHdrToneMap, 'HDR 色调映射',
                'HDR 片源在普通屏幕上不过曝'),
            _flagTile(PlayerEnhanceKeys.optDownmix, '多声道下混',
                '5.1/7.1 正确下混为立体声，人声不丢'),
            _flagTile(PlayerEnhanceKeys.optBlendSubs, '字幕融合渲染',
                '字幕随视频一起缩放，全屏更锐利'),
            _flagTile(PlayerEnhanceKeys.optFrameDrop, '弱机丢帧保流畅',
                '解码跟不上时丢帧而不是卡住'),
            _flagTile(PlayerEnhanceKeys.optVideoQueue, '视频解码队列',
                '加深解码队列，码率突变不抖'),
            _flagTile(PlayerEnhanceKeys.optAudioQueue, '音频解码队列',
                '加深音频队列，音画更稳'),
            _flagTile(PlayerEnhanceKeys.optNetTimeout, '网络超时放宽',
                '慢 CDN 给足 20 秒，不轻易判失败'),
            _flagTile(PlayerEnhanceKeys.optReadahead, '预读 30 秒',
                '提前解复用后续内容，拖动响应快'),
            _flagTile(PlayerEnhanceKeys.optSamplerate, '采样率锁定 48kHz',
                '避免采样率切换的爆音/重采样开销'),
            _flagTile(PlayerEnhanceKeys.optSwapchain, '三重交换链',
                '渲染队列加深，帧 pacing 更稳'),
            _flagTile(PlayerEnhanceKeys.optFboFormat, '高精度渲染目标',
                '16 位浮点帧缓冲，渐变与 HDR 更细腻'),
            _flagTile(PlayerEnhanceKeys.optHrSeek, '精确拖动',
                '逐帧定位而不是跳关键帧（稍慢）'),
          ]),
          SettingsSection(title: const Text('播放功能（12）'), tiles: [
            _chips(PlayerEnhanceKeys.featAspect, '画面比例', const [
              ('auto', '自动'),
              ('16:9', '16:9'),
              ('4:3', '4:3'),
              ('21:9', '21:9'),
              ('fill', '充满屏幕'),
            ]),
            _chips(PlayerEnhanceKeys.featRotate, '画面旋转', const [
              ('0', '0°'),
              ('90', '90°'),
              ('180', '180°'),
              ('270', '270°'),
            ]),
            _flagTile(PlayerEnhanceKeys.featMirror, '镜像翻转',
                '水平镜像画面（舞蹈跟练等场景）'),
            _flagTile(PlayerEnhanceKeys.featLoopEpisode, '单集循环',
                '本集播完自动从头重播'),
            _slider(
              PlayerEnhanceKeys.featAudioDelay,
              '音频延迟校准（蓝牙耳机对口型）',
              -1,
              1,
              40,
              (v) => '${(v * 1000).round()} ms',
            ),
            _slider(
              PlayerEnhanceKeys.featSubDelay,
              '字幕延迟校准',
              -1,
              1,
              40,
              (v) => '${(v * 1000).round()} ms',
            ),
            _chips(PlayerEnhanceKeys.featAudioTrack, '首选音轨', const [
              ('auto', '自动'),
              ('1', '音轨 1'),
              ('2', '音轨 2'),
              ('3', '音轨 3'),
            ]),
            _chips(PlayerEnhanceKeys.featSubTrack, '首选字幕', const [
              ('auto', '自动'),
              ('no', '关闭'),
              ('1', '字幕 1'),
              ('2', '字幕 2'),
              ('3', '字幕 3'),
            ]),
            _chips(PlayerEnhanceKeys.featSecondSubTrack, '双字幕（第二字幕）',
                const [
                  ('no', '关闭'),
                  ('1', '字幕 1'),
                  ('2', '字幕 2'),
                  ('3', '字幕 3'),
                ]),
            _chips(PlayerEnhanceKeys.featEqualizer, '均衡器预设', const [
              ('off', '关闭'),
              ('bass', '低音增强'),
              ('voice', '人声清晰'),
              ('treble', '高音明亮'),
            ]),
            _chips(PlayerEnhanceKeys.featChannelMode, '声道模式', const [
              ('normal', '正常'),
              ('mono', '单声道'),
            ]),
            _slider(
              PlayerEnhanceKeys.featBrightness,
              '亮度',
              -50,
              50,
              50,
              (v) => v.round().toString(),
            ),
            _slider(
              PlayerEnhanceKeys.featContrast,
              '对比度',
              -50,
              50,
              50,
              (v) => v.round().toString(),
            ),
            _slider(
              PlayerEnhanceKeys.featSaturation,
              '饱和度',
              -50,
              50,
              50,
              (v) => v.round().toString(),
            ),
          ]),
        ],
      ),
    );
  }
}
