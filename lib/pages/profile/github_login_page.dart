import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/profile/github_sync.dart';

/// Batch 258: GitHub sign-in lives on ONE in-app page —
/// the device code sits in a banner over GitHub's own
/// device page in an embedded browser. The first cut
/// sent the user to an external browser; switching apps
/// backgrounded Anikumo and the polling login quietly
/// died there, so nothing ever took effect. Here the
/// page (and its polling) stays in the foreground the
/// whole time, and returning to the app re-polls at
/// once for good measure.
class GithubLoginPage extends StatefulWidget {
  const GithubLoginPage({super.key});

  @override
  State<GithubLoginPage> createState() => _GithubLoginPageState();
}

class _GithubLoginPageState extends State<GithubLoginPage>
    with WidgetsBindingObserver {
  GithubDeviceCode? _code;
  PlatformInAppWebViewWidget? _webView;
  String? _error;
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the foreground — check the authorization
    // right away instead of waiting out the interval.
    if (state == AppLifecycleState.resumed && !_done) _poll();
  }

  Future<void> _start() async {
    _timer?.cancel();
    setState(() {
      _code = null;
      _webView = null;
      _error = null;
    });
    try {
      final code = await GithubSync.startDeviceFlow();
      if (!mounted) return;
      setState(() {
        _code = code;
        _webView = PlatformInAppWebViewWidget(
          PlatformInAppWebViewWidgetCreationParams(
            initialUrlRequest: URLRequest(url: WebUri(code.verificationUri)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useWideViewPort: true,
              loadWithOverviewMode: true,
            ),
          ),
        );
      });
      _schedule(code.intervalSeconds);
    } on GithubSyncException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _schedule(int seconds) {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: seconds), _poll);
  }

  Future<void> _poll() async {
    final code = _code;
    if (code == null || _done) return;
    final state = await GithubSync.pollDeviceFlow(code);
    if (!mounted || _done) return;
    switch (state) {
      case GithubPollState.authorized:
        _done = true;
        AnikumoDialog.showToast(context: context, message: 'GitHub 已连接');
        Navigator.of(context).pop(true);
      case GithubPollState.pending:
        _schedule(code.intervalSeconds);
      case GithubPollState.slowDown:
        _schedule(code.intervalSeconds + 5);
      case GithubPollState.denied:
        setState(() => _error = '已在 GitHub 上拒绝授权，关闭本页即可。');
      case GithubPollState.expired:
        setState(() => _error = '登录码已过期，点下方按钮重新获取。');
      case GithubPollState.error:
        _schedule(code.intervalSeconds + 5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _code;
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub 登录')),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _start, child: const Text('重新获取登录码')),
                ],
              ),
            )
          else if (code == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '在下方 GitHub 页面输入这串码并授权，完成后自动登录：',
                          style: theme.textTheme.bodySmall,
                        ),
                        SelectableText(
                          code.userCode,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '复制登录码',
                    icon: const Icon(AnikumoIcons.content_copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code.userCode));
                      AnikumoDialog.showToast(
                        context: context,
                        message: '登录码已复制',
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(child: _webView!.build(context)),
          ],
        ],
      ),
    );
  }
}
