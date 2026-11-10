import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import '../../bean/dialog/dialog.dart';
import '../../models/novel_item.dart';
import '../../services/novel/legado_parse.dart';
import '../../services/novel/novel_api.dart';
import '../../services/novel/novel_features.dart';
import '../../services/novel/tts_service.dart';
import '../../services/novel/novel_sources.dart';
import '../../services/novel/novel_downloads.dart';
import '../../services/novel/novel_library.dart';
import '../../services/storage/storage.dart';
import 'novel_widgets.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Args for the /novel/reader route.
typedef NovelReaderArgs = ({
  NovelItem item,
  List<NovelChapter> chapters,
  int chapterIndex,
});

/// Batch 184: what the chapter list's tail shows. The
/// chapter-end marker is a READER state, not a claim
/// about the source: [complete] means this chapter's
/// content loaded and nothing known is missing;
/// [truncated] means the engine stopped following the
/// chapter's pagination early, so the text may continue
/// beyond what is shown; [none] (no readable content)
/// renders no tail at all — the page shows its empty
/// state instead of crowning a blank chapter as finished.
enum NovelChapterTail { none, complete, truncated }

NovelChapterTail novelChapterTail({
  required bool hasContent,
  required bool possiblyTruncated,
}) =>
    !hasContent
        ? NovelChapterTail.none
        : possiblyTruncated
            ? NovelChapterTail.truncated
            : NovelChapterTail.complete;

