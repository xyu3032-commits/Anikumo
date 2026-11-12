import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_account_section.dart';
import 'package:anikumo/pages/profile/github_login_page.dart';
import 'package:anikumo/pages/profile/user_center.dart';
import 'package:anikumo/services/profile/github_sync.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 257: 个人信息 — the user center's home. A local
/// display name (editable), the GitHub connection that
/// powers cross-device sync (device-code sign-in, repo
/// choice or auto-create, manual sync), and the linked
/// TMDB / Bangumi accounts (the film zone's account
/// section, hosted here as-is).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _repoBusy = false;

  String get _displayName =>
      GStorage.getSetting(SettingsKeys.profileDisplayName);

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(text: _displayName);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('显示名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(hintText: '只在这台设备上显示的名字'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await GStorage.putSetting(
        SettingsKeys.profileDisplayName,
        controller.text.trim(),
      );
      if (mounted) setState(() {});
    }
    controller.dispose();
  }

  Future<void> _loginGithub() async {
    // Batch 258: the in-app login page (code banner +
    // embedded GitHub page) replaces the dialog that
    // sent users to an external browser.
    final ok = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const GithubLoginPage()));
    if (mounted && ok == true) setState(() {});
  }

  Future<void> _disconnectGithub() async {
    await GithubSync.disconnect();
    if (mounted) setState(() {});
  }

  Future<void> _createRepo() async {
    setState(() => _repoBusy = true);
    try {
      final fullName = await GithubSync.createSyncRepo();
      await GithubSync.chooseRepo(fullName);
      if (mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: '同步仓库已就绪：$fullName（私有）',
        );
      }
    } on GithubSyncException catch (e) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: e.message);
      }
    } finally {
      if (mounted) setState(() => _repoBusy = false);
    }
  }

  Future<void> _pickRepo() async {
    setState(() => _repoBusy = true);
    try {
      final repos = await GithubSync.listOwnRepos();
      if (!mounted) return;
      if (repos.isEmpty) {
        AnikumoDialog.showToast(
          context: context,
          message: '这个账号下还没有仓库，可以用「自动创建」建一个',
        );
        return;
      }
      final picked = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('选择同步仓库'),
          children: [
            for (final repo in repos)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(repo.fullName),
                child: Row(
                  children: [
                    Expanded(child: Text(repo.fullName)),
                    Text(
                      repo.isPrivate ? '私有' : '公开',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
      if (picked != null) {
        await GithubSync.chooseRepo(picked);
        if (mounted) setState(() {});
      }
    } on GithubSyncException catch (e) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: e.message);
      }
    } finally {
      if (mounted) setState(() => _repoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ghName = GithubSync.username;
    final avatar = GithubSync.avatarUrl;
    final repo = GithubSync.syncRepo;
    final lastSync = GithubSync.lastSyncAt;
    return Scaffold(
      appBar: AppBar(title: const Text('个人信息')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: avatar.isNotEmpty
                    ? NetworkImage(avatar)
                    : null,
                child: avatar.isEmpty
                    ? const Icon(AnikumoIcons.account_circle_outlined, size: 34)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName.isNotEmpty
                          ? _displayName
                          : (ghName.isNotEmpty ? ghName : '还没有名字'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      ghName.isNotEmpty ? 'GitHub @$ghName' : 'GitHub 未连接',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _editDisplayName,
                child: const Text('改显示名'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(),
          Text(
            'GitHub 同步',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          if (!GithubSync.configured)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(AnikumoIcons.info_outline_rounded),
              title: Text('当前版本未配置 GitHub 登录'),
              subtitle: Text('其余功能（显示名、关联账户）不受影响。'),
            )
          else if (!GithubSync.connected)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AnikumoIcons.account_circle_outlined),
              title: const Text('使用 GitHub 登录'),
              subtitle: const Text('用设备码授权，登录后可把数据同步到你自己的仓库'),
              trailing: FilledButton(
                onPressed: _loginGithub,
                child: const Text('登录'),
              ),
            )
          else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AnikumoIcons.check_circle_outline_rounded),
              title: Text('已连接 @$ghName'),
              subtitle: Text(
                lastSync.isNotEmpty
                    ? '上次同步 ${lastSync.substring(0, 16).replaceFirst('T', ' ')}'
                    : '还没有同步过',
              ),
              trailing: TextButton(
                onPressed: _disconnectGithub,
                child: const Text('断开'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AnikumoIcons.account_tree_rounded),
              title: Text(repo.isNotEmpty ? repo : '还没有选择同步仓库'),
              subtitle: const Text('数据文件 anikumo-backup.json 存放在这个仓库里'),
            ),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _repoBusy ? null : _pickRepo,
                  child: const Text('选择仓库'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _repoBusy ? null : _createRepo,
                  child: const Text('自动创建'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () => runGithubSync(context).then((_) {
                    if (mounted) setState(() {});
                  }),
                  child: const Text('立即同步'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.pushNamed('/profile/about-sync'),
              icon: const Icon(AnikumoIcons.info_outline_rounded, size: 18),
              label: const Text('同步怎么运作？有没有风险？'),
            ),
          ),
          const Divider(),
          const FilmAccountSection(),
        ],
      ),
    );
  }
}
