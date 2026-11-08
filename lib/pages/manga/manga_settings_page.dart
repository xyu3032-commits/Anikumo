import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/pages/manga/manga_downloads_page.dart';
import 'package:anikumo/pages/manga/manga_sources_page.dart';
import 'package:anikumo/services/manga/manga_image_pipeline.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/manga/manga_page_cache.dart';
import 'package:anikumo/services/manga/reader_settings.dart';
import 'package:anikumo/services/storage/storage.dart';

/// Manga settings, structured after Venera's SettingsPage: an
/// index of categories （探索 / 阅读 / 外观 / 本地收藏 / 网络 /
/// 关于）, each opening its own detail page. Used both as the
/// zone's 设置 tab and as a pushed page from the reader.
class MangaSettingsIndex extends StatelessWidget {
  const MangaSettingsIndex({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = <(IconData, String, Widget Function())>[
      (Icons.explore_rounded, '探索', () => const _ExploreSettingsPage()),
      (Icons.hub_rounded, '漫画源', () => const MangaSourcesPage()),
      (Icons.menu_book_rounded, '阅读', () => const _ReadingSettingsPage()),
      (Icons.color_lens_rounded, '外观', () => const _AppearanceSettingsPage()),
      (
        Icons.collections_bookmark_rounded,
        '本地收藏',
        () => const _DataSettingsPage()
      ),
      (
        Icons.download_rounded,
        '下载管理',
        () => const MangaDownloadsPage()
      ),
      (
        Icons.bar_chart_rounded,
        '阅读数据',
        () => const MangaStatsPage()
      ),
      (Icons.public_rounded, '网络', () => const _NetworkSettingsPage()),
      (Icons.info_rounded, '关于', () => const _AboutSettingsPage()),
    ];
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                '设置',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final (icon, title, builder) in entries)
                  ListTile(
                    leading: Icon(icon),
                    title: Text(title),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => builder()),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Route wrapper used when settings are opened from the reader.
class MangaSettingsPage extends StatelessWidget {
  const MangaSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('漫画设置')),
      body: const MangaSettingsIndex(showHeader: false),
    );
  }
}

// ── shared rows ─────────────────────────────────────────────────

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(children: children),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SelectRow<T> extends StatelessWidget {
  const _SelectRow({
    required this.title,
    required this.valueLabel,
    required this.options,
    required this.onSelected,
  });

  final String title;
  final String valueLabel;

  /// (value, label) pairs.
  final List<(T, String)> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            valueLabel,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: () async {
        final selected = await showDialog<T>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(title),
            children: [
              for (final (value, label) in options)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(value),
                  child: Row(
                    children: [
                      Expanded(child: Text(label)),
                      if (label == valueLabel)
                        Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (selected != null) onSelected(selected);
      },
    );
  }
}

// ── 探索 ────────────────────────────────────────────────────────

class _ExploreSettingsPage extends StatefulWidget {
  const _ExploreSettingsPage();

  @override
  State<_ExploreSettingsPage> createState() => _ExploreSettingsPageState();
}

class _ExploreSettingsPageState extends State<_ExploreSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final allowSuggestive =
        GStorage.getSetting(SettingsKeys.mangaAllowSuggestive);
    final railCount = GStorage.getSetting(SettingsKeys.mangaHistoryRailCount);
    return _SettingsScaffold(
      title: '探索',
      children: [
        _SwitchRow(
          title: '显示 Suggestive 内容',
          subtitle: '关掉后，源的列表只返回全年龄（safe）作品',
          value: allowSuggestive,
          onChanged: (value) {
            GStorage.putSetting(SettingsKeys.mangaAllowSuggestive, value);
            setState(() {});
          },
        ),
        _SelectRow<int>(
          title: '首页历史显示数量',
          valueLabel: '$railCount 本',
          options: const [(6, '6 本'), (10, '10 本'), (20, '20 本')],
          onSelected: (value) {
            GStorage.putSetting(SettingsKeys.mangaHistoryRailCount, value);
            setState(() {});
          },
        ),
      ],
    );
  }
}

