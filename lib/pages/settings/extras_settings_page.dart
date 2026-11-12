import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/settings/settings_dropdown_tile.dart';
import 'package:anikumo/bean/settings/settings_list.dart';
import 'package:anikumo/pages/settings/player_enhance_page.dart';
import 'package:anikumo/pages/settings/anime_feature_repo_page.dart';
import 'package:anikumo/pages/settings/anime_stats_page.dart';
import 'package:anikumo/bean/widget/motion_kit.dart';
import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/repositories/history_repository.dart';
import 'package:anikumo/services/anime/anime_features.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/bean/settings/theme_provider.dart';
import 'package:anikumo/services/ui/app_extras.dart';
import 'package:anikumo/services/ui/custom_font.dart';
import 'package:anikumo/services/ui/glass_style.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 15 control center: the twelve "big features" that are
/// settings-shaped live here (text scale, start tab, scheduled
/// dark, smooth mode, PIN lock, title filter), plus entries to
/// the storage manager, unified history search, watching
/// progress and the CSV export.
class ExtrasSettingsPage extends StatefulWidget {
  const ExtrasSettingsPage({super.key});

  @override
  State<ExtrasSettingsPage> createState() => _ExtrasSettingsPageState();
}

class _ExtrasSettingsPageState extends State<ExtrasSettingsPage> {
  static const _textScales = [0.85, 1.0, 1.15, 1.3];
  static const _tabNames = ['推荐', '精选', '发现', '时光', '时间表', '追番', '我的', '漫画'];

  Future<void> _setSmoothMode(bool value) async {
    if (value) {
      await GStorage.putSetting(
        SettingsKeys.glassLevelBackup,
        GlassStyle.level,
      );
      await GlassStyle.setLevel(GlassStyle.levelOff);
      await GStorage.putSetting(SettingsKeys.mangaImageQuality, 'saver');
    } else {
      final backup = GStorage.getSetting(SettingsKeys.glassLevelBackup);
      await GlassStyle.setLevel(
        backup >= 0 ? backup : GlassStyle.levelLight,
      );
      await GStorage.putSetting(SettingsKeys.mangaImageQuality, '');
    }
    await SmoothMode.setEnabled(value);
    if (mounted) setState(() {});
  }

  Future<void> _exportHistory() async {
    final histories = inject<IHistoryRepository>().getAllHistories();
    final manga = MangaLibraryStore.loadProgressList();
    final docs = await getApplicationDocumentsDirectory();
    final animeFile = File('${docs.path}/anikumo_anime_history.csv');
    final mangaFile = File('${docs.path}/anikumo_manga_history.csv');
    await animeFile.writeAsString(buildAnimeHistoryCsv(histories));
    await mangaFile.writeAsString(buildMangaHistoryCsv(manga));
    await Clipboard.setData(
      ClipboardData(text: '${animeFile.path}\n${mangaFile.path}'),
    );
    AnikumoDialog.showToast(
      message: '已导出 ${histories.length} 条动漫 + ${manga.length} 条漫画记录，文件路径已复制',
    );
  }

  Future<void> _pinDialog({required bool changing}) async {
    final firstController = TextEditingController();
    final secondController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(changing ? '修改 PIN' : '设置 PIN（4-6 位数字）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (changing)
              TextField(
                controller: secondController,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: const InputDecoration(labelText: '当前 PIN'),
              ),
            TextField(
              controller: firstController,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新 PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final pin = firstController.text.trim();
    if (pin.length < 4 || pin.length > 6 || int.tryParse(pin) == null) {
      AnikumoDialog.showToast(message: 'PIN 需为 4-6 位数字');
      return;
    }
    if (changing && !PinLock.verify(secondController.text.trim())) {
      AnikumoDialog.showToast(message: '当前 PIN 不对');
      return;
    }
    await PinLock.setPin(pin);
    if (mounted) setState(() {});
    AnikumoDialog.showToast(message: '应用锁已开启，下次打开 App 需要 PIN');
  }

  /// Batch 84: pick a ttf/otf file and apply it app-wide.
  Future<void> _importCustomFont() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
      allowMultiple: false,
      withData: false,
    );
    final file = picked?.files.singleOrNull;
    final path = file?.path;
    if (file == null || path == null) {
      return;
    }
    if (!mounted) return;
    final provider = Provider.of<ThemeProvider>(context, listen: false);
    try {
      await CustomFontService.importAndApply(
        provider,
        pickedPath: path,
        name: file.name,
      );
      AnikumoDialog.showToast(message: '字体已应用：${file.name}');
    } catch (_) {
      AnikumoDialog.showToast(message: '这个字体文件用不了，换一个试试');
    }
    if (mounted) setState(() {});
  }

