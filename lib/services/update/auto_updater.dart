import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/bean/dialog/update_available_dialog.dart';
import 'package:anikumo/request/config/api_endpoints.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/platform/app_exit.dart';
import 'package:anikumo/services/update/update_download_source.dart';
import 'package:anikumo/services/update/update_downloader.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:anikumo/utils/device.dart';
import 'package:anikumo/utils/version.dart';

enum InstallationType {
  windowsMsix('MSIX'),
  windowsPortable('ZIP'),
  linuxDeb('DEB'),
  linuxTar('TAR'),
  macosDmg('DMG'),
  androidApk('APK'),
  ios('IPA'),
  unknown('未知类型');

  const InstallationType(this.label);

  final String label;

  /// Types without a matching asset are updated from the release page.
  bool get downloadsInApp => getUpdateFilePatterns(this).isNotEmpty;
}

class UpdateInfo {
  final String version;
  final String description;
  final String downloadUrl;
  final String releaseNotes;
  final String publishedAt;
  final InstallationType? installationType;
  final List<InstallationType> availableInstallationTypes;
  final List<dynamic> assets;

  UpdateInfo({
    required this.version,
    required this.description,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    this.installationType,
    this.availableInstallationTypes = const [],
    this.assets = const [],
  });
  InstallationType get recommendedInstallationType {
    if (availableInstallationTypes.isNotEmpty) {
      return availableInstallationTypes.first;
    }
    return installationType ?? InstallationType.unknown;
  }
}

Map<String, dynamic>? getUpdateAssetForType(
    List<dynamic> assets, InstallationType type) {
  final patterns = getUpdateFilePatterns(type).map((p) => p.toLowerCase());

  try {
    final matches = assets.cast<Map<String, dynamic>>().where((asset) {
      final name = (asset['name'] as String?)?.toLowerCase() ?? '';
      return patterns.every((pattern) => name.contains(pattern));
    }).toList();
    if (matches.isEmpty) {
      return null;
    }
    // Batch 85: our releases ship several APK splits
    // (arm64 / armeabi-v7a / x86_64) that all match the
    // pattern — the phones this runs on are arm64, so
    // prefer that asset when present.
    for (final asset in matches) {
      final name = (asset['name'] as String?)?.toLowerCase() ?? '';
      if (name.contains('arm64')) {
        return asset;
      }
    }
    return matches.first;
  } catch (_) {
    return null;
  }
}

String getUpdateFileHashFromAsset(Map<String, dynamic> asset) {
  final digest = asset['digest'] as String? ?? '';
  if (digest.startsWith('sha256:')) {
    return digest.substring(7);
  }
  return '';
}

List<String> getUpdateFilePatterns(InstallationType installationType) {
  switch (installationType) {
    case InstallationType.windowsMsix:
      return ['windows', '.msix'];
    case InstallationType.windowsPortable:
      return ['windows', '.zip'];
    case InstallationType.macosDmg:
      return ['macos', '.dmg'];
    case InstallationType.androidApk:
      // Batch 85: our release assets are named
      // anikumo_v<NN>_<abi>.apk — they carry no 'android'
      // token, so match on the extension alone (the arm64
      // split is preferred in getUpdateAssetForType).
      return ['.apk'];
    case InstallationType.linuxDeb:
    case InstallationType.linuxTar:
    case InstallationType.ios:
    case InstallationType.unknown:
      return [];
  }
}

class AutoUpdater {
  static final AutoUpdater _instance = AutoUpdater._internal();

  factory AutoUpdater() => _instance;

  AutoUpdater._internal();

  List<InstallationType> _detectAvailableInstallationTypes() {
    if (Platform.isWindows) {
      return [InstallationType.windowsMsix, InstallationType.windowsPortable];
    }
    if (Platform.isLinux) {
      return [InstallationType.linuxDeb, InstallationType.linuxTar];
    }
    if (Platform.isMacOS) return [InstallationType.macosDmg];
    if (Platform.isIOS) return [InstallationType.ios];
    if (Platform.isAndroid) return [InstallationType.androidApk];
    return [InstallationType.unknown];
  }

