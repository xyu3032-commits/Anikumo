import 'package:flutter/material.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';
import 'package:anikumo/services/liuguang/film_prefs.dart';
import 'package:anikumo/services/liuguang/film_probes.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/liuguang/video_repository.dart';

/// Batches 203–204 / 209: 源 — the zone's repository （仓库）
/// and interface-source registry. A repository can be
/// imported （导入） to install all its directly-usable
/// sources at once; a configuration can also be pasted by
/// hand. Batch 209 designed the management surface the user
/// asked for: 片源检测 (one-tap 全部检测 with progress,
/// per-source latency / failure reason / 上次检测， persisted
/// across restarts), 片源设置 (tap a source for its settings
/// sheet: rename, re-address, enable, test, delete) and
/// 片源搜索 (filter the installed list by name / address /
/// repository).
class FilmSourcesTab extends StatefulWidget {
  const FilmSourcesTab({super.key});

  @override
  State<FilmSourcesTab> createState() => _FilmSourcesTabState();
}

class _FilmSourcesTabState extends State<FilmSourcesTab> {
  final Set<String> _importing = {};
  final VideoRepositoryImporter _importer = VideoRepositoryImporter();
  final TextEditingController _searchCtl = TextEditingController();
  String _query = '';

  /// Batch 237 (speed half): per-row 测速 state; results
  /// land in the shared FilmSourceSpeeds table the home
  /// page's fastest-first order reads.
  final Set<String> _speedTesting = {};
  bool _speedBusyAll = false;
  int _speedDone = 0;
  int _speedTotal = 0;

  Future<void> _testSpeed(VideoSourceEntry source) async {
    if (!_speedTesting.add(source.id)) return;
    setState(() {});
    await probeFilmSourceSpeed(source);
    _speedTesting.remove(source.id);
    if (mounted) setState(() {});
  }

