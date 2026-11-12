import 'package:flutter/material.dart';

import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/manga/manga_features.dart';

/// Batch 234: the manga zone's feature repository —
/// same pattern as the novel (Batch 158), film
/// (Batch 232) and anime (Batch 233) zones. Optional
/// capability features live here; the user installs or
/// uninstalls each one, and only installed features exist
/// anywhere else in the zone. Extra repository addresses
/// can list more entries — an entry is installable only
/// when this version implements its capability, otherwise
/// it is marked unsupported.
class MangaFeatureRepoPage extends StatefulWidget {
  const MangaFeatureRepoPage({super.key});

  @override
  State<MangaFeatureRepoPage> createState() => _MangaFeatureRepoPageState();
}

class _MangaFeatureRepoPageState extends State<MangaFeatureRepoPage> {
  List<MangaFeatureDef> _remote = const [];
  bool _loadingRemote = false;

  @override
  void initState() {
    super.initState();
    MangaFeatures.revision.addListener(_onRevision);
    _refreshRemote();
  }

  @override
  void dispose() {
    MangaFeatures.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshRemote() async {
    final urls = MangaFeatures.repoUrls();
    if (urls.isEmpty) {
      setState(() => _remote = const []);
      return;
    }
    setState(() => _loadingRemote = true);
    final merged = <String, MangaFeatureDef>{};
    for (final url in urls) {
      try {
        for (final def in await MangaFeatures.fetchCatalog(url)) {
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

  Future<void> _install(MangaFeatureDef def) async {
    await MangaFeatures.setInstalled(def.id, true);
    if (mounted) {
      AnikumoDialog.showToast(message: '已安装「${def.name}」');
    }
  }

  Future<void> _uninstall(MangaFeatureDef def) async {
    await MangaFeatures.setInstalled(def.id, false);
    // Batch 251: uninstall used to be the silent twin
    // of install (which toasts) — the button flipping
    // back was the only sign anything happened.
    if (mounted) {
      AnikumoDialog.showToast(message: '已卸载「${def.name}」');
    }
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
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      await MangaFeatures.fetchCatalog(url);
    } catch (e) {
      if (mounted) {
        AnikumoDialog.showToast(message: '仓库不可用：$e');
      }
      return;
    }
    await MangaFeatures.addRepo(url);
    await _refreshRemote();
    if (mounted) {
      AnikumoDialog.showToast(message: '已添加仓库');
    }
  }

  IconData _iconFor(String id) => switch (id) {
    MangaFeatures.cbzExportId => AnikumoIcons.folder_zip_outlined,
    MangaFeatures.readerFiltersId => AnikumoIcons.color_lens_rounded,
    MangaFeatures.autoScrollId => AnikumoIcons.play_circle_rounded,
    MangaFeatures.deepPrefetchId => AnikumoIcons.rocket_launch_rounded,
    _ => AnikumoIcons.extension_rounded,
  };

  Widget _featureTile(MangaFeatureDef def) {
    final installed = MangaFeatures.isInstalled(def.id);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconFor(def.id), size: 28),
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
    final builtinIds = {for (final f in MangaFeatures.builtinCatalog) f.id};
    final remoteOnly = [
      for (final f in _remote)
        if (!builtinIds.contains(f.id)) f,
    ];
    final mergedBuiltin = [
      for (final f in MangaFeatures.builtinCatalog)
        _remote.where((r) => r.id == f.id).firstOrNull ?? f,
    ];
    final repos = MangaFeatures.repoUrls();
    return Scaffold(
      appBar: AppBar(title: const Text('漫画功能仓库')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              '功能',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final def in mergedBuiltin) _featureTile(def),
          if (_loadingRemote)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          for (final def in remoteOnly) _featureTile(def),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(
              '仓库地址',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
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
              title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(AnikumoIcons.delete_outline, size: 20),
                onPressed: () async {
                  await MangaFeatures.removeRepo(url);
                  if (mounted) {
                    AnikumoDialog.showToast(message: '已移除仓库');
                  }
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