  /// Batch 85: updates come from Anikumo's OWN GitHub
  /// repository — never the upstream project this app was
  /// forked from. (Batch 53 stubbed checks to a local
  /// "no update" because the inherited feed pointed at
  /// upstream; the feed is ours now, so real checks are
  /// back.)
  static const String releasesApiUrl =
      'https://api.github.com/repos/xyu3032-commits/Anikumo/releases/latest';
  static const String releasesPageUrl =
      'https://github.com/xyu3032-commits/Anikumo/releases';

  /// Parses a GitHub "latest release" payload into an
  /// [UpdateInfo] when its tag names a version newer than
  /// [localVersion]; null otherwise (including tags that
  /// are not plain dotted versions). Pure — unit-tested.
  static UpdateInfo? parseGithubRelease(
    Map<String, dynamic> json, {
    required String localVersion,
    required List<InstallationType> types,
  }) {
    var tag = (json['tag_name'] as String? ?? '').trim();
    if (tag.startsWith('v') || tag.startsWith('V')) {
      tag = tag.substring(1);
    }
    if (tag.isEmpty) {
      return null;
    }
    try {
      if (!needUpdate(localVersion, tag)) {
        return null;
      }
    } catch (_) {
      return null;
    }
    final assets = json['assets'];
    return UpdateInfo(
      version: tag,
      description: (json['name'] as String?) ?? '',
      downloadUrl: (json['html_url'] as String?) ?? releasesPageUrl,
      releaseNotes: (json['body'] as String?) ?? '',
      publishedAt: (json['published_at'] as String?) ?? '',
      installationType:
          types.isEmpty ? InstallationType.unknown : types.first,
      availableInstallationTypes: types,
      assets: assets is List ? assets : const [],
    );
  }

