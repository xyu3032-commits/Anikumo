import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import '../../bean/dialog/dialog.dart';
import '../../services/novel/legado_def.dart';
import '../../services/novel/login_info.dart';
import '../../services/novel/moyuan_host.dart';
import '../../services/novel/novel_source.dart';
import '../../services/novel/novel_sources.dart';

/// Batch 68: sign in to a login-gated novel source.
///
/// Some sources declare a loginUrl and serve nothing (or
/// an empty shell) until the reader is signed in. The
/// user signs in here in a real WebView; on 完成 the
/// WebView's cookies for the source's site are harvested
/// into the engine's persistent jar, so the source's
/// search/explore/detail requests carry the session from
/// then on. 清除登录 drops both the jar entries and the
/// WebView cookies for the site.
///
/// Batch 169: sources may instead (or also) declare a
/// login FORM (their loginUi field): text/password inputs,
/// selects, and buttons whose JS action runs in the
/// source's own script context — a web-login button
/// (its action asks to open a page) lands here as a
/// browse request and opens the WebView below the form.
/// Saved values persist per source and are what rule
/// scripts read back as their login info.
///
/// Batch 174: the jar and the script context are the
/// MoYuan engine's now (MoyuanHost); the persisted form
/// values stay the app's own store and are seeded into
/// the engine from there.
class NovelLoginPage extends StatefulWidget {
  const NovelLoginPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  State<NovelLoginPage> createState() => _NovelLoginPageState();
}

class _NovelLoginPageState extends State<NovelLoginPage> {
  PlatformInAppWebViewWidget? _webView;
  String? _webViewUrl;
  bool _saving = false;

  /// Batch 169: the declared form rows, the values in
  /// force, and a browse target a button action asked for.
  List<LoginRow> _rows = const [];
  final Map<String, String> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  String? _browseUrl;

  LegadoSourceDef? get _def {
    final source = NovelSources.byId(widget.sourceId);
    return source is LegadoNovelSource ? source.def : null;
  }

