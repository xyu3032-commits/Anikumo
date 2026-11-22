import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/services/backup/auto_backup.dart';
import 'package:anikumo/services/backup/backup_crypto.dart';
import 'package:anikumo/services/backup/local_backup.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/sync/lan_transfer.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

/// 本地备份/恢复 (hub 区三）: export the user's own data to one JSON
/// file, or merge a previously exported file back in. Complements —
/// does not replace — the WebDAV sync: no account, no server.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key, this.lanEndpoint});

  /// Batch 284 (#33): a LAN transfer endpoint handed over
  /// by the scanner (search page) — receiving starts as
  /// soon as the page opens.
  final LanTransferEndpoint? lanEndpoint;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  LanTransferServer? _lanServer;

  // Batch 83: the manga download index lives in a file, so
  // its count loads asynchronously.
  int? _mangaDownloadCount;

  @override
  void initState() {
    super.initState();
    MangaDownloadStore.loadIndex().then((entries) {
      if (mounted) setState(() => _mangaDownloadCount = entries.length);
    });
    final endpoint = widget.lanEndpoint;
    if (endpoint != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_receiveViaLan(endpoint));
      });
    }
  }

  @override
  void dispose() {
    final server = _lanServer;
    if (server != null) unawaited(server.close());
    super.dispose();
  }

  String get _fileName {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'anikumo-backup-$stamp.json';
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final bytes = utf8.encode(await LocalBackup.exportJson());
      final path = await FilePicker.platform.saveFile(
        dialogTitle: S.t('保存备份文件'),
        fileName: _fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (!mounted) return;
      AnikumoDialog.showToast(
        context: context,
        message: path == null ? S.t('已取消导出') : S.t('备份已保存'),
      );
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: S.t('导出失败，请稍后重试'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Batch 271: full bundle export — the JSON backup
  /// plus downloaded manga chapter files in one zip.
  Future<void> _exportBundle() async {
    setState(() => _busy = true);
    try {
      final bytes = await LocalBackup.exportBundleBytes();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: S.t('保存备份文件'),
        fileName: _fileName.replaceAll('.json', '.zip'),
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: bytes,
      );
      if (!mounted) return;
      AnikumoDialog.showToast(
        context: context,
        message: path == null ? S.t('已取消导出') : S.t('备份已保存'),
      );
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: S.t('导出失败，请稍后重试'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Batch 274 (#40): asks for a password (set or
  /// enter mode) in a small dialog.
  Future<String?> _askPassword({required bool confirm}) async {
    final first = TextEditingController();
    final second = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(confirm ? S.t('设置备份密码') : S.t('输入备份密码')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: first,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(labelText: S.t('密码')),
            ),
            if (confirm)
              TextField(
                controller: second,
                obscureText: true,
                decoration: InputDecoration(labelText: S.t('再输入一次')),
              ),
            const SizedBox(height: 8),
            Text(
              S.t('密码只用于加密这份文件，不会保存；忘了密码就无法恢复这份备份。'),
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () {
              final value = first.text;
              if (value.length < 4) {
                AnikumoDialog.showToast(
                  context: dialogContext,
                  message: S.t('密码至少 4 位'),
                );
                return;
              }
              if (confirm && second.text != value) {
                AnikumoDialog.showToast(
                  context: dialogContext,
                  message: S.t('两次输入的密码不一致'),
                );
                return;
              }
              Navigator.of(dialogContext).pop(value);
            },
            child: Text(S.t('确定')),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  /// Batch 274 (#40): encrypted export of the JSON
  /// backup.
  Future<void> _exportEncrypted() async {
    final password = await _askPassword(confirm: true);
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final encrypted =
          BackupCrypto.encrypt(await LocalBackup.exportJson(), password);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: S.t('保存备份文件'),
        fileName: _fileName.replaceAll('.json', '.enc'),
        type: FileType.custom,
        allowedExtensions: const ['enc'],
        bytes: utf8.encode(encrypted),
      );
      if (!mounted) return;
      AnikumoDialog.showToast(
        context: context,
        message: path == null ? S.t('已取消导出') : S.t('备份已保存'),
      );
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: S.t('导出失败，请稍后重试'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'zip', 'enc'],
        withData: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FileSystemException('无法读取所选文件');
      if (!mounted) return;
      await _processImportBytes(bytes);
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: S.t('导入失败，请稍后重试'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The restore half of an import — decrypt if needed,
  /// unpack a bundle, confirm with the usual counts
  /// dialog, apply. Shared by the file picker above and
  /// the LAN receiver (#33) below; errors propagate to
  /// the caller's catch.
  Future<void> _processImportBytes(List<int> bytes) async {
      // Batch 274 (#40): an encrypted backup asks for
      // its password first and then flows through the
      // plain-JSON path below.
      var effectiveBytes = bytes;
      final asText = utf8.decode(bytes, allowMalformed: true);
      if (BackupCrypto.isEncrypted(asText)) {
        final password = await _askPassword(confirm: false);
        if (password == null || !mounted) return;
        try {
          effectiveBytes =
              utf8.encode(BackupCrypto.decrypt(asText, password));
        } catch (_) {
          AnikumoDialog.showToast(
            context: context,
            message: S.t('密码不正确或文件已损坏'),
          );
          return;
        }
      }
      // Batch 271: a bundle zip lands its chapter files
      // FIRST, so the JSON apply below finds them on disk
      // instead of skipping those download records.
      var jsonText = '';
      if (LocalBackup.isBundle(effectiveBytes)) {
        await LocalBackup.extractBundleFiles(effectiveBytes);
        jsonText = LocalBackup.bundleJson(effectiveBytes) ?? '';
      } else {
        jsonText = utf8.decode(effectiveBytes);
      }
      final data = LocalBackup.parse(jsonText);
      if (data == null) {
        AnikumoDialog.showToast(
          context: context,
          message: S.t('这不是有效的 anikumo 备份文件'),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(S.t('恢复这份备份？')),
          content: Text(
            S.f(
              '将合并：观看历史 {} 条 · 追番 {} 部 · 搜索记录 {} 条 · 榜单 {} 个 · '
              '笔记 {} 条 · 漫画收藏 {} 部 · 漫画进度 {} 条 · 小说收藏 {} 部 · '
              '小说进度 {} 条 · 下载记录 {} 条。\n\n'
              '恢复只会覆盖同名记录，不会删除现有数据。'
              '下载只恢复记录：文件已不在本机的记录会被跳过。',
              [
                data.histories.length,
                data.collectibles.length,
                data.searchHistories.length,
                data.userLists.length,
                data.notes.length,
                data.mangaFavorites.length,
                data.mangaProgress.length,
                data.novelFavorites.length,
                data.novelProgress.length,
                data.mangaDownloads.length + data.animeDownloads.length,
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(S.t('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.t('恢复')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final report = await LocalBackup.apply(data);
      if (!mounted) return;
      AnikumoDialog.showToast(
        context: context,
        message: report.downloadsSkipped > 0
            ? S.f('恢复完成；{} 条下载记录因文件不在本机已跳过', [report.downloadsSkipped])
            : S.t('恢复完成'),
      );
      setState(() {});
  }

  /// Batch 284 (#33): serves the full bundle on the LAN
  /// behind a one-time token and shows the address as a
  /// QR code + selectable text until the dialog closes
  /// or the server retires itself (one download, or five
  /// minutes — see LanTransferServer).
  Future<void> _sendViaLan() async {
    setState(() => _busy = true);
    LanTransferServer? server;
    try {
      final bytes = await LocalBackup.exportBundleBytes();
      server = await LanTransferServer.start(bytes: bytes);
      _lanServer = server;
      if (!mounted) return;
      if (server.endpoint.host == '127.0.0.1') {
        await server.close();
        _lanServer = null;
        if (!mounted) return;
        AnikumoDialog.showToast(
          context: context,
          message: S.t('未找到可用的局域网地址，请确认已连接 Wi-Fi'),
        );
        return;
      }
      final payload = server.endpoint.payload;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(S.t('通过局域网发送备份')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 12),
              SelectableText(
                payload,
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                S.t('在另一台设备上打开「从局域网接收备份」，扫码或输入上面的地址下载这份备份。'),
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color: Theme.of(dialogContext).colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                S.t('这份地址 5 分钟内有效，且只能下载一次。'),
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color: Theme.of(dialogContext).colorScheme.outline,
                    ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(S.t('完成')),
            ),
          ],
        ),
      );
      await server.close();
      if (_lanServer == server) _lanServer = null;
    } catch (_) {
      if (server != null) await server.close();
      if (_lanServer == server) _lanServer = null;
      if (mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: S.t('发送失败，请确认已连接 Wi-Fi 后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Batch 284 (#33): downloads the bundle behind
  /// [endpoint] and runs it through the normal restore
  /// (bundle check first, confirmation dialog included).
  Future<void> _receiveViaLan(LanTransferEndpoint endpoint) async {
    setState(() => _busy = true);
    try {
      final bytes = await LanTransferClient.download(endpoint);
      if (!mounted) return;
      await _processImportBytes(bytes);
    } on LanTransferException {
      if (mounted) {
        AnikumoDialog.showToast(
          context: context,
          message: S.t('下载失败，请确认两台设备在同一局域网且发送方仍在等待'),
        );
      }
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(context: context, message: S.t('导入失败，请稍后重试'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Batch 284 (#33): the manual receive form — paste the
  /// sender's address (and token, when the address does
  /// not carry one), or scan the sender's QR code.
  Future<void> _promptLanReceive() async {
    final address = TextEditingController();
    final token = TextEditingController();
    final endpoint = await showDialog<LanTransferEndpoint>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('从局域网接收备份')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: address,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: S.t('传输地址')),
            ),
            TextField(
              controller: token,
              decoration: InputDecoration(
                labelText: S.t('传输令牌（地址不含令牌时填写）'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.t('也可以点下方「扫码」，对准发送方显示的二维码。'),
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.outline,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final raw = await context.pushNamed<Object?>(
                '/search/scan/',
                arguments: 'raw',
              );
              if (raw is! String) return;
              final parsed = parseLanEndpoint(raw);
              if (parsed != null) {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(parsed);
                }
              } else if (mounted) {
                AnikumoDialog.showToast(
                  context: context,
                  message: S.t('这不是局域网传输二维码'),
                );
              }
            },
            child: Text(S.t('扫码')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () {
              final parsed = parseLanAddressInput(address.text, token.text);
              if (parsed == null) {
                AnikumoDialog.showToast(
                  context: dialogContext,
                  message: S.t('地址或令牌不正确'),
                );
                return;
              }
              Navigator.of(dialogContext).pop(parsed);
            },
            child: Text(S.t('开始接收')),
          ),
        ],
      ),
    );
    address.dispose();
    token.dispose();
    if (endpoint == null || !mounted) return;
    await _receiveViaLan(endpoint);
  }

  @override
  Widget build(BuildContext context) {
    final counts = <(IconData, String, String)>[
      (AnikumoIcons.history_rounded, '${GStorage.histories.length}', '观看历史'),
      (AnikumoIcons.favorite_rounded, '${GStorage.collectibles.length}', '追番收藏'),
      (
        AnikumoIcons.manage_search_rounded,
        '${GStorage.searchHistory.length}',
        '搜索记录',
      ),
      (AnikumoIcons.list_alt_rounded, '${UserListsStore.load().length}', '自建榜单'),
      (AnikumoIcons.sticky_note_2_outlined, '${BangumiNotesStore.load().length}', '番剧笔记'),
      (
        AnikumoIcons.menu_book_rounded,
        '${MangaLibraryStore.loadFavorites().length}',
        '漫画收藏',
      ),
      (
        AnikumoIcons.bookmark_rounded,
        '${MangaLibraryStore.loadProgressList().length}',
        '漫画进度',
      ),
      (
        AnikumoIcons.library_books_rounded,
        '${NovelLibraryStore.loadFavorites().length}',
        '小说收藏',
      ),
      (
        AnikumoIcons.auto_stories_rounded,
        '${NovelLibraryStore.loadProgressList().length}',
        '小说进度',
      ),
      (AnikumoIcons.download_rounded, '${GStorage.downloads.length}', '动漫下载'),
      (
        AnikumoIcons.download_for_offline_rounded,
        _mangaDownloadCount?.toString() ?? '—',
        '漫画下载',
      ),
    ];
    return Scaffold(
      appBar: SysAppBar(title: Text(S.t('本地备份与恢复'))),
      body: ListView(
        padding: const EdgeInsets.all(StyleString.pagePadding),
        children: [
          GlassSurface(
            padding: const EdgeInsets.all(StyleString.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.t('当前设备上的数据'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                for (final (icon, value, label) in counts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(icon, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(S.t(label))),
                        Text(
                          value,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: StyleString.sectionSpace),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(AnikumoIcons.upload_file_outlined),
            label: Text(S.t('导出备份文件')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _exportBundle,
            icon: const Icon(AnikumoIcons.folder_zip_outlined),
            label: Text(S.t('完整备份（含已下载漫画）')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _exportEncrypted,
            icon: const Icon(Icons.lock_outline),
            label: Text(S.t('加密导出（设密码）')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(AnikumoIcons.file_download_outlined),
            label: Text(S.t('从文件恢复')),
          ),
          const SizedBox(height: 10),
          // Batch 284 (#33): device-to-device LAN transfer.
          OutlinedButton.icon(
            onPressed: _busy ? null : _sendViaLan,
            icon: const Icon(AnikumoIcons.wifi_tethering),
            label: Text(S.t('通过局域网发送备份')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _promptLanReceive,
            icon: const Icon(AnikumoIcons.lan),
            label: Text(S.t('从局域网接收备份')),
          ),
          const SizedBox(height: StyleString.sectionSpace),
          // Batch 274 (#41): automatic backup schedule.
          GlassSurface(
            padding: const EdgeInsets.all(StyleString.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        S.t('自动备份'),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Switch(
                      value:
                          GStorage.getSetting(SettingsKeys.autoBackupEnabled),
                      onChanged: _busy
                          ? null
                          : (value) async {
                              await GStorage.putSetting(
                                SettingsKeys.autoBackupEnabled,
                                value,
                              );
                              if (mounted) setState(() {});
                            },
                    ),
                  ],
                ),
                Text(
                  S.t('按计划把备份存到应用私有目录（不加密，最多保留最近 3 份）。'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(S.t('间隔')),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: GStorage.getSetting(
                        SettingsKeys.autoBackupIntervalDays,
                      ),
                      items: [
                        for (final days in [1, 3, 7, 14, 30])
                          DropdownMenuItem(
                            value: days,
                            child: Text(S.f('{} 天', [days])),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) async {
                              if (value == null) return;
                              await GStorage.putSetting(
                                SettingsKeys.autoBackupIntervalDays,
                                value,
                              );
                              if (mounted) setState(() {});
                            },
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              final done = await AutoBackupService.runNow();
                              if (mounted) {
                                setState(() => _busy = false);
                                AnikumoDialog.showToast(
                                  context: context,
                                  message: done
                                      ? S.t('备份已保存')
                                      : S.t('导出失败，请稍后重试'),
                                );
                              }
                            },
                      child: Text(S.t('立即备份一次')),
                    ),
                  ],
                ),
                if (GStorage.getSetting(SettingsKeys.lastAutoBackupMs) >
                    0)
                  Text(
                    S.f('上次自动备份：{}', [
                      DateTime.fromMillisecondsSinceEpoch(
                        GStorage.getSetting(SettingsKeys.lastAutoBackupMs),
                      ).toString().substring(0, 16),
                    ]),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(height: StyleString.sectionSpace),
          Text(
            S.t('备份文件包含你的观看历史、三区收藏与进度、榜单、笔记、已装内容源和下载记录，'
            '请像对待其他私人文件一样保管。普通备份不含下载文件本身；'
            '「完整备份」会把已下载的漫画章节一并打包，恢复后可直接离线阅读。'
            '换手机或重装前先导出一份，装好后在这里恢复即可。'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
