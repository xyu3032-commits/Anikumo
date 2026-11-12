import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../bean/widget/anikumo_icons.dart';
import '../../models/novel_item.dart';
import '../../services/novel/legado_http.dart';
import '../../services/novel/moyuan_host.dart';
import '../../services/novel/novel_api.dart';

/// Batch 200: the headers a verification request rides
/// out on — the source's own headers, with the engine's
/// default UA filled in when the source declares none.
/// The engine's own fetches always carry that UA
/// (LegadoHttp puts it on every request); these dialog
/// requests used to fall back to the HTTP library's
/// tell-tale default UA instead — exactly the sort of
/// header a site's anti-bot rule screens submissions
/// for, while the chapter fetch beside it looked like a
/// phone browser.
Map<String, dynamic> verificationSessionHeaders({
  required Map<String, String> sourceHeaders,
  required String pageUrl,
  required String cookie,
}) {
  final headers = <String, dynamic>{
    ...sourceHeaders,
    'Referer': pageUrl,
  };
  final hasUa =
      sourceHeaders.keys.any((k) => k.toLowerCase() == 'user-agent');
  if (!hasUa) headers['User-Agent'] = LegadoHttp.defaultUa;
  if (cookie.isNotEmpty) headers['Cookie'] = cookie;
  return headers;
}

/// Batch 197: in-place solve for an image-code
/// verification wall (layer 1 of the verification
/// support; B196's browser view is layer 2 for challenge
/// shapes this dialog cannot express).
///
/// The descriptor comes from the engine's reading of the
/// wall page: the captcha image, the code field, the
/// submit target and any hidden form fields. Both the
/// image fetch and the form post ride the ENGINE's
/// session — the jar's cookie header goes out, and any
/// Set-Cookie coming back is planted into the jar —
/// because the code a site issues is bound to the session
/// it was issued under. The reader (a human) supplies the
/// answer; nothing here tries to read the image itself.
/// Pops true once a submit was accepted (below 400): the
/// chapter reload that follows is the ground truth about
/// whether the wall cleared. An error status keeps the
/// dialog open and says the site refused the submission
/// (batch 200) — the two outcomes used to look identical.
class NovelVerificationDialog extends StatefulWidget {
  const NovelVerificationDialog({
    super.key,
    required this.item,
    required this.verification,
  });

  final NovelItem item;
  final Map<String, dynamic> verification;

  @override
  State<NovelVerificationDialog> createState() =>
      _NovelVerificationDialogState();
}

class _NovelVerificationDialogState
    extends State<NovelVerificationDialog> {
  final _codeController = TextEditingController();
  Uint8List? _imageBytes;
  bool _loadingImage = true;
  bool _submitting = false;
  String? _errorText;

  String get _imageUrl =>
      widget.verification['imageUrl']?.toString() ?? '';
  String get _submitUrl =>
      widget.verification['submitUrl']?.toString() ?? '';
  String get _field => widget.verification['field']?.toString() ?? '';
  String get _pageUrl =>
      widget.verification['pageUrl']?.toString() ?? _submitUrl;

  Map<String, String> get _fields {
    final raw = widget.verification['fields'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        e.key.toString(): e.value?.toString() ?? '',
    };
  }

  Map<String, dynamic> _sessionHeaders(String url) {
    return verificationSessionHeaders(
      sourceHeaders: NovelApi.headersFor(widget.item),
      pageUrl: _pageUrl,
      cookie: MoyuanHost.instance.cookieHeaderFor(url),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    setState(() {
      _loadingImage = true;
      _errorText = null;
    });
    try {
      final response = await Dio().get<List<int>>(
        _imageUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: _sessionHeaders(_imageUrl),
        ),
      );
      // The image response may rotate the session the
      // code is bound to — the jar must carry the new
      // one before the post goes out.
      await MoyuanHost.instance.plantSetCookies(
        _imageUrl,
        response.headers.map['set-cookie'] ?? const [],
      );
      if (!mounted) return;
      setState(() {
        _imageBytes = Uint8List.fromList(response.data ?? const []);
        _loadingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingImage = false;
        _errorText = '验证码图片加载失败，点刷新重试';
      });
    }
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      final response = await Dio().post<dynamic>(
        _submitUrl,
        data: {_field: code, ..._fields},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: _sessionHeaders(_submitUrl),
          // Any HTTP answer — even a refusal — closes the
          // dialog; the chapter reload shows what the
          // site actually decided.
          validateStatus: (_) => true,
        ),
      );
      await MoyuanHost.instance.plantSetCookies(
        _submitUrl,
        response.headers.map['set-cookie'] ?? const [],
      );
      if (!mounted) return;
      // Batch 200: an error status means the site never
      // accepted the submission at all (these walls sit
      // behind anti-bot rules that answer 444/403 to
      // requests they dislike) — say that, and keep the
      // dialog open, instead of closing silently and
      // leaving the reader to guess whether the code was
      // wrong or never arrived.
      final status = response.statusCode ?? 0;
      if (status >= 400) {
        setState(() {
          _submitting = false;
          _errorText =
              '站点没有接受这次提交（$status）——可能正在限流，稍后再试，或改用网页中打开本章';
        });
        return;
      }
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = '提交没有送达——站点拒绝了连接或网络异常，稍后再试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('输入验证码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 56,
                child: _loadingImage
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : _imageBytes != null && _imageBytes!.isNotEmpty
                        ? Image.memory(_imageBytes!, height: 56)
                        : const Center(child: Text('（图片不可用）')),
              ),
              IconButton(
                onPressed: _loadingImage ? null : _loadImage,
                icon: const Icon(AnikumoIcons.refresh_rounded, size: 20),
                tooltip: '换一张',
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            autofocus: true,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: '验证码',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '输入图中字符后点确认，本章会重新加载',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? '提交中…' : '确认'),
        ),
      ],
    );
  }
}
