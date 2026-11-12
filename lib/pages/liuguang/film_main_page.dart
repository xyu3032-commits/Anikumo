import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/bean/widget/channel_glyphs.dart';
import 'package:anikumo/bean/widget/zone_switcher.dart';
import 'package:anikumo/pages/profile/user_center.dart';
import 'package:anikumo/pages/liuguang/film_discover_tab.dart';
import 'package:anikumo/pages/liuguang/film_favorites_tab.dart';
import 'package:anikumo/pages/liuguang/film_home_tab.dart';
import 'package:anikumo/pages/liuguang/film_settings_tab.dart';
import 'package:anikumo/pages/liuguang/film_sources_tab.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/liuguang/film_auto_update.dart';
import 'package:anikumo/services/liuguang/film_probes.dart';

/// Batch 203: the 影视专区 shell with five tabs:
/// 首页 / 发现 / 收藏 / 源 / 设置.
///
/// Batch 221 (user: 「重构影视区UI要跟动漫区一样但是又不是
/// 完全一样，功能都要留着」): the shell now speaks the
/// anime zone's editorial language — the same masthead
/// (logo, wordmark, zone chip, search) over a numbered
/// channel rail with an animated underline, and no stock
/// bottom bar. What keeps it the film zone's own: the
/// rail's numbers and underline wear the zone's amber
/// accent, the channels are the film zone's five
/// （精选 / 发现 / 收藏 / 片源 / 设置）, and every tab's
/// content and function is unchanged.
class FilmMainPage extends StatefulWidget {
  const FilmMainPage({super.key});

  @override
  State<FilmMainPage> createState() => _FilmMainPageState();
}

class _FilmMainPageState extends State<FilmMainPage> {
  int _index = 0;

  static const _tabs = <Widget>[
    FilmHomeTab(),
    FilmDiscoverTab(),
    FilmFavoritesTab(),
    FilmSourcesTab(),
    FilmSettingsTab(),
  ];

  /// Channel rail entries: label + the channel glyph pair
  /// (outline / filled), numbered like the anime shell's.
  static const _channels = <(String, String, String)>[
    ('精选', ChannelGlyphs.featuredOutline, ChannelGlyphs.featuredFilled),
    ('发现', ChannelGlyphs.discoverOutline, ChannelGlyphs.discoverFilled),
    ('收藏', ChannelGlyphs.followingOutline, ChannelGlyphs.followingFilled),
    ('片源', ChannelGlyphs.scheduleOutline, ChannelGlyphs.scheduleFilled),
    ('设置', ChannelGlyphs.mineOutline, ChannelGlyphs.mineFilled),
  ];

  @override
  void initState() {
    super.initState();
    VideoEngineService.instance.loadRegistry();
    // Warm the engine in the background so the first search
    // or detail open doesn't pay the boot cost.
    VideoEngineService.instance.engine().ignore();
    // Batch 232 （追剧自动更新 pack): entering the zone
    // runs the throttled favorites check in the
    // background; findings wait on the favorites tab.
    FilmAutoUpdate.maybeCheck().ignore();
    // Batch 249: refresh stale source-speed records in
    // the background so the 自动 order rides fresh
    // numbers; fresh records (24 h) are not re-probed
    // and nothing here blocks first paint.
    FilmSpeedAutoProbe.maybeProbe().ignore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _masthead(context),
          Expanded(
            child: IndexedStack(index: _index, children: _tabs),
          ),
        ],
      ),
    );
  }

  Widget _masthead(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 2),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset(
                      'assets/images/logo/logo_rounded.png',
                      width: 27,
                      height: 27,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Anikumo',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const ZoneWheelChip(current: AppZone.video, english: true),
                  const Spacer(),
                  IconButton(
                    tooltip: '搜索',
                    onPressed: () => context.pushNamed('/film/search'),
                    icon: const Icon(AnikumoIcons.search_rounded),
                  ),
                  // Batch 257: user-center entry.
                  const UserCenterAvatarButton(),
                ],
              ),
            ),
            _channelRail(context),
          ],
        ),
      ),
    );
  }

  /// The numbered channel rail, mirrored from the anime
  /// shell — number + glyph over the label, with an
  /// animated underline on the active channel. The film
  /// zone's mark: numbers and underline in the zone accent.
  Widget _channelRail(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = zoneAccent(AppZone.video, scheme);
    // Batch 222: the five channels divide the full width
    // evenly (Expanded cells) — the content-hugging items
    // read as cramped narrow buttons.
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          for (var index = 0; index < _channels.length; index++)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _index = index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (index + 1).toString().padLeft(2, '0'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: index == _index ? accent : scheme.outline,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 5),
                        ChannelGlyph(
                          svg: index == _index
                              ? _channels[index].$3
                              : _channels[index].$2,
                          size: 15,
                          color: index == _index
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _channels[index].$1,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: index == _index
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: index == _index
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      height: 3,
                      width: index == _index ? 36 : 0,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
