import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/pages/liuguang/film_widgets.dart';

import 'package:anikumo/pages/liuguang/film_account_section.dart';
import 'package:anikumo/services/liuguang/film_prefs.dart';
import 'package:anikumo/services/liuguang/film_probes.dart';
import 'package:anikumo/services/liuguang/tmdb_enrich.dart';
import 'package:anikumo/services/liuguang/video_engine.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Batches 203–208: 设置 — since Batch 208 the zone plays
/// through the shared player page, so playback preferences
/// (skip intro/outro, speed, danmaku display) are the app's
/// global player settings rather than zone-local copies.
/// What remains here: the downloads entry and the zone's
/// registry status.
class FilmSettingsTab extends StatelessWidget {
  const FilmSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VideoEngineService.instance,
      builder: (context, _) {
        final service = VideoEngineService.instance;
        service.loadRegistry();
        final variant = Theme.of(context).colorScheme.onSurfaceVariant;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Batch 221: editorial title bar.
            FilmEditorialTitle(
              eyebrow: 'SETTINGS · 设置',
              title: filmHeadline(context, '设置'),
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            ),
            _title(context, '播放'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AnikumoIcons.play_circle_rounded),
              title: const Text('与动漫区共用播放器'),
              subtitle: const Text(
                '跳过片头片尾、默认倍速、弹幕显示等在「设置 → 播放设置」里调整，对本专区同样生效。',
              ),
            ),
            const SizedBox(height: 14),
            const _TmdbModeSection(),
            const SizedBox(height: 14),
            const FilmAccountSection(),
            const SizedBox(height: 14),
            _title(context, '扩展功能'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AnikumoIcons.extension_rounded),
              title: const Text('功能仓库'),
              subtitle: const Text('极速解析、线路测速、下载省空间、追剧自动更新等可选功能'),
              trailing: const Icon(AnikumoIcons.chevron_right_rounded),
              onTap: () => context.pushNamed('/film/features'),
            ),
            const SizedBox(height: 14),
            const _PlaybackSourceSection(),
            const SizedBox(height: 14),
            const _HomeSourceSection(),
            const SizedBox(height: 14),
            _title(context, '下载'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AnikumoIcons.download_rounded),
              title: const Text('下载管理'),
              subtitle: const Text('查看进度、暂停续传、离线播放已下载的剧集'),
              trailing: const Icon(AnikumoIcons.chevron_right_rounded),
              onTap: () => context.pushNamed('/film/downloads'),
            ),
            const SizedBox(height: 14),
            _title(context, '数据源'),
            _infoRow(context, '已添加仓库', '${service.repositories.length} 个'),
            _infoRow(context, '已装接口源', '${service.sources.length} 个'),
            _infoRow(
              context,
              '已启用接口源',
              '${service.sources.where((s) => s.enabled).length} 个',
            ),
            const SizedBox(height: 6),
            Text(
              '仓库与接口源在「源」页签里管理。',
              style: TextStyle(color: variant, fontSize: 12.5),
            ),
          ],
        );
      },
    );
  }

  Widget _title(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Batch 243: TMDB 资料模式 — 国内 pulls zh-CN metadata
/// (titles, overviews, posters, reviews); 海外 pulls
/// TMDB's default original-language data. One switch,
/// applied at the next metadata fetch; caches are kept
/// per mode so flipping back is instant.
class _TmdbModeSection extends StatefulWidget {
  const _TmdbModeSection();

  @override
  State<_TmdbModeSection> createState() => _TmdbModeSectionState();
}

class _TmdbModeSectionState extends State<_TmdbModeSection> {
  bool _overseas = false;

  @override
  void initState() {
    super.initState();
    _overseas = tmdbOverseasMode();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '资料',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(AnikumoIcons.language_rounded),
          title: const Text('TMDB 海外资料'),
          subtitle: Text(
            _overseas
                ? '当前：海外 — 标题、简介、海报与影评按原文（多为英文）显示'
                : '当前：国内 — 标题、简介、海报与影评优先中文',
          ),
          value: _overseas,
          onChanged: (value) {
            setState(() => _overseas = value);
            try {
              GStorage.putSetting(SettingsKeys.filmTmdbOverseas, value);
            } catch (_) {
              // The in-memory choice still applies.
            }
          },
        ),
      ],
    );
  }
}

/// Batch 250: 看剧取源 — the playback source strategy:
/// 最快优先 (the shared speed table decides) or 自定义
/// (one pinned interface's copy wins; no copy there =
/// the automatic default). Sits directly above 主页
/// 接口 on purpose: the two answer different questions
/// （播放取源 vs 货架目录） off the same source list and
/// the same speed table.
class _PlaybackSourceSection extends StatefulWidget {
  const _PlaybackSourceSection();

  @override
  State<_PlaybackSourceSection> createState() => _PlaybackSourceSectionState();
}

