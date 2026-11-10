import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/widget/editorial_kit.dart';
import 'package:anikumo/pages/discover/command_palette.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// 工具箱 (batch 37: its own shell tab, split out of the
/// discover page). Batch 55: at the user's request it now
/// lives inside Settings — same seven rows in the same
/// numbered editorial index style, presented as a settings
/// detail page; its three own sub-pages (card style, glass,
/// backup) moved along to /settings/toolbox/*.
class ToolboxPage extends StatelessWidget {
  const ToolboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('工具箱'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          EditorialIndexRow(
            index: '01',
            icon: AnikumoIcons.terminal_rounded,
            title: '命令面板',
            subtitle: '输入关键词，直达任意功能',
            onTap: () => showCommandPalette(context),
          ),
          const EditorialHairline(),
          EditorialIndexRow(
            index: '02',
            icon: AnikumoIcons.style_outlined,
            title: '卡片样式',
            subtitle: '五种番剧卡片外观，全局生效',
            onTap: () => context.pushNamed('/settings/toolbox/card-style'),
          ),
          const EditorialHairline(),
          EditorialIndexRow(
            index: '03',
            icon: AnikumoIcons.blur_on_rounded,
            title: '玻璃效果',
            subtitle: '刊头与面板的半透明强度',
            onTap: () => context.pushNamed('/settings/toolbox/glass'),
          ),
          const EditorialHairline(),
          EditorialIndexRow(
            index: '04',
            icon: AnikumoIcons.backup_outlined,
            title: '本地备份与恢复',
            subtitle: '历史、收藏、榜单导出为一个文件',
            onTap: () => context.pushNamed('/settings/toolbox/backup'),
          ),
          const EditorialHairline(),
          EditorialIndexRow(
            index: '05',
            icon: AnikumoIcons.block_rounded,
            title: '弹幕屏蔽',
            subtitle: '关键词与规则屏蔽',
            onTap: () => context.pushNamed('/settings/danmaku/shield'),
          ),
          const EditorialHairline(),
          EditorialIndexRow(
            index: '06',
            icon: AnikumoIcons.extension_outlined,
            title: '规则管理',
            subtitle: '视频源规则的导入与编辑',
            onTap: () => context.pushNamed('/settings/plugin/'),
          ),
          const EditorialHairline(),
          EditorialIndexRow(
            index: '07',
            icon: AnikumoIcons.download_outlined,
            title: '下载设置',
            subtitle: '下载目录与并发选项',
            onTap: () => context.pushNamed('/settings/download/'),
          ),
        ],
      ),
    );
  }
}
