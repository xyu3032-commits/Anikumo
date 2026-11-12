import 'package:flutter/material.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/pages/novel/novel_widgets.dart';
import 'package:anikumo/services/novel/novel_cabinets.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 124: the novel 书柜 tab — the novel-zone counterpart
/// of the manga cabinets. The user's collected and in-progress
/// novels live here, organized into cabinets they can name
/// and add; long-press a book to move it between cabinets.
class NovelCabinetsTab extends StatefulWidget {
  const NovelCabinetsTab({super.key});

  @override
  State<NovelCabinetsTab> createState() => _NovelCabinetsTabState();
}

class _NovelCabinetsTabState extends State<NovelCabinetsTab> {
  @override
  void initState() {
    super.initState();
    NovelCabinets.revision.addListener(_refresh);
    NovelLibraryStore.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    NovelCabinets.revision.removeListener(_refresh);
    NovelLibraryStore.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<NovelItem> _universe() {
    return NovelCabinets.universe(
      favorites: NovelLibraryStore.loadFavorites(),
      progressBooks: [
        for (final progress in NovelLibraryStore.loadProgressList())
          progress.item,
      ],
    );
  }

  Future<String?> _nameDialog({
    required String title,
    String initial = '',
    required String confirmLabel,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '柜子名称'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _createCabinet() async {
    final name = await _nameDialog(title: '新建柜子', confirmLabel: '创建');
    if (name == null) return;
    await NovelCabinets.create(name);
    if (mounted) {
      AnikumoDialog.showToast(message: '已创建柜子');
    }
  }

  Future<void> _renameCabinet(NovelCabinet cabinet) async {
    final name = await _nameDialog(
      title: '重命名柜子',
      initial: cabinet.name,
      confirmLabel: '保存',
    );
    if (name == null) return;
    await NovelCabinets.rename(cabinet.id, name);
  }

  Future<void> _deleteCabinet(NovelCabinet cabinet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除柜子'),
        content: Text('确定要删除《${cabinet.name}》吗？柜子里的小说会回到默认柜子，不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NovelCabinets.delete(cabinet.id);
  }

  Future<void> _moveBook(NovelItem book) async {
    final current = NovelCabinets.cabinetIdOf(book.storageKey);
    final target = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '把《${book.title}》移动到',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final cabinet in NovelCabinets.cabinets())
              ListTile(
                leading: Icon(
                  cabinet.id == current
                      ? AnikumoIcons.check_circle_rounded
                      : AnikumoIcons.library_books_outlined,
                ),
                title: Text(cabinet.name),
                onTap: () => Navigator.pop(sheetContext, cabinet.id),
              ),
          ],
        ),
      ),
    );
    if (target == null || target == current) return;
    await NovelCabinets.assign(book.storageKey, target);
    if (mounted) {
      AnikumoDialog.showToast(message: '已移动');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = _universe();
    final cabinets = NovelCabinets.cabinets();
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(
              children: [
                Text('书柜', style: theme.textTheme.headlineSmall),
                const SizedBox(width: 10),
                Text(
                  '我的小说',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _createCabinet,
                  icon: const Icon(AnikumoIcons.add_rounded, size: 18),
                  label: const Text('新建柜子'),
                ),
              ],
            ),
          ),
          Expanded(
            child: books.isEmpty
                ? _buildEmpty(context)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final cabinet in cabinets)
                        _buildSection(context, cabinet, books),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AnikumoIcons.library_books_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text('书柜还是空的'),
            const SizedBox(height: 8),
            Text(
              '收藏或开始阅读的小说会自动放进默认柜子，\n你也可以新建柜子，把书分类放好。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    NovelCabinet cabinet,
    List<NovelItem> allBooks,
  ) {
    final theme = Theme.of(context);
    final books = NovelCabinets.booksIn(cabinet.id, allBooks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
          child: Row(
            children: [
              Icon(
                AnikumoIcons.shelves,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                cabinet.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${books.length} 本',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (cabinet.id != NovelCabinets.defaultId)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') {
                      _renameCabinet(cabinet);
                    } else if (value == 'delete') {
                      _deleteCabinet(cabinet);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除柜子')),
                  ],
                ),
            ],
          ),
        ),
        if (books.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '这个柜子还是空的 — 长按任意一本小说可以把它移动到这里。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final book in books)
            ListTile(
              onTap: () => openNovelDetail(context, book),
              onLongPress: () => _moveBook(book),
              leading: NovelCover(url: book.coverUrl, width: 42, height: 56),
              title: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (book.author.isNotEmpty) book.author,
                  if (book.lastChapter.isNotEmpty) book.lastChapter,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(
                AnikumoIcons.chevron_right_rounded,
                size: 18,
              ),
            ),
      ],
    );
  }
}
