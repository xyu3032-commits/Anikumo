import 'package:flutter/material.dart';

import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/widget/content_section.dart';
import 'package:anikumo/pages/about/about_widgets.dart';
import 'package:anikumo/request/config/api_endpoints.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.onCheckUpdate});

  final Future<bool> Function() onCheckUpdate;

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('关于'),
        body: AboutContent(
          children: [
            _ProjectHeader(onCheckUpdate: onCheckUpdate),
            const SizedBox(height: 24),
            // Batch 53: the old About page linked out to the
            // upstream project's site, repository and group.
            // anikumo is a standalone build; what remains is
            // what is genuinely local: credits for the
            // services it talks to and the third-party
            // licenses bundled with it.
            // Batch 60: the project's OWN official site and
            // open-source repository join the group (user
            // links, not upstream's).
            const ContentSection.group(
              title: '开源',
              children: [
                AboutLinkTile(
                  icon: Icons.language_rounded,
                  title: '官方网站',
                  subtitle: 'anikumo-brown.vercel.app',
                  url: 'https://anikumo-brown.vercel.app/',
                ),
                AboutLinkTile(
                  icon: Icons.code_rounded,
                  title: '开源仓库',
                  subtitle: 'GitHub · GPL-3.0',
                  url: 'https://github.com/xyu3032-commits/Anikumo',
                ),
                AboutLinkTile.route(
                  icon: Icons.favorite_outline_rounded,
                  title: '致谢',
                  route: '/settings/about/credits',
                ),
                AboutLinkTile.route(
                  icon: Icons.description_outlined,
                  title: '第三方许可证',
                  route: '/settings/about/license',
                ),
              ],
            ),
          ],
        ),
      );
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.onCheckUpdate});

  final Future<bool> Function() onCheckUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Anikumo',
              style: theme.textTheme.displayMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ApiEndpoints.version,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '基于自定义规则的开源番剧应用',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CheckUpdateButton(onCheckUpdate: onCheckUpdate),
            ],
          ),
        ],
      ),
    );
  }
}
