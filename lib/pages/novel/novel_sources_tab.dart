import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../services/novel/novel_sources.dart';
import '../../bean/dialog/dialog.dart';
import '../../bean/widget/github_file_picker.dart';
import '../../utils/error_message.dart';
import '../../utils/github_links.dart';
import 'novel_widgets.dart';

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

  @override
  void initState() {
    super.initState();
    NovelSources.revision.addListener(_onRevision);
  }

  @override
  void dispose() {
    NovelSources.revision.removeListener(_onRevision);
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
  String _importMessage(int added, ImportProbe probe) {
    if (added > 0) {
      return '已导入 $added 个书源'
          '${probe.encrypted > 0 ? '（其中 ${probe.encrypted} 个含加密规则，可能无法完整使用）' : ''}';
    }
    if (probe.entries == 0) {
      return '无法识别这个格式（支持 Legado / 阅读书源 JSON，含 base16、base64 压缩格式）';
    }
    if (probe.recognized == 0) {
      return '识别到 ${probe.entries} 条内容，但都缺少书源名或地址，未能导入';
    }
    return '没有新的书源（都已存在）';
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
      final added = await NovelSources.importFromText(text);
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
                ? '粘贴 Legado 书源 JSON（数组或单个对象，base16 也可以）'
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
        final added = await NovelSources.importFromText(text);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Batch 46: pinned sources lead the list.
    final sources = NovelSources.sortForDisplay(NovelSources.all());
    final activeId = sources.isEmpty ? '' : NovelSources.active().id;
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
          for (final source in sources)
            ListTile(
              leading: Icon(
                source.id == activeId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (source.loginUrl.isNotEmpty)
                    IconButton(
                      tooltip: '登录此源',
                      icon: const Icon(Icons.login),
                      onPressed: () => context.pushNamed(
                        '/novel/login',
                        arguments: source.id,
                      ),
                    ),
                  IconButton(
                    tooltip: NovelSources.isPinned(source.id)
                        ? '取消置顶'
                        : '置顶这个源',
                    icon: Icon(
                      NovelSources.isPinned(source.id)
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      color: NovelSources.isPinned(source.id)
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    onPressed: () => NovelSources.togglePin(source.id),
                  ),
                  IconButton(
                    tooltip: '删除这个源',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await NovelSources.removeImported(source.id);
                        AnikumoDialog.showToast(message: '已删除');
                      },
                    ),
                ],
              ),
              onTap: () => NovelSources.setActive(source.id),
            ),
          if (sources.any(
            (s) => NovelSources.isDead(s.id),
          ))
            ListTile(
              leading: Icon(
                Icons.cleaning_services_outlined,
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
            secondary: const Icon(Icons.auto_delete_outlined),
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
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('书源诊断'),
            subtitle: Text(
              '逐源实测搜索/章节/内容，显示真实错误',
              style: theme.textTheme.bodySmall,
            ),
            onTap: () => context.pushNamed('/novel/diagnostics'),
          ),
          const NovelSectionHeader(title: '手动导入'),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('从 URL 导入'),
            onTap: () => _showImportDialog(paste: false),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('粘贴 JSON 导入'),
            onTap: () => _showImportDialog(paste: true),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('从文件导入'),
            subtitle: const Text('选择本地 .json / .txt 书源文件'),
            onTap: _busyKey == null ? _importFromFile : null,
          ),
        ],
      ),
    );
  }
}
