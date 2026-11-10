import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../bean/dialog/dialog.dart';
import '../../models/novel_item.dart';
import '../../services/build_info.dart';
import '../../services/novel/moyuan_host.dart';
import '../../services/novel/novel_api.dart';
import '../../services/novel/novel_source.dart';
import '../../services/novel/novel_sources.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 166: the report also carries each tested source's own
/// definition (rules only). Two repair rounds aimed at sibling
/// variants of the user's sources missed: the decisive details
/// (a GBK flag here, a different search route there) live in
/// the definitions actually installed on the device, so the
/// diagnostics now ship them with the results.
const _defReportKeys = [
  'bookSourceUrl',
  'searchUrl',
  'exploreUrl',
  'loginUrl',
  'header',
  'ruleSearch',
  'ruleExplore',
  'ruleBookInfo',
  'ruleToc',
  'ruleContent',
  'bookUrlPattern',
];

Map<String, dynamic> trimDefForReport(Map<dynamic, dynamic> raw) {
  final out = <String, dynamic>{};
  for (final key in _defReportKeys) {
    final value = raw[key];
    if (value != null) out[key] = value;
  }
  return out;
}

/// Batch 171: the raw-response excerpt quoted when a
/// chapter list comes back suspiciously short. Prefers
/// the directory response (its URL carries 'directory'
/// for the API-shaped sources), else the most recently
/// captured body; whitespace is compacted so the excerpt
/// stays one report line.
String debugTocExcerpt(Map<String, String> bodies, {int limit = 1500}) {
  if (bodies.isEmpty) return '';
  var body = bodies.entries.last.value;
  for (final entry in bodies.entries) {
    if (entry.key.contains('directory')) {
      body = entry.value;
      break;
    }
  }
  final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= limit ? flat : '${flat.substring(0, limit)}…';
}

/// Batch 180: the raw-response excerpt quoted when a search
/// comes back empty — whether the list selector rotted or the
/// request itself changed cannot be settled without seeing
/// the page the site actually returned. Centers the excerpt
/// on the diagnosis keyword when it appears (result lists
/// live mid-page), else quotes the head; whitespace is
/// compacted so the excerpt stays one report line.
String debugSearchExcerpt(
  Map<String, String> bodies, {
  String keyword = '斗罗',
  int limit = 1500,
}) {
  if (bodies.isEmpty) return '';
  final flat =
      bodies.entries.last.value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= limit) return flat;
  final at = keyword.isEmpty ? -1 : flat.indexOf(keyword);
  if (at > limit ~/ 2) {
    final start = at - limit ~/ 2;
    return '…${flat.substring(start, start + limit)}…';
  }
  return '${flat.substring(0, limit)}…';
}

/// Batch 176: classify one step's error text into a plain
/// verdict. Only patterns the text itself proves are used;
/// anything else stays "unclassified" with the raw error
/// kept in the step line above.
String _classifyErrorText(String stageLabel, String errorText) {
  final text = errorText;
  if (text.contains('Stack Overflow')) {
    return '$stageLabel失败 · App 的 Dart 代码栈溢出'
        '（不是书源规则问题，错误原文已标注层级）';
  }
  if (text.contains('Stack overflow while loading')) {
    return '$stageLabel失败 · 引擎在正文规则处栈溢出'
        '（错误原文含源名/规则/页面大小）';
  }
  if (text.contains('Failed host lookup') ||
      text.contains('No address associated with hostname')) {
    return '$stageLabel失败 · DNS 解析失败——域名解析不了'
        '（网络问题，或该站域名已失效）';
  }
  if (text.contains('E_TEMPLATE') ||
      text.contains('URL template was not fully evaluated')) {
    return '$stageLabel失败 · 网址模板未执行——引擎模板求值异常（请报开发者）';
  }
  final http = RegExp(r'HTTP (\d{3})').firstMatch(text);
  if (http != null) {
    return '$stageLabel失败 · 网站返回 HTTP ${http.group(1)}';
  }
  final lower = text.toLowerCase();
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return '$stageLabel失败 · 请求超时';
  }
  if (text.contains('SocketException') ||
      text.contains('E_NETWORK') ||
      lower.contains('connection error') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable')) {
    return '$stageLabel失败 · 网络连接失败';
  }
  return '$stageLabel失败 · 未分类错误（见上方步骤原文）';
}

