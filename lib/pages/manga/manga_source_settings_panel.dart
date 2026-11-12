import 'package:flutter/material.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/js/mangakit_source.dart';
import 'package:anikumo/services/manga/manga_sources.dart';

/// Batch 191: the expanded panel under a JS source's row
/// in source management — the source's info, its links,
/// and editors for every setting it declares (select /
/// input / switch / callback), applied to the persisted
/// KV the runtime reads. This is the in-app replacement
/// for "go change it on the source's website".
/// Batch 198: one-line summary of the framework's
/// registration diagnostics for this source (surfaces the
/// compat layer could not map, init warnings) — shown in
/// the info block instead of silently swallowing them.
String mangaDiagnosticsText(Map<String, dynamic> diagnostics) {
  final parts = <String>[];
  final unmapped = diagnostics['unmappedSurfaces'];
  if (unmapped is List && unmapped.isNotEmpty) {
    parts.add('以下功能暂未适配：${unmapped.join('、')}');
  }
  final warning = diagnostics['initWarning']?.toString() ?? '';
  if (warning.isNotEmpty) parts.add('初始化提示：$warning');
  return parts.isEmpty
      ? '兼容性检查：全部通过'
      : '兼容性提示：${parts.join('；')}';
}

class MangaSourceSettingsPanel extends StatefulWidget {
  const MangaSourceSettingsPanel({
    super.key,
    required this.source,
    required this.isActive,
    required this.onActivate,
  });

  final JsBackedMangaSource source;
  final bool isActive;
  final VoidCallback onActivate;

  @override
  State<MangaSourceSettingsPanel> createState() =>
      _MangaSourceSettingsPanelState();
}

class _MangaSourceSettingsPanelState
    extends State<MangaSourceSettingsPanel> {
  List<MangaSettingDef>? _schema;
  Map<String, dynamic> _values = const {};
  bool _failed = false;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final schema = await widget.source.settingsSchema();
      if (!mounted) return;
      setState(() {
        _schema = schema;
        _values = widget.source.settingValues();
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _write(String key, Object? value) async {
    setState(() => _busyKey = key);
    try {
      await widget.source.writeSetting(key, value);
      if (!mounted) return;
      setState(() => _values = widget.source.settingValues());
      AnikumoDialog.showToast(message: '已保存');
    } catch (_) {
      if (mounted) AnikumoDialog.showToast(message: '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _runCallback(MangaSettingDef def) async {
    setState(() => _busyKey = def.key);
    try {
      await widget.source.invokeSettingCallback(def.key);
      if (!mounted) return;
      setState(() => _values = widget.source.settingValues());
      AnikumoDialog.showToast(message: '已执行「${def.title}」');
    } catch (_) {
      if (mounted) AnikumoDialog.showToast(message: '执行失败，请重试');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = widget.source;
    // Registration diagnostics exist only on the MangaKit
    // engine (batch 198); the legacy engine has none to show.
    final diagnostics =
        source is MangaKitMangaSource ? source.diagnostics : null;
    final origin = MangaSources.originOfKey(source.jsKey);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '版本 ${source.version} · ${source.jsKey} · ${source.fileName}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (source.declaredUrl != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              '源站：${source.declaredUrl}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (origin != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              '来源：$origin',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (diagnostics != null) ...[
            const SizedBox(height: 6),
            Text(
              mangaDiagnosticsText(diagnostics),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (!widget.isActive) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.onActivate,
                child: const Text('设为当前源'),
              ),
            ),
          ],
          const Divider(height: 20),
          if (_failed)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('设置读取失败，折叠后重新展开可重试'),
            )
          else if (_schema == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_schema!.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('这个源没有可设置的项'),
            )
          else
            for (final def in _schema!) _editor(theme, def),
        ],
      ),
    );
  }

  Widget _editor(ThemeData theme, MangaSettingDef def) {
    final busy = _busyKey == def.key;
    final current = _values[def.key] ?? def.defaultValue;
    switch (def.type) {
      case 'select':
        final options = def.options;
        final value = options.any((o) => o.value == current?.toString())
            ? current.toString()
            : (options.isNotEmpty ? options.first.value : null);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: Text(def.title)),
              DropdownButton<String>(
                value: value,
                items: [
                  for (final option in options)
                    DropdownMenuItem(
                      value: option.value,
                      child: Text(option.text),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (v) {
                        if (v != null) _write(def.key, v);
                      },
              ),
            ],
          ),
        );
      case 'switch':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(def.title),
          value: current == true,
          onChanged: busy ? null : (v) => _write(def.key, v),
        );
      case 'callback':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: Text(def.title)),
              FilledButton.tonal(
                onPressed: busy ? null : () => _runCallback(def),
                child: Text(def.buttonText ?? '执行'),
              ),
            ],
          ),
        );
      default:
        return _InputSettingEditor(
          key: ValueKey('${widget.source.jsKey}:${def.key}:$current'),
          def: def,
          current: current?.toString() ?? '',
          busy: busy,
          onSave: (v) => _write(def.key, v),
        );
    }
  }
}

class _InputSettingEditor extends StatefulWidget {
  const _InputSettingEditor({
    super.key,
    required this.def,
    required this.current,
    required this.busy,
    required this.onSave,
  });

  final MangaSettingDef def;
  final String current;
  final bool busy;
  final void Function(String value) onSave;

  @override
  State<_InputSettingEditor> createState() => _InputSettingEditorState();
}

class _InputSettingEditorState extends State<_InputSettingEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    final validator = widget.def.validator;
    if (validator != null && validator.isNotEmpty) {
      try {
        if (!RegExp(validator).hasMatch(value)) {
          AnikumoDialog.showToast(message: '「${widget.def.title}」格式不正确');
          return;
        }
      } catch (_) {
        // A validator the Dart regex engine cannot parse
        // must not block saving altogether.
      }
    }
    widget.onSave(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: widget.def.title,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.busy ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
