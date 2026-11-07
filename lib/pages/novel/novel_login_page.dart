import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import '../../bean/dialog/dialog.dart';
import '../../services/novel/legado_http.dart';
import '../../services/novel/novel_sources.dart';

/// Batch 68: sign in to a login-gated novel source.
///
/// Some sources declare a loginUrl and serve nothing (or
/// an empty shell) until the reader is signed in. The
/// user signs in here in a real WebView; on 完成 the
/// WebView's cookies for the source's site are harvested
/// into the engine's persistent jar (LegadoHttp), so the
/// source's search/explore/detail requests carry the
/// session from then on. 清除登录 drops both the jar
/// entries and the WebView cookies for the site.
class NovelLoginPage extends StatefulWidget {
  const NovelLoginPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  State<NovelLoginPage> createState() => _NovelLoginPageState();
}

class _NovelLoginPageState extends State<NovelLoginPage> {
  PlatformInAppWebViewWidget? _webView;
  bool _saving = false;

  @override
  void dispose() {
    _webView?.dispose();
    super.dispose();
  }

  String get _sourceHost {
    final source = NovelSources.byId(widget.sourceId);
    if (source == null) return '';
    return Uri.tryParse(source.id)?.host ?? '';
  }

  /// The jar keys cookies ride under: the full host and
  /// its registrable-looking parent (www.example.com →
  /// example.com), so subdomains share the session.
  List<String> get _jarHosts {
    final host = _sourceHost;
    if (host.isEmpty) return const [];
    final labels = host.split('.');
    if (labels.length >= 3) {
      return [host, labels.sublist(labels.length - 2).join('.')];
    }
    return [host];
  }

  Future<void> _harvestAndPop() async {
    final source = NovelSources.byId(widget.sourceId);
    if (source == null) return;
    setState(() => _saving = true);
    try {
      final manager =
          PlatformCookieManager(const PlatformCookieManagerCreationParams());
      final byDomain = <String, Map<String, String>>{};
      final urls = <String>{
        source.loginUrl,
        'https://$_sourceHost/',
      };
      for (final url in urls) {
        if (url.isEmpty) continue;
        final cookies = await manager.getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          final name = cookie.name;
          final value = cookie.value?.toString() ?? '';
          if (name.isEmpty || value.isEmpty) continue;
          final domain = (cookie.domain ?? '').replaceFirst(RegExp(r'^\.'), '');
          for (final key in {domain, ..._jarHosts}) {
            if (key.isEmpty) continue;
            byDomain.putIfAbsent(key, () => {})[name] = value;
          }
        }
      }
      var total = 0;
      for (final entry in byDomain.entries) {
        await LegadoHttp.importCookies(entry.key, entry.value);
        total += entry.value.length;
      }
      if (!mounted) return;
      AnikumoDialog.showToast(
        message: total > 0
            ? '已保存登录状态（$total 个 Cookie），回去重新打开这个源试试'
            : '没有读到登录 Cookie，请确认已在页面里完成登录',
      );
      if (total > 0) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        AnikumoDialog.showToast(message: '保存登录状态失败：$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearLogin() async {
    final source = NovelSources.byId(widget.sourceId);
    if (source == null) return;
    try {
      final manager =
          PlatformCookieManager(const PlatformCookieManagerCreationParams());
      for (final url in {source.loginUrl, 'https://$_sourceHost/'}) {
        if (url.isEmpty) continue;
        await manager.deleteCookies(url: WebUri(url));
      }
    } catch (_) {}
    for (final host in _jarHosts) {
      await LegadoHttp.clearCookiesFor(host);
    }
    if (mounted) {
      AnikumoDialog.showToast(message: '已清除这个源的登录状态');
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = NovelSources.byId(widget.sourceId);
    if (source == null || source.loginUrl.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('书源登录')),
        body: const Center(child: Text('这个源没有声明登录页，或源已不存在。')),
      );
    }
    final ua = source.headers.entries
        .where((e) => e.key.toLowerCase() == 'user-agent')
        .map((e) => e.value)
        .firstOrNull;
    _webView ??= PlatformInAppWebViewWidget(
      PlatformInAppWebViewWidgetCreationParams(
        initialUrlRequest: URLRequest(
          url: WebUri(source.loginUrl),
          headers: source.headers,
        ),
        initialSettings: InAppWebViewSettings(
          userAgent: ua ?? '',
          javaScriptEnabled: true,
          useWideViewPort: true,
          loadWithOverviewMode: true,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('登录 · ${source.name}'),
        actions: [
          TextButton(
            onPressed: _clearLogin,
            child: const Text('清除登录'),
          ),
          TextButton(
            onPressed: _saving ? null : _harvestAndPop,
            child: Text(_saving ? '保存中…' : '完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              '在页面里登录这个网站，登录成功后点右上角「完成」，'
              '登录状态会保存下来，这个源的搜索和目录就会带上它。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: _webView!.build(context)),
        ],
      ),
    );
  }
}
