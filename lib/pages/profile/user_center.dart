import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/profile/github_sync.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batch 257: the user-center entry — one avatar button
/// in every zone's top-right corner, opening a small
/// menu （个人信息 / 设置 / 立即同步 / 本地备份与恢复）.
/// The avatar is the connected GitHub account's picture
/// when there is one; the profile page behind 个人信息
/// hosts sign-in, the display name and the linked
/// accounts.

class UserCenterAvatarButton extends StatelessWidget {
  const UserCenterAvatarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final avatar = GithubSync.avatarUrl;
    return IconButton(
      tooltip: '用户中心',
      onPressed: () => showUserCenterMenu(context),
      icon: avatar.isEmpty
          ? const Icon(AnikumoIcons.account_circle_outlined)
          : ClipOval(
              child: Image.network(
                avatar,
                width: 26,
                height: 26,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(AnikumoIcons.account_circle_outlined),
              ),
            ),
    );
  }
}

/// Runs one GitHub sync with the pull-confirmation
/// dialog and result toasts. Shared by the user-center
/// menu and the profile page.
Future<void> runGithubSync(BuildContext context) async {
  if (!GithubSync.connected) {
    AnikumoDialog.showToast(context: context, message: '请先在个人信息里登录 GitHub');
    return;
  }
  if (GithubSync.syncRepo.isEmpty) {
    AnikumoDialog.showToast(context: context, message: '请先在个人信息里选择或创建同步仓库');
    return;
  }
  try {
    final outcome = await GithubSync.syncNow(
      confirmPull: (remoteAt) async {
        if (!context.mounted) return false;
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('云端数据较新'),
            content: Text(
              '云端仓库里的备份（${remoteAt.toLocal()}）与这台设备上次同步的版本不同。'
              '继续将用云端数据覆盖本机的收藏、历史与进度，本机未同步的改动会丢失。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('先不拉取'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('拉取并覆盖'),
              ),
            ],
          ),
        );
        return ok ?? false;
      },
    );
    if (context.mounted) {
      AnikumoDialog.showToast(context: context, message: outcome);
    }
  } on GithubSyncException catch (e) {
    if (context.mounted) {
      AnikumoDialog.showToast(context: context, message: e.message);
    }
  } catch (e) {
    if (context.mounted) {
      AnikumoDialog.showToast(context: context, message: '同步失败：$e');
    }
  }
}

void showUserCenterMenu(BuildContext context) {
  final displayName = GStorage.getSetting(SettingsKeys.profileDisplayName);
  final ghName = GithubSync.username;
  final lastSync = GithubSync.lastSyncAt;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      void go(String route) {
        Navigator.of(sheetContext).pop();
        context.pushNamed(route);
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AnikumoIcons.account_circle_outlined),
              title: Text(
                displayName.isNotEmpty
                    ? displayName
                    : (ghName.isNotEmpty ? ghName : '用户中心'),
              ),
              subtitle: Text(
                ghName.isNotEmpty
                    ? 'GitHub @$ghName${lastSync.isNotEmpty ? ' · 上次同步 ${lastSync.substring(0, 16).replaceFirst('T', ' ')}' : ''}'
                    : '尚未登录 GitHub',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(AnikumoIcons.person_outline_rounded),
              title: const Text('个人信息'),
              onTap: () => go('/profile'),
            ),
            ListTile(
              leading: const Icon(AnikumoIcons.settings_rounded),
              title: const Text('设置'),
              onTap: () => go('/settings'),
            ),
            ListTile(
              leading: const Icon(AnikumoIcons.sync_rounded),
              title: const Text('立即同步'),
              subtitle: const Text('与 GitHub 仓库对账：远端较新先拉取，否则推送本机'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                runGithubSync(context);
              },
            ),
            ListTile(
              leading: const Icon(AnikumoIcons.backup_outlined),
              title: const Text('本地备份与恢复'),
              onTap: () => go('/settings/toolbox/backup'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => go('/profile/about-sync'),
                child: const Text('同步怎么运作？有没有风险？'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