  Future<UpdateInfo?> checkForUpdates() async {
    try {
      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      ).get<dynamic>(
        releasesApiUrl,
        options: Options(
          headers: const {'Accept': 'application/vnd.github+json'},
        ),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return null;
      }
      return parseGithubRelease(
        data,
        localVersion: ApiEndpoints.version,
        types: _detectAvailableInstallationTypes(),
      );
    } catch (_) {
      // No releases published yet (404), offline, or
      // rate-limited — all read as "no update". The
      // manual check reports through the same null.
      return null;
    }
  }

  Future<void> autoCheckForUpdates() async {
    final autoUpdate = GStorage.getSetting(SettingsKeys.autoUpdate);
    if (!autoUpdate) return;

    try {
      final updateInfo = await checkForUpdates();
      if (updateInfo != null) {
        _showUpdateDialog(updateInfo, isAutoCheck: true);
      }
    } catch (e) {
      AnikumoLogger().w('Update: auto check for updates failed', error: e);
    }
  }

  Future<void> manualCheckForUpdates() async {
    try {
      final updateInfo = await checkForUpdates();
      if (updateInfo != null) {
        _showUpdateDialog(updateInfo, isAutoCheck: false);
      } else {
        AnikumoDialog.showToast(message: '当前已经是最新版本！');
      }
    } catch (e) {
      AnikumoDialog.showToast(message: '检查更新失败');
    }
  }

  Future<void> _showUpdateDialog(UpdateInfo updateInfo,
      {bool isAutoCheck = false}) async {
    var disableAutoUpdate = false;
    final choice = await AnikumoDialog.show<UpdateDialogChoice>(
      builder: (context) => UpdateAvailableDialog(
        updateInfo: updateInfo,
        onDisableAutoUpdateChanged:
            isAutoCheck ? (value) => disableAutoUpdate = value : null,
      ),
    );
    if (disableAutoUpdate) {
      GStorage.putSetting(SettingsKeys.autoUpdate, false);
      AnikumoDialog.showToast(message: '已关闭自动更新');
    }
    if (choice != null) {
      _downloadUpdateWithType(updateInfo, choice.type, choice.source);
    }
  }

  Future<void> _downloadUpdateWithType(
      UpdateInfo updateInfo, InstallationType selectedType,
      UpdateDownloadSource source) async {
    try {
      if (!selectedType.downloadsInApp) {
        // Batch 85: open the release PAGE. (The inherited
        // code launched releaseNotes — the notes text —
        // as if it were the URL.)
        final releaseUrl = updateInfo.downloadUrl.isNotEmpty
            ? updateInfo.downloadUrl
            : updateInfo.releaseNotes;
        if (releaseUrl.isEmpty) {
          return;
        }
        launchUrl(Uri.parse(releaseUrl), mode: LaunchMode.externalApplication);
        return;
      }

      final asset = getUpdateAssetForType(updateInfo.assets, selectedType);
      final downloadUrl = getUpdateDownloadUrlFromAsset(asset, source);
      if (asset == null || downloadUrl.isEmpty) {
        AnikumoDialog.showToast(message: '没有找到 ${selectedType.label} 的下载链接');
        return;
      }

      final expectedHash = getUpdateFileHashFromAsset(asset);
      final downloadInfo = UpdateInfo(
        version: updateInfo.version,
        description: updateInfo.description,
        downloadUrl: downloadUrl,
        releaseNotes: updateInfo.releaseNotes,
        publishedAt: updateInfo.publishedAt,
        installationType: selectedType,
        availableInstallationTypes: [selectedType],
        assets: updateInfo.assets,
      );

      _downloadUpdate(downloadInfo, expectedHash);
    } catch (e) {
      AnikumoDialog.showToast(message: '下载失败: ${e.toString()}');
      AnikumoLogger().e('Update: download update failed', error: e);
    }
  }

  Future<void> _downloadUpdate(
      UpdateInfo updateInfo, String expectedHash) async {
    if (_downloadDialogs.isRunning) return;
    await _downloadDialogs.run((task) async {
      _downloadProgress.value = 0;
      final cancelToken = CancelToken();
      final downloadPath = await task.loading(
        action: () => _downloadFile(updateInfo.downloadUrl, updateInfo.version,
            expectedHash, cancelToken),
        onCancel: cancelToken.cancel,
        builder: (context) {
          return AlertDialog(
            title: const Text('正在下载更新'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _downloadProgress,
                  builder: (context, value, child) {
                    return Column(
                      children: [
                        LinearProgressIndicator(value: value),
                        const SizedBox(height: 8),
                        Text('${(value * 100).toStringAsFixed(1)}%'),
                      ],
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => AnikumoDialog.dismiss(context: context),
                child: const Text('取消'),
              ),
            ],
          );
        },
      );

      _showDownloadCompleteDialog(downloadPath, updateInfo);
    }, onError: (e, stackTrace) {
      final errorMessage = getUpdateDownloadErrorMessage(e);

      AnikumoDialog.show(
        builder: (context) {
          return AlertDialog(
            title: const Text('下载失败'),
            content: Text(errorMessage),
            actions: [
              TextButton(
                onPressed: () => AnikumoDialog.dismiss(context: context),
                child: const Text('确定'),
              ),
            ],
          );
        },
      );

      AnikumoLogger().e(
          'Update: download failed | source=${updateInfo.downloadUrl} | '
          '${describeUpdateDownloadError(e, stackTrace)}',
          error: e);
    });
  }

  final ValueNotifier<double> _downloadProgress = ValueNotifier(0.0);
  final _downloadDialogs = AnikumoDialogController();

  void _showDownloadCompleteDialog(String filePath, UpdateInfo updateInfo) {
    AnikumoDialog.show(
      builder: (context) {
        return AlertDialog(
          title: const Text('下载完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('新版本 ${updateInfo.version} 已下载完成'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '安装过程中应用将会退出',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '文件位置:',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      filePath,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => AnikumoDialog.dismiss(),
              child: Text(
                '稍后安装',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            if (isDesktop())
              TextButton(
                onPressed: () {
                  AnikumoDialog.dismiss(context: context);
                  _revealInFileManager(filePath);
                },
                child: const Text('打开文件夹'),
              ),
            TextButton(
              onPressed: () {
                AnikumoDialog.dismiss();
                _installUpdate(
                    filePath, updateInfo.recommendedInstallationType);
              },
              child: const Text('立即安装'),
            ),
          ],
        );
      },
    );
  }

  Future<String> _downloadFile(String url, String version, String expectedHash,
      CancelToken cancelToken) async {
    final tempDir = await getTemporaryDirectory();
    return downloadUpdateFile(
      url: url,
      filePath: '${tempDir.path}/${_getFileNameFromUrl(url, version)}',
      expectedHash: expectedHash,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        _downloadProgress.value = total > 0 ? received / total : 0;
      },
    );
  }

  void _installUpdate(
      String filePath, InstallationType installationType) async {
    try {
      AnikumoDialog.showToast(message: '准备安装更新，应用即将退出...');

      await Future.delayed(const Duration(seconds: 2));

      if (Platform.isWindows) {
        if (installationType == InstallationType.windowsMsix) {
          final Uri fileUri = Uri.file(filePath);
          if (await canLaunchUrl(fileUri)) {
            await launchUrl(fileUri);
          } else {
            throw 'Could not launch $fileUri';
          }
        } else {
          await Process.start('explorer.exe', [filePath], runInShell: true);
        }
        await Future.delayed(const Duration(seconds: 1));
        await AppExit.quit();
      } else if (Platform.isMacOS) {
        if (filePath.endsWith('.dmg')) {
          await Process.start('open', [filePath]);
          await AppExit.quit();
        }
      } else if (Platform.isAndroid) {
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          AnikumoDialog.showToast(message: '无法打开安装文件: ${result.message}');
          return;
        }
      }
    } catch (e) {
      AnikumoDialog.showToast(message: '启动安装程序失败: ${e.toString()}');
      AnikumoLogger().e('Update: launch installer failed', error: e);
    }
  }

  void _revealInFileManager(String filePath) async {
    try {
      final type = await FileSystemEntity.type(filePath);
      String targetDirOrFile;
      if (type == FileSystemEntityType.notFound) {
        AnikumoDialog.showToast(message: '文件或目录不存在');
        return;
      } else if (type == FileSystemEntityType.directory) {
        targetDirOrFile = filePath;
      } else {
        targetDirOrFile = File(filePath).parent.path;
      }

      if (Platform.isWindows) {
        if (type == FileSystemEntityType.file) {
          final arg = '/select,${filePath.replaceAll('/', r'\')}';
          await Process.start('explorer.exe', [arg], runInShell: true);
        } else {
          await Process.start(
              'explorer.exe', [targetDirOrFile.replaceAll('/', r'\')],
              runInShell: true);
        }
      } else if (Platform.isMacOS) {
        if (type == FileSystemEntityType.file) {
          await Process.start('open', ['-R', filePath]);
        } else {
          await Process.start('open', [targetDirOrFile]);
        }
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [targetDirOrFile]);
      } else {
        AnikumoDialog.showToast(message: '此平台不支持通过此方法打开文件管理器');
      }
    } catch (e) {
      AnikumoDialog.showToast(message: '无法打开文件管理器');
      AnikumoLogger().w('Update: reveal in file manager failed', error: e);
    }
  }

  String _getFileNameFromUrl(String url, String version) {
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.last;

    if (fileName.isNotEmpty) {
      return fileName;
    }
    String extension = '';
    if (Platform.isWindows) {
      extension = '.msix';
    } else if (Platform.isMacOS) {
      extension = '.dmg';
    } else if (Platform.isLinux) {
      extension = '.deb';
    } else if (Platform.isAndroid) {
      extension = '.apk';
    }
    return 'Anikumo-$version$extension';
  }
}