// ── 阅读 ────────────────────────────────────────────────────────

class _ReadingSettingsPage extends StatefulWidget {
  const _ReadingSettingsPage();

  @override
  State<_ReadingSettingsPage> createState() => _ReadingSettingsPageState();
}

class _ReadingSettingsPageState extends State<_ReadingSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final mode = normalizeMangaReaderMode(
      GStorage.getSetting(SettingsKeys.mangaReaderMode),
    );
    final autoSeconds = GStorage.getSetting(SettingsKeys.mangaAutoPageSeconds);
    return _SettingsScaffold(
      title: '阅读',
      children: [
        _SelectRow<String>(
          title: '阅读模式',
          valueLabel: MangaReaderModes.labels[mode] ?? mode,
          options: [
            for (final entry in MangaReaderModes.labels.entries)
              (entry.key, entry.value),
          ],
          onSelected: (value) {
            GStorage.putSetting(SettingsKeys.mangaReaderMode, value);
            setState(() {});
          },
        ),
        _SwitchRow(
          title: '点击翻页',
          subtitle: '点屏幕左 / 右侧翻页，中间呼出菜单',
          value: GStorage.getSetting(SettingsKeys.mangaTapToTurn),
          onChanged: (value) {
            GStorage.putSetting(SettingsKeys.mangaTapToTurn, value);
            setState(() {});
          },
        ),
        _SwitchRow(
          title: '反转点击翻页方向',
          value: GStorage.getSetting(SettingsKeys.mangaReverseTap),
          onChanged: (value) {
            GStorage.putSetting(SettingsKeys.mangaReverseTap, value);
            setState(() {});
          },
        ),
        _SwitchRow(
          title: '翻页动画',
          value: GStorage.getSetting(SettingsKeys.mangaPageAnimation),
          onChanged: (value) {
            GStorage.putSetting(SettingsKeys.mangaPageAnimation, value);
            setState(() {});
          },
        ),
        _SwitchRow(
          title: '显示页码',
          subtitle: '菜单隐藏时在右下角显示当前页码',
          value: GStorage.getSetting(SettingsKeys.mangaShowPageNumber),
          onChanged: (value) {
            GStorage.putSetting(SettingsKeys.mangaShowPageNumber, value);
            setState(() {});
          },
        ),
        _SwitchRow(
          title: '阅读时保持屏幕常亮',
          value: GStorage.getSetting(SettingsKeys.mangaKeepScreenOn),
          onChanged: (value) {
            GStorage.putSetting(SettingsKeys.mangaKeepScreenOn, value);
            setState(() {});
          },
        ),
        ListTile(
          title: const Text('自动翻页间隔'),
          subtitle: Text(
            autoSeconds == 0 ? '关（仅分页模式可用）' : '$autoSeconds 秒一页（仅分页模式）',
          ),
        ),
        Slider(
          value: autoSeconds.toDouble(),
          min: 0,
          max: 20,
          divisions: 20,
          label: autoSeconds == 0 ? '关' : '$autoSeconds 秒',
          onChanged: (value) {
            GStorage.putSetting(
              SettingsKeys.mangaAutoPageSeconds,
              value.round(),
            );
            setState(() {});
          },
        ),
      ],
    );
  }
}

// ── 外观 ────────────────────────────────────────────────────────

class _AppearanceSettingsPage extends StatefulWidget {
  const _AppearanceSettingsPage();

  @override
  State<_AppearanceSettingsPage> createState() =>
      _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<_AppearanceSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final columns = GStorage.getSetting(SettingsKeys.mangaGridColumns);
    return _SettingsScaffold(
      title: '外观',
      children: [
        _SelectRow<int>(
          title: '网格列数',
          valueLabel: '$columns 列',
          options: const [(2, '2 列'), (3, '3 列'), (4, '4 列')],
          onSelected: (value) {
            GStorage.putSetting(SettingsKeys.mangaGridColumns, value);
            setState(() {});
          },
        ),
        const ListTile(
          title: Text('说明'),
          subtitle: Text('列数作用于探索、收藏与分类结果的封面网格。'),
        ),
      ],
    );
  }
}

