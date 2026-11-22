import 'package:flutter/material.dart';

import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/notifications/notification_inbox.dart';

String _stamp(DateTime time) {
  String pad(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${pad(time.month)}-${pad(time.day)} '
      '${pad(time.hour)}:${pad(time.minute)}';
}

String _categoryLabel(String category) => switch (category) {
      'anime' => S.t('追番更新'),
      'novel' => S.t('小说更新'),
      'film' => S.t('追剧更新'),
      'sync' => S.t('自动同步'),
      _ => S.t('通知'),
    };

/// Batch 282 (#20): the in-app notification center.
/// Every system notification the update checker posts
/// lands here too (see [NotificationInbox]), so a ping
/// survives the notification shade being cleared.
class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  State<NotificationCenterPage> createState() =>
      _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  late List<NotificationInboxEntry> _entries = NotificationInbox.entries();

  void _reload() {
    if (mounted) {
      setState(() => _entries = NotificationInbox.entries());
    }
  }

  Future<void> _open(int index) async {
    await NotificationInbox.markRead(index);
    _reload();
  }

  Future<void> _markAllRead() async {
    await NotificationInbox.markAllReadNow();
    _reload();
  }

  Future<void> _clear() async {
    await NotificationInbox.clear();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = NotificationInbox.unreadOf(_entries);
    return SettingsDetailScaffold(
      title: Text(S.t('通知中心')),
      actions: [
        if (unread > 0)
          TextButton(
            onPressed: _markAllRead,
            child: Text(S.t('全部已读')),
          ),
        if (_entries.isNotEmpty)
          TextButton(
            onPressed: _clear,
            child: Text(S.t('清空')),
          ),
      ],
      body: _entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  S.t('暂无通知'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return ListTile(
                  leading: Icon(
                    AnikumoIcons.inbox_rounded,
                    color: entry.read ? scheme.outline : scheme.primary,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: entry.read
                                ? FontWeight.normal
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!entry.read)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.body.isNotEmpty) Text(entry.body),
                      const SizedBox(height: 2),
                      Text(
                        '${_categoryLabel(entry.category)} · '
                        '${_stamp(DateTime.fromMillisecondsSinceEpoch(entry.atMs))}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  onTap: () => _open(index),
                );
              },
            ),
    );
  }
}
