import 'package:flutter/material.dart';

import 'package:anikumo/services/novel/novel_source.dart';

/// Batch 191: the expanded panel under a novel source's
/// row in source management — the source's link, group
/// and declared comment, plus the entry to its login /
/// settings form (the login page renders the fields the
/// source declares; that form is this format's settings
/// surface).
class NovelSourceInfoPanel extends StatelessWidget {
  const NovelSourceInfoPanel({
    super.key,
    required this.source,
    required this.isActive,
    required this.onActivate,
    required this.onOpenLogin,
  });

  final LegadoNovelSource source;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onOpenLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = source.def;
    final comment = def.raw['bookSourceComment']?.toString().trim() ?? '';
    final hasLoginForm = def.raw['loginUi'] != null &&
        def.raw['loginUi'].toString().trim().isNotEmpty;
    final hasLogin = source.loginUrl.isNotEmpty || hasLoginForm;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '源链接：${def.url}',
            style: theme.textTheme.bodySmall,
          ),
          if (def.group.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('分组：${def.group}', style: theme.textTheme.bodySmall),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(comment, style: theme.textTheme.bodySmall),
          ],
          if (source.loginUrl.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              '登录页：${source.loginUrl}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          Row(
            children: [
              if (!isActive)
                TextButton(
                  onPressed: onActivate,
                  child: const Text('设为当前源'),
                ),
              if (hasLogin)
                TextButton(
                  onPressed: onOpenLogin,
                  child: const Text('打开源登录/设置'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