  /// Batch 84: back to the original (bundled / system)
  /// font.
  Future<void> _restoreDefaultFont() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复默认字体？'),
        content: Text(
          '将移除自定义字体「${CustomFontService.displayName}」，'
          '回到原来的字体。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await CustomFontService.clear(Provider.of<ThemeProvider>(context, listen: false));
    AnikumoDialog.showToast(message: '已恢复默认字体');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final textScale = GStorage.getSetting(SettingsKeys.textScaleFactor);
    final startTab = GStorage.getSetting(SettingsKeys.startTabIndex);
    final scheduledDark = GStorage.getSetting(SettingsKeys.scheduledDark);
    // Batch 57: this page was the last settings page still
    // built from raw ListTiles — it now uses the same
    // SettingsDetailScaffold + SettingsList design system as
    // every other settings page. Controls and behavior are
    // unchanged, only the presentation layer moved.
    return SettingsDetailScaffold(
      title: const Text('Anikumo 增强'),
      body: SettingsList(
        sections: [
          SettingsSection(title: const Text('动漫扩展'), tiles: [
            SettingsTile(
              leading: AnikumoIcons.extension_rounded,
              title: const Text('动漫功能仓库'),
              description: const Text('可选功能包：装好立即生效，没装的不会出现在动漫区里'),
              onPressed: (context) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AnimeFeatureRepoPage(),
                ),
              ),
            ),
            if (AnimeFeatures.isInstalled(AnimeFeatures.statsId))
              SettingsTile(
                leading: AnikumoIcons.bar_chart_rounded,
                title: const Text('观影报告'),
                description: const Text('累计时长、看过的番与集数、最近 7 天节奏'),
                onPressed: (context) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AnimeStatsPage(),
                  ),
                ),
              ),
          ]),
          SettingsSection(title: const Text('显示'), tiles: [
            SettingsTile(
              leading: AnikumoIcons.format_size_rounded,
              title: const Text('字体大小'),
              description: const Text('全应用文字缩放'),
              // Batch 84: the four-segment switch is too
              // wide to share a row with the label — at
              // larger scales it crushed the label into a
              // one-character-wide vertical strip. It gets
              // its own full-width row instead.
              stackTrailing: true,
              trailing: SizedBox(
                width: double.infinity,
                child: SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0.85, label: Text('小')),
                  ButtonSegment(value: 1.0, label: Text('标准')),
                  ButtonSegment(value: 1.15, label: Text('大')),
                  ButtonSegment(value: 1.3, label: Text('特大')),
                ],
                selected: {
                  _textScales.contains(textScale) ? textScale : 1.0,
                },
                onSelectionChanged: (selection) async {
                  await GStorage.putSetting(
                    SettingsKeys.textScaleFactor,
                    selection.first,
                  );
                  if (mounted) setState(() {});
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                ),
              ),
            ),
            SettingsTile(
              leading: AnikumoIcons.font_download_outlined,
              title: const Text('自定义字体'),
              description: Text(
                CustomFontService.hasCustomFont
                    ? '当前：${CustomFontService.displayName}'
                    : '导入 ttf / otf 字体文件，全应用生效',
              ),
              value: Text(
                CustomFontService.hasCustomFont ? '已启用' : '未设置',
              ),
              onPressed: (_) => _importCustomFont(),
            ),
            SettingsTile(
              leading: AnikumoIcons.restart_alt_rounded,
              title: const Text('恢复默认字体'),
              description: const Text('移除自定义字体，回到原来的字体'),
              enabled: CustomFontService.hasCustomFont,
              onPressed: (_) => _restoreDefaultFont(),
            ),
            SettingsTile.switchTile(
              leading: AnikumoIcons.dark_mode_rounded,
              title: const Text('定时深色模式'),
              description: const Text('跟随系统时，21:00–06:00 自动深色'),
              initialValue: scheduledDark,
              onToggle: (value) async {
                await GStorage.putSetting(
                  SettingsKeys.scheduledDark,
                  value ?? !scheduledDark,
                );
                if (mounted) setState(() {});
              },
            ),
            SettingsDropdownTile<int>(
              leading: AnikumoIcons.home_rounded,
              title: const Text('默认启动页'),
              description: const Text('打开 App 时先显示的页面'),
              value: startTab.clamp(0, 7),
              options: {
                for (var i = 0; i < _tabNames.length; i++) i: _tabNames[i],
              },
              onChanged: (value) async {
                await GStorage.putSetting(SettingsKeys.startTabIndex, value);
                if (mounted) setState(() {});
              },
            ),
          ]),
          SettingsSection(title: const Text('流畅'), tiles: [
            SettingsTile.switchTile(
              leading: AnikumoIcons.speed_rounded,
              title: const Text('流畅模式'),
              description:
                  const Text('关玻璃效果、停大部分入场动画（榜单 3D 入场除外）、漫画图片省流，换取最大流畅'),
              initialValue: SmoothMode.enabled,
              onToggle: (value) =>
                  _setSmoothMode(value ?? !SmoothMode.enabled),
            ),
          ]),
          SettingsSection(title: const Text('安全'), tiles: [
            SettingsTile(
              leading: AnikumoIcons.lock_rounded,
              title: const Text('应用锁（PIN）'),
              description: Text(PinLock.isEnabled ? '已开启' : '未开启'),
              trailing: PinLock.isEnabled
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _pinDialog(changing: true),
                          child: const Text('修改'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await PinLock.clear();
                            if (mounted) setState(() {});
                          },
                          child: const Text('关闭'),
                        ),
                      ],
                    )
                  : TextButton(
                      onPressed: () => _pinDialog(changing: false),
                      child: const Text('设置'),
                    ),
            ),
          ]),
          SettingsSection(title: const Text('播放'), tiles: [
            SettingsTile(
              leading: AnikumoIcons.play_circle_rounded,
              title: const Text('播放增强'),
              description: const Text('24 项播放优化 + 12 项播放功能'),
              onPressed: (context) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PlayerEnhancePage(),
                ),
              ),
            ),
          ]),
          SettingsSection(title: const Text('内容'), tiles: [
            SettingsTile(
              leading: AnikumoIcons.filter_alt_rounded,
              title: const Text('标题关键词过滤'),
              description: const Text('含关键词的番剧不在热门/发现里出现'),
              onPressed: (context) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TitleFilterPage(),
                ),
              ),
            ),
          ]),
          SettingsSection(title: const Text('数据'), tiles: [
            SettingsTile(
              leading: AnikumoIcons.storage_rounded,
              title: const Text('存储管理'),
              description: const Text('图片缓存、漫画下载、文档占用与清理'),
              onPressed: (context) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StorageManagePage(),
                ),
              ),
            ),
            SettingsTile(
              leading: AnikumoIcons.history_rounded,
              title: const Text('统一历史搜索'),
              description: const Text('动漫观看 + 漫画阅读历史一起搜'),
              onPressed: (context) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const UnifiedHistoryPage(),
                ),
              ),
            ),
            SettingsTile(
              leading: AnikumoIcons.pie_chart_rounded,
              title: const Text('追番进度总览'),
              description: const Text('每部在看番剧看到第几话'),
              onPressed: (context) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WatchingProgressPage(),
                ),
              ),
            ),
            SettingsTile(
              leading: AnikumoIcons.file_download_outlined,
              title: const Text('导出历史 CSV'),
              description: const Text('动漫 + 漫画记录导出为表格文件'),
              onPressed: (_) => _exportHistory(),
            ),
          ]),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