const _verifyPageMarkers = [
  '验证码',
  '滑动验证',
  '安全验证',
  '访问验证',
  'captcha',
  'cloudflare',
  '人机验证',
];

/// Batch 176: one-line verdict for a whole source run,
/// derived only from what the run actually observed:
/// step errors, result counts and the search response
/// body. "0 results" splits into an empty response, a
/// verification/intercept page, and a non-empty page the
/// list rule matched nothing on (rule rot) — the three
/// look identical in the step line alone.
String novelDiagVerdict({
  String? searchError,
  int searchCount = -1,
  String searchBody = '',
  String? chaptersError,
  int chaptersCount = -1,
  String? contentError,
  int contentBlocks = -1,
}) {
  if (searchError != null) return _classifyErrorText('搜索', searchError);
  if (searchCount == 0) {
    final body = searchBody.trim();
    final lowerBody = body.toLowerCase();
    for (final marker in _verifyPageMarkers) {
      if (lowerBody.contains(marker)) {
        return '搜索 0 条 · 疑似网站验证/拦截页（返回的不是搜索结果页）';
      }
    }
    if (body.isEmpty) return '搜索 0 条 · 网站响应为空';
    if (body.length < 200) {
      return '搜索 0 条 · 网站响应异常短（${body.length} 字）';
    }
    return '搜索 0 条 · 页面有返回但列表规则 0 匹配——多半是站点改版、'
        '规则失效（也可能该词真无结果，可换个热门词再测）';
  }
  if (chaptersError != null) {
    return _classifyErrorText('目录', chaptersError);
  }
  if (chaptersCount == 0) {
    return '目录为空 · 目录规则未匹配到章节（站点改版或该书目录结构特殊）';
  }
  if (contentError != null) return _classifyErrorText('正文', contentError);
  if (contentBlocks == 0) {
    return '正文为空 · 正文规则未匹配（页面有返回但正文提取为空）';
  }
  if (searchCount > 0 && chaptersCount > 0 && contentBlocks > 0) {
    return '全链通过 · 搜索/目录/正文均正常';
  }
  return '见上方步骤明细';
}

