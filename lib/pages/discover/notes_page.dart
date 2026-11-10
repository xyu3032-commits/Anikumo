import 'package:flutter/material.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/card/network_img_layer.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/state_presentation.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/pages/discover/bangumi_picker.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// 番剧笔记 (hub 区二）: short private notes attached to bangumis —
/// 「第 8 集封神」「等第二季一起看」 — stored locally, never synced.
class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  Map<int, String> _notes = {};
  Map<int, BangumiItem> _resolved = {};

  @override
  void initState() {
    super.initState();
    _notes = BangumiNotesStore.load();
    _resolved = {
      for (final item in loadBangumiCandidates()) item.id: item,
    };
  }

  Future<void> _editNote(int bangumiId, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('番剧笔记'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: '记一句只有你懂的话…',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || !mounted) return;
    setState(() {
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        _notes.remove(bangumiId);
      } else {
        _notes[bangumiId] = trimmed;
      }
    });
    await BangumiNotesStore.save(_notes);
  }

  Future<void> _addNote() async {
    final picked = await showBangumiPicker(context, title: '给哪部番写笔记');
    if (picked == null || !mounted) return;
    await _editNote(picked.id, initial: _notes[picked.id] ?? '');
  }

  Future<void> _deleteNote(int bangumiId) async {
    setState(() => _notes.remove(bangumiId));
    await BangumiNotesStore.save(_notes);
    if (mounted) {
      AnikumoDialog.showToast(context: context, message: '笔记已删除');
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _notes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('番剧笔记'),
        actions: [
          IconButton(
            tooltip: '写笔记',
            onPressed: _addNote,
            icon: const Icon(AnikumoIcons.add),
          ),
        ],
      ),
      body: entries.isEmpty
          ? GeneralEmptyState(
              icon: AnikumoIcons.sticky_note_2_outlined,
              title: '还没有笔记',
              actions: [
                StateActionButton.tonal(
                  onPressed: _addNote,
                  icon: AnikumoIcons.add,
                  text: '写第一条笔记',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(StyleString.pagePadding),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final item = _resolved[entry.key];
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: StyleString.lgRadius,
                  ),
                  tileColor:
                      Theme.of(context).colorScheme.surfaceContainerLow,
                  leading: item == null
                      ? const Icon(AnikumoIcons.movie_outlined)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: NetworkImgLayer(
                            src: item.images['large'] ?? '',
                            width: 36,
                            height: 48,
                          ),
                        ),
                  title: Text(
                    item != null
                        ? bangumiDisplayTitle(item)
                        : '条目 #${entry.key}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    entry.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '删除笔记',
                    onPressed: () => _deleteNote(entry.key),
                    icon: const Icon(AnikumoIcons.delete_outline),
                  ),
                  onTap: () => _editNote(entry.key, initial: entry.value),
                );
              },
            ),
    );
  }
}
