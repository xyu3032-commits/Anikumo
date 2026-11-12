import 'package:flutter/material.dart';

/// Batch 257: the plain-language explainer behind the
/// user center's 「同步怎么运作？有没有风险？」button —
/// how GitHub sync works, what it covers, and its real
/// limits and risks. Static text on purpose: what the
/// page promises is what the code does.
class SyncExplainerPage extends StatelessWidget {
  const SyncExplainerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    Widget body(String text) =>
        Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.55));
    return Scaffold(
      appBar: AppBar(title: const Text('同步的运作方式与风险')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          heading('它怎么运作'),
          body(
            '登录用的是 GitHub 的设备码方式：应用给你一串短码，'
            '你在浏览器打开 GitHub 输入这串码确认，应用就拿到一枚只属于你账号的令牌。'
            '全程不需要把 GitHub 密码告诉应用，应用里也不内置任何密钥。\n\n'
            '令牌只保存在这台设备的本地设置里。同步时，应用把一份和「本地备份」相同的'
            '数据文件（anikumo-backup.json）写到你选择或自动创建的仓库里；'
            '换设备时在新设备登录同一账号、选同一仓库，同步一次就能把数据恢复过来。',
          ),
          heading('先后规则（冲突怎么办）'),
          body(
            '每份备份都带导出时间。点「立即同步」时先看云端：云端那份的时间和这台设备'
            '上次同步的对不上，说明另一台设备更新过——这时先拉取云端那份覆盖本机'
            '（覆盖前会弹窗让你确认，本机未同步的改动会丢失，确认前请想清楚）；'
            '对得上就把本机最新数据推上去。上传时如果云端文件刚好被改动，会自动重试一次。',
          ),
          heading('同步范围'),
          body(
            '与本地备份一致：动漫的收藏与观看历史、漫画与小说的收藏和阅读进度、'
            '部分设置与已安装的源配置。不包含：下载好的视频、漫画章节等文件本身'
            '（太大，也不适合放仓库）；影视区的收藏与历史暂时还没有纳入备份范围。'
            '另外 GitHub 接口对单个文件有约 1MB 的上限，数据量特别大时同步会提示失败，'
            '可以改用本地备份页导出文件手动保存。',
          ),
          heading('有哪些风险'),
          body(
            '· 令牌等于你 GitHub 账号的仓库读写权。设备丢失或外借时，'
            '请到 GitHub 的设置 → 应用授权里撤销 Anikumo 的授权，令牌立即失效。\n'
            '· 数据文件存在 GitHub 的服务器上。自动创建的仓库是私有的，'
            '但请不要把仓库改成公开，也不要把令牌发给任何人。\n'
            '· GitHub 在部分网络环境下连接不稳定，同步可能失败或很慢；'
            '失败不影响本机使用，数据都在本地，联网正常时再同步即可。\n'
            '· 两台设备交替使用时，请尽量在一台上同步完成后再换另一台，'
            '避免旧的那份盖掉新的。',
          ),
          heading('断开与删除'),
          body(
            '在个人信息里「断开连接」只删除这台设备上的令牌，云端仓库和文件还在你的账号里。'
            '想连云端数据一起删掉，去 GitHub 把仓库里的 anikumo-backup.json 删除、'
            '或直接删除整个同步仓库即可，本机数据不受任何影响。',
          ),
        ],
      ),
    );
  }
}
