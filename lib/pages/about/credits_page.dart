import 'package:flutter/material.dart';

import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/widget/content_section.dart';
import 'package:anikumo/pages/about/about_widgets.dart';
import 'package:anikumo/request/config/api_endpoints.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('致谢'),
        body: AboutContent(
          children: [
            ContentSection.group(
              title: '服务',
              children: const [
                AboutLinkTile(
                  icon: AnikumoIcons.menu_book_rounded,
                  title: 'Bangumi',
                  subtitle: '番剧信息',
                  url: ApiEndpoints.bangumiIndex,
                ),
                AboutLinkTile(
                  icon: AnikumoIcons.subtitles_rounded,
                  title: '弹弹play',
                  subtitle: '弹幕',
                  url: ApiEndpoints.dandanIndex,
                ),
                AboutLinkTile(
                  icon: AnikumoIcons.image_rounded,
                  title: 'TMDB',
                  subtitle: '剧集图片与资料',
                  url: 'https://www.themoviedb.org',
                ),
              ],
            ),
            const SizedBox(height: 24),
            ContentSection.group(
              title: '开源项目',
              children: const [
                AboutLinkTile(
                  icon: AnikumoIcons.flutter_dash_rounded,
                  title: 'Flutter',
                  subtitle: '应用框架',
                  url: 'https://flutter.dev',
                ),
                AboutLinkTile(
                  icon: AnikumoIcons.javascript_rounded,
                  title: 'QuickJS-NG',
                  subtitle: 'JavaScript 引擎',
                  url: 'https://github.com/quickjs-ng/quickjs-ng',
                ),
                AboutLinkTile(
                  icon: AnikumoIcons.code_rounded,
                  title: 'QuickJS',
                  subtitle: 'JavaScript 引擎',
                  url: 'https://github.com/bellard/quickjs',
                ),
                AboutLinkTile(
                  icon: AnikumoIcons.play_circle_outline_rounded,
                  title: 'media-kit',
                  subtitle: '视频播放',
                  url: 'https://github.com/media-kit/media-kit',
                ),
                AboutLinkTile(
                  icon: AnikumoIcons.auto_awesome_rounded,
                  title: 'Anime4K',
                  subtitle: '实时超分辨率',
                  url: 'https://github.com/bloc97/Anime4K',
                ),
                AboutLinkTile(
                  icon: AnikumoIcons.sync_rounded,
                  title: 'Syncplay',
                  subtitle: '播放同步',
                  url: 'https://github.com/Syncplay/syncplay',
                ),
                AboutLinkTile(
                  icon: AnikumoIcons.account_tree_rounded,
                  title: 'XpathSelector',
                  subtitle: 'XPath 解析',
                  url: 'https://github.com/simonkimi/xpath_selector',
                ),
                AboutLinkTile(
                  icon: AnikumoIcons.video_settings_rounded,
                  title: 'avbuild',
                  subtitle: '非标准视频流支持',
                  url: 'https://github.com/wang-bin/avbuild',
                ),
                AboutLinkTile(
                  icon: AnikumoIcons.storage_rounded,
                  title: 'Hive CE',
                  subtitle: '本地存储',
                  url: 'https://github.com/IO-Design-Team/hive_ce',
                ),
              ],
            ),
          ],
        ),
      );
}