/// The novel reader: a scrolling page of text paragraphs
/// and inline images, chapter by chapter.
class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({super.key, required this.args});

  final NovelReaderArgs args;

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  late int _index = widget.args.chapterIndex;

  // Batch 46: the reader holds its own copies so a failed
  // chapter can switch the whole book to another source
  // in place （换源阅读） without leaving the reader.
  // Batch 186: this field self-initialized (`= _item`)
  // since batch 46 — a late field whose initializer reads
  // itself throws StackOverflowError on first access, so
  // every chapter load died before it could render (the
  // error state's own message reads the field too, which
  // is why the page showed nothing at all). It must seed
  // from the route arguments; _switchSource reassigns it.
  late NovelItem _item = widget.args.item;
  late List<NovelChapter> _chapters = widget.args.chapters;
  bool _switchingSource = false;
  List<NovelBlock> _blocks = const [];
  bool _loading = true;
  String? _errorText;
  // Batch 184: the current chapter may be truncated (the
  // engine's page cap stopped its pagination) — the tail
  // marker then warns instead of declaring completion.
  bool _possiblyTruncated = false;
  // Batch 30: chapter changes reset the scroll position, and
  // a load ticket keeps a slow earlier chapter from winning
  // the race against a newer one.
  final _scrollController = ScrollController();
  int _loadTicket = 0;

  // Batch 31: WebView reading mode for chapters the source
  // declares WebView-only (their content is injected by page
  // scripts — image chapters on 读漫屋 are the canonical
  // case: the HTTP page has an empty image container and
  // only a real browser rendering fills it). The site's own
  // page becomes the reader; our bottom bar still drives
  // chapter navigation.
  bool _webViewMode = false;
  int? _forcedWebViewIndex;
  PlatformInAppWebViewWidget? _webView;
  PlatformInAppWebViewController? _webController;

  // Batch 158: read-aloud (feature repository's 语音朗读，
  // present only while that feature is installed). The
  // player is a shared singleton; this page feeds it the
  // current chapter's paragraphs and, when a chapter's
  // queue runs out, advances and feeds the next one.
  final _tts = TtsPlayer.instance;
  bool _ttsContinue = false;

  @override
  void dispose() {
    _tts.removeListener(_onTtsChanged);
    if (_tts.onQueueFinished == _onTtsQueueFinished) {
      _tts.onQueueFinished = null;
    }
    _tts.stop();
    _scrollController.dispose();
    _webView?.dispose();
    super.dispose();
  }

  void _onTtsChanged() {
    if (mounted) setState(() {});
  }

  void _onTtsQueueFinished() {
    if (!mounted) return;
    if (_index < _chapters.length - 1) {
      _ttsContinue = true;
      setState(() => _index++);
      _load();
    }
  }

  void _speakChapter() {
    final paragraphs = [
      for (final block in _blocks)
        if (block is NovelTextBlock) block.text,
    ];
    if (paragraphs.isEmpty) {
      AnikumoDialog.showToast(message: '这一章没有可朗读的文字');
      return;
    }
    _tts.speakParagraphs(paragraphs);
  }

  void _stopTts() {
    _ttsContinue = false;
    _tts.stop();
  }

  String get _cleanChapterUrl =>
      LegadoParse.splitUrlOptions(_chapter.url).$1;

  bool get _chapterWantsWebView =>
      _chapter.webView || _forcedWebViewIndex == _index;

  Future<void> _enterWebView() async {
    final url = _cleanChapterUrl;
    final headers = NovelApi.headersFor(_item);
    _ensureWebView(url, headers);
    setState(() {
      _webViewMode = true;
      _loading = false;
      _errorText = null;
    });
    if (_webController != null) {
      await _webController!.loadUrl(
        urlRequest: URLRequest(url: WebUri(url), headers: headers),
      );
    }
    await NovelLibraryStore.recordProgress(
      NovelProgress(
        item: _item,
        chapterIndex: _index,
        chapterTitle: _chapter.title,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void _ensureWebView(String url, Map<String, String> headers) {
    if (_webView != null) return;
    final ua = headers.entries
        .where((e) => e.key.toLowerCase() == 'user-agent')
        .map((e) => e.value)
        .firstOrNull;
    _webView = PlatformInAppWebViewWidget(
      PlatformInAppWebViewWidgetCreationParams(
        initialUrlRequest: URLRequest(url: WebUri(url), headers: headers),
        initialSettings: InAppWebViewSettings(
          userAgent: ua ?? '',
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          useWideViewPort: true,
          loadWithOverviewMode: true,
        ),
        onWebViewCreated: (controller) {
          _webController = controller;
          // If the chapter moved on while the widget was
          // being created, land on the current one.
          final current = _cleanChapterUrl;
          if (current != url) {
            controller.loadUrl(
              urlRequest: URLRequest(
                url: WebUri(current),
                headers: NovelApi.headersFor(_item),
              ),
            );
          }
        },
      ),
    );
  }

  NovelChapter get _chapter => _chapters[_index];

  @override
  void initState() {
    super.initState();
    _tts.addListener(_onTtsChanged);
    _tts.onQueueFinished = _onTtsQueueFinished;
    _load();
  }

  Future<void> _load() async {
    final ticket = ++_loadTicket;
    if (_chapterWantsWebView) {
      await _enterWebView();
      return;
    }
    setState(() {
      _webViewMode = false;
      _loading = true;
      _errorText = null;
      _possiblyTruncated = false;
    });
    try {
      // Batch 31: downloaded chapters read from disk first
      // (offline parity with the manga reader).
      final local =
          await NovelDownloadStore.loadLocal(_item, _chapter);
      // Batch 184: a cached chapter only counts when it
      // carries readable content — a blank or corrupt
      // cache falls through to the network instead of
      // rendering as a finished, empty chapter.
      if (local != null && novelBlocksHaveContent(local)) {
        if (!mounted || ticket != _loadTicket) return;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        setState(() {
          _blocks = local;
          _loading = false;
        });
        await NovelLibraryStore.recordProgress(
          NovelProgress(
            item: _item,
            chapterIndex: _index,
            chapterTitle: _chapter.title,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        if (_ttsContinue) {
          _ttsContinue = false;
          if (local.isNotEmpty) _speakChapter();
        }
        return;
      }
      final result = await NovelApi.contentDetailed(_item, _chapter);
      final blocks = result.blocks;
      if (!mounted || ticket != _loadTicket) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      setState(() {
        _blocks = blocks;
        _loading = false;
        _possiblyTruncated = result.possiblyTruncated;
        // Batch 184: success means readable content, not
        // merely a non-empty list — whitespace-only blocks
        // land in the same empty state as no blocks.
        if (!novelBlocksHaveContent(blocks)) {
          _errorText = '这一章没有取到内容（源站可能需要网页渲染或暂时不可用）';
        }
      });
      await NovelLibraryStore.recordProgress(
        NovelProgress(
          item: _item,
          chapterIndex: _index,
          chapterTitle: _chapter.title,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (_ttsContinue) {
        _ttsContinue = false;
        if (novelBlocksHaveContent(blocks)) _speakChapter();
      }
      // Batch 192: warm the next chapter in the
      // background so flipping to it doesn't pay the
      // full engine + network path again.
      if (_index + 1 < _chapters.length) {
        NovelApi.prefetchContent(_item, _chapters[_index + 1]);
      }
    } catch (e) {
      if (!mounted || ticket != _loadTicket) return;
      // Batch 46: a chapter that dies hard marks its source.
      if (NovelSources.isHardDeadError(e.toString())) {
        NovelSources.recordDead(_item.source);
      }
      setState(() {
        _loading = false;
        _errorText = e is StackOverflowError
            ? 'Stack Overflow（Dart 阅读器层）— 源：${_item.sourceName}，章节：${_chapter.title}'
            : e.toString();
      });
    }
  }

  /// Batch 46: 换源阅读 — find the same book on another
  /// source (chapters verified non-empty by the API helper),
  /// keep the reading position by chapter title when the
  /// title matches, else by index, and reload in place.
  Future<void> _switchSource() async {
    if (_switchingSource) return;
    _stopTts();
    setState(() => _switchingSource = true);
    try {
      final found = await NovelApi.findReadableEdition(_item);
      if (!mounted) return;
      if (found == null) {
        AnikumoDialog.showToast(message: '没有找到可用的其他书源');
        return;
      }
      final chapters = await NovelApi.chapters(found);
      if (!mounted) return;
      if (chapters.isEmpty) {
        AnikumoDialog.showToast(message: '没有找到可用的其他书源');
        return;
      }
      final currentTitle = _chapter.title;
      var nextIndex = chapters.indexWhere((c) => c.title == currentTitle);
      if (nextIndex < 0) {
        nextIndex = _index.clamp(0, chapters.length - 1);
      }
      setState(() {
        _item = found;
        _chapters = chapters;
        _index = nextIndex;
        _forcedWebViewIndex = null;
        _errorText = null;
      });
      AnikumoDialog.showToast(
        message: '已切换到 ${NovelApi.sourceFor(found).name} 继续阅读',
      );
      _load();
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(message: '换源失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _switchingSource = false);
    }
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _chapters.length) return;
    _stopTts();
    setState(() => _index = next);
    _load();
  }

  void _showChapterList() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: _chapters.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(
            widget.args.chapters[index].title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          selected: index == _index,
          onTap: () {
            Navigator.pop(context);
            if (index != _index) {
              _stopTts();
              setState(() => _index = index);
              _load();
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = GStorage.getSetting(SettingsKeys.novelFontSize);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _chapter.title,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        actions: [
          if (NovelFeatures.isInstalled(NovelFeatures.ttsId))
            IconButton(
              icon: Icon(
                _tts.speaking
                    ? AnikumoIcons.stop_rounded
                    : AnikumoIcons.volume_up_rounded,
              ),
              tooltip: _tts.speaking ? '停止朗读' : '朗读本章',
              onPressed: _loading
                  ? null
                  : () => _tts.speaking ? _stopTts() : _speakChapter(),
            ),
        ],
      ),
      body: _webViewMode && _webView != null
          ? _webView!.build(context)
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _errorText != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NovelErrorState(
                            message: _errorText!, onRetry: _load),
                        TextButton.icon(
                          onPressed: () {
                            _forcedWebViewIndex = _index;
                            _load();
                          },
                          icon: const Icon(AnikumoIcons.public, size: 18),
                          label: const Text('用网页模式打开本章（图片章常用）'),
                        ),
                        TextButton.icon(
                          onPressed: _switchingSource ? null : _switchSource,
                          icon: const Icon(AnikumoIcons.swap_horiz, size: 18),
                          label: Text(_switchingSource ? '正在换源…' : '换个书源继续读'),
                        ),
                      ],
                    )
              // Batch 73: landscape/wide screens cap the
              // reading column and center it — full-width
              // lines at ~900dp are hard to track back
              // across. Portrait phones are narrower than
              // the cap and see no change.
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView.builder(
                  // A fresh scrollable per chapter: the new
                  // chapter always starts at the top.
                  key: ValueKey(_index),
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  // Batch 184: the tail exists only when the
                  // chapter-end state says so (see
                  // novelChapterTail) — never as an
                  // unconditional +1.
                  itemCount: _blocks.length +
                      (novelChapterTail(
                                hasContent:
                                    novelBlocksHaveContent(_blocks),
                                possiblyTruncated: _possiblyTruncated,
                              ) ==
                              NovelChapterTail.none
                          ? 0
                          : 1),
                  itemBuilder: (context, index) {
                    if (index == _blocks.length) {
                      final truncated = novelChapterTail(
                        hasContent: novelBlocksHaveContent(_blocks),
                        possiblyTruncated: _possiblyTruncated,
                      ) == NovelChapterTail.truncated;
                      return Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Center(
                          child: Text(
                            truncated
                                ? '— 内容可能不完整 · 源站分页未取完 —'
                                : '— 本章完 —',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: truncated
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      );
                    }
                    final block = _blocks[index];
                    return switch (block) {
                      NovelTextBlock(:final text) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          // Batch 32: plain Text, not
                          // SelectableText — a selection overlay
                          // per paragraph made long chapters
                          // stutter and resist scrolling/page
                          // turns (ninth-build feedback). Text
                          // lays out and paints far cheaper.
                          child: Text(
                            '　　$text',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: fontSize,
                              height: 1.75,
                            ),
                          ),
                        ),
                      NovelImageBlock(:final url, :final headers) =>
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: url.startsWith('file://')
                              ? Image.file(
                                  File(url.substring('file://'.length)),
                                  fit: BoxFit.fitWidth,
                                  errorBuilder: (context, _, _) =>
                                      const SizedBox(
                                    height: 120,
                                    child: Center(
                                      child:
                                          Icon(AnikumoIcons.broken_image_outlined),
                                    ),
                                  ),
                                )
                              : CachedNetworkImage(
                            imageUrl: url,
                            httpHeaders: headers.isEmpty ? null : headers,
                            fit: BoxFit.fitWidth,
                            placeholder: (context, _) => Container(
                              height: 180,
                              color:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                            errorWidget: (context, _, _) => Container(
                              height: 120,
                              color:
                                  theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(AnikumoIcons.broken_image_outlined),
                            ),
                                ),
                        ),
                    };
                  },
                    ),
                  ),
                ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_tts.speaking) _buildTtsStrip(theme),
          SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _index > 0 ? () => _go(-1) : null,
                icon: const Icon(AnikumoIcons.arrow_back_ios, size: 16),
                label: const Text('上一章'),
              ),
              TextButton.icon(
                onPressed: _showChapterList,
                icon: const Icon(AnikumoIcons.list, size: 18),
                label: Text('${_index + 1}/${_chapters.length}'),
              ),
              TextButton.icon(
                onPressed: _index < _chapters.length - 1
                    ? () => _go(1)
                    : null,
                icon: const Icon(AnikumoIcons.arrow_forward_ios, size: 16),
                label: const Text('下一章'),
              ),
            ],
          ),
        ),
          ),
        ],
      ),
    );
  }

  /// Batch 158: the read-aloud control strip, shown above
  /// the chapter bar while speech is active.
  Widget _buildTtsStrip(ThemeData theme) {
    const rates = [0.75, 1.0, 1.25, 1.5];
    final at = rates.indexWhere((r) => (r - _tts.rate).abs() < 0.01);
    final nextRate = rates[(at + 1) % rates.length];
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _tts.paused
                    ? AnikumoIcons.play_arrow_rounded
                    : AnikumoIcons.pause_rounded,
              ),
              tooltip: _tts.paused ? '继续朗读' : '暂停朗读',
              onPressed: () => _tts.paused ? _tts.resume() : _tts.pause(),
            ),
            IconButton(
              icon: const Icon(AnikumoIcons.stop_rounded),
              tooltip: '停止朗读',
              onPressed: _stopTts,
            ),
            Expanded(
              child: Text(
                _tts.paused
                    ? '朗读已暂停'
                    : '朗读中 · 第 ${_tts.currentChunk + 1}/${_tts.totalChunks} 段',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () => _tts.setRate(nextRate),
              child: Text('语速 ${_tts.rate}x'),
            ),
          ],
        ),
      ),
    );
  }
}
