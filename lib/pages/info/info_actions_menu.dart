import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/anikumo_menu.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/utils/device.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:url_launcher/url_launcher.dart';

class InfoActionsMenu extends StatefulWidget {
  const InfoActionsMenu({super.key, required this.bangumiItem});

  final BangumiItem bangumiItem;

  @override
  State<InfoActionsMenu> createState() => _InfoActionsMenuState();
}

class _InfoActionsMenuState extends State<InfoActionsMenu> {
  bool _savingCover = false;

  String get _title => widget.bangumiItem.nameCn.trim().isEmpty
      ? widget.bangumiItem.name
      : widget.bangumiItem.nameCn;

  void _notify(String message) {
    if (mounted) AnikumoDialog.showToast(context: context, message: message);
  }

  Future<void> _copyTitle() async {
    try {
      await Clipboard.setData(ClipboardData(text: _title));
      _notify('标题已复制');
    } catch (error) {
      AnikumoLogger().w('InfoActionsMenu: failed to copy title', error: error);
      _notify('复制失败，请重试');
    }
  }

  Future<void> _openExternally() async {
    try {
      if (await launchUrl(
        Uri.https('bangumi.tv', '/subject/${widget.bangumiItem.id}'),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (error) {
      AnikumoLogger().w('InfoActionsMenu: failed to open browser', error: error);
    }
    _notify('无法打开浏览器');
  }

  Future<void> _saveCover() async {
    if (_savingCover) return;
    final item = widget.bangumiItem;
    final imageUrl = ['large', 'common', 'medium', 'small', 'grid']
        .map((size) => item.images[size]?.trim() ?? '')
        .firstWhere((url) => url.isNotEmpty, orElse: () => '');
    if (imageUrl.isEmpty) {
      _notify('暂无封面');
      return;
    }
    final fileName = _coverFileName(_title, item.id);
    setState(() => _savingCover = true);
    try {
      final bytes = await _loadCoverPng(imageUrl);
      if (!mounted) return;

      if (isDesktop()) {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '保存封面',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['png'],
          bytes: bytes,
          lockParentWindow: true,
        );
        if (path != null) _notify('封面已保存');
        return;
      }

      final result = await SaverGallery.saveImage(
        bytes,
        fileName: fileName,
        skipIfExists: false,
      );
      if (!result.isSuccess) {
        throw StateError(result.errorMessage ?? 'Gallery save failed');
      }
      _notify('已保存到相册');
    } catch (error) {
      AnikumoLogger().w('InfoActionsMenu: failed to save cover', error: error);
      _notify('封面保存失败，请重试');
    } finally {
      if (mounted) setState(() => _savingCover = false);
    }
  }

  Future<void> _addToList() async {
    final lists = UserListsStore.load();
    if (lists.isEmpty) {
      _notify('还没有榜单，先在发现页「我的榜单」里建一个');
      return;
    }
    final picked = await AnikumoDialog.show<UserList>(
      builder: (dialogContext) => SimpleDialog(
        title: const Text('加入榜单'),
        children: [
          for (final list in lists)
            SimpleDialogOption(
              onPressed: () =>
                  AnikumoDialog.dismiss(context: dialogContext, popWith: list),
              child: Text(list.name),
            ),
        ],
      ),
    );
    if (picked == null) return;
    if (picked.bangumiIds.contains(widget.bangumiItem.id)) {
      _notify('这部番已经在「${picked.name}」里了');
      return;
    }
    picked.bangumiIds.add(widget.bangumiItem.id);
    final all = UserListsStore.load();
    final index = all.indexWhere((entry) => entry.id == picked.id);
    if (index >= 0) {
      all[index] = picked;
      await UserListsStore.save(all);
    }
    _notify('已加入「${picked.name}」');
  }

  Future<void> _editNote() async {
    final bangumiId = widget.bangumiItem.id;
    final existing = BangumiNotesStore.load()[bangumiId] ?? '';
    final controller = TextEditingController(text: existing);
    final saved = await AnikumoDialog.show<bool>(
      builder: (dialogContext) => AlertDialog(
        title: Text('「$_title」的笔记'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '写点只有你能看到的备注…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                AnikumoDialog.dismiss(context: dialogContext, popWith: false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                AnikumoDialog.dismiss(context: dialogContext, popWith: true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final notes = BangumiNotesStore.load();
    final text = controller.text.trim();
    if (text.isEmpty) {
      notes.remove(bangumiId);
    } else {
      notes[bangumiId] = text;
    }
    await BangumiNotesStore.save(notes);
    _notify(text.isEmpty ? '笔记已删除' : '笔记已保存');
  }

  @override
  Widget build(BuildContext context) {
    return AnikumoMenuButton(
      menuChildren: [
        AnikumoMenuItem(
          onPressed: _addToList,
          label: '加入榜单',
        ),
        AnikumoMenuItem(
          onPressed: _editNote,
          label: '写笔记',
        ),
        AnikumoMenuItem(
          onPressed: _savingCover ? null : _saveCover,
          label: _savingCover ? '保存中…' : '保存封面',
        ),
        AnikumoMenuItem(
          onPressed: _title.trim().isEmpty ? null : _copyTitle,
          label: '复制标题',
        ),
        AnikumoMenuItem(
          onPressed: _openExternally,
          label: '外部打开',
        ),
      ],
      builder: (context, toggle) => IconButton(
        tooltip: '更多操作',
        icon: const Icon(Icons.more_horiz_rounded),
        onPressed: toggle,
      ),
    );
  }
}

String _coverFileName(String title, int subjectId) {
  final safeTitle = String.fromCharCodes(
    title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim()
        .runes
        .take(60),
  );
  return '${safeTitle.isEmpty ? '封面' : safeTitle}-$subjectId.png';
}

Future<Uint8List> _loadCoverPng(String imageUrl) async {
  final file = await CachedNetworkImageProvider.defaultCacheManager
      .getSingleFile(imageUrl)
      .timeout(const Duration(seconds: 30));
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  try {
    final frame = await codec.getNextFrame();
    try {
      // Normalize cached formats to PNG without downscaling.
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode cover');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
