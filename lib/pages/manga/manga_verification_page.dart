import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import 'package:anikumo/navigation.dart';
import 'package:anikumo/services/manga/js/mangakit_host.dart';

/// Batch 198: the manga zone's verification flow — the
/// MangaKit counterpart of the novel zone's two layers. When
/// a source's site answers with a verification wall (a
/// Cloudflare challenge, a captcha form), the framework
/// asks the host to open this page; the USER personally
/// clears the wall in a real WebView, and the cookies the
/// site issues are planted into the engine's jar so the
/// retried request rides the earned session. Nothing is
/// solved automatically — no OCR, no token farming — the
/// exact policy the framework itself enforces.
class MangaVerification {
  MangaVerification._();

  static bool _installed = false;

  /// Registers the framework-side solver hook. Idempotent;
  /// called when the manga zone is entered.
  static void install() {
    if (_installed) return;
    _installed = true;
    MangaKitRuntime.onSolveVerification = ({required url, required kind}) {
      return solve(url: url);
    };
  }

  static bool isVerificationError(Object? error) =>
      error is MangaKitException && error.isVerificationRequired;

  /// Opens the verification page over the current stack.
  /// Resolves true when the user tapped 已完成验证 (cookies
  /// harvested and planted), false on dismissal.
  static Future<bool> solve({required String url}) async {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null || url.isEmpty) return false;
    final result = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => MangaVerificationPage(url: url),
      ),
    );
    return result == true;
  }
}

/// The verification WebView page: the wall's own page, a
/// hint bar, and the completion button that harvests the
/// session cookies into the MangaKit jar.
class MangaVerificationPage extends StatefulWidget {
  const MangaVerificationPage({super.key, required this.url});

  final String url;

  @override
  State<MangaVerificationPage> createState() => _MangaVerificationPageState();
}

class _MangaVerificationPageState extends State<MangaVerificationPage> {
  PlatformInAppWebViewWidget? _webView;
  var _finishing = false;

  @override
  void initState() {
    super.initState();
    _webView = PlatformInAppWebViewWidget(
      PlatformInAppWebViewWidgetCreationParams(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useWideViewPort: true,
          loadWithOverviewMode: true,
        ),
      ),
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final manager =
          PlatformCookieManager(const PlatformCookieManagerCreationParams());
      final host = Uri.tryParse(widget.url)?.host ?? '';
      final urls = <String>{
        widget.url,
        if (host.isNotEmpty) 'https://$host/',
      };
      final raw = <String>[];
      for (final url in urls) {
        final cookies = await manager.getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          final name = cookie.name;
          final value = cookie.value?.toString() ?? '';
          if (name.isEmpty || value.isEmpty) continue;
          final domain = (cookie.domain ?? '').replaceFirst(
            RegExp(r'^\.'),
            '',
          );
          raw.add(
            domain.isEmpty
                ? '$name=$value'
                : '$name=$value; Domain=$domain',
          );
        }
      }
      MangaKitRuntime.instance.plantRawSetCookies(widget.url, raw);
    } catch (_) {
      // Harvest is best-effort: the framework replays the
      // request either way, and a still-walled reply simply
      // surfaces the verification state again.
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('完成验证')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Text(
              '源站要求先完成人机验证。在下面页面里完成验证后，点「已完成验证」回到阅读。',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: _webView?.build(context) ?? const SizedBox.shrink(),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _finishing ? null : _finish,
                  child: Text(_finishing ? '正在同步…' : '已完成验证'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The error-state button pages show when a load failed
/// with a verification wall: opens [MangaVerificationPage]
/// for [url] and calls [onSolved] after a completed solve
/// (pages retry their load there).
class MangaVerificationButton extends StatelessWidget {
  const MangaVerificationButton({
    super.key,
    required this.url,
    required this.onSolved,
  });

  final String url;
  final VoidCallback onSolved;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () async {
        final solved = await MangaVerification.solve(url: url);
        if (solved) onSolved();
      },
      icon: const Icon(Icons.verified_user_outlined, size: 18),
      label: const Text('完成验证'),
    );
  }
}
