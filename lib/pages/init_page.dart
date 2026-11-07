import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/pages/my/my_controller.dart';
import 'package:anikumo/services/sync/bangumi_sync_service.dart';
import 'package:anikumo/services/sync/danmaku_shield_sync_service.dart';
import 'package:anikumo/services/sync/webdav.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/plugins/plugins_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/pages/collect/collect_controller.dart';
import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/shaders/shader_asset_service.dart';
import 'package:anikumo/pages/download/download_controller.dart';
import 'package:anikumo/services/download/background_download_service.dart';
import 'package:anikumo/services/platform/windows_shortcut.dart';
import 'package:anikumo/services/platform/platform_environment_service.dart';
import 'package:anikumo/services/platform/app_exit.dart';
import 'package:anikumo/services/update/startup_update_check.dart';
import 'package:anikumo/navigation.dart';

class InitPage extends StatefulWidget {
  const InitPage({
    super.key,
    required this.pluginsController,
    required this.collectController,
    required this.shaderAssetService,
    required this.myController,
    required this.downloadController,
    required this.danmakuShieldSync,
  });

  final PluginsController pluginsController;
  final CollectController collectController;
  final ShaderAssetService shaderAssetService;
  final MyController myController;
  final DownloadController downloadController;
  final DanmakuShieldSyncService danmakuShieldSync;

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  PluginsController get pluginsController => widget.pluginsController;
  CollectController get collectController => widget.collectController;
  ShaderAssetService get shaderAssetService => widget.shaderAssetService;
  MyController get myController => widget.myController;
  DownloadController get downloadController => widget.downloadController;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeApp());
  }

  Future<void> _initializeApp() async {
    widget.danmakuShieldSync.start();
    _migrateStorage();
    _loadShaders();
    unawaited(myController.loadShieldList());
    _webDavInit();
    _bangumiInit();
    try {
      await downloadController.init();
      _setupBackgroundDownloadNavigation();
    } catch (e) {
      AnikumoLogger().e('InitPage: downloadController.init() failed', error: e);
    }

    await _checkRunningOnX11();
    await _showShortcutDialog();
    await _pluginInit();

    if (!mounted) {
      return;
    }
    // Installs that predate the flag already have rules; don't re-onboard them.
    if (!GStorage.getSetting(SettingsKeys.onboardingCompleted) &&
        pluginsController.pluginList.isEmpty) {
      context.navigate('/onboarding');
      return;
    }

    final updateController = myController;
    unawaited(runStartupUpdateCheck(
      isEnabled: () => GStorage.getSetting(SettingsKeys.autoUpdate),
      checkForUpdate: () => updateController.checkUpdate(type: 'auto'),
    ));
    context.navigate(GStorage.getSetting(SettingsKeys.defaultStartupPage));
  }

  void _setupBackgroundDownloadNavigation() {
    final backgroundService = BackgroundDownloadService();

    backgroundService.onNavigateToDownloadRequested = () {
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final navigationContext = rootNavigatorKey.currentContext;
          if (navigationContext == null || !navigationContext.mounted) return;
          final path = navigationContext.routeState(listen: false).uri.path;
          if (path.contains('/download')) return;
          navigationContext.pushNamed('/settings/download/');
        } catch (e) {
          AnikumoLogger()
              .w('InitPage: failed to navigate to download page', error: e);
        }
      });
    };

    backgroundService.onNotificationPermissionRequired = () async {
      final result = await AnikumoDialog.show<bool>(
        clickMaskDismiss: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('需要通知权限'),
            content: const Text(
              '开启通知权限后，可以在后台下载时显示进度，并防止系统终止下载任务。\n\n'
              '如果拒绝，下载功能仍可使用，但在后台时可能被系统中断。',
            ),
            actions: [
              TextButton(
                onPressed: () => AnikumoDialog.dismiss(popWith: false),
                child: Text(
                  '稍后再说',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              TextButton(
                onPressed: () => AnikumoDialog.dismiss(popWith: true),
                child: const Text('允许'),
              ),
            ],
          );
        },
      );
      return result ?? false;
    };
  }

  // migrate collect from old version (favorites)
  Future<void> _migrateStorage() async {
    await collectController.migrateCollect();
  }

  Future<void> _loadShaders() async {
    await shaderAssetService.copyShadersToExternalDirectory();
  }

  Future<void> _webDavInit() async {
    bool webDavEnable = await GStorage.getSetting(SettingsKeys.webDavEnable);
    bool webDavEnableHistory =
        await GStorage.getSetting(SettingsKeys.webDavEnableHistory);
    if (webDavEnable) {
      var webDav = WebDav();
      AnikumoLogger().i('WebDav: Starting WebDav initialization');
      try {
        await webDav.init();
        await widget.danmakuShieldSync.syncIfEnabled();
        if (webDavEnableHistory) {
          try {
            await webDav.syncHistory();
            AnikumoLogger().i('WebDav: Completed syncing watch history');
          } catch (e, stackTrace) {
            AnikumoLogger().w(
              'WebDav: automatic watch history sync failed',
              error: e,
              stackTrace: stackTrace,
            );
          }
        }
      } catch (e, stackTrace) {
        AnikumoLogger().w(
          'WebDav: automatic initialization failed',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _bangumiInit() async {
    final bangumiEnable = GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    if (bangumiEnable) {
      final bangumi = BangumiSyncService();
      AnikumoLogger().i('Bangumi: Starting Bangumi initialization');
      try {
        await bangumi.ping();
      } catch (e) {
        AnikumoLogger().w(
          'Bangumi: initialization failed; keeping sync enabled for retry',
          error: e,
        );
        AnikumoDialog.showToast(
          message:
              'Bangumi 暂未连接，同步设置已保留：${BangumiSyncService.describeError(e)}',
        );
      }
    }
  }

  Future<void> _checkRunningOnX11() async {
    if (!Platform.isLinux) {
      return;
    }
    bool isRunningOnX11 = await PlatformEnvironmentService.isRunningOnX11();
    if (isRunningOnX11) {
      await AnikumoDialog.show(
        clickMaskDismiss: false,
        builder: (context) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('X11环境检测'),
              content: const Text(
                  '检测到您当前运行在X11环境下，Anikumo在X11环境下可能出现性能问题或界面异常，建议切换到Wayland以获得更好的体验。您是否希望在X11下继续使用Anikumo？'),
              actions: [
                TextButton(
                  onPressed: AppExit.quit,
                  child: Text(
                    '退出',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    AnikumoDialog.dismiss();
                  },
                  child: const Text('继续'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _showShortcutDialog() async {
    if (!Platform.isWindows) return;
    if (GStorage.getSetting(SettingsKeys.shortcutDialogShown)) {
      return;
    }

    final create = await AnikumoDialog.show<bool>(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: const Text('创建桌面快捷方式'),
        content: const Text('是否在桌面创建 anikumo 的快捷方式？'),
        actions: [
          TextButton(
            onPressed: () => AnikumoDialog.dismiss(popWith: false),
            child: Text('暂不创建',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          TextButton(
            onPressed: () => AnikumoDialog.dismiss(popWith: true),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    await GStorage.putSetting(SettingsKeys.shortcutDialogShown, true);
    if (create ?? false) {
      final success = await WindowsShortcut.createDesktopShortcut();
      AnikumoDialog.showToast(message: success ? '桌面快捷方式已创建' : '桌面快捷方式创建失败');
    }
  }

  Future<void> _pluginInit() async {
    try {
      await pluginsController.init();
      // Batch 59: no rule catalog — no startup update check.
    } catch (error, stackTrace) {
      AnikumoLogger().e(
        'Plugin: failed to initialize rules',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LoadingWidget();
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container());
  }
}
