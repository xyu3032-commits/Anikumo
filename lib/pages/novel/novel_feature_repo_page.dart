import 'package:flutter/material.dart';

import '../../bean/dialog/dialog.dart';
import '../../bean/widget/anikumo_icons.dart';
import '../../services/novel/novel_features.dart';
import '../../services/novel/tts_service.dart';
import 'novel_widgets.dart';

/// Batch 158: the novel zone's feature repository.
/// Optional capability features live here; the user
/// installs or uninstalls each one, and only installed
/// features exist anywhere else in the zone. Extra
/// repository addresses can list more entries — an entry
/// is installable only when this version implements its
/// capability, otherwise it is marked unsupported.
class NovelFeatureRepoPage extends StatefulWidget {
  const NovelFeatureRepoPage({super.key});

  @override
  State<NovelFeatureRepoPage> createState() => _NovelFeatureRepoPageState();
}

class _NovelFeatureRepoPageState extends State<NovelFeatureRepoPage> {
  List<NovelFeatureDef> _remote = const [];
  bool _loadingRemote = false;

  @override
  void initState() {
    super.initState();
    NovelFeatures.revision.addListener(_onRevision);
    _refreshRemote();
  }

  @override
  void dispose() {
    NovelFeatures.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshRemote() async {
    final urls = NovelFeatures.repoUrls();
    if (urls.isEmpty) {
      setState(() => _remote = const []);
      return;
    }
    setState(() => _loadingRemote = true);
    final merged = <String, NovelFeatureDef>{};
    for (final url in urls) {
      try {
        for (final def in await NovelFeatures.fetchCatalog(url)) {
          merged[def.id] = def;
        }
      } catch (_) {
        // A dead repository must not break the page; its
        // entries simply do not appear.
      }
    }
    if (!mounted) return;
    setState(() {
      _remote = merged.values.toList();
      _loadingRemote = false;
    });
  }

  Future<void> _install(NovelFeatureDef def) async {
    if (def.id == NovelFeatures.ttsId) {
      final available = await TtsPlayer.isAvailable();
      if (!available) {
        if (mounted) {
          AnikumoDialog.showToast(message: '当前设备没有可用的系统语音，无法安装');
        }
        return;
      }
    }
    await NovelFeatures.setInstalled(def.id, true);
    if (mounted) {
      AnikumoDialog.showToast(message: '已安装「${def.name}」');
    }
  }

  Future<void> _uninstall(NovelFeatureDef def) async {
    if (def.id == NovelFeatures.localBooksId) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('卸载本地书籍？'),
          content: const Text(
            '卸载后，本地书籍会从书架、搜索和发现中隐藏；'
            '已导入的文件会保留，重新安装即可恢复。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('卸载'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (def.id == NovelFeatures.ttsId) {
      await TtsPlayer.instance.stop();
    }
    await NovelFeatures.setInstalled(def.id, false);
  }

  Future<void> _addRepo() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加仓库地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://…/catalog.json',
            labelText: '目录文件地址（JSON）',
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      await NovelFeatures.fetchCatalog(url);
    } catch (e) {
      if (mounted) {
        AnikumoDialog.showToast(message: '仓库不可用：$e');
      }
      return;
    }
    await NovelFeatures.addRepo(url);
    await _refreshRemote();
    if (mounted) {
      AnikumoDialog.showToast(message: '已添加仓库');
    }
  }

  Widget _featureTile(NovelFeatureDef def) {
    final installed = NovelFeatures.isInstalled(def.id);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              def.id == NovelFeatures.ttsId
                  ? AnikumoIcons.volume_up_rounded
                  : AnikumoIcons.library_books_rounded,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        def.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (def.version.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          'v${def.version}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    def.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          height: 1.45,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!def.supported)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('此版本暂不支持'),
              )
            else if (installed)
              Column(
                children: [
                  const Chip(
                    label: Text('已安装'),
                    visualDensity: VisualDensity.compact,
                  ),
                  TextButton(
                    onPressed: () => _uninstall(def),
                    child: const Text('卸载'),
                  ),
                ],
              )
            else
              FilledButton(
                onPressed: () => _install(def),
                child: const Text('安装'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final builtinIds = {for (final f in NovelFeatures.builtinCatalog) f.id};
    final remoteOnly = [
      for (final f in _remote)
        if (!builtinIds.contains(f.id)) f,
    ];
    final mergedBuiltin = [
      for (final f in NovelFeatures.builtinCatalog)
        _remote.where((r) => r.id == f.id).firstOrNull ?? f,
    ];
    final repos = NovelFeatures.repoUrls();
    return Scaffold(
      appBar: AppBar(title: const Text('功能仓库')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const NovelSectionHeader(title: '功能'),
          for (final def in mergedBuiltin) _featureTile(def),
          if (_loadingRemote)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          for (final def in remoteOnly) _featureTile(def),
          const NovelSectionHeader(title: '仓库地址'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '仓库地址指向一个功能目录文件（JSON 数组，每项含 id / name / description）。'
              '只有当前版本已适配的功能可以安装，其余会标注暂不支持。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    height: 1.45,
                  ),
            ),
          ),
          for (final url in repos)
            ListTile(
              leading: const Icon(AnikumoIcons.link, size: 20),
              title: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(AnikumoIcons.delete_outline, size: 20),
                onPressed: () async {
                  await NovelFeatures.removeRepo(url);
                  await _refreshRemote();
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _addRepo,
              icon: const Icon(AnikumoIcons.add, size: 18),
              label: const Text('添加仓库地址'),
            ),
          ),
        ],
      ),
    );
  }
}