/// Title keyword filter editor (G7).
class TitleFilterPage extends StatefulWidget {
  const TitleFilterPage({super.key});

  @override
  State<TitleFilterPage> createState() => _TitleFilterPageState();
}

class _TitleFilterPageState extends State<TitleFilterPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final word = _controller.text.trim();
    if (word.isEmpty) return;
    final keywords = {...TitleFilterStore.loadKeywords(), word}.toList();
    await TitleFilterStore.saveKeywords(keywords);
    _controller.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keywords = TitleFilterStore.loadKeywords();
    return Scaffold(
      appBar: AppBar(title: const Text('标题关键词过滤')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: '输入要屏蔽的关键词，如：剧场版',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _add, child: const Text('添加')),
            ],
          ),
          const SizedBox(height: 16),
          if (keywords.isEmpty)
            const Text('还没有关键词。添加后，标题含该词的番剧会从热门和发现里隐藏。'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in keywords)
                Chip(
                  label: Text(keyword),
                  onDeleted: () async {
                    await TitleFilterStore.saveKeywords(
                      [
                        for (final k in keywords)
                          if (k != keyword) k,
                      ],
                    );
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Storage manager (G1).
class StorageManagePage extends StatefulWidget {
  const StorageManagePage({super.key});

  @override
  State<StorageManagePage> createState() => _StorageManagePageState();
}

class _StorageManagePageState extends State<StorageManagePage> {
  int _imageBytes = 0;
  int _downloadBytes = 0;
  int _docsBytes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> _load() async {
    final temp = await getTemporaryDirectory();
    final image = await _dirSize(Directory('${temp.path}/libCachedImageData'));
    final downloads = await MangaDownloadStore.totalSizeBytes();
    final docs = await getApplicationDocumentsDirectory();
    final docsSize = await _dirSize(docs);
    if (!mounted) return;
    setState(() {
      _imageBytes = image;
      _downloadBytes = downloads;
      _docsBytes = docsSize;
      _loading = false;
    });
  }

  String _label(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb >= 100
        ? '${mb.toStringAsFixed(0)} MB'
        : '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('存储管理')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  title: const Text('图片缓存'),
                  subtitle: Text(_label(_imageBytes)),
                  trailing: TextButton(
                    onPressed: () async {
                      final temp = await getTemporaryDirectory();
                      final dir =
                          Directory('${temp.path}/libCachedImageData');
                      if (await dir.exists()) {
                        await dir.delete(recursive: true);
                      }
                      await _load();
                    },
                    child: const Text('清理'),
                  ),
                ),
                ListTile(
                  title: const Text('漫画下载'),
                  subtitle: Text(_label(_downloadBytes)),
                  trailing: TextButton(
                    onPressed: () async {
                      await MangaDownloadStore.clearAll();
                      await _load();
                    },
                    child: const Text('清理'),
                  ),
                ),
                ListTile(
                  title: const Text('应用文档总量'),
                  subtitle: Text(_label(_docsBytes)),
                ),
              ],
            ),
    );
  }
}

