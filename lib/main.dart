import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:anikumo/app_module.dart';
import 'package:anikumo/app_widget.dart';
import 'package:anikumo/splash_gate.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/settings/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:anikumo/services/deep_links/app_deep_links.dart';
import 'package:anikumo/services/storage/cache_budget_trimmer.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/download/download_directory_service.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:anikumo/services/network/metered_network_service.dart';
import 'package:anikumo/services/network/ech_http_licenses.dart';
import 'package:anikumo/services/network/proxy_manager.dart';
import 'package:anikumo/services/network/system_proxy_service.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:anikumo/pages/error/storage_error_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:anikumo/utils/device.dart';
import 'package:anikumo/services/platform/desktop_window_config.dart';
import 'package:anikumo/services/platform/webview_feature_service.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/navigation.dart';
import 'package:anikumo/services/player/mini_player_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Batch 18: the default image cache (1000 images / 100 MB)
  // evicts covers aggressively on cover-dense screens (anime
  // grids, manga rails), forcing re-decode on every revisit.
  // 2000 images / 256 MB keeps a working set of covers hot;
  // entries are still evicted under memory pressure.
  PaintingBinding.instance.imageCache.maximumSize = 2000;
  // Batch 32: byte cap trimmed 256 -> 192 MB (still ~2x the
  // framework default). Covers are decode-capped at 2x their
  // display width by the cover widgets, so the resident set
  // holds MORE covers in fewer bytes; the old cap mostly
  // bought headroom for a few oversized decodes.
  // Batch 145: 192 -> 128 MB for long-session memory: still
  // above the framework default, and the width-capped
  // decodes mean the working set of covers/pages fits
  // comfortably — the trimmed headroom was mostly occupied
  // by pages from chapters read long ago in the session.
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      128 * 1024 * 1024;
  AppDeepLinks().start();
  registerEchHttpLicenses();
  MediaKit.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
  }

  if (Platform.isAndroid) {
    await WebViewFeatureService.initialize();
  }

  try {
    final hivePath = '${(await getApplicationSupportDirectory()).path}/hive';
    await Hive.initFlutter(hivePath);
    await GStorage.init();
  } catch (e) {
    debugPrint('Storage initialization failed: $e');

    if (isDesktop()) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(null, () async {
        // window_manager controls desktop visibility to avoid startup flicker.
        await windowManager.show();
        await windowManager.focus();
      });
    }
    runApp(MaterialApp(
        title: '初始化失败',
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN")
        ],
        locale: const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN"),
        builder: (context, child) {
          return const StorageErrorPage();
        }));
    return;
  }
  await DownloadDirectoryService().restoreAccess();
  final showWindowButton = DesktopWindowConfig.showWindowButton;
  if (isDesktop()) {
    await windowManager.ensureInitialized();
    final lowResolution = await isLowResolution();
    final windowOptions = WindowOptions(
      size: lowResolution ? const Size(840, 600) : const Size(1280, 860),
      center: true,
      skipTaskbar: false,
      // macOS embeds native buttons in the Flutter view.
      titleBarStyle: (Platform.isMacOS || !showWindowButton)
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: showWindowButton,
      title: 'Anikumo',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // window_manager controls desktop visibility to avoid startup flicker.
      await windowManager.show();
      await windowManager.focus();
    });
  }
  if (Platform.isWindows) {
    SystemProxyService.init();
  }
  await MeteredNetworkService.refresh();
  ProxyManager.applyProxy();
  // Batch 145: bound the on-disk image stores by bytes (the
  // managers only cap object counts). Fire-and-forget IO;
  // runs before the first frame is even requested.
  unawaited(trimImageCachesToBudgets());
  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [
        AnikumoDialog.observer,
        rootRouteObserver,
        miniPlayerRouteObserver,
      ],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
      },
      // Batch 93: the animated launch intro overlays the
      // real app (which builds underneath it) on cold start.
      child: const SplashGate(child: AppWidget()),
    ),
  );
}