  @override
  void initState() {
    super.initState();
    final def = _def;
    if (def != null) {
      _rows = LoginUi.parse(def.raw['loginUi']);
      if (_rows.isNotEmpty) {
        _values.addAll(NovelLoginInfo.valuesFor(widget.sourceId, _rows));
        for (final row in _rows) {
          if (row.isButton || row.isSelect) continue;
          _controllers[row.name] =
              TextEditingController(text: _values[row.name] ?? '');
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _webView?.dispose();
    super.dispose();
  }

  Future<void> _onBrowse(String url, String title) async {
    if (!mounted) return;
    setState(() {
      _browseUrl = url;
      _webView = null;
      _webViewUrl = null;
    });
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

  Set<String> get _harvestUrls {
    final source = NovelSources.byId(widget.sourceId);
    return {
      if (source != null && source.loginUrl.startsWith('http'))
        source.loginUrl,
      ?_browseUrl,
      'https://$_sourceHost/',
    };
  }

  Future<int> _harvestCookies() async {
    final manager =
        PlatformCookieManager(const PlatformCookieManagerCreationParams());
    var total = 0;
    final planted = <String>{};
    for (final url in _harvestUrls) {
      if (url.isEmpty) continue;
      final cookies = await manager.getCookies(url: WebUri(url));
      for (final cookie in cookies) {
        final name = cookie.name;
        final value = cookie.value?.toString() ?? '';
        if (name.isEmpty || value.isEmpty) continue;
        final domain = (cookie.domain ?? '').replaceFirst(RegExp(r'^\.'), '');
        // Plant under the cookie's own domain and the
        // source's host keys: the engine jar matches by
        // host, and a session cookie is no use filed
        // under a host the source never talks to.
        for (final host in {domain, ..._jarHosts}) {
          if (host.isEmpty) continue;
          if (!planted.add('$host|$name')) continue;
          await MoyuanHost.instance
              .setCookie('https://$host/', name, value);
          total++;
        }
      }
    }
    return total;
  }

  Future<void> _saveAll() async {
    final source = NovelSources.byId(widget.sourceId);
    if (source == null) return;
    setState(() => _saving = true);
    try {
      if (_rows.isNotEmpty) {
        for (final row in _rows) {
          if (row.isButton || row.isSelect) continue;
          final controller = _controllers[row.name];
          if (controller != null) _values[row.name] = controller.text;
        }
        final saved = {
          for (final row in _rows)
            if (!row.isButton) row.name: _values[row.name] ?? '',
        };
        await NovelLoginInfo.save(widget.sourceId, saved);
        // The save flow then hands the values to the
        // engine, which runs the source's own login hook
        // when it declares a script one.
        try {
          await MoyuanHost.instance
              .submitLoginForm(widget.sourceId, saved);
        } catch (_) {
          // A failing login hook must not lose the save.
        }
      }
      var total = 0;
      if (_webView != null) total = await _harvestCookies();
      if (!mounted) return;
      if (_rows.isNotEmpty) {
        AnikumoDialog.showToast(
          message: total > 0
              ? '已保存登录信息与登录状态（$total 个 Cookie）'
              : '已保存登录信息',
        );
        Navigator.of(context).pop();
      } else {
        AnikumoDialog.showToast(
          message: total > 0
              ? '已保存登录状态（$total 个 Cookie），回去重新打开这个源试试'
              : '没有读到登录 Cookie，请确认已在页面里完成登录',
        );
        if (total > 0) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        AnikumoDialog.showToast(message: '保存登录状态失败：$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runAction(LoginRow row) async {
    final def = _def;
    if (def == null || row.action.trim().isEmpty) return;
    // The overwhelmingly common button action asks to
    // open a web login page; the engine cannot browse,
    // so a literal target in the action opens the
    // WebView below the form directly.
    final browse = RegExp(r"""startBrowserAwait\(\s*['"]([^'"]+)['"]""")
        .firstMatch(row.action);
    if (browse != null) {
      await _onBrowse(browse.group(1)!, row.label);
      return;
    }
    try {
      await MoyuanHost.instance
          .runLoginAction(widget.sourceId, row.action);
    } catch (e) {
      if (mounted) {
        AnikumoDialog.showToast(message: '执行失败：$e');
      }
    }
  }

  Future<void> _clearLogin() async {
    final source = NovelSources.byId(widget.sourceId);
    if (source == null) return;
    await NovelLoginInfo.clear(widget.sourceId);
    try {
      final manager =
          PlatformCookieManager(const PlatformCookieManagerCreationParams());
      for (final url in _harvestUrls) {
        if (url.isEmpty) continue;
        await manager.deleteCookies(url: WebUri(url));
      }
    } catch (_) {}
    await MoyuanHost.instance
        .clearSourceLogin(widget.sourceId, _jarHosts);
    if (mounted) {
      AnikumoDialog.showToast(message: '已清除这个源的登录状态');
    }
  }

  Widget _rowField(LoginRow row, ThemeData theme) {
    if (row.isButton) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: OutlinedButton(
          onPressed: () => _runAction(row),
          child: Text(row.label),
        ),
      );
    }
    if (row.isSelect) {
      final value = _values[row.name];
      return ListTile(
        title: Text(row.label),
        trailing: DropdownButton<String>(
          value: row.chars.contains(value) ? value : null,
          hint: const Text('请选择'),
          items: [
            for (final choice in row.chars)
              DropdownMenuItem(value: choice, child: Text(choice)),
          ],
          onChanged: (next) {
            if (next != null) {
              setState(() => _values[row.name] = next);
            }
          },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: TextField(
        controller: _controllers[row.name],
        obscureText: row.isPassword,
        decoration: InputDecoration(
          labelText: row.label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = NovelSources.byId(widget.sourceId);
    if (source == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('书源登录')),
        body: const Center(child: Text('这个源已不存在。')),
      );
    }
    final theme = Theme.of(context);
    final loginUrl = source.loginUrl;
    final webUrl = _browseUrl ??
        (loginUrl.startsWith('http') ? loginUrl : null);
    if (_rows.isEmpty && webUrl == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('书源登录')),
        body: const Center(child: Text('这个源没有声明登录页，或源已不存在。')),
      );
    }
    if (webUrl != null && _webViewUrl != webUrl) {
      _webViewUrl = webUrl;
      final ua = source.headers.entries
          .where((e) => e.key.toLowerCase() == 'user-agent')
          .map((e) => e.value)
          .firstOrNull;
      _webView = PlatformInAppWebViewWidget(
        PlatformInAppWebViewWidgetCreationParams(
          initialUrlRequest: URLRequest(
            url: WebUri(webUrl),
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
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('登录 · ${source.name}'),
        actions: [
          TextButton(
            onPressed: _clearLogin,
            child: const Text('清除登录'),
          ),
          TextButton(
            onPressed: _saving ? null : _saveAll,
            child: Text(_saving ? '保存中…' : '完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Text(
              _rows.isNotEmpty
                  ? '按这个源的要求填写下面几项，点右上角「完成」保存；'
                      '需要网页登录时，点表单里的按钮打开登录页，登录后同样点「完成」。'
                  : '在页面里登录这个网站，登录成功后点右上角「完成」，'
                      '登录状态会保存下来，这个源的搜索和目录就会带上它。',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (_rows.isNotEmpty)
            Expanded(
              flex: webUrl == null ? 1 : 2,
              child: ListView(
                children: [
                  for (final row in _rows) _rowField(row, theme),
                ],
              ),
            ),
          if (webUrl != null)
            Expanded(flex: 3, child: _webView!.build(context)),
        ],
      ),
    );
  }
}
