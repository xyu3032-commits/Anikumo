import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../bean/dialog/dialog.dart';
import '../../services/manga/manga_source.dart';
import '../../services/manga/manga_sources.dart';
import '../../utils/error_message.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 74: sign in to a JS manga source's own account.
///
/// Sources in the Venera shape may define `account.login`
/// (picacg / jm / kavita do): the source itself talks to its
/// site and keeps the session — a token in its persisted
/// data, or cookies in the shared jar. This page is only the
/// form: it asks the source whether it has a login, hands
/// the credentials to the source's function, and reports the
/// session state the dispatcher + host session store agree
/// on. The password is never stored by the host (a source
/// may keep it in its own data for re-login — its choice,
/// same as in Venera).
class MangaLoginPage extends StatefulWidget {
  const MangaLoginPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  State<MangaLoginPage> createState() => _MangaLoginPageState();
}

class _MangaLoginPageState extends State<MangaLoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  MangaAccountInfo? _info;
  bool _probing = true;
  bool _busy = false;
  String? _probeError;
  bool _obscurePassword = true;

  MangaSource? get _source => MangaSources.byId(widget.sourceId);

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final source = _source;
    if (source == null) {
      setState(() => _probing = false);
      return;
    }
    try {
      final info = await source.accountInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _probing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeError = friendlyError(e);
      });
    }
  }

  Future<void> _login() async {
    final source = _source;
    if (source == null || _busy) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      AnikumoDialog.showToast(message: '账号和密码都要填');
      return;
    }
    setState(() => _busy = true);
    try {
      await source.login(username, password);
      if (!mounted) return;
      AnikumoDialog.showToast(message: '登录成功');
      await _probe();
    } catch (e) {
      if (!mounted) return;
      AnikumoDialog.showToast(message: '登录失败：${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final source = _source;
    if (source == null || _busy) return;
    setState(() => _busy = true);
    try {
      await source.logout();
      if (!mounted) return;
      AnikumoDialog.showToast(message: '已退出登录');
      await _probe();
    } catch (e) {
      if (!mounted) return;
      AnikumoDialog.showToast(message: '退出失败：${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRegister() async {
    final website = _info?.registerWebsite;
    if (website == null) return;
    final uri = Uri.tryParse(website);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _source;
    return Scaffold(
      appBar: AppBar(title: Text(source?.name ?? '源账号')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          if (source == null)
            const Text('这个源已经不存在了')
          else if (_probing)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_probeError != null) ...[
            Icon(
              AnikumoIcons.error_outline,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text('读取源的账号信息失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(_probeError!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _probe, child: const Text('重试')),
          ] else if (_info == null) ...[
            Icon(
              AnikumoIcons.account_circle_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('这个源没有账号登录', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '它的内容不需要登录即可使用；如果某个功能提示要登录，可能是这个源的登录方式比较特殊，本 App 暂不支持。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (_info!.isLoggedIn) ...[
            Icon(
              AnikumoIcons.verified_user_outlined,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('已登录', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '这个源的会话已经生效，搜索、详情和收藏等功能会带登录状态请求。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _busy ? null : _logout,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('退出登录'),
            ),
          ] else ...[
            Text(
              '登录 ${source.name}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '账号密码只交给这个源自己的登录函数，App 不保存密码。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '账号',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              autocorrect: false,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? AnikumoIcons.visibility_outlined
                        : AnikumoIcons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
            if (_info!.registerWebsite != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _openRegister,
                child: const Text('没有账号？去注册'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
