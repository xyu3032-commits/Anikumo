import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../bean/dialog/dialog.dart';
import '../../models/novel_item.dart';
import '../../services/build_info.dart';
import '../../services/novel/novel_api.dart';
import '../../services/novel/novel_sources.dart';

/// Batch 33: novel source diagnostics — the novel twin of the
/// manga diagnostics page. Device-only failures (built-in
/// sources showing no chapters/images, imported sources failing
/// downloads) need the device's own step-by-step results:
/// search → chapters → first chapter content, with the real
/// error text at the exact step that breaks.
class NovelDiagnosticsPage extends StatefulWidget {
  const NovelDiagnosticsPage({super.key});

  @override
  State<NovelDiagnosticsPage> createState() => _NovelDiagnosticsPageState();
}

class _NovelDiagnosticsPageState extends State<NovelDiagnosticsPage> {
  bool _running = false;
  String _report = '';

  Future<String> _step(
    String label,
    Future<dynamic> Function() run,
    String Function(dynamic value) describe,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final value = await run();
      watch.stop();
      return '  [$label] 成功 · ${describe(value)} · '
          '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s';
    } catch (e) {
      watch.stop();
      return '  [$label] 失败 · '
          '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s · $e';
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _report = '';
    });
    final lines = <String>[
      'anikumo 小说源诊断 · 构建 $kAnikumoBuildStamp',
    ];
    final sources = NovelSources.all();
    lines.add('已装源 ${sources.length} 个');
    for (final source in sources) {
      lines.add('');
      lines.add('== ${source.name}（类型 ${source.type}）==');
      NovelItem? first;
      lines.add(await _step('搜索「斗罗大陆」', () async {
        final items = await NovelApi.searchOn(source, '斗罗大陆');
        if (items.isNotEmpty) first = items.first;
        return items;
      }, (v) => '${(v as List).length} 条'));
      if (first == null) {
        lines.add('  （无结果，后续步骤跳过）');
        continue;
      }
      List<NovelChapter>? chapters;
      lines.add(await _step('章节列表', () async {
        chapters = await NovelApi.chapters(first!);
        return chapters;
      }, (v) => '${(v as List).length} 章'));
      if (chapters == null || chapters!.isEmpty) {
        lines.add('  （无章节，后续步骤跳过）');
        continue;
      }
      final chapter = chapters!.first;
      if (chapter.webView) {
        lines.add('  [第一章内容] 网页模式章节（webView），不走内容提取');
        continue;
      }
      lines.add(await _step('第一章内容', () async {
        return NovelApi.content(first!, chapter);
      }, (v) {
        final blocks = v as List<NovelBlock>;
        final texts = blocks.whereType<NovelTextBlock>().length;
        final images = blocks.whereType<NovelImageBlock>().length;
        return '文本 $texts 段 · 图片 $images 张';
      }));
    }
    lines.add('');
    lines.add('（完）');
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = lines.join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小说源诊断')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '构建 $kAnikumoBuildStamp',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          const Text(
            '逐个源跑阅读链（搜索 → 章节 → 第一章内容），'
            '每步显示真实结果或真实错误。跑完可点「复制报告」，'
            '把报告发给开发者协助排查。',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(_running ? '诊断中…' : '开始诊断'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _report.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: _report),
                        );
                        AnikumoDialog.showToast(message: '报告已复制');
                      },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制报告'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_report.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _report,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
