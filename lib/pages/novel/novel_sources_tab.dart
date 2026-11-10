import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../services/novel/local_books.dart';
import '../../services/novel/novel_source.dart';
import '../../services/novel/novel_sources.dart';
import '../../services/novel/rss_sources.dart';
import 'novel_rss_page.dart';
import '../../bean/dialog/dialog.dart';
import '../../bean/widget/github_file_picker.dart';
import '../../utils/error_message.dart';
import '../../utils/github_links.dart';
import 'novel_source_info_panel.dart';
import 'novel_widgets.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Sources tab: pick the active source, manage imported
/// ones, and import from the 书源库 bundles or any URL /
/// pasted JSON (base16 payloads decode automatically).
class NovelSourcesTab extends StatefulWidget {
  const NovelSourcesTab({super.key});

  @override
  State<NovelSourcesTab> createState() => _NovelSourcesTabState();
}

class _NovelSourcesTabState extends State<NovelSourcesTab> {
  String? _busyKey;

  // Batch 159: batch-delete selection mode.
  bool _selecting = false;

  /// Batch 191: the source whose info panel is expanded
  /// under its row (tap toggles).
  String? _expandedId;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    NovelSources.revision.addListener(_onRevision);
    RssSources.revision.addListener(_onRevision);
  }

  @override
  void dispose() {
    NovelSources.revision.removeListener(_onRevision);
    RssSources.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (mounted) setState(() {});
  }

  Future<void> _importUrl(String url, String busyKey) async {
    // Batch 63: a GitHub *repository* address opens the
    // file picker (batch import); file-page addresses are
    // rewritten to raw inside NovelSources.importFromUrl.
    final repoRef = GithubLinks.parseRepo(url);
    if (repoRef != null) {
      await _importGithubRepo(repoRef, busyKey);
      return;
    }
    setState(() => _busyKey = busyKey);
    try {
      final (added, probe) =
          await NovelSources.importFromUrlDiagnosed(url);
      AnikumoDialog.showToast(message: _importMessage(added, probe));
    } catch (e) {
      AnikumoDialog.showToast(message: '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  /// Batch 66: an honest import result — "nothing added"
  /// has three different causes (unrecognized format /
  /// entries missing name or url / all already installed)
  /// and the user deserves to know which one it was.
  String _importMessage((int, int) added, ImportProbe probe) {
    final (bookAdded, rssAdded) = added;
    final total = bookAdded + rssAdded;
    if (total > 0) {
      return '已导入 $total 个'
          '${rssAdded > 0 ? '（书源 $bookAdded · 订阅源 $rssAdded，在下方「订阅源」里打开）' : '书源'}'
          '${probe.encrypted > 0 ? '（其中 ${probe.encrypted} 个含加密规则，可能无法完整使用）' : ''}';
    }
    if (probe.foreignPack) {
      return '这是其他阅读应用的加密规则包（.yds），不是通用书源格式，无法导入';
    }
    if (probe.entries == 0) {
      return '无法识别这个格式（支持书源/订阅源 JSON，含 base16、base64 压缩格式）';
    }
    if (probe.recognized == 0 && probe.rss == 0) {
      return '识别到 ${probe.entries} 条内容，但都缺少源名或地址，未能导入';
    }
    return '没有新的内容（都已存在）';
  }

  /// Batch 63: list the repo directory's .json/.txt files
  /// and import the ones the user checks.
  Future<void> _importGithubRepo(GithubRepoRef ref, String busyKey) async {
    setState(() => _busyKey = busyKey);
    try {
      final files = await GithubLinks.listFiles(ref);
      final candidates = [
        for (final f in files)
          if (f.name.toLowerCase().endsWith('.json') ||
              f.name.toLowerCase().endsWith('.txt'))
            f,
      ];
      if (!mounted) return;
      setState(() => _busyKey = null);
      if (candidates.isEmpty) {
        AnikumoDialog.showToast(
          message: '这个仓库目录里没有 .json/.txt 书源文件',
        );
        return;
      }
      final picked = await showGithubFilePicker(
        context,
        title: '从 GitHub 仓库导入书源',
        files: candidates,
      );
      if (picked == null || picked.isEmpty || !mounted) return;
      setState(() => _busyKey = busyKey);
      var total = 0;
      var failed = 0;
      for (final file in picked) {
        try {
          total += await NovelSources.importFromUrl(file.downloadUrl);
        } catch (_) {
          failed++;
        }
      }
      AnikumoDialog.showToast(
        message: '已导入 $total 个书源'
            '${failed > 0 ? '，$failed 个文件导入失败' : ''}',
      );
    } catch (e) {
      AnikumoDialog.showToast(message: '导入失败：${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  /// Batch 45: import book sources from a local file — the
  /// same parser as paste/URL import (JSON array or single
  /// object, base16 payloads included).
  Future<void> _importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      AnikumoDialog.showToast(message: '导入失败：读不到该文件');
      return;
    }
    setState(() => _busyKey = 'file');
    try {
      final text = utf8.decode(bytes);
      final added = await NovelSources.importFromTextSplit(text);
      AnikumoDialog.showToast(
        message: _importMessage(added, NovelSources.probeImport(text)),
      );
    } catch (e) {
      AnikumoDialog.showToast(message: '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _showImportDialog({required bool paste}) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(paste ? '粘贴书源 JSON' : '从 URL 导入'),
        content: TextField(
          controller: controller,
          maxLines: paste ? 8 : 1,
          decoration: InputDecoration(
            hintText: paste
                ? '粘贴书源 JSON（数组或单个对象，base16 也可以）'
                : 'https://…/sources.json，或 GitHub 仓库/文件链接',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    if (paste) {
      setState(() => _busyKey = 'paste');
      try {
        final added = await NovelSources.importFromTextSplit(text);
        AnikumoDialog.showToast(
          message:
              _importMessage(added, NovelSources.probeImport(text)),
        );
      } catch (e) {
        AnikumoDialog.showToast(message: '导入失败：$e');
      } finally {
        if (mounted) setState(() => _busyKey = null);
      }
    } else {
      await _importUrl(text, 'url');
    }
  }

  /// Trailing controls of one source tile. In selection
  /// mode there are none (the checkbox leads); the local
  /// source points at the feature repository instead of
  /// offering pin/delete it does not own.
  Widget? _tileTrailing(NovelSource source, ThemeData theme) {
    if (_selecting) return null;
    if (source.id == LocalNovelSource.sourceId) {
      return IconButton(
        tooltip: '在功能仓库管理',
        icon: const Icon(AnikumoIcons.chevron_right, size: 18),
        onPressed: () => context.pushNamed('/novel/features'),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (source.loginUrl.isNotEmpty)
          IconButton(
            tooltip: '登录此源',
            icon: const Icon(AnikumoIcons.login),
            onPressed: () => context.pushNamed(
              '/novel/login',
              arguments: source.id,
            ),
          ),
        if (source is LegadoNovelSource)
          Icon(
            _expandedId == source.id
                ? AnikumoIcons.expand_less_rounded
                : AnikumoIcons.expand_more,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        IconButton(
          tooltip: NovelSources.isPinned(source.id) ? '取消置顶' : '置顶这个源',
          icon: Icon(
            NovelSources.isPinned(source.id)
                ? AnikumoIcons.push_pin
                : AnikumoIcons.push_pin_outlined,
            color: NovelSources.isPinned(source.id)
                ? theme.colorScheme.primary
                : null,
          ),
          onPressed: () => NovelSources.togglePin(source.id),
        ),
        IconButton(
          tooltip: '删除这个源',
          icon: const Icon(AnikumoIcons.delete_outline),
          onPressed: () async {
            await NovelSources.removeImported(source.id);
            AnikumoDialog.showToast(message: '已删除');
          },
        ),
      ],
    );
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _deleteSelected(Set<String> ids) async {
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书源'),
        content: Text('确定要删除选中的 ${ids.length} 个书源吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await NovelSources.removeImportedBatch(ids);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    AnikumoDialog.showToast(message: '已删除 $removed 个书源');
  }

  Future<void> _deleteAll(Set<String> ids) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('全部删除'),
        content: Text('确定要删除全部 ${ids.length} 个已导入书源吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await NovelSources.removeImportedBatch(ids);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    AnikumoDialog.showToast(message: '已删除 $removed 个书源');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Batch 46: pinned sources lead the list.
    final sources = NovelSources.sortForDisplay(NovelSources.all());
    final activeId = sources.isEmpty ? '' : NovelSources.active().id;
    // Batch 159: the local-books source is managed by the
    // feature repository, not by this tab's deletion tools.
    final importedIds = {
      for (final s in sources)
        if (s.id != LocalNovelSource.sourceId) s.id,
    };
    final effectiveSelected = _selected.intersection(importedIds);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const NovelSectionHeader(title: '当前书源'),
          if (sources.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('还没有书源。用下方「从 URL 导入」添加你自己的书源链接。'),
            ),
          for (final source in sources) ...[
            ListTile(
              leading: _selecting &&
                      source.id != LocalNovelSource.sourceId
                  ? Checkbox(
                      value: _selected.contains(source.id),
                      onChanged: (_) => _toggleSelected(source.id),
                    )
                  : Icon(
                      source.id == activeId
                          ? AnikumoIcons.radio_button_checked
                          : AnikumoIcons.radio_button_unchecked,
                    ),
              title: Row(
                children: [
                  Flexible(child: Text(source.name)),
                  if (NovelSources.isPinned(source.id)) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '置顶',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  if (NovelSources.isDead(source.id)) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '已失效',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                // Batch 33: label the source TYPE honestly —
                // Legado type 2 sources are image (comic)
                // sources; users asked why "novel" sources
                // contained manga.
                '已导入 · '
                '${switch (source.type) {
                  0 => '小说源',
                  1 => '音频源',
                  2 => '图片源（漫画）',
                  _ => '其他类型',
                }}',
                style: theme.textTheme.bodySmall,
              ),
              trailing: _tileTrailing(source, theme),
              onTap: _selecting
                  ? (source.id == LocalNovelSource.sourceId
                      ? null
                      : () => _toggleSelected(source.id))
                  : () {
                      // Batch 191: tapping an imported
                      // source expands its info panel in
                      // place; the local source keeps
                      // tap-to-activate.
                      if (source is LegadoNovelSource) {
                        setState(() {
                          _expandedId = _expandedId == source.id
                              ? null
                              : source.id;
                        });
                      } else {
                        NovelSources.setActive(source.id);
                      }
                    },
            ),
            if (_expandedId == source.id &&
                source is LegadoNovelSource &&
                !_selecting)
              NovelSourceInfoPanel(
                key: ValueKey('novel-source-info:${source.id}'),
                source: source,
                isActive: source.id == activeId,
                onActivate: () => NovelSources.setActive(source.id),
                onOpenLogin: () => context.pushNamed(
                  '/novel/login',
                  arguments: source.id,
                ),
              ),
          ],
          if (_selecting)
            ListTile(
              leading: const Icon(AnikumoIcons.delete_sweep_outlined),
              title: Text(
                '已选 ${effectiveSelected.length} / ${importedIds.length} 个',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () =>
                        setState(() => _selected.addAll(importedIds)),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: effectiveSelected.isEmpty
                        ? null
                        : () => _deleteSelected(effectiveSelected),
                    child: Text(
                      '删除选中',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _selecting = false;
                      _selected.clear();
                    }),
                    child: const Text('完成'),
                  ),
                ],
              ),
            )
          else if (importedIds.isNotEmpty) ...[
            ListTile(
              leading: const Icon(AnikumoIcons.delete_sweep_outlined),
              title: const Text('批量删除'),
              subtitle: Text(
                '多选后一次删完，不再逐个卡顿',
                style: theme.textTheme.bodySmall,
              ),
              onTap: () => setState(() => _selecting = true),
            ),
            ListTile(
              leading: Icon(
                AnikumoIcons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                '全部删除',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: Text(
                '删除全部 ${importedIds.length} 个已导入书源',
                style: theme.textTheme.bodySmall,
              ),
              onTap: () => _deleteAll(importedIds),
            ),
          ],
          const NovelSectionHeader(title: '订阅源'),
          if (RssSources.all().isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('还没有订阅源。订阅仓库（如源仓库的订阅链接）导入后会出现在这里。'),
            ),
          for (final rss in RssSources.all())
            ListTile(
              leading: const Icon(AnikumoIcons.public_rounded),
              title: Text(rss.name),
              subtitle: Text(
                rss.hasArticleRules
                    ? '订阅源 · 文章列表'
                    : '目录型 · 打开网页',
                style: theme.textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!rss.hasArticleRules)
                    const Icon(AnikumoIcons.open_in_new_rounded),
                  IconButton(
                    icon: const Icon(AnikumoIcons.delete_outline),
                    tooltip: '删除这个订阅源',
                    onPressed: () async {
                      await RssSources.remove(rss.id);
                      AnikumoDialog.showToast(message: '已删除');
                    },
                  ),
                ],
              ),
              onTap: () {
                if (rss.hasArticleRules) {
                  context.pushNamed('/novel/rss', arguments: rss.id);
                } else {
                  openRssExternal(rss.url);
                }
              },
            ),
          if (sources.any(
            (s) => NovelSources.isDead(s.id),
          ))
            ListTile(
              leading: Icon(
                AnikumoIcons.cleaning_services_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                '清理失效源（${sources.where((s) => NovelSources.isDead(s.id)).length}）',
              ),
              subtitle: Text(
                '删除已确认不可用的已导入书源',
                style: theme.textTheme.bodySmall,
              ),
              onTap: () async {
                final removed =
                    await NovelSources.cleanupDeadImported();
                AnikumoDialog.showToast(
                  message: removed > 0 ? '已清理 $removed 个失效源' : '没有可清理的源',
                );
              },
            ),
          SwitchListTile(
            secondary: const Icon(AnikumoIcons.auto_delete_outlined),
            title: const Text('自动删除失效书源'),
            subtitle: Text(
              '书源连续两次确认不可用（域名失效 / 403 / '
              '502 / 握手失败）时自动删除',
              style: theme.textTheme.bodySmall,
            ),
            value: NovelSources.autoDeleteDeadSources,
            onChanged: (value) =>
                NovelSources.setAutoDeleteDeadSources(value),
          ),
          ListTile(
            leading: const Icon(AnikumoIcons.fact_check_outlined),
            title: const Text('书源诊断'),
            subtitle: Text(
              '逐源实测搜索/章节/内容，显示真实错误',
              style: theme.textTheme.bodySmall,
            ),
            onTap: () => context.pushNamed('/novel/diagnostics'),
          ),
          const NovelSectionHeader(title: '手动导入'),
          ListTile(
            leading: const Icon(AnikumoIcons.link),
            title: const Text('从 URL 导入'),
            onTap: () => _showImportDialog(paste: false),
          ),
          ListTile(
            leading: const Icon(AnikumoIcons.content_paste),
            title: const Text('粘贴 JSON 导入'),
            onTap: () => _showImportDialog(paste: true),
          ),
          ListTile(
            leading: const Icon(AnikumoIcons.folder_open_outlined),
            title: const Text('从文件导入'),
            subtitle: const Text('选择本地 .json / .txt 书源文件'),
            onTap: _busyKey == null ? _importFromFile : null,
          ),
        ],
      ),
    );
  }
}
