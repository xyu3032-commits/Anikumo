import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/card/rule_card.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/widget/anikumo_menu.dart';
import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/state_presentation.dart';
import 'package:anikumo/pages/plugin_editor/rule_dialogs.dart';
import 'package:anikumo/pages/plugin_editor/rule_management_widgets.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/plugins/plugins_controller.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/plugin/plugin_import_parser.dart';

class PluginViewPage extends StatefulWidget {
  const PluginViewPage({super.key, required this.controller});
  final PluginsController controller;

  @override
  State<PluginViewPage> createState() => _PluginViewPageState();
}

class _PluginViewPageState extends State<PluginViewPage> {
  PluginsController get _controller => widget.controller;
  final _search = TextEditingController();
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _deleting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final source = await showRuleAddDialog(context);
    if (!mounted || source == null) return;
    await _runAddSource(source);
  }

  Future<void> _runAddSource(RuleAddSource source) async {
    switch (source) {
      case RuleAddSource.create:
        context.pushNamed('/settings/plugin/editor',
            arguments: Plugin.fromTemplate());
      case RuleAddSource.clipboard:
        String? initialValue;
        try {
          initialValue = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        } catch (_) {
          initialValue = null;
        }
        if (mounted) {
          // Batch 62: the dialog hands back a repository
          // address when one was pasted — open the
          // repository page with it.
          final repoAddress = await showRuleImportDialog(context, _controller,
              initialValue: initialValue ?? '');
          if (repoAddress != null && mounted) {
            context.pushNamed('/settings/plugin/repository',
                arguments: repoAddress);
          }
        }
      case RuleAddSource.file:
        await _importFromFile();
    }
  }

  Future<void> _importFromFile() async {
    try {
      // Batch 62 optimization: several rule files can be
      // picked at once; each is parsed on its own and the
      // results merged (same-name rules dedupe, later file
      // wins) into a single install + summary.
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['json'],
          allowMultiple: true,
          withData: true);
      if (result == null) return;
      final parsedList = <PluginImportParseResult>[];
      for (final file in result.files) {
        final bytes = file.bytes ??
            (file.path == null ? null : await File(file.path!).readAsBytes());
        if (bytes == null) throw const FileSystemException('无法读取所选文件');
        parsedList.add(PluginImportParser.parse(utf8.decode(bytes)));
      }
      final parsed = mergeImportResults(parsedList);
      if (parsed.plugins.isEmpty) {
        AnikumoDialog.showToast(
            message: parsed.failures.isEmpty
                ? '文件中没有可导入的规则'
                : parsed.failures.first);
        return;
      }
      await _controller.updatePlugins(parsed.plugins);
      AnikumoDialog.showToast(
          message: '已导入 ${parsed.plugins.length} 条规则，'
              '跳过重复 ${parsed.duplicateCount} 条，失败 ${parsed.failureCount} 条');
    } catch (error, stackTrace) {
      AnikumoLogger().e('Plugin: failed to import rules from file',
          error: error, stackTrace: stackTrace);
      AnikumoDialog.showToast(message: '导入规则文件失败：$error');
    }
  }

  void _leaveSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _toggleSelection(String name) => setState(() {
        if (!_selected.add(name)) _selected.remove(name);
      });

  Future<void> _delete(Set<String> names) async {
    if (_deleting || names.isEmpty) return;
    setState(() => _deleting = true);
    final confirmed = await confirmRuleDeletion(context, names);
    if (!mounted) return;
    if (!confirmed) {
      setState(() => _deleting = false);
      return;
    }
    try {
      await _controller.removePlugins(names);
      if (mounted) _leaveSelection();
      AnikumoDialog.showToast(message: '已删除 ${names.length} 条规则');
    } catch (_) {
      AnikumoDialog.showToast(message: '删除规则失败，请重试');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    try {
      await _controller.onReorder(oldIndex, newIndex);
    } catch (_) {
      AnikumoDialog.showToast(message: '保存规则顺序失败');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _selecting) _leaveSelection();
        },
        child: SettingsDetailScaffold(
          title: Text(_selecting ? '已选择 ${_selected.length} 条' : '规则管理'),
          leading: _selecting
              ? IconButton(
                  tooltip: '退出多选',
                  onPressed: _leaveSelection,
                  icon: const Icon(Icons.close_rounded))
              : null,
          actions: [
            if (_selecting)
              IconButton(
                tooltip: '删除所选规则',
                onPressed: _selected.isEmpty || _deleting
                    ? null
                    : () => _delete(Set.of(_selected)),
                icon: const Icon(Icons.delete_outline_rounded),
              )
            else
              IconButton(
                tooltip: '批量选择',
                onPressed: () => setState(() => _selecting = true),
                icon: const Icon(Icons.checklist_rounded),
              ),
            const SizedBox(width: 8),
          ],
          body: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Observer(builder: (context) {
                  final colors = Theme.of(context).colorScheme;
                  final all = _controller.pluginList.toList();
                  final query = _search.text.trim().toLowerCase();
                  final visible = all
                      .where((p) =>
                          p.name.toLowerCase().contains(query) ||
                          p.baseUrl.toLowerCase().contains(query))
                      .toList();
                  final canReorder = query.isEmpty && !_selecting;
                  return ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) => Material(
                        elevation: 0, color: Colors.transparent, child: child),
                    onReorderItem: (oldIndex, newIndex) =>
                        unawaited(_reorder(oldIndex, newIndex)),
                    header: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RulePageIntro(
                          title: '我的规则',
                          description: '管理你的番剧来源。拖动调整搜索顺序，点按规则进行编辑。',
                          icon: Icons.extension_rounded,
                          actions: [
                            FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    minimumSize: const Size(120, 48)),
                                onPressed: _add,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('添加规则')),
                            OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(120, 48)),
                                onPressed: () => context.pushNamed(
                                    '/settings/plugin/repository'),
                                icon: const Icon(
                                    Icons.inventory_2_outlined),
                                label: const Text('规则仓库')),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: ruleInputDecoration(context,
                              hint: '搜索名称或站点',
                              prefix: const Icon(Icons.search_rounded),
                              suffix: query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: '清除搜索',
                                      onPressed: () => setState(_search.clear),
                                      icon: const Icon(Icons.close_rounded))),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(
                                label: Text('全部 ${all.length}'),
                                visualDensity: VisualDensity.compact),
                            if (_selecting)
                              TextButton(
                                  onPressed: () => setState(() {
                                        if (visible.every((p) =>
                                            _selected.contains(p.name))) {
                                          _selected.removeAll(
                                              visible.map((p) => p.name));
                                        } else {
                                          _selected.addAll(
                                              visible.map((p) => p.name));
                                        }
                                      }),
                                  child: Text(visible.isNotEmpty &&
                                          visible.every(
                                              (p) => _selected.contains(p.name))
                                      ? '取消全选'
                                      : '全选当前列表')),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                    footer: all.isEmpty
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const GeneralEmptyState(
                                icon: Icons.extension_rounded,
                                title: '还没有安装规则',
                                compact: true,
                              ),
                              // Batch 61: no built-in library —
                              // show what a rule is and the
                              // three add paths, with icons,
                              // right where a new user lands.
                              RuleAddGuide(options: [
                                RuleAddOption(
                                  icon: Icons.content_paste_rounded,
                                  title: '从剪贴板导入',
                                  subtitle: '粘贴规则链接或 JSON，链接会自动下载',
                                  onTap: () =>
                                      _runAddSource(RuleAddSource.clipboard),
                                ),
                                RuleAddOption(
                                  icon: Icons.file_open_outlined,
                                  title: '从文件导入',
                                  subtitle: '读取本地 JSON 规则文件',
                                  onTap: () =>
                                      _runAddSource(RuleAddSource.file),
                                ),
                                RuleAddOption(
                                  icon: Icons.edit_note_rounded,
                                  title: '新建规则',
                                  subtitle: '从模板开始编写',
                                  onTap: () =>
                                      _runAddSource(RuleAddSource.create),
                                ),
                              ]),
                            ],
                          )
                        : visible.isEmpty
                            ? GeneralEmptyState(
                                icon: Icons.search_off_rounded,
                                title: '没有符合条件的规则',
                                actions: [
                                  StateActionButton.tonal(
                                      onPressed: () =>
                                          setState(_search.clear),
                                      text: '显示全部规则'),
                                ],
                              )
                            : null,
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final plugin = visible[index];
                      final actualIndex = all.indexOf(plugin);
                      return RuleCard(
                        key: ValueKey(plugin.name),
                        title: plugin.name,
                        subtitle: Uri.tryParse(plugin.baseUrl)?.host ??
                            plugin.baseUrl,
                        selected: _selected.contains(plugin.name),
                        onTap: () {
                          if (_selecting) {
                            _toggleSelection(plugin.name);
                          } else {
                            context.pushNamed('/settings/plugin/editor',
                                arguments: plugin);
                          }
                        },
                        onLongPress: () => setState(() {
                          _selecting = true;
                          _selected.add(plugin.name);
                        }),
                        tags: [
                          RuleTag(
                              label: plugin.version,
                              background: colors.surfaceContainerHighest,
                              foreground: colors.onSurfaceVariant),
                          if (_controller.validityTracker
                              .isSearchValid(plugin.name))
                            RuleTag(
                                label: '搜索通过',
                                background: colors.tertiaryContainer,
                                foreground: colors.onTertiaryContainer),
                        ],
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          if (_selecting)
                            Checkbox(
                                value: _selected.contains(plugin.name),
                                semanticLabel: '选择 ${plugin.name}',
                                onChanged: (_) => _toggleSelection(plugin.name))
                          else
                            _menu(plugin, actualIndex),
                          if (canReorder)
                            Tooltip(
                              message: '拖动排序',
                              child: ReorderableDragStartListener(
                                index: index,
                                child: const SizedBox.square(
                                    dimension: 48,
                                    child: Icon(Icons.drag_indicator_rounded)),
                              ),
                            ),
                        ]),
                      );
                    },
                  );
                }),
              ),
            ),
          ),
        ),
      );

  Widget _menu(Plugin plugin, int index) => AnikumoMenuButton(
        style: MenuStyle(
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        ),
        builder: (context, toggle) => IconButton(
            tooltip: '${plugin.name} 的更多操作',
            onPressed: toggle,
            icon: const Icon(Icons.more_horiz_rounded)),
        menuChildren: [
          AnikumoMenuItem(
              onPressed: () => context.pushNamed('/settings/plugin/editor',
                  arguments: plugin),
              label: '编辑规则'),
          AnikumoMenuItem(
              onPressed: () =>
                  context.pushNamed('/settings/plugin/test', arguments: plugin),
              label: '测试规则'),
          AnikumoMenuItem(
              onPressed: () => showRuleShareDialog(context, plugin),
              label: '分享规则'),
          const Divider(),
          AnikumoMenuItem(
              onPressed: index == 0 ? null : () => _reorder(index, index - 1),
              label: '上移'),
          AnikumoMenuItem(
              onPressed: index == _controller.pluginList.length - 1
                  ? null
                  : () => _reorder(index, index + 1),
              label: '下移'),
          const Divider(),
          AnikumoMenuItem(
              destructive: true,
              onPressed: _deleting ? null : () => _delete({plugin.name}),
              label: '删除规则'),
        ],
      );
}
