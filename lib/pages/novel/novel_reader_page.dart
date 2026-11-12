import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import '../../bean/dialog/dialog.dart';
import '../../models/novel_item.dart';
import '../../services/novel/legado_http.dart';
import '../../services/novel/legado_parse.dart';
import '../../services/novel/moyuan_host.dart';
import '../../services/novel/novel_api.dart';
import '../../services/reader_chrome_prefs.dart';
import '../../services/novel/novel_features.dart';
import '../../services/novel/novel_reader_themes.dart';
import '../../services/novel/tts_service.dart';
import '../../services/novel/novel_sources.dart';
import '../../services/novel/novel_downloads.dart';
import '../../services/novel/novel_library.dart';
import '../../services/storage/storage.dart';
import 'novel_verification_dialog.dart';
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
/// Batch 195 adds [verification]: the site gated the
/// chapter behind a verification check and only a short
/// preview was served — the tail then explains that and
/// offers the browser view instead of a warning alone.
enum NovelChapterTail { none, complete, truncated, verification }

NovelChapterTail novelChapterTail({
  required bool hasContent,
  required bool possiblyTruncated,
  bool verificationRequired = false,
}) => !hasContent
    ? NovelChapterTail.none
    : verificationRequired
    ? NovelChapterTail.verification
    : possiblyTruncated
    ? NovelChapterTail.truncated
    : NovelChapterTail.complete;

