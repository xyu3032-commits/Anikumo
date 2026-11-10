import 'package:flutter/material.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/services/ui/glass_style.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// 玻璃效果 (hub 区三）: one intensity switch for every frosted surface
/// in the app — bottom navigation bar, hub panels, stat tiles. Changes
/// apply live; there is no restart and no hidden "apply" step.
class GlassSettingsPage extends StatefulWidget {
  const GlassSettingsPage({super.key});

  @override
  State<GlassSettingsPage> createState() => _GlassSettingsPageState();
}

class _GlassSettingsPageState extends State<GlassSettingsPage> {
  static const _options = <(int, String, String)>[
    (GlassStyle.levelOff, '关闭', '所有面板恢复不透明，刊头与导航改为实色'),
    (GlassStyle.levelLight, '轻盈', '半透明面板 + 高透光，日常推荐'),
    (GlassStyle.levelStrong, '强效', '更通透的半透明感，适合纯色壁纸式背景'),
  ];

  @override
  Widget build(BuildContext context) {
    final level = GlassStyle.level;
    return Scaffold(
      appBar: const SysAppBar(title: Text('玻璃效果')),
      body: ListView(
        padding: const EdgeInsets.all(StyleString.pagePadding),
        children: [
          _Preview(),
          const SizedBox(height: StyleString.sectionSpace),
          RadioGroup<int>(
            groupValue: level,
            onChanged: (next) async {
              if (next == null) return;
              await GlassStyle.setLevel(next);
              if (mounted) setState(() {});
            },
            child: Column(
              children: [
                for (final (value, title, subtitle) in _options)
                  RadioListTile<int>(
                    value: value,
                    title: Text(title),
                    subtitle: Text(subtitle),
                    shape: RoundedRectangleBorder(
                      borderRadius: StyleString.lgRadius,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: StyleString.sectionSpace),
          Text(
            '生效范围：底部导航栏、发现页三大区的面板、观看统计的玻璃卡片等。'
            '调低或关闭可以减少老设备上的滑动开销。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// A busy backdrop (icons + text) under a strong glass surface, so the
/// blur change is visible while sliding between levels.
class _Preview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: StyleString.xlRadius,
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final icon in const [
                      AnikumoIcons.movie_rounded,
                      AnikumoIcons.music_note_rounded,
                      AnikumoIcons.star_rounded,
                      AnikumoIcons.favorite_rounded,
                      AnikumoIcons.explore_rounded,
                      AnikumoIcons.schedule_rounded,
                      AnikumoIcons.bookmark_rounded,
                      AnikumoIcons.play_circle_fill_rounded,
                      AnikumoIcons.local_fire_department_rounded,
                      AnikumoIcons.emoji_events_rounded,
                      AnikumoIcons.coffee_rounded,
                      AnikumoIcons.pets_rounded,
                    ])
                      Icon(icon, size: 40, color: scheme.primary),
                  ],
                ),
              ),
            ),
            Center(
              child: GlassSurface(
                strong: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(AnikumoIcons.blur_on_rounded),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '玻璃预览',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '切换下面的档位，看通透程度变化',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