  Future<void> _testAllSpeeds(VideoEngineService service) async {
    if (_speedBusyAll) return;
    final targets = service.sources.where((s) => s.enabled).toList();
    if (targets.isEmpty) return;
    setState(() {
      _speedBusyAll = true;
      _speedDone = 0;
      _speedTotal = targets.length;
    });
    await probeAllFilmSourceSpeeds(
      targets,
      onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _speedDone = done;
            _speedTotal = total;
          });
        }
      },
    );
    if (mounted) setState(() => _speedBusyAll = false);
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _importRepository(VideoRepositoryEntry repo) async {
    if (_importing.contains(repo.url)) return;
    setState(() => _importing.add(repo.url));
    final report = await _importer.importFromUrl(repo);
    if (!mounted) return;
    setState(() => _importing.remove(repo.url));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(report.describe())));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VideoEngineService.instance,
      builder: (context, _) {
        final service = VideoEngineService.instance;
        service.loadRegistry();
        final visible = filterFilmSources(service.sources, _query);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Batch 221: editorial title bar.
            FilmEditorialTitle(
              eyebrow: 'SOURCES · 片源',
              title: filmHeadline(context, '片源'),
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _sectionTitle(
                    context,
                    '仓库',
                    '仓库地址指向一份配置，导入后一次装入其中全部可用的接口源。',
                  ),
                ),
                TextButton(
                  onPressed: () => _pasteConfig(context),
                  child: const Text('粘贴配置'),
                ),
                IconButton(
                  tooltip: '添加仓库',
                  icon: const Icon(AnikumoIcons.add_rounded),
                  onPressed: () => _addRepository(context),
                ),
              ],
            ),
            if (service.repositories.isEmpty)
              _hint(context, '还没有添加仓库')
            else
              for (final repo in service.repositories)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(AnikumoIcons.inbox_rounded),
                  title: Text(repo.name),
                  subtitle: Text(
                    repo.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_importing.contains(repo.url))
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        TextButton(
                          onPressed: () => _importRepository(repo),
                          child: const Text('导入'),
                        ),
                      IconButton(
                        tooltip: '删除仓库',
                        icon: const Icon(AnikumoIcons.delete_outline_rounded),
                        onPressed: () => service.removeRepository(repo.url),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _sectionTitle(
                    context,
                    '接口源',
                    '单个接口地址也可以直接添加；开关关闭的源不参与搜索与浏览。点源一行打开它的设置。',
                  ),
                ),
                if (service.sources.isNotEmpty)
                  TextButton(
                    onPressed: service.checkingAll
                        ? null
                        : () => service.checkAllSources(),
                    child: Text(
                      service.checkingAll
                          ? '检测中 ${service.checkDone}/${service.checkTotal}'
                          : '全部检测',
                    ),
                  ),
                if (service.sources.any((s) => s.enabled))
                  TextButton(
                    onPressed: _speedBusyAll
                        ? null
                        : () => _testAllSpeeds(service),
                    child: Text(
                      _speedBusyAll ? '测速中 $_speedDone/$_speedTotal' : '全部测速',
                    ),
                  ),
                // Batch 222: once checks mark sources unusable,
                // offer their removal right here — the user's
                // call, never automatic.
                if (service.sources.any(
                  (s) => service.healthById[s.id]?.ok == false,
                ))
                  TextButton(
                    onPressed: service.checkingAll
                        ? null
                        : () => _confirmDeleteFailed(context, service),
                    child: Text(
                      '删除不可用',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '添加接口源',
                  icon: const Icon(AnikumoIcons.add_rounded),
                  onPressed: () => _addSource(context),
                ),
              ],
            ),
            if (service.sources.length > 3) ...[
              TextField(
                controller: _searchCtl,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(AnikumoIcons.search_rounded, size: 20),
                  hintText: '搜索片源（名称 / 地址 / 仓库）',
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(
                            AnikumoIcons.close_rounded,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchCtl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 6),
              Text(
                '共 ${service.sources.length} 个，显示 ${visible.length} 个',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (service.sources.isEmpty)
              _hint(context, '还没有接口源')
            else if (visible.isEmpty)
              _hint(context, '没有匹配「$_query」的片源')
            else
              for (final source in visible)
                _sourceTile(context, service, source),
          ],
        );
      },
    );
  }

  Widget _sourceTile(
    BuildContext context,
    VideoEngineService service,
    VideoSourceEntry source,
  ) {
    final health = service.healthById[source.id];
    final colors = Theme.of(context).colorScheme;
    final dotColor = health == null
        ? colors.outlineVariant
        : health.ok
        ? Colors.green
        : colors.error;
    return InkWell(
      onTap: () => _openSourceSettings(context, source),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [
                      source.api,
                      if (source.fromRepository.isNotEmpty)
                        '来自仓库「${source.fromRepository}」',
                      if (health != null)
                        health.ok
                            ? '可用 · ${health.latencyMs}ms · '
                                  '${filmCheckAgeText(health.checkedAt, DateTime.now())}检测'
                            : '不可用：${health.message} · '
                                  '${filmCheckAgeText(health.checkedAt, DateTime.now())}检测',
                      if (FilmSourceSpeeds.recordOf(source.id)
                          case final speed?)
                        speed.ms >= 0
                            ? '测速 ${speed.ms}ms · '
                                  '${filmCheckAgeText(speed.at, DateTime.now())}测'
                            : '测速失败 · '
                                  '${filmCheckAgeText(speed.at, DateTime.now())}测',
                    ].join('\n'),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Batch 222: a source the check found unusable
            // can be deleted straight from its row.
            if (health != null && !health.ok)
              IconButton(
                tooltip: '删除此源',
                icon: Icon(
                  AnikumoIcons.delete_outline_rounded,
                  color: colors.error,
                ),
                onPressed: () =>
                    _confirmDeleteSources(context, service, [source]),
              ),
            TextButton(
              onPressed: () => service.checkSourceHealth(source),
              child: const Text('检测'),
            ),
            if (_speedTesting.contains(source.id))
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton(
                onPressed: () => _testSpeed(source),
                child: const Text('测速'),
              ),
            Switch(
              value: source.enabled,
              onChanged: (v) => service.setSourceEnabled(source.id, v),
            ),
            const Icon(AnikumoIcons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  /// Batch 222: delete-after-failed-check, always behind a
  /// confirmation the user controls.
  Future<void> _confirmDeleteFailed(
    BuildContext context,
    VideoEngineService service,
  ) {
    final failed = service.sources
        .where((s) => service.healthById[s.id]?.ok == false)
        .toList();
    if (failed.isEmpty) return Future.value();
    return _confirmDeleteSources(context, service, failed);
  }

  Future<void> _confirmDeleteSources(
    BuildContext context,
    VideoEngineService service,
    List<VideoSourceEntry> targets,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          targets.length == 1
              ? '删除源「${targets.first.name}」？'
              : '删除 ${targets.length} 个不可用的源？',
        ),
        content: Text(
          '${targets.map((e) => '「${e.name}」').join('、')} 已检测为不可用。'
          '删除后不再参与搜索与浏览，之后可以重新添加。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    for (final target in targets) {
      await service.removeSource(target.id);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除 ${targets.length} 个源')));
    }
  }

  Future<void> _openSourceSettings(
    BuildContext context,
    VideoSourceEntry source,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SourceSettingsSheet(sourceId: source.id),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _hint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _pasteConfig(BuildContext context) async {
    final nameCtl = TextEditingController();
    final textCtl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴配置导入'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: '仓库名称（可空）'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: textCtl,
                decoration: const InputDecoration(
                  labelText: '配置内容',
                  hintText: '把整份配置文本粘贴到这里',
                  alignLabelWithHint: true,
                ),
                minLines: 5,
                maxLines: 9,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || textCtl.text.trim().isEmpty) {
      nameCtl.dispose();
      textCtl.dispose();
      return;
    }
    final report = await _importer.importFromText(
      textCtl.text,
      repositoryName: nameCtl.text.trim().isEmpty
          ? '粘贴导入'
          : nameCtl.text.trim(),
    );
    nameCtl.dispose();
    textCtl.dispose();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(report.describe())));
  }

  Future<void> _addSource(BuildContext context) async {
    final result = await _entryDialog(
      context,
      title: '添加接口源',
      nameLabel: '名称',
      urlLabel: '接口地址',
    );
    if (result == null) return;
    final api = result.$2.trim();
    await VideoEngineService.instance.addSources([
      VideoSourceEntry(
        id: VideoSourceEntry.idForApi(api),
        name: result.$1.trim().isEmpty ? api : result.$1.trim(),
        api: api,
      ),
    ]);
  }

  Future<void> _addRepository(BuildContext context) async {
    final result = await _entryDialog(
      context,
      title: '添加仓库',
      nameLabel: '仓库名称',
      urlLabel: '仓库地址',
    );
    if (result == null) return;
    await VideoEngineService.instance.addRepository(
      VideoRepositoryEntry(name: result.$1.trim(), url: result.$2.trim()),
    );
  }

  Future<(String, String)?> _entryDialog(
    BuildContext context, {
    required String title,
    required String nameLabel,
    required String urlLabel,
  }) async {
    final nameCtl = TextEditingController();
    final urlCtl = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: InputDecoration(labelText: nameLabel),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlCtl,
              decoration: InputDecoration(
                labelText: urlLabel,
                hintText: 'https://…',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (urlCtl.text.trim().isEmpty) return;
              Navigator.of(dialogContext).pop((nameCtl.text, urlCtl.text));
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    nameCtl.dispose();
    urlCtl.dispose();
    return result;
  }
}

