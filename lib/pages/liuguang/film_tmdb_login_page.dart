import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import '../../bean/dialog/dialog.dart';
import '../../services/liuguang/film_accounts.dart';

/// Batch 254: TMDB account sign-in. Creates a v3 request
/// token, lets the user approve it on TMDB's own page in
/// this WebView, then exchanges it for a session when
/// they tap 完成授权 (TMDB's approve page has no redirect
/// back into the app, so the explicit confirm is the
/// reliable signal — the same shape as the novel zone's
/// login page).
class FilmTmdbLoginPage extends StatefulWidget {
  const FilmTmdbLoginPage({super.key});

  @override
  State<FilmTmdbLoginPage> createState() => _FilmTmdbLoginPageState();
}

class _FilmTmdbLoginPageState extends State<FilmTmdbLoginPage> {
  PlatformInAppWebViewWidget? _webView;
  String? _token;
  String? _error;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final token = await TmdbAccount.createRequestToken();
    if (!mounted) return;
    if (token == null) {
      setState(() => _error = '无法连接 TMDB，请检查网络后重试。');
      return;
    }
    _token = token;
    setState(() {
      _webView = PlatformInAppWebViewWidget(
        PlatformInAppWebViewWidgetCreationParams(
          initialUrlRequest: URLRequest(
            url: WebUri(TmdbAccount.authenticateUrl(token)),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useWideViewPort: true,
            loadWithOverviewMode: true,
          ),
        ),
      );
    });
  }

  Future<void> _complete() async {
    final token = _token;
    if (token == null || _completing) return;
    setState(() => _completing = true);
    final ok = await TmdbAccount.completeLogin(token);
    if (!mounted) return;
    setState(() => _completing = false);
    if (ok) {
      AnikumoDialog.showToast(
        context: context,
        message: '已连接 TMDB 账户 @${TmdbAccount.username}',
      );
      Navigator.of(context).pop(true);
    } else {
      AnikumoDialog.showToast(
        context: context,
        message: '还没有检测到授权——请先在网页上登录并点「允许」，再点完成授权。',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接 TMDB 账户'),
        actions: [
          TextButton(
            onPressed: (_token == null || _completing) ? null : _complete,
            child: Text(_completing ? '连接中…' : '完成授权'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              '在 TMDB 官网登录并允许授权后，点右上角「完成授权」。'
              '连接后可以在详情页把作品同步到 TMDB 的收藏 / 想看，'
              '也能在「我的云端片单」里打开它们。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : _webView == null
                ? const Center(child: CircularProgressIndicator())
                : _webView!.build(context),
          ),
        ],
      ),
    );
  }
}
