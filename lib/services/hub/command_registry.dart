/// One entry in the 命令面板 (command palette): a destination the
/// user can jump to by typing a few characters.
class HubCommand {
  const HubCommand({
    required this.title,
    required this.keywords,
    required this.route,
  });

  final String title;

  /// Extra match terms (pinyin-free: synonyms and feature words).
  final String keywords;

  final String route;
}

/// Every destination the palette knows about: hub pages first, then
/// the settings shortcuts.
const List<HubCommand> hubCommands = [
  HubCommand(title: '漫画专区', keywords: '漫画 看漫画 manga comic', route: '/manga/'),
  HubCommand(title: '小说专区', keywords: '小说 看小说 novel legado 书源', route: '/novel/'),
  HubCommand(title: '排行榜', keywords: '热门 排名 rank', route: '/tab/discover/rank/'),
  HubCommand(title: '今日上新', keywords: '今天 新番 更新 today', route: '/tab/discover/today/'),
  HubCommand(title: '每日推荐', keywords: '推荐 daily 今日推荐', route: '/tab/discover/daily/'),
  HubCommand(title: '更新中心', keywords: '追番更新 放送 日历', route: '/tab/discover/updates/'),
  HubCommand(title: '相似推荐', keywords: '相似 类似 找番 similar', route: '/tab/discover/similar/'),
  HubCommand(title: '即将开播', keywords: '想看 倒计时 未播 预告', route: '/tab/discover/coming/'),
  HubCommand(title: '随便看一部', keywords: '随机 纠结 选择困难 random', route: '/tab/discover/random/'),
  HubCommand(title: '我的榜单', keywords: '片单 自建 列表 list', route: '/tab/discover/my-lists/'),
  HubCommand(title: '观看统计', keywords: '数据 集数 时长 stats', route: '/tab/discover/watch-stats/'),
  HubCommand(title: '观看报告', keywords: '月报 月度 报告 热力图', route: '/tab/discover/report/'),
  HubCommand(title: '观看成就', keywords: '徽章 里程碑 成就 badge', route: '/tab/discover/achievements/'),
  HubCommand(title: '番剧笔记', keywords: '备注 笔记 note', route: '/tab/discover/notes/'),
  HubCommand(title: '玻璃效果', keywords: '毛玻璃 glass 模糊', route: '/settings/toolbox/glass/'),
  HubCommand(title: '卡片样式', keywords: '卡片 封面 样式 UI card', route: '/settings/toolbox/card-style/'),
  HubCommand(title: '本地备份与恢复', keywords: '备份 导出 导入 backup', route: '/settings/toolbox/backup/'),
  HubCommand(title: '番剧搜索', keywords: '搜索 找番 search', route: '/search/'),
  HubCommand(title: '弹幕屏蔽', keywords: '弹幕 屏蔽 关键词', route: '/settings/danmaku/shield'),
  HubCommand(title: '规则管理', keywords: '规则 源 插件 plugin', route: '/settings/plugin/'),
  HubCommand(title: '播放设置', keywords: '播放 倍速 缓冲 跳过 设置', route: '/settings/player/'),
  HubCommand(title: '下载设置', keywords: '下载 download', route: '/settings/download/'),
];

/// Pure matcher for the palette: case-insensitive substring matching
/// over title and keywords. Title hits rank above keyword hits, and a
/// title prefix hit ranks highest. An empty query returns everything
/// in registry order.
List<HubCommand> matchCommands(String query, [List<HubCommand> all = hubCommands]) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  final scored = <({HubCommand command, int score})>[];
  for (final command in all) {
    final title = command.title.toLowerCase();
    var score = 0;
    if (title.startsWith(q)) {
      score = 100;
    } else if (title.contains(q)) {
      score = 80;
    } else if (command.keywords.toLowerCase().contains(q)) {
      score = 50;
    }
    if (score > 0) {
      scored.add((command: command, score: score));
    }
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.map((entry) => entry.command).toList();
}
