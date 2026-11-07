import 'package:flutter/material.dart';
import 'package:anikumo/utils/github_links.dart';

/// Batch 63: multi-select dialog over the files of a
/// GitHub repository directory, shared by the novel and
/// manga GitHub imports. Returns the picked files, or
/// null when dismissed.
Future<List<GithubFileEntry>?> showGithubFilePicker(
  BuildContext context, {
  required String title,
  required List<GithubFileEntry> files,
}) =>
    showDialog<List<GithubFileEntry>>(
      context: context,
      builder: (context) => _GithubFilePicker(title: title, files: files),
    );

class _GithubFilePicker extends StatefulWidget {
  const _GithubFilePicker({required this.title, required this.files});

  final String title;
  final List<GithubFileEntry> files;

  @override
  State<_GithubFilePicker> createState() => _GithubFilePickerState();
}

class _GithubFilePickerState extends State<_GithubFilePicker> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.files.length; i++) i,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('仓库里有 ${widget.files.length} 个可导入文件，'
                    '已选 ${_selected.length} 个'),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selected
                      .addAll(List.generate(widget.files.length, (i) => i))),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清空'),
                ),
              ],
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.files.length,
                itemBuilder: (context, index) {
                  final file = widget.files[index];
                  return CheckboxListTile(
                    dense: true,
                    value: _selected.contains(index),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _selected.add(index);
                      } else {
                        _selected.remove(index);
                      }
                    }),
                    title: Text(file.name),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    [
                      for (final i in _selected.toList()..sort())
                        widget.files[i],
                    ],
                  ),
          child: Text('导入所选（${_selected.length}）'),
        ),
      ],
    );
  }
}
