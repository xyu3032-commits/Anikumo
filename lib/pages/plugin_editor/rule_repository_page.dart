import 'package:flutter/material.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/plugins/plugins.dart';
import 'package:anikumo/plugins/plugins_controller.dart';
import 'package:anikumo/services/plugin/rule_repository.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/utils/error_message.dart';
import 'package:anikumo/utils/transient_retry.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 62: the rule repository, restored as a purely
/// user-driven feature (the built-in repository was removed
/// in batch 59). The user supplies a repository address —
/// a raw directory containing index.json, or a GitHub repo
/// page address — and can batch-import rules from it with
/// checkboxes instead of installing one by one.
class RuleRepositoryPage extends StatefulWidget {
  const RuleRepositoryPage({
    super.key,
    required this.controller,
    this.initialAddress,
  });

  final PluginsController controller;
  final String? initialAddress;

  @override
  State<RuleRepositoryPage> createState() => _RuleRepositoryPageState();
}

class _RuleRepositoryPageState extends State<RuleRepositoryPage> {
  late final _address = TextEditingController(
    text: widget.initialAddress ??
        GStorage.getSetting(SettingsKeys.ruleRepositoryUrl),
  );
  String? _loadedBase;
  List<RuleCatalogItem> _items = const [];
  final Set<String> _selected = {};
  bool _loading = false;
  bool _importing = false;
  String? _error;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    if (_address.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Set<String> get _installedKeys => {
        for (final plugin in widget.controller.pluginList)
          pluginNameKey(plugin.name),
      };

  Future<void> _load() async {
    final base = RuleRepository.normalizeBase(_address.text);
    if (base == null) {
      setState(() => _error =
          '这不像仓库地址。支持 raw 目录地址（内含 index.json），'
          '或 GitHub 仓库地址，如 github.com/用户/仓库。');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await RuleRepository.fetchCatalog(base);
      await GStorage.putSetting(SettingsKeys.ruleRepositoryUrl, base);
      if (!mounted) return;
      setState(() {
        _loadedBase = base;
        _items = catalog.items;
        _selected.clear();
        _loading = false;
      });
      if (catalog.items.isEmpty) {
        setState(() => _error = '仓库目录是空的，没有可导入的规则。');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载仓库失败：${friendlyError(e)}';
      });
    }
  }

  Future<void> _importSelected() async {
    final base = _loadedBase;
    if (base == null || _selected.isEmpty || _importing) return;
    final names = [
      for (final item in _items)
        if (_selected.contains(item.name)) item.name,
    ];
    setState(() {
      _importing = true;
      _progress = '';
    });
    final plugins = <Plugin>[];
    final failures = <String>[];
    // Batch 62 optimization: bounded-concurrency downloads
    // (5 in flight) with one transient retry each — a full
    // repository used to download strictly one file at a
    // time. Progress counts completions as they land.
    var done = 0;
    const concurrency = 5;
    for (var start = 0; start < names.length; start += concurrency) {
      if (!mounted) return;
      final end = start + concurrency > names.length
          ? names.length
          : start + concurrency;
      final chunk = names.sublist(start, end);
      final fetched = await Future.wait(chunk.map((name) async {
        try {
          return await retryTransient(
              () => RuleRepository.fetchRule(base, name));
        } catch (_) {
          return null;
        }
      }));
      for (var i = 0; i < chunk.length; i++) {
        final plugin = fetched[i];
        if (plugin == null) {
          failures.add(chunk[i]);
        } else {
          plugins.add(plugin);
        }
      }
      done += chunk.length;
      if (!mounted) return;
      setState(() => _progress = '已下载 $done/${names.length}');
    }
    if (plugins.isNotEmpty) {
      await widget.controller.updatePlugins(plugins);
    }
    if (!mounted) return;
    setState(() {
      _importing = false;
      _progress = '';
      _selected.clear();
    });
    AnikumoDialog.showToast(
      message: failures.isEmpty
          ? '已导入 ${plugins.length} 条规则'
          : '已导入 ${plugins.length} 条，失败 ${failures.length} 条'
              '（${failures.take(3).join('、')}）',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final installed = _installedKeys;
    return Scaffold(
      appBar: AppBar(title: const Text('规则仓库')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '仓库是一个集中存放规则文件的地址。填入后这里会列出'
                        '仓库里的全部规则，勾选即可批量导入，不必再一条条添加。',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _address,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: '仓库地址',
                          hintText: 'github.com/用户/仓库 或 raw 目录地址',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: '加载仓库',
                            onPressed: _loading ? null : _load,
                            icon: const Icon(AnikumoIcons.refresh_rounded),
                          ),
                        ),
                        onSubmitted: (_) => _loading ? null : _load(),
                      ),
                      if (_loadedBase != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '已加载：${_loadedBase}index.json（共 ${_items.length} 条）',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.outline),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: colors.error),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _loading ? null : _load,
                            icon: _loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(AnikumoIcons.cloud_download_outlined),
                            label: Text(_loading ? '加载中…' : '加载仓库'),
                          ),
                          const Spacer(),
                          if (_items.isNotEmpty) ...[
                            TextButton(
                              onPressed: _importing
                                  ? null
                                  : () => setState(() => _selected
                                      .addAll(_items.map((e) => e.name))),
                              child: const Text('全选'),
                            ),
                            TextButton(
                              onPressed: _importing
                                  ? null
                                  : () => setState(_selected.clear),
                              child: const Text('清空'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              _loading
                                  ? '正在读取仓库目录…'
                                  : '填入仓库地址并点「加载仓库」，规则会列在这里。',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final isInstalled =
                                installed.contains(pluginNameKey(item.name));
                            return CheckboxListTile(
                              value: _selected.contains(item.name),
                              onChanged: _importing
                                  ? null
                                  : (checked) => setState(() {
                                        if (checked ?? false) {
                                          _selected.add(item.name);
                                        } else {
                                          _selected.remove(item.name);
                                        }
                                      }),
                              title: Row(
                                children: [
                                  Flexible(child: Text(item.name)),
                                  if (isInstalled) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colors.tertiaryContainer,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '已安装',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: colors.onTertiaryContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                [
                                  if (item.version.isNotEmpty)
                                    'v${item.version}',
                                  if (item.author.isNotEmpty) item.author,
                                ].join(' · '),
                              ),
                            );
                          },
                        ),
                ),
                if (_items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_progress.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(_progress,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant)),
                          ),
                        FilledButton.icon(
                          onPressed: _selected.isEmpty || _importing
                              ? null
                              : _importSelected,
                          icon: const Icon(AnikumoIcons.download_rounded),
                          label: Text(_importing
                              ? '导入中…'
                              : '导入所选（${_selected.length} 条）'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