// ── 本地收藏（数据） ─────────────────────────────────────────────

class _DataSettingsPage extends StatefulWidget {
  const _DataSettingsPage();

  @override
  State<_DataSettingsPage> createState() => _DataSettingsPageState();
}

class _DataSettingsPageState extends State<_DataSettingsPage> {
  Future<void> _export() async {
    await Clipboard.setData(
      ClipboardData(text: MangaLibraryStore.exportLibrary()),
    );
    AnikumoDialog.showToast(message: '书架已复制，去粘贴保存吧');
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入书架'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '把导出的书架文本粘贴到这里',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await MangaLibraryStore.importLibrary(controller.text);
    AnikumoDialog.showToast(
      message: result == null
          ? '导入失败：文本不是有效的书架导出'
          : '已导入 ${result.favorites} 本收藏、${result.progress} 条进度',
    );
  }

  Future<void> _confirmClear({
    required String title,
    required Future<void> Function() action,
    required String doneMessage,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('这个操作不能撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await action();
    AnikumoDialog.showToast(message: doneMessage);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: '本地收藏',
      children: [
        ListTile(
          leading: const Icon(Icons.upload_outlined),
          title: const Text('导出书架'),
          subtitle: const Text('收藏与阅读进度导出为一段文本'),
          onTap: _export,
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('导入书架'),
          subtitle: const Text('粘贴导出的文本合并进当前书架'),
          onTap: _import,
        ),
        ListTile(
          leading: const Icon(Icons.history_rounded),
          title: const Text('清除阅读历史'),
          onTap: () => _confirmClear(
            title: '清除全部阅读历史？',
            action: MangaLibraryStore.clearProgress,
            doneMessage: '阅读历史已清除',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border_rounded),
          title: const Text('清除全部收藏'),
          onTap: () => _confirmClear(
            title: '清除全部收藏？',
            action: MangaLibraryStore.clearFavorites,
            doneMessage: '收藏已清除',
          ),
        ),
      ],
    );
  }
}

// ── 网络 ────────────────────────────────────────────────────────

class _NetworkSettingsPage extends StatefulWidget {
  const _NetworkSettingsPage();

  @override
  State<_NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<_NetworkSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final quality = GStorage.getSetting(SettingsKeys.mangaImageQuality);
    return _SettingsScaffold(
      title: '网络',
      children: [
        _SelectRow<String>(
          title: '章节图片质量',
          valueLabel: quality == 'saver' ? '省流' : '原图',
          options: const [('original', '原图'), ('saver', '省流')],
          onSelected: (value) {
            GStorage.putSetting(SettingsKeys.mangaImageQuality, value);
            setState(() {});
          },
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('清除图片缓存'),
          subtitle: const Text('封面与章节图片的本地缓存'),
          onTap: () async {
            await DefaultCacheManager().emptyCache();
            // Batch 51: the reader's dedicated page cache
            // is a separate store — clear it too.
            await mangaPageCacheManager.emptyCache();
            // Batch 102: and the covers' own gated store.
            await mangaCoverCacheManager.emptyCache();
            AnikumoDialog.showToast(message: '图片缓存已清除');
          },
        ),
      ],
    );
  }
}

// ── 关于 ────────────────────────────────────────────────────────

class _AboutSettingsPage extends StatelessWidget {
  const _AboutSettingsPage();

  @override
  Widget build(BuildContext context) {
    return const _SettingsScaffold(
      title: '关于',
      children: [
        ListTile(
          title: Text('漫画源'),
          subtitle: Text('免费公共 API'),
        ),
        ListTile(
          title: Text('界面与设置结构'),
          subtitle: Text(
            '参考开源项目（GPL-3.0）的四页签导航、首页卡片流与'
            '分类设置结构；本实现为独立编写，未使用其代码。',
          ),
        ),
        ListTile(
          title: Text('内容说明'),
          subtitle: Text(
            '章节来自各汉化组与上传者，版权归原作者与出版社所有；'
            '官方授权作品在源站多为外链，可能无法在应用内阅读。',
          ),
        ),
      ],
    );
  }
}
