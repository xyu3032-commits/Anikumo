import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:anikumo/bean/widget/loading_indicator.dart';
import 'package:anikumo/pages/onboarding/onboarding_step_layout.dart';
import 'package:anikumo/plugins/plugins_controller.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/services/plugin/plugin_import_parser.dart';
import 'package:anikumo/utils/github_links.dart';

/// Batch 59: first-run source setup. The app ships with no
/// built-in sources, so each zone gets one step: paste your
/// own URL and import, or leave it empty and tap 下一步 —
/// sources can always be added later from source
/// management.
class AnimeSourceUrlStep extends StatelessWidget {
  const AnimeSourceUrlStep({super.key, required this.controller});

  final PluginsController controller;

  @override
  Widget build(BuildContext context) => _SourceUrlStep(
        icon: Icons.live_tv_rounded,
        shape: OnboardingIconShape.sunny,
        title: '添加动漫来源',
        subtitle: '粘贴你自己的规则文件 URL，导入后即可搜索和播放番剧。',
        fieldLabel: '动漫规则 URL',
        hint: 'https://…/rule.json，或 anikumo:// 规则链接',
        importer: (text) async {
          // Batch 62 optimization: same shared pipeline as
          // the import dialog (local parse, then per-line
          // URL downloads). A repository address comes back
          // as a guidance failure pointing at the repository
          // page instead of a raw parse error.
          final result = await importFromPastedText(text);
          if (result.plugins.isEmpty) {
            throw FormatException(
              result.failures.isEmpty ? '没有识别到规则' : result.failures.first,
            );
          }
          await controller.updatePlugins(result.plugins);
          return '已导入 ${result.plugins.length} 条规则';
        },
      );
}

class MangaSourceUrlStep extends StatelessWidget {
  const MangaSourceUrlStep({super.key});

  @override
  Widget build(BuildContext context) => _SourceUrlStep(
        icon: Icons.menu_book_rounded,
        shape: OnboardingIconShape.cookie,
        title: '添加漫画来源',
        subtitle: '粘贴你自己的 Venera JS 漫画源文件 URL。',
        fieldLabel: '漫画源 URL',
        hint: 'https://…/source.js（Venera JS 源文件直链）',
        importer: (text) async {
          if (!isBareRuleUrl(text)) {
            throw const FormatException('请粘贴以 http 开头的源文件链接');
          }
          // Batch 63: GitHub repository addresses need the
          // picker in source management; file-page addresses
          // are rewritten to raw before downloading.
          if (GithubLinks.parseRepo(text) != null) {
            throw const FormatException(
              '这是 GitHub 仓库地址。先进首页，之后在漫画的源管理里'
              '粘贴它，就能勾选仓库里的源文件批量导入。',
            );
          }
          final response = await Dio().get<String>(
            GithubLinks.rawFileUrl(text) ?? text,
            options: Options(
              responseType: ResponseType.plain,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
          final code = response.data ?? '';
          if (code.trim().isEmpty) {
            throw const FormatException('下载到的文件是空的');
          }
          final meta = await MangaSources.installCustomJs(
            code,
            fileName: text.split('/').last,
          );
          return '已导入漫画源「${meta.name}」v${meta.version}';
        },
      );
}

class NovelSourceUrlStep extends StatelessWidget {
  const NovelSourceUrlStep({super.key});

  @override
  Widget build(BuildContext context) => _SourceUrlStep(
        icon: Icons.auto_stories_rounded,
        shape: OnboardingIconShape.flower,
        title: '添加小说来源',
        subtitle: '粘贴你自己的 Legado 书源 URL（JSON 或合集链接）。',
        fieldLabel: '小说书源 URL',
        hint: 'https://…/sources.json',
        importer: (text) async {
          if (!isBareRuleUrl(text)) {
            throw const FormatException('请粘贴以 http 开头的书源链接');
          }
          // Batch 63: a GitHub repository address needs the
          // file picker in source management (GitHub *file*
          // links are rewritten to raw automatically).
          if (GithubLinks.parseRepo(text) != null) {
            throw const FormatException(
              '这是 GitHub 仓库地址。先进首页，之后在小说的书源管理里'
              '粘贴它，就能勾选仓库里的书源文件批量导入。',
            );
          }
          final count = await NovelSources.importFromUrl(text);
          if (count == 0) {
            throw const FormatException(
              '没有导入新书源（可能已导入过，或链接里没有书源）',
            );
          }
          return '已导入 $count 个书源';
        },
      );
}

class _SourceUrlStep extends StatefulWidget {
  const _SourceUrlStep({
    required this.icon,
    required this.shape,
    required this.title,
    required this.subtitle,
    required this.fieldLabel,
    required this.hint,
    required this.importer,
  });

  final IconData icon;
  final OnboardingIconShape shape;
  final String title;
  final String subtitle;
  final String fieldLabel;
  final String hint;
  final Future<String> Function(String text) importer;

  @override
  State<_SourceUrlStep> createState() => _SourceUrlStepState();
}

class _SourceUrlStepState extends State<_SourceUrlStep> {
  final _text = TextEditingController();
  bool _importing = false;
  String? _status;
  bool _statusOk = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final text = _text.text.trim();
    if (text.isEmpty || _importing) return;
    setState(() {
      _importing = true;
      _status = null;
    });
    try {
      final message = await widget.importer(text);
      if (!mounted) return;
      setState(() {
        _importing = false;
        _status = message;
        _statusOk = true;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _status = '导入失败：${error.message}';
        _statusOk = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _status = '导入失败：无法下载，请检查链接与网络';
        _statusOk = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OnboardingStepLayout(
      leading: OnboardingStepIcon(icon: widget.icon, shape: widget.shape),
      title: widget.title,
      subtitle: widget.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            enabled: !_importing,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _import(),
            decoration: InputDecoration(
              labelText: widget.fieldLabel,
              hintText: widget.hint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed:
                _importing || _text.text.trim().isEmpty ? null : _import,
            icon: _importing
                ? const LoadingIndicator(size: 18)
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(_importing ? '导入中' : '导入'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _statusOk
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          const OnboardingHint(
            text: '不输入也可以直接点「下一步」，之后随时能在源管理里添加。',
          ),
        ],
      ),
    );
  }
}