/// Unified history search (G5).
class UnifiedHistoryPage extends StatefulWidget {
  const UnifiedHistoryPage({super.key});

  @override
  State<UnifiedHistoryPage> createState() => _UnifiedHistoryPageState();
}

class _UnifiedHistoryPageState extends State<UnifiedHistoryPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    bool matches(String title) =>
        needle.isEmpty || title.toLowerCase().contains(needle);
    final anime = [
      for (final h in inject<IHistoryRepository>().getAllHistories())
        if (matches(
          h.bangumiItem.nameCn.isNotEmpty
              ? h.bangumiItem.nameCn
              : h.bangumiItem.name,
        ))
          h,
    ];
    final manga = [
      for (final p in MangaLibraryStore.loadProgressList())
        if (matches(p.mangaTitle)) p,
    ];
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索全部历史',
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
      ),
      body: ListView(
        children: [
          if (anime.isNotEmpty) ...[
            const _SectionTitle('动漫历史'),
            for (var i = 0; i < anime.length; i++)
              SlideInX(
                delay: Duration(milliseconds: i * 30),
                child: ListTile(
                title: Text(
                  anime[i].bangumiItem.nameCn.isNotEmpty
                      ? anime[i].bangumiItem.nameCn
                      : anime[i].bangumiItem.name,
                ),
                subtitle: Text(
                  '看到第 ${anime[i].lastWatchEpisode} 话 · ${anime[i].adapterName}',
                ),
                trailing: const Icon(AnikumoIcons.chevron_right_rounded),
                onTap: () => context.pushNamed(
                  '/info/',
                  arguments: anime[i].bangumiItem,
                ),
                ),
              ),
          ],
          if (manga.isNotEmpty) ...[
            const _SectionTitle('漫画历史'),
            for (final p in manga)
              ListTile(
                title: Text(p.mangaTitle),
                subtitle: Text(
                  '${p.chapterLabel} · 第 ${p.page + 1} 页 · ${p.mangaSource}',
                ),
                trailing: const Icon(AnikumoIcons.chevron_right_rounded),
                onTap: () => context.pushNamed(
                  '/manga/detail',
                  arguments: MangaItem(
                    id: p.mangaId,
                    title: p.mangaTitle,
                    description: '',
                    coverUrl: p.coverUrl,
                    author: '',
                    status: '',
                    year: null,
                    tags: const [],
                    source: p.mangaSource,
                  ),
                ),
              ),
          ],
          if (anime.isEmpty && manga.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('没有匹配的历史记录')),
            ),
        ],
      ),
    );
  }
}

/// Watching progress overview (G9).
class WatchingProgressPage extends StatelessWidget {
  const WatchingProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final histories = inject<IHistoryRepository>().getAllHistories()
      ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    return Scaffold(
      appBar: AppBar(title: const Text('追番进度总览')),
      body: histories.isEmpty
          ? const Center(child: Text('还没有观看记录'))
          : ListView(
              children: [
                for (final h in histories)
                  ListTile(
                    title: Text(
                      h.bangumiItem.nameCn.isNotEmpty
                          ? h.bangumiItem.nameCn
                          : h.bangumiItem.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已看 ${h.progresses.length} 集 · 最新第 ${h.lastWatchEpisode} 话',
                        ),
                        const SizedBox(height: 4),
                        AnimatedBar(
                          value: h.lastWatchEpisode <= 0
                              ? 0
                              : (h.progresses.length / h.lastWatchEpisode)
                                  .clamp(0.0, 1.0),
                        ),
                      ],
                    ),
                    trailing: const Icon(AnikumoIcons.chevron_right_rounded),
                    onTap: () => context.pushNamed(
                      '/info/',
                      arguments: h.bangumiItem,
                    ),
                  ),
              ],
            ),
    );
  }
}