/// Batch 196: the cookie-jar hosts for a chapter URL —
/// the full host plus its registrable-looking parent
/// (wap.example.com → example.com), mirroring the login
/// page's harvest keys so a session planted from the
/// WebView lands where the engine jar looks for it.
List<String> novelCookieJarHosts(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return const [];
  final labels = host.split('.');
  if (labels.length >= 3) {
    return [host, labels.sublist(labels.length - 2).join('.')];
  }
  return [host];
}

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
  // Batch 195: the chapter stopped at a verification wall
  // (preview + captcha gate) — the tail explains and offers
  // the web view where the check can actually be passed.
  bool _verificationRequired = false;
  // Batch 196: the current WebView session was entered to
  // pass a verification wall. Leaving it for a native load
  // first plants the WebView's cookies into the engine
  // jar, so the native fetch rides the cleared session.
  bool _verificationWebView = false;
  bool _finishingVerification = false;
  // Batch 197: the wall's challenge descriptor (image-code
  // form), when the engine extracted one — the tail and
  // the empty state then offer an in-place solve prompt.
  Map<String, dynamic>? _verification;
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

  // Batch 251: reader chrome auto-hide — the app bar
  // and chapter bar used to be on screen for the whole
  // chapter. They now fade after a few idle seconds and
  // come back on a tap; scrolling restarts the countdown
  // while they are visible. WebView chapters keep their
  // chrome (their taps belong to the page, so there
  // would be no way to call the bars back).
  bool _chromeVisible = true;
  Timer? _chromeTimer;

  void _armChromeTimer() {
    _chromeTimer?.cancel();
    if (!_chromeVisible || _webViewMode) return;
    _chromeTimer = Timer(readerChromeHideDelay(), () {
      if (!mounted || !_chromeVisible) return;
      setState(() => _chromeVisible = false);
      _syncSystemUi();
    });
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    _syncSystemUi();
    _armChromeTimer();
  }

  void _showChrome() {
    if (!_chromeVisible) {
      setState(() => _chromeVisible = true);
      _syncSystemUi();
    }
    _armChromeTimer();
  }

  void _pokeChrome() {
    if (_chromeVisible) _armChromeTimer();
  }

  void _syncSystemUi() {
    SystemChrome.setEnabledSystemUIMode(
      _chromeVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  // Batch 235 （听书定时关闭 pack): sleep state — stop at
  // the end of the current chapter, or when the timer
  // fires.
  bool _ttsSleepAfterChapter = false;
  Timer? _ttsSleepTimer;

  @override
  void dispose() {
    _chromeTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _tts.removeListener(_onTtsChanged);
    if (_tts.onQueueFinished == _onTtsQueueFinished) {
      _tts.onQueueFinished = null;
    }
    _ttsSleepTimer?.cancel();
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
    // Batch 235 （听书定时关闭）: "stop after this chapter"
    // consumes the auto-advance once.
    if (_ttsSleepAfterChapter) {
      _ttsSleepAfterChapter = false;
      return;
    }
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
    _ttsSleepAfterChapter = false;
    _ttsSleepTimer?.cancel();
    _ttsSleepTimer = null;
    _tts.stop();
  }

  /// Batch 235 （听书定时关闭 pack): pick a sleep mode
  /// while TTS is running.
  Future<void> _pickTtsSleep() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('定时关闭朗读'),
        children: [
          for (final (value, label) in const [
            ('off', '关闭定时'),
            ('chapter', '读完本章停'),
            ('15', '15 分钟后停'),
            ('30', '30 分钟后停'),
            ('60', '60 分钟后停'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, value),
              child: Text(label),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    _ttsSleepTimer?.cancel();
    _ttsSleepTimer = null;
    _ttsSleepAfterChapter = choice == 'chapter';
    final minutes = int.tryParse(choice);
    if (minutes != null) {
      _ttsSleepTimer = Timer(Duration(minutes: minutes), () {
        if (mounted) _stopTts();
      });
    }
    setState(() {});
    AnikumoDialog.showToast(
      message: switch (choice) {
        'off' => '已关闭定时',
        'chapter' => '将读完本章后停止',
        _ => '将在 $minutes 分钟后停止朗读',
      },
    );
  }

  String get _cleanChapterUrl => LegadoParse.splitUrlOptions(_chapter.url).$1;

  bool get _chapterWantsWebView =>
      _chapter.webView || _forcedWebViewIndex == _index;

  Future<void> _enterWebView() async {
    // Batch 196: remember when this WebView session exists
    // to pass a verification wall — leaving it harvests
    // cookies (see the native path of _load).
    if (_verificationRequired) _verificationWebView = true;
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

  /// Batch 196: the reader passed the site's check in the
  /// WebView — drop this chapter's forced-WebView pin and
  /// reload natively; _load plants the WebView's cookies
  /// into the engine jar on the way in.
  void _finishVerification() {
    if (_finishingVerification) return;
    _finishingVerification = true;
    setState(() => _forcedWebViewIndex = null);
    AnikumoDialog.showToast(message: '正在用正常模式重新打开本章');
    _load().whenComplete(() => _finishingVerification = false);
  }

  /// Batch 197: solve the wall's image-code challenge in
  /// place — the dialog fetches the code image under the
  /// engine's session and posts the reader's answer the
  /// same way; this chapter then reloads natively, and
  /// the reload itself says whether the wall cleared.
  Future<void> _promptVerification() async {
    final verification = _verification;
    if (verification == null) return;
    final solved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          NovelVerificationDialog(item: _item, verification: verification),
    );
    if (solved == true && mounted) {
      await _load();
      // Batch 200: say how it turned out. The reload used
      // to be the only feedback, and a wall that quietly
      // came back read as "nothing happened at all".
      if (!mounted) return;
      AnikumoDialog.showToast(
        message: _verificationRequired ? '验证未通过，源站仍要求验证' : '验证已通过',
      );
    }
  }

  /// Batch 196: copy the WebView's cookies for this
  /// chapter's site into the engine's jar — the same
  /// harvest the login page performs after a sign-in, so
  /// the mechanism (and its host keys) stay identical.
  /// Best-effort: returns how many cookies were planted.
  Future<int> _harvestChapterCookies() async {
    try {
      final manager = PlatformCookieManager(
        const PlatformCookieManagerCreationParams(),
      );
      final urls = <String>{_cleanChapterUrl};
      final current = _webController != null
          ? await _webController!.getUrl()
          : null;
      if (current != null) urls.add(current.toString());
      var total = 0;
      final planted = <String>{};
      for (final url in urls) {
        if (url.isEmpty) continue;
        final cookies = await manager.getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          final name = cookie.name;
          final value = cookie.value?.toString() ?? '';
          if (name.isEmpty || value.isEmpty) continue;
          final domain = (cookie.domain ?? '').replaceFirst(RegExp(r'^\.'), '');
          for (final host in {
            domain,
            ...novelCookieJarHosts(_cleanChapterUrl),
          }) {
            if (host.isEmpty) continue;
            if (!planted.add('$host|$name')) continue;
            await MoyuanHost.instance.setCookie('https://$host/', name, value);
            total++;
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
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
          // Batch 200: a source with no UA of its own used
          // to leave the WebView with an EMPTY user agent —
          // a header anti-bot rules screen for on sight,
          // while the engine's fetches beside it carried
          // the default phone UA and loaded fine. Fall
          // back to that same default.
          userAgent: (ua == null || ua.isEmpty) ? LegadoHttp.defaultUa : ua,
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
    _scrollController.addListener(_pokeChrome);
    _load();
    _armChromeTimer();
  }

  Future<void> _load() async {
    _showChrome();
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
      _verificationRequired = false;
      _verification = null;
    });
    // Batch 196: leaving a verification WebView — plant
    // its cookies in the engine jar before fetching, so
    // this load rides the session the reader just cleared.
    // Best-effort: a failed harvest simply means the wall
    // notice comes back and the reader can retry.
    if (_verificationWebView) {
      _verificationWebView = false;
      await _harvestChapterCookies();
      if (!mounted || ticket != _loadTicket) return;
    }
    try {
      // Batch 31: downloaded chapters read from disk first
      // (offline parity with the manga reader).
      final local = await NovelDownloadStore.loadLocal(_item, _chapter);
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
        _verificationRequired = result.verificationRequired;
        _verification = result.verification;
        // Batch 184: success means readable content, not
        // merely a non-empty list — whitespace-only blocks
        // land in the same empty state as no blocks.
        // Batch 195: a walled chapter with no readable
        // preview at all says why, in the same empty state
        // (its buttons already offer the web view).
        if (!novelBlocksHaveContent(blocks)) {
          _errorText = result.verificationRequired
              ? '源站要求完成验证后才能阅读全文'
              : '这一章没有取到内容（源站可能需要网页渲染或暂时不可用）';
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
      // Batch 235 （深度预读 pack): warm two more chapters
      // ahead so a long reading run never waits at a
      // chapter boundary.
      if (NovelFeatures.isInstalled(NovelFeatures.deepPrefetchId)) {
        for (var ahead = 2; ahead <= 3; ahead++) {
          if (_index + ahead < _chapters.length) {
            NovelApi.prefetchContent(_item, _chapters[_index + ahead]);
          }
        }
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
        _verificationWebView = false;
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
    // Batch 235 （排版主题 pack): the chosen paper theme,
    // only while the pack is installed.
    final readerTheme = NovelFeatures.isInstalled(NovelFeatures.readerThemesId)
        ? NovelReaderTheme.byId(
            GStorage.getSetting(SettingsKeys.novelReaderTheme),
          )
        : null;
    return Scaffold(
      backgroundColor: readerTheme?.background,
      appBar: _chromeVisible
          ? AppBar(
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
                // Batch 235 （听书定时关闭 pack): the timer button
                // rides next to the TTS button it extends.
                if (NovelFeatures.isInstalled(NovelFeatures.ttsId) &&
                    NovelFeatures.isInstalled(NovelFeatures.ttsSleepId))
                  IconButton(
                    icon: Icon(
                      AnikumoIcons.timer_rounded,
                      color: (_ttsSleepAfterChapter || _ttsSleepTimer != null)
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    tooltip: '定时关闭朗读',
                    onPressed: _tts.speaking ? _pickTtsSleep : null,
                  ),
              ],
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleChrome,
        child: _webViewMode && _webView != null
            ? _webView!.build(context)
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorText != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  NovelErrorState(message: _errorText!, onRetry: _load),
                  // Batch 197: a walled chapter with no
                  // readable preview offers the
                  // in-place solve here too.
                  if (_verification != null)
                    TextButton.icon(
                      onPressed: _promptVerification,
                      icon: const Icon(AnikumoIcons.password_rounded, size: 18),
                      label: const Text('输入验证码'),
                    ),
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
                    itemCount:
                        _blocks.length +
                        (novelChapterTail(
                                  hasContent: novelBlocksHaveContent(_blocks),
                                  possiblyTruncated: _possiblyTruncated,
                                  verificationRequired: _verificationRequired,
                                ) ==
                                NovelChapterTail.none
                            ? 0
                            : 1),
                    itemBuilder: (context, index) {
                      if (index == _blocks.length) {
                        final tail = novelChapterTail(
                          hasContent: novelBlocksHaveContent(_blocks),
                          possiblyTruncated: _possiblyTruncated,
                          verificationRequired: _verificationRequired,
                        );
                        // Batch 195: a walled chapter's tail is
                        // an explanation plus the way through —
                        // the web view, where the site's check
                        // can actually be completed.
                        if (tail == NovelChapterTail.verification) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Column(
                              children: [
                                Text(
                                  '— 源站要求完成验证后才能阅读全文 · 以上只是开头预览 —',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Batch 197: when the challenge
                                // has the image-code shape, the
                                // fastest way through is right
                                // here — no browser detour.
                                if (_verification != null)
                                  TextButton.icon(
                                    onPressed: _promptVerification,
                                    icon: const Icon(
                                      AnikumoIcons.password_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('输入验证码'),
                                  ),
                                TextButton.icon(
                                  onPressed: () {
                                    _forcedWebViewIndex = _index;
                                    _load();
                                  },
                                  icon: const Icon(
                                    AnikumoIcons.public,
                                    size: 18,
                                  ),
                                  label: const Text('在网页中打开本章完成验证'),
                                ),
                              ],
                            ),
                          );
                        }
                        final truncated = tail == NovelChapterTail.truncated;
                        return Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Column(
                            children: [
                              Center(
                                child: Text(
                                  truncated
                                      ? '— 内容可能不完整 · 源站分页未取完 —'
                                      : novelChapterIsImageOnly(_blocks)
                                      ? '— 本章由源站以图片形式提供 —'
                                      : '— 本章完 —',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: truncated
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                              // Batch 200: a short chapter can
                              // also be a wall the engine could
                              // not describe (its form matched
                              // nothing) — give the truncated
                              // tail the same way through as the
                              // verification tail: the web view,
                              // whose cookies sync back on exit.
                              if (truncated) ...[
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    _forcedWebViewIndex = _index;
                                    _load();
                                  },
                                  icon: const Icon(
                                    AnikumoIcons.public,
                                    size: 18,
                                  ),
                                  label: const Text('在网页中打开本章'),
                                ),
                              ],
                            ],
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
                              height: readerTheme?.lineHeight ?? 1.75,
                              color: readerTheme?.foreground,
                            ),
                          ),
                        ),
                        NovelImageBlock(:final url, :final headers) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: url.startsWith('file://')
                              ? Image.file(
                                  File(url.substring('file://'.length)),
                                  fit: BoxFit.fitWidth,
                                  errorBuilder: (context, _, _) =>
                                      const SizedBox(
                                        height: 120,
                                        child: Center(
                                          child: Icon(
                                            AnikumoIcons.broken_image_outlined,
                                          ),
                                        ),
                                      ),
                                )
                              : CachedNetworkImage(
                                  imageUrl: url,
                                  // Batch 252: completed
                                  // headers (UA / chapter
                                  // Referer / jar cookies)
                                  // — see
                                  // novelImageRequestHeaders.
                                  httpHeaders: novelImageRequestHeaders(
                                    blockHeaders: headers,
                                    sourceHeaders: NovelApi.headersFor(_item),
                                    chapterUrl: _chapter.url,
                                    imageUrl: url,
                                    cookieHeader: novelCookieHeaderFor(url),
                                  ),
                                  fit: BoxFit.fitWidth,
                                  placeholder: (context, _) => Container(
                                    height: 180,
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                  errorWidget: (context, _, _) => Container(
                                    height: 120,
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: const Icon(
                                      AnikumoIcons.broken_image_outlined,
                                    ),
                                  ),
                                ),
                        ),
                      };
                    },
                  ),
                ),
              ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_webViewMode && _verificationWebView)
            _buildVerificationStrip(theme),
          if (_tts.speaking) _buildTtsStrip(theme),
          if (_chromeVisible)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
                      icon: const Icon(
                        AnikumoIcons.arrow_forward_ios,
                        size: 16,
                      ),
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

  /// Batch 196: shown above the chapter bar while a
  /// verification WebView is up — the way back to native
  /// reading once the site's check has been passed there.
  Widget _buildVerificationStrip(ThemeData theme) {
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            const Icon(AnikumoIcons.check_circle, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '在网页里完成验证后，点右边按钮用正常模式打开',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: _finishingVerification ? null : _finishVerification,
              child: const Text('已完成验证'),
            ),
          ],
        ),
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
