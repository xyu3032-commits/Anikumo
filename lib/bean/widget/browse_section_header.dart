import 'package:flutter/material.dart';
import 'package:anikumo/bean/theme/signature.dart';
import 'package:anikumo/utils/constants.dart';

/// Section header for browse pages （精选/发现）.
///
/// One visual language for every section on the new browse surfaces:
/// a title in the app's own type scale, an optional one-line subtitle,
/// and an optional trailing text action (e.g. 换一批）. Spacing comes
/// from [StyleString] tokens so sections align across pages.
class BrowseSectionHeader extends StatelessWidget {
  const BrowseSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        StyleString.pagePadding,
        0,
        StyleString.pagePadding,
        StyleString.sectionHeaderSpace,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SectionAccentBar(height: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