class _PlaybackSourceSectionState extends State<_PlaybackSourceSection> {
  @override
  void initState() {
    super.initState();
    FilmPlaybackSource.revision.addListener(_refresh);
    FilmSourceSpeeds.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    FilmPlaybackSource.revision.removeListener(_refresh);
    FilmSourceSpeeds.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String? get _pinName {
    final pin = FilmPlaybackSource.pinnedId;
    if (pin == null) return null;
    for (final s in VideoEngineService.instance.sources) {
      if (s.id == pin) return s.name;
    }
    return null;
  }

  String get _fastestLabel {
    final fastest = FilmSourceSpeeds.fastestId(DateTime.now());
    if (fastest != null) {
      for (final s in VideoEngineService.instance.sources) {
        if (s.id == fastest) return '当前最快：${s.name}';
      }
    }
    return '按自动测速排序取源';
  }

  Future<void> _pickCustom() async {
    final service = VideoEngineService.instance;
    service.loadRegistry();
    final enabled = service.sources.where((s) => s.enabled).toList();
    if (!mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('自定义看剧接口'),
        children: [
          for (final s in enabled)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s.id),
              child: Text(s.name),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await FilmPlaybackSource.setPinned(picked);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pin = FilmPlaybackSource.pinnedId;
    final variant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '看剧取源',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '点开一部剧时用哪个接口的片源。与下面的「主页接口」分工不同：主页接口管首页货架的目录，这个管播放取源；两者共用同一份接口列表和测速结果。',
          style: TextStyle(color: variant, fontSize: 12.5),
        ),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('最快优先'),
          subtitle: Text(_fastestLabel),
          trailing: pin == null
              ? const Icon(AnikumoIcons.check_circle_rounded)
              : null,
          onTap: () => FilmPlaybackSource.setPinned(null),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('自定义'),
          subtitle: Text(
            pin == null
                ? '指定一个接口，它有这部剧时就用它的'
                : '当前指定：${_pinName ?? '接口已停用或移除（走自动）'}',
          ),
          trailing: pin != null
              ? const Icon(AnikumoIcons.check_circle_rounded)
              : const Icon(AnikumoIcons.chevron_right_rounded),
          onTap: _pickCustom,
        ),
      ],
    );
  }
}

/// Batch 237: 主页接口 — one row per home channel
/// （电视剧 / 电影 / 综艺 / 动漫 / 直播）: which interface
/// feeds that shelf, or 自动 (every enabled source races,
/// first answer wins — the pre-237 behavior).
class _HomeSourceSection extends StatefulWidget {
  const _HomeSourceSection();

  @override
  State<_HomeSourceSection> createState() => _HomeSourceSectionState();
}

class _HomeSourceSectionState extends State<_HomeSourceSection> {
  static const _kinds = [
    FilmKindFilter.series,
    FilmKindFilter.movie,
    FilmKindFilter.variety,
    FilmKindFilter.anime,
    FilmKindFilter.shortDrama,
    FilmKindFilter.manju,
    FilmKindFilter.live,
  ];

  bool _speedBusy = false;
  int _speedDone = 0;
  int _speedTotal = 0;

  @override
  void initState() {
    super.initState();
    FilmSourceSpeeds.revision.addListener(_onSpeedsChanged);
  }

  @override
  void dispose() {
    FilmSourceSpeeds.revision.removeListener(_onSpeedsChanged);
    super.dispose();
  }

  void _onSpeedsChanged() {
    if (mounted) setState(() {});
  }

  String _currentLabel(FilmKindFilter kind) {
    final id = FilmHomeSources.preferredId(kind.name);
    if (id == null) {
      final fastest = FilmSourceSpeeds.fastestId(DateTime.now());
      if (fastest != null) {
        for (final s in VideoEngineService.instance.sources) {
          if (s.id == fastest) return '自动 · 最快 ${s.name}';
        }
      }
      return '自动';
    }
    for (final s in VideoEngineService.instance.sources) {
      if (s.id == id) return s.name;
    }
    return '自动';
  }

  String get _speedLabel {
    if (_speedBusy) return '测速中 $_speedDone/$_speedTotal';
    final now = DateTime.now();
    final fastest = FilmSourceSpeeds.fastestId(now);
    if (fastest != null) {
      final record = FilmSourceSpeeds.recordOf(fastest)!;
      for (final s in VideoEngineService.instance.sources) {
        if (s.id == fastest) {
          return '最快：${s.name} · ${record.ms}ms · '
              '${filmCheckAgeText(record.at, now)}测';
        }
      }
    }
    return '测一测哪个接口最快，「自动」会优先用最快的';
  }

  Future<void> _runSpeedTest() async {
    final service = VideoEngineService.instance;
    service.loadRegistry();
    final enabled = service.sources.where((s) => s.enabled).toList();
    if (enabled.isEmpty || _speedBusy) return;
    setState(() {
      _speedBusy = true;
      _speedDone = 0;
      _speedTotal = enabled.length;
    });
    await probeAllFilmSourceSpeeds(
      enabled,
      onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _speedDone = done;
            _speedTotal = total;
          });
        }
      },
    );
    if (mounted) setState(() => _speedBusy = false);
  }

  Future<void> _pick(FilmKindFilter kind) async {
    final service = VideoEngineService.instance;
    service.loadRegistry();
    final enabled = service.sources.where((s) => s.enabled).toList();
    if (!mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${kind.label}主页接口'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('自动（按测速优先，没测过时竞赛）'),
          ),
          for (final s in enabled)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s.id),
              child: Text(s.name),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await FilmHomeSources.setPreferred(
      kind.name,
      picked.isEmpty ? null : picked,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '主页接口',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '给每个频道指定供内容的接口；选「自动」时先按测速结果从最快的接口取，没测过则所有已启用接口竞赛、先返回的先用。指定的接口取不到内容时会自动回退，不会让货架空着。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('接口测速'),
          subtitle: Text(_speedLabel),
          trailing: _speedBusy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(onPressed: _runSpeedTest, child: const Text('测速')),
        ),
        for (final kind in _kinds)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${kind.label}主页'),
            subtitle: Text(_currentLabel(kind)),
            trailing: const Icon(AnikumoIcons.chevron_right_rounded),
            onTap: () => _pick(kind),
          ),
      ],
    );
  }
}
