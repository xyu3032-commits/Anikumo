import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/services/manga/local_manga_source.dart';
import 'package:anikumo/services/manga/manga_cabinets.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 122: the 书柜 tab — a dedicated home for the user's
/// own imported (CBZ/ZIP) manga, organized into cabinets the
/// user can name and add. Imported books used to exist only
/// as an anonymous local source in the registry; here every
/// book is visible in its cabinet, movable by long-press.
class MangaCabinetsTab extends StatefulWidget {
  const MangaCabinetsTab({super.key});

  @override
  State<MangaCabinetsTab> createState() => _MangaCabinetsTabState();
}

class _MangaCabinetsTabState extends State<MangaCabinetsTab> {
  @override
  void initState() {
    super.initState();
    MangaCabinets.revision.addListener(_refresh);
    MangaSources.revision.addListener(_refresh);
    LocalMangaLibrary.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    MangaCabinets.revision.removeListener(_refresh);
    MangaSources.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
    await MangaCabinets.create(name);
    if (mounted) {
      AnikumoDialog.showToast(message: '已创建柜子');
    }
  }

  Future<void> _renameCabinet(MangaCabinet cabinet) async {
    final name = await _nameDialog(
      title: '重命名柜子',
      initial: cabinet.name,
      confirmLabel: '保存',
    );
    if (name == null) return;
    await MangaCabinets.rename(cabinet.id, name);
  }

  Future<void> _deleteCabinet(MangaCabinet cabinet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除柜子'),
        content: Text('确定要删除《${cabinet.name}》吗？柜子里的漫画会回到默认柜子，不会被删除。'),
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
    await MangaCabinets.delete(cabinet.id);
  }

  Future<void> _moveBook(LocalBook book) async {
    final current = MangaCabinets.cabinetIdOf(book.id);
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
            for (final cabinet in MangaCabinets.cabinets())
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
    await MangaCabinets.assign(book.id, target);
    if (mounted) {
      AnikumoDialog.showToast(message: '已移动');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = LocalMangaLibrary.cachedBooks;
    final cabinets = MangaCabinets.cabinets();
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
                  '我导入的漫画',
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
            const Text('还没有导入本地漫画'),
            const SizedBox(height: 8),
            Text(
              '在漫画源管理里导入 CBZ / ZIP 文件后，\n漫画会自动放进这里的默认柜子，你也可以新建柜子分类放好。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.pushNamed('/manga/sources'),
              child: const Text('去导入'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    MangaCabinet cabinet,
    List<LocalBook> allBooks,
  ) {
    final theme = Theme.of(context);
    final books = MangaCabinets.booksIn(cabinet.id, allBooks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 10),
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
              if (cabinet.id != MangaCabinets.defaultId)
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
              '这个柜子还是空的 — 长按任意一本漫画可以把它移动到这里。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
              childAspectRatio: 0.58,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) => _BookCard(
              book: books[index],
              onTap: () => context.pushNamed(
                '/manga/detail',
                arguments: books[index].toItem(),
              ),
              onLongPress: () => _moveBook(books[index]),
            ),
          ),
      ],
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.onTap,
    required this.onLongPress,
  });

  final LocalBook book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(book.coverPath),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Center(
                    child: Icon(AnikumoIcons.menu_book_rounded, size: 36),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            '${book.pages} 页 · 长按移动',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