String novelSourceDefDigest(NovelSource source) {
  if (source is! LegadoNovelSource) return '';
  final trimmed = trimDefForReport(source.def.raw);
  if (trimmed.isEmpty) return '';
  var text = const JsonEncoder.withIndent(' ').convert(trimmed);
  if (text.length > 6000) text = '${text.substring(0, 6000)}…';
  return text;
}

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
    String Function(dynamic value) describe, {
    void Function(Object error)? onError,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final value = await run();
      watch.stop();
      return '  [$label] 成功 · ${describe(value)} · '
          '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s';
    } catch (e) {
      watch.stop();
      onError?.call(e);
      return '  [$label] 失败 · '
          '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s · $e';
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _report = '';
    });
    MoyuanHost.instance.recentBodies.clear();
    final lines = <String>[
      'anikumo 小说源诊断 · 构建 $kAnikumoBuildStamp',
    ];
    final sources = NovelSources.all();
    lines.add('已装源 ${sources.length} 个');
    for (final source in sources) {
      lines.add('');
      lines.add('== ${source.name}（类型 ${source.type}）==');
      final digest = novelSourceDefDigest(source);
      if (digest.isNotEmpty) {
        lines.add('  [源定义] ${digest.replaceAll('\n', '\n  ')}');
      }
      MoyuanHost.instance.recentBodies.clear();
      // Batch 174: engine features a source asked for
      // that the host cannot serve (recorded by the
      // engine as it goes) are part of the diagnosis —
      // flush the ones this source produced after each
      // step boundary and at every early exit.
      var unsupportedMark = MoyuanHost.instance.unsupportedLog.length;
      void flushUnsupported() {
        final log = MoyuanHost.instance.unsupportedLog;
        for (var i = unsupportedMark; i < log.length; i++) {
          if (log[i]['sourceId'] == source.id) {
            lines.add('  [未支持] ${log[i]['feature']}');
          }
        }
        unsupportedMark = log.length;
      }

      // Batch 176: per-step evidence for the verdict line
      // (error texts, counts, the search response body).
      String? searchError;
      String? chaptersError;
      String? contentError;
      var contentBlocks = -1;
      var searchBody = '';
      NovelItem? first;
      lines.add(await _step('搜索「斗罗大陆」', () async {
        final items = await NovelApi.searchOn(source, '斗罗大陆');
        if (items.isNotEmpty) first = items.first;
        return items;
      },
          (v) =>
              '${(v as List).length} 条${first == null ? '' : ' · 首条《${first!.title}》'}',
          onError: (e) => searchError = '$e'));
      final bodiesAfterSearch = MoyuanHost.instance.recentBodies;
      if (bodiesAfterSearch.isNotEmpty) {
        searchBody = bodiesAfterSearch.values.last;
      }
      // Batch 181: kinds get their own step — the explore
      // tab's categories come from this call, and its failures
      // used to be invisible (the page-level resolver swallows
      // them into an empty list). Calling the engine directly
      // keeps the real error text in the report.
      if (source is LegadoNovelSource && source.hasDynamicExplore) {
        lines.add(await _step(
          '分类生成',
          () => source.engine.exploreKinds(),
          (v) {
            final kinds = (v as List).cast<NovelExploreCategory>();
            return kinds.isEmpty
                ? '0 个'
                : '${kinds.length} 个 · 首个「${kinds.first.title}」';
          },
        ));
      } else {
        lines.add('  [分类] 静态 · ${source.exploreCategories.length} 个');
      }
      if (first == null) {
        flushUnsupported();
        lines.add('  [结论] ${novelDiagVerdict(
          searchError: searchError,
          searchCount: 0,
          searchBody: searchBody,
        )}');
        final searchExcerpt =
            debugSearchExcerpt(MoyuanHost.instance.recentBodies);
        if (searchExcerpt.isNotEmpty) {
          lines.add('  [搜索原文] $searchExcerpt');
        }
        lines.add('  （无结果，后续步骤跳过）');
        continue;
      }
      List<NovelChapter>? chapters;
      lines.add(await _step('章节列表', () async {
        chapters = await NovelApi.chapters(first!, fresh: true);
        return chapters;
      }, (v) => '${(v as List).length} 章',
          onError: (e) => chaptersError = '$e'));
      // Batch 171: a suspiciously short (or failed) chapter
      // list cannot be diagnosed from the count alone —
      // quote the raw directory response so the actual
      // payload shape is on the record.
      if (chapters == null || chapters!.length <= 3) {
        final excerpt = debugTocExcerpt(MoyuanHost.instance.recentBodies);
        if (excerpt.isNotEmpty) {
          lines.add('  [目录原文] $excerpt');
        }
      }
      if (chapters == null || chapters!.isEmpty) {
        flushUnsupported();
        lines.add('  [结论] ${novelDiagVerdict(
          searchCount: 1,
          chaptersError: chaptersError,
          chaptersCount: chapters?.length ?? -1,
        )}');
        lines.add('  （无章节，后续步骤跳过）');
        continue;
      }
      final chapter = chapters!.first;
      if (chapter.webView) {
        flushUnsupported();
        lines.add('  [第一章内容] 网页模式章节（webView），不走内容提取');
        continue;
      }
      lines.add(await _step('第一章内容', () async {
        return NovelApi.content(first!, chapter);
      }, (v) {
        final blocks = v as List<NovelBlock>;
        contentBlocks = blocks.length;
        final texts = blocks.whereType<NovelTextBlock>().length;
        final images = blocks.whereType<NovelImageBlock>().length;
        return '文本 $texts 段 · 图片 $images 张';
      }, onError: (e) => contentError = '$e'));
      flushUnsupported();
      lines.add('  [结论] ${novelDiagVerdict(
        searchCount: 1,
        chaptersCount: chapters!.length,
        contentError: contentError,
        contentBlocks: contentBlocks,
      )}');
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
                    : const Icon(AnikumoIcons.play_arrow_rounded),
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
                icon: const Icon(AnikumoIcons.copy_rounded),
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
