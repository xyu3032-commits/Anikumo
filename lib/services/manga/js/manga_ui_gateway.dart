import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/navigation.dart';

/// Batch 74: the UI half of the Venera bridge. Sources call
/// `UI.showMessage/showDialog/showInputDialog/...` (login
/// flows ask for captcha codes this way); those calls run
/// inside the QuickJS isolate, which cannot touch widgets,
/// so they relay here — the main isolate renders primitives
/// on the root navigator and reports the outcome back as
/// JSON. Callbacks and input validators never cross: the JS
/// shim resolves them locally from the reported outcome
/// (see `__anikumoUi` in venera_scripts.dart).
///
/// Supported: showMessage (toast), showDialog (labelled
/// buttons, any tap closes), launchUrl, showLoading /
/// cancelLoading (no cancel affordance — the library's
/// onCancel callback cannot be signalled back), and
/// showInputDialog (text, optional image URL + error hint),
/// showSelectDialog.
class MangaUiGateway {
  MangaUiGateway._();

  static int _loadingSeq = 0;
  static final Map<int, AnikumoDialogHandle<void>> _loadingHandles = {};

  /// Handles one UI payload (the JSON the source sent);
  /// always resolves to a JSON string, never throws.
  static Future<String> handle(String payloadJson) async {
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return jsonEncode({'error': 'bad UI message'});
      message = decoded.cast<String, dynamic>();
    } catch (_) {
      return jsonEncode({'error': 'bad UI message json'});
    }
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return jsonEncode({'error': '界面尚未就绪，请稍后重试'});
    }
    try {
      // The context is the root navigator's; AnikumoDialog.show
      // re-validates it (mounted check) before every push, so
      // handing it to the helpers across awaits is safe here.
      return switch (message['function']) {
        'showMessage' => _showMessage(message),
        'launchUrl' => await _launchUrl(message),
        // ignore: use_build_context_synchronously
        'showDialog' => await _showDialog(context, message),
        'showLoading' => _showLoading(message),
        'cancelLoading' => _cancelLoading(message),
        // ignore: use_build_context_synchronously
        'showInputDialog' => await _showInputDialog(context, message),
        // ignore: use_build_context_synchronously
        'showSelectDialog' => await _showSelectDialog(context, message),
        _ => jsonEncode({'error': '不支持的界面调用：${message['function']}'}),
      };
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  static String _showMessage(Map<String, dynamic> message) {
    AnikumoDialog.showToast(message: message['message']?.toString() ?? '');
    return 'null';
  }

  static Future<String> _launchUrl(Map<String, dynamic> message) async {
    final url = message['url']?.toString() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return jsonEncode({'error': '链接无效：$url'});
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return ok ? 'null' : jsonEncode({'error': '打不开这个链接：$url'});
  }

  static Future<String> _showDialog(
    BuildContext context,
    Map<String, dynamic> message,
  ) async {
    final actions = <Map<String, dynamic>>[];
    final rawActions = message['actions'];
    if (rawActions is List) {
      for (final raw in rawActions) {
        if (raw is Map) actions.add(raw.cast<String, dynamic>());
      }
    }
    final title = message['title']?.toString() ?? '';
    final content = message['content']?.toString() ?? '';
    final picked = await AnikumoDialog.show<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: title.isEmpty ? null : Text(title),
        content: content.isEmpty ? null : Text(content),
        actions: [
          for (var i = 0; i < actions.length; i++)
            if (actions[i]['style'] == 'filled')
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, i),
                child: Text(actions[i]['text']?.toString() ?? ''),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, i),
                style: actions[i]['style'] == 'danger'
                    ? TextButton.styleFrom(
                        foregroundColor:
                            Theme.of(dialogContext).colorScheme.error,
                      )
                    : null,
                child: Text(actions[i]['text']?.toString() ?? ''),
              ),
        ],
      ),
    );
    return jsonEncode({'action': picked ?? -1});
  }

  static String _showLoading(Map<String, dynamic> message) {
    final id = ++_loadingSeq;
    final handle = AnikumoDialogHandle<void>();
    _loadingHandles[id] = handle;
    unawaited(
      AnikumoDialog.show<void>(
        handle: handle,
        clickMaskDismiss: false,
        builder: (dialogContext) => const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Text('加载中…'),
            ],
          ),
        ),
      ).whenComplete(() => _loadingHandles.remove(id)),
    );
    return jsonEncode(id);
  }

  static String _cancelLoading(Map<String, dynamic> message) {
    final id = (message['id'] as num?)?.toInt();
    if (id != null) {
      _loadingHandles.remove(id)?.dismiss();
    }
    return 'null';
  }

  static Future<String> _showInputDialog(
    BuildContext context,
    Map<String, dynamic> message,
  ) async {
    final controller = TextEditingController();
    final title = message['title']?.toString() ?? '';
    final image = message['image']?.toString();
    final error = message['error']?.toString();
    final result = await AnikumoDialog.show<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: title.isEmpty ? null : Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (image != null && image.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Image.network(
                  image,
                  height: 96,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                errorText: (error != null && error.isNotEmpty) ? error : null,
              ),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return jsonEncode({'value': result});
  }

  static Future<String> _showSelectDialog(
    BuildContext context,
    Map<String, dynamic> message,
  ) async {
    final options = <String>[];
    final rawOptions = message['options'];
    if (rawOptions is List) {
      for (final raw in rawOptions) {
        options.add(raw?.toString() ?? '');
      }
    }
    final title = message['title']?.toString() ?? '';
    final initial = (message['initialIndex'] as num?)?.toInt() ?? -1;
    final picked = await AnikumoDialog.show<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: title.isEmpty ? null : Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (itemContext, index) => ListTile(
              dense: true,
              title: Text(options[index]),
              trailing: index == initial
                  ? Icon(
                      Icons.check,
                      color: Theme.of(itemContext).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(dialogContext, index),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    return jsonEncode(picked);
  }
}