/// Batch 209: one source's settings sheet — rename,
/// re-address, enable/disable, health status with one-tap
/// re-test, and delete (with confirmation).
class _SourceSettingsSheet extends StatefulWidget {
  const _SourceSettingsSheet({required this.sourceId});

  final String sourceId;

  @override
  State<_SourceSettingsSheet> createState() => _SourceSettingsSheetState();
}

class _SourceSettingsSheetState extends State<_SourceSettingsSheet> {
  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _apiCtl = TextEditingController();
  bool _seeded = false;
  bool _saving = false;
  bool _testing = false;

  @override
  void dispose() {
    _nameCtl.dispose();
    _apiCtl.dispose();
    super.dispose();
  }

  VideoSourceEntry? _entry(VideoEngineService service) {
    for (final s in service.sources) {
      if (s.id == widget.sourceId) return s;
    }
    return null;
  }

  Future<void> _save(VideoEngineService service) async {
    if (_saving) return;
    setState(() => _saving = true);
    final updated = await service.updateSource(
      widget.sourceId,
      name: _nameCtl.text,
      api: _apiCtl.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (updated == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败：地址为空，或与已有片源重复。')));
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('片源已更新')));
  }

  Future<void> _delete(
    VideoEngineService service,
    VideoSourceEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除片源'),
        content: Text('确定删除「${entry.name}」吗？它的收藏与历史不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await service.removeSource(entry.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VideoEngineService.instance,
      builder: (context, _) {
        final service = VideoEngineService.instance;
        service.loadRegistry();
        final entry = _entry(service);
        if (entry == null) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('这个片源已经不在了。'),
            ),
          );
        }
        if (!_seeded) {
          _seeded = true;
          _nameCtl.text = entry.name;
          _apiCtl.text = entry.api;
        }
        final health = service.healthById[entry.id];
        final variant = Theme.of(context).colorScheme.onSurfaceVariant;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '片源设置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameCtl,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _apiCtl,
                  decoration: const InputDecoration(labelText: '接口地址'),
                  keyboardType: TextInputType.url,
                ),
                if (entry.fromRepository.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '来自仓库「${entry.fromRepository}」',
                      style: TextStyle(color: variant, fontSize: 12.5),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用'),
                  subtitle: const Text('关闭后不参与搜索与浏览'),
                  value: entry.enabled,
                  onChanged: (v) => service.setSourceEnabled(entry.id, v),
                ),
                const Divider(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        health == null
                            ? '还没有检测过'
                            : health.ok
                            ? '上次检测：可用 · ${health.latencyMs}ms · '
                                  '${filmCheckAgeText(health.checkedAt, DateTime.now())}'
                            : '上次检测：不可用 · '
                                  '${filmCheckAgeText(health.checkedAt, DateTime.now())}\n'
                                  '${health.message}',
                        style: TextStyle(color: variant, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: _testing
                          ? null
                          : () async {
                              setState(() => _testing = true);
                              await service.checkSourceHealth(entry);
                              if (mounted) {
                                setState(() => _testing = false);
                              }
                            },
                      child: Text(_testing ? '检测中…' : '立即检测'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _delete(service, entry),
                      child: Text(
                        '删除片源',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : () => _save(service),
                      child: Text(_saving ? '保存中…' : '保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
