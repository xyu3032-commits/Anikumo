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
import 'package:anikumo/services/platform/app_shortcuts.dart';
import 'package:anikumo/services/platform/windows_shortcut.dart';
import 'package:anikumo/services/platform/platform_environment_service.dart';
import 'package:anikumo/services/platform/app_exit.dart';
import 'package:anikumo/services/announcement/announcement_service.dart';
import 'package:anikumo/services/backup/auto_backup.dart';
import 'package:anikumo/services/sync/auto_sync.dart';
import 'package:anikumo/services/platform/home_widget_publisher.dart';
import 'package:anikumo/services/notifications/update_notification_service.dart';
import 'package:anikumo/services/collect/auto_archive.dart';
import 'package:anikumo/services/storage/library_housekeeping.dart';
import 'package:anikumo/services/update/startup_update_check.dart';
import 'package:anikumo/navigation.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

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
    // Batch 276 (#62): launcher shortcuts registration.
    AppShortcuts.initialize();
    _migrateStorage();
    _loadShaders();
    unawaited(myController.loadShieldList());
    _webDavInit();
    _bangumiInit();
    // Batch 268: the nav callbacks are cheap and must be
    // registered before any notification tap can arrive,
    // but restoring download state can take real time and
    // used to block the first navigation. It now runs after
    // the app shell is up (see the end of this method).
    _setupBackgroundDownloadNavigation();
    unawaited(_initDownloadsDeferred());

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
    // Batch 267: community announcement (published from the
    // Discord community into the repo's announcement.json).
    unawaited(runStartupAnnouncementCheck());
    // Batch 269: update notifications for watching anime /
    // favorite novels. Delayed so it never competes with the
    // first paint or the checks above; internally throttled
    // and toggle-gated.
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 10),
        () => UpdateNotificationService.runChecksIfEnabled(),
      ),
    );
    // Batch 274 (#41): scheduled local backup, same
    // deferred pattern; the service itself checks the
    // toggle and the interval.
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 15),
        () => AutoBackupService.runIfDue(),
      ),
    );
    // Batch 282 (#24): timed auto sync — checked a
    // little after the backup so the two never race
    // the first frame; the service re-checks every
    // 30 minutes while the app keeps running.
    AutoSyncService.startPeriodicChecks();
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 18),
        () => AutoSyncService.runIfDue(),
      ),
    );
    // Batch 276 (#61): refresh the home-screen
    // continue-watching widget (Android only inside).
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 20),
        HomeWidgetPublisher.publishContinue,
      ),
    );
    // Batch 283 (#23): finished-show auto archive —
    // same deferred rhythm as the checks above, with
    // its own throttle inside the service.
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 22),
        AutoArchiveService.runIfDue,
      ),
    );
    // Batch 283 (#27/#28): cache cap + history
    // retention housekeeping, last in the chain.
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 24),
        LibraryHousekeeping.runStartupChecks,
      ),
    );
    // Batch 284 (#32): refresh the home-screen
    // calendar widget on the same deferred rhythm.
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 26),
        HomeWidgetPublisher.publishCalendar,
      ),
    );
    context.navigate(GStorage.getSetting(SettingsKeys.defaultStartupPage));
  }

  /// Batch 268: download state restore, deferred until
  /// after the first navigation so a cold start reaches the
  /// home page without waiting on it.
  Future<void> _initDownloadsDeferred() async {
    try {
      await downloadController.init();
    } catch (e) {
      AnikumoLogger()
          .e('InitPage: downloadController.init() failed', error: e);
    }
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
            title: Text(S.t('需要通知权限')),
            content: Text(
              S.t('开启通知权限后，可以在后台下载时显示进度，并防止系统终止下载任务。\n\n如果拒绝，下载功能仍可使用，但在后台时可能被系统中断。'),
            ),
            actions: [
              TextButton(
                onPressed: () => AnikumoDialog.dismiss(popWith: false),
                child: Text(
                  S.t('稍后再说'),
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              TextButton(
                onPressed: () => AnikumoDialog.dismiss(popWith: true),
                child: Text(S.t('允许')),
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
              S.f('Bangumi 暂未连接，同步设置已保留：{}', [BangumiSyncService.describeError(e)]),
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
              title: Text(S.t('X11环境检测')),
              content: Text(
                  S.t('检测到您当前运行在X11环境下，Anikumo在X11环境下可能出现性能问题或界面异常，建议切换到Wayland以获得更好的体验。您是否希望在X11下继续使用Anikumo？')),
              actions: [
                TextButton(
                  onPressed: AppExit.quit,
                  child: Text(
                    S.t('退出'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    AnikumoDialog.dismiss();
                  },
                  child: Text(S.t('继续')),
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
        title: Text(S.t('创建桌面快捷方式')),
        content: Text(S.t('是否在桌面创建 anikumo 的快捷方式？')),
        actions: [
          TextButton(
            onPressed: () => AnikumoDialog.dismiss(popWith: false),
            child: Text(S.t('暂不创建'),
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          TextButton(
            onPressed: () => AnikumoDialog.dismiss(popWith: true),
            child: Text(S.t('创建')),
          ),
        ],
      ),
    );

    await GStorage.putSetting(SettingsKeys.shortcutDialogShown, true);
    if (create ?? false) {
      final success = await WindowsShortcut.createDesktopShortcut();
      AnikumoDialog.showToast(message: success ? S.t('桌面快捷方式已创建') : S.t('桌面快捷方式创建失败'));
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
