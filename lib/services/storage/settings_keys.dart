import 'package:anikumo/services/player/syncplay_endpoint.dart';
import 'package:anikumo/utils/device.dart';

enum SettingGroup {
  player,
  danmaku,
  theme,
  interface,
  proxy,
  webdav,
  download,
  bangumi,
  collect,
  sync,
  update,
  misc,
}

class SettingContext {
  const SettingContext({this.compactLayout = false});

  final bool compactLayout;
}

class SettingKey<T> {
  const SettingKey(
    this.name,
    this.defaultValue, {
    required this.group,
    this.defaultResolver,
  });

  final String name;
  final T defaultValue;
  final SettingGroup group;
  final T Function(SettingContext context)? defaultResolver;

  T resolveDefault(SettingContext context) {
    return defaultResolver?.call(context) ?? defaultValue;
  }
}

// Add new settings here. SettingsKeys is the public typed registry used by
// callers; new keys can use literal string names directly.
class SettingsKeys {
  static const hAenable = SettingKey<bool>(
    _SettingBoxKey.hAenable,
    true,
    group: SettingGroup.player,
  );
  static const hardwareDecoder = SettingKey<String>(
    _SettingBoxKey.hardwareDecoder,
    'auto-safe',
    group: SettingGroup.player,
  );
  static const searchEnhanceEnable = SettingKey<bool>(
    _SettingBoxKey.searchEnhanceEnable,
    true,
    group: SettingGroup.misc,
  );
  static const autoUpdate = SettingKey<bool>(
    _SettingBoxKey.autoUpdate,
    true,
    group: SettingGroup.update,
  );
  static const alwaysOntop = SettingKey<bool>(
    _SettingBoxKey.alwaysOntop,
    false,
    group: SettingGroup.misc,
  );
  static const defaultPlaySpeed = SettingKey<double>(
    _SettingBoxKey.defaultPlaySpeed,
    1.0,
    group: SettingGroup.player,
  );
  static const defaultShortcutForwardPlaySpeed = SettingKey<double>(
    _SettingBoxKey.defaultShortcutForwardPlaySpeed,
    2.0,
    group: SettingGroup.player,
  );
  static const defaultAspectRatioType = SettingKey<int>(
    _SettingBoxKey.defaultAspectRatioType,
    1,
    group: SettingGroup.player,
  );
  static const buttonSkipTime = SettingKey<int>(
    _SettingBoxKey.buttonSkipTime,
    80,
    group: SettingGroup.player,
  );
  static const arrowKeySkipTime = SettingKey<int>(
    _SettingBoxKey.arrowKeySkipTime,
    10,
    group: SettingGroup.player,
  );
  static const danmakuEnhance = SettingKey<bool>(
    _SettingBoxKey.danmakuEnhance,
    true,
    group: SettingGroup.danmaku,
  );
  /// Off on desktop and on on mobile, like the B 站 client.
  static final pauseOnDanmakuEdit = SettingKey<bool>(
    'pauseOnDanmakuEdit',
    true,
    group: SettingGroup.danmaku,
    defaultResolver: (_) => !isDesktop(),
  );
  static const danmakuBorder = SettingKey<bool>(
    _SettingBoxKey.danmakuBorder,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBorderSize = SettingKey<double>(
    _SettingBoxKey.danmakuBorderSize,
    1.5,
    group: SettingGroup.danmaku,
  );
  static const danmakuOpacity = SettingKey<double>(
    _SettingBoxKey.danmakuOpacity,
    1.0,
    group: SettingGroup.danmaku,
  );
  static final danmakuFontSize = SettingKey<double>(
    _SettingBoxKey.danmakuFontSize,
    25.0,
    group: SettingGroup.danmaku,
    defaultResolver: (context) => context.compactLayout ? 16.0 : 25.0,
  );
  static const danmakuTop = SettingKey<bool>(
    _SettingBoxKey.danmakuTop,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuScroll = SettingKey<bool>(
    _SettingBoxKey.danmakuScroll,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBottom = SettingKey<bool>(
    _SettingBoxKey.danmakuBottom,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuMassive = SettingKey<bool>(
    _SettingBoxKey.danmakuMassive,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuDeduplication = SettingKey<bool>(
    _SettingBoxKey.danmakuDeduplication,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuChConvert = SettingKey<int>(
    'danmakuChConvert',
    0,
    group: SettingGroup.danmaku,
  );
  static const danmakuArea = SettingKey<double>(
    _SettingBoxKey.danmakuArea,
    1.0,
    group: SettingGroup.danmaku,
  );

  // Batch 18: user-supplied DanDanPlay API credentials. Release
  // builds inject them via --dart-define (DANDANAPI_APPID /
  // DANDANAPI_KEY); when those are empty (self-built packages)
  // every danmaku request is signed with empty credentials and
  // the API answers 403 — danmaku search and display both die
  // silently. Users can register their own app at
  // open.dandanplay.net and paste the pair here instead.
  static const danmakuAppId = SettingKey<String>(
    'danmakuAppId',
    '',
    group: SettingGroup.danmaku,
  );
  static const danmakuAppKey = SettingKey<String>(
    'danmakuAppKey',
    '',
    group: SettingGroup.danmaku,
  );
  static const danmakuColor = SettingKey<bool>(
    _SettingBoxKey.danmakuColor,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuDuration = SettingKey<double>(
    _SettingBoxKey.danmakuDuration,
    8.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuLineHeight = SettingKey<double>(
    _SettingBoxKey.danmakuLineHeight,
    1.6,
    group: SettingGroup.danmaku,
  );
  static const danmakuTimeOffset = SettingKey<double>(
    _SettingBoxKey.danmakuTimeOffset,
    0.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuEnabledByDefault = SettingKey<bool>(
    _SettingBoxKey.danmakuEnabledByDefault,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuBiliBiliSource = SettingKey<bool>(
    _SettingBoxKey.danmakuBiliBiliSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuGamerSource = SettingKey<bool>(
    _SettingBoxKey.danmakuGamerSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuDanDanSource = SettingKey<bool>(
    _SettingBoxKey.danmakuDanDanSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuFontWeight = SettingKey<int>(
    _SettingBoxKey.danmakuFontWeight,
    4,
    group: SettingGroup.danmaku,
  );
  static const danmakuFollowSpeed = SettingKey<bool>(
    _SettingBoxKey.danmakuFollowSpeed,
    true,
    group: SettingGroup.danmaku,
  );
  static const themeMode = SettingKey<String>(
    _SettingBoxKey.themeMode,
    'system',
    group: SettingGroup.theme,
  );
  static const themeColor = SettingKey<String>(
    _SettingBoxKey.themeColor,
    'default',
    group: SettingGroup.theme,
  );

  /// Glass (frosted) surface intensity: 0 = off, 1 = light, 2 = strong.
  static const glassEffectLevel = SettingKey<int>(
    'glassEffectLevel',
    1,
    group: SettingGroup.theme,
  );

  /// User-created custom lists （我的榜单）, stored as one JSON string.
  static const userListsJson = SettingKey<String>(
    'userListsJson',
    '',
    group: SettingGroup.misc,
  );

  /// Per-bangumi local notes （番剧笔记）, stored as one JSON string.
  static const bangumiNotesJson = SettingKey<String>(
    'bangumiNotesJson',
    '',
    group: SettingGroup.misc,
  );

  /// What happens when an episode finishes: 'next' (follow the
  /// auto-play-next switch), 'loop' (replay the same episode),
  /// 'stop' (stay on the ended episode).
  static const playbackMode = SettingKey<String>(
    'playbackMode',
    'next',
    group: SettingGroup.player,
  );

  /// Buffer strategy: 'auto' (follow low-memory/metered logic),
  /// 'smooth' (always the large buffer), 'saver' (capped small buffer).
  static const bufferProfile = SettingKey<String>(
    'bufferProfile',
    'auto',
    group: SettingGroup.player,
  );

  /// Global default intro skip length in seconds (0 = off).
  static const defaultOpSkipSeconds = SettingKey<int>(
    'defaultOpSkipSeconds',
    0,
    group: SettingGroup.player,
  );

  /// Global default outro skip length in seconds (0 = off).
  static const defaultEdSkipSeconds = SettingKey<int>(
    'defaultEdSkipSeconds',
    0,
    group: SettingGroup.player,
  );

  /// When a source fails to resolve, try the plugin's other roads
  /// automatically before reporting the failure.
  static const autoSwitchRoad = SettingKey<bool>(
    'autoSwitchRoad',
    true,
    group: SettingGroup.player,
  );

  /// Per-bangumi OP/ED skip overrides, stored as one JSON string.
  static const skipMemoryJson = SettingKey<String>(
    'skipMemoryJson',
    '',
    group: SettingGroup.player,
  );

  /// Last known-good road per plugin name, stored as one JSON string.
  static const roadPreferenceJson = SettingKey<String>(
    'roadPreferenceJson',
    '',
    group: SettingGroup.player,
  );

  /// Weekly episode goal shown on the watch-report page.
  static const weeklyGoalEpisodes = SettingKey<int>(
    'weeklyGoalEpisodes',
    7,
    group: SettingGroup.misc,
  );

  /// Bangumi card visual style: 0 classic, 1 wide, 2 magazine,
  /// 3 minimal, 4 framed. See CardStyle.
  static const cardStyle = SettingKey<int>(
    'cardStyle',
    1,
    group: SettingGroup.theme,
  );

  /// Manga zone favorites, stored as one JSON string.
  static const mangaFavoritesJson = SettingKey<String>(
    'mangaFavoritesJson',
    '',
    group: SettingGroup.misc,
  );

  /// Manga reading progress (per manga: chapter + page), JSON string.
  static const mangaProgressJson = SettingKey<String>(
    'mangaProgressJson',
    '',
    group: SettingGroup.misc,
  );

  /// Novel zone favorites (Legado sources), JSON string.
  static const novelFavoritesJson = SettingKey<String>(
    'novelFavoritesJson',
    '',
    group: SettingGroup.misc,
  );

  /// Novel reading progress (per book: chapter + offset), JSON.
  static const novelProgressJson = SettingKey<String>(
    'novelProgressJson',
    '',
    group: SettingGroup.misc,
  );

  /// User-imported Legado book sources, JSON array string.
  static const novelInstalledSourcesJson = SettingKey<String>(
    'novelInstalledSourcesJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 68: persistent cookie jar for novel source
  /// sites, JSON object {domain: {name: value}}. Filled
  /// from Set-Cookie responses and WebView logins.
  static const novelCookieJarJson = SettingKey<String>(
    'novelCookieJarJson',
    '',
    group: SettingGroup.misc,
  );

  /// Active novel source id (a Legado bookSourceUrl or a
  /// built-in id).
  static const novelActiveSource = SettingKey<String>(
    'novelActiveSource',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 42: ids of novel sources proven dead (domain no
  /// longer resolves), JSON array string — drives the
  /// 已失效 badge, the one-tap cleanup and optional
  /// auto-delete in the sources tab.
  static const novelDeadSourceIds = SettingKey<String>(
    'novelDeadSourceIds',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 42: when true, an imported source proven dead
  /// (host lookup failure) is removed automatically.
  static const novelAutoDeleteDeadSources = SettingKey<bool>(
    'novelAutoDeleteDeadSources',
    false,
    group: SettingGroup.misc,
  );

  /// Batch 46: consecutive hard-failure counts per novel
  /// source (JSON object id → count). Auto-delete of an
  /// imported source needs two strikes, so one bad evening
  /// never deletes a source.
  static const novelDeadStrikeCounts = SettingKey<String>(
    'novelDeadStrikeCounts',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 46: user-pinned novel source ids (JSON array,
  /// pin order) — pinned sources lead the sources tab and
  /// the home tab's per-source sections.
  static const novelPinnedSourceIds = SettingKey<String>(
    'novelPinnedSourceIds',
    '',
    group: SettingGroup.misc,
  );

  /// Novel reader font size (logical px).
  static const novelFontSize = SettingKey<double>(
    'novelFontSize',
    17,
    group: SettingGroup.misc,
  );

  /// Manga reader mode (Venera-style): 'galleryLTR', 'galleryRTL'
  /// or 'continuous'. Legacy values 'paged'/'scroll' are migrated
  /// by normalizeMangaReaderMode.
  static const mangaReaderMode = SettingKey<String>(
    'mangaReaderMode',
    'galleryLTR',
    group: SettingGroup.misc,
  );

  /// Reader: tap the screen sides to turn pages.
  static const mangaTapToTurn = SettingKey<bool>(
    'mangaTapToTurn',
    true,
    group: SettingGroup.misc,
  );

  /// Reader: swap the tap-to-turn sides.
  static const mangaReverseTap = SettingKey<bool>(
    'mangaReverseTap',
    false,
    group: SettingGroup.misc,
  );

  /// Reader: animate page turns instead of jumping.
  static const mangaPageAnimation = SettingKey<bool>(
    'mangaPageAnimation',
    true,
    group: SettingGroup.misc,
  );

  /// Reader: show a small page-number chip over the page.
  static const mangaShowPageNumber = SettingKey<bool>(
    'mangaShowPageNumber',
    true,
    group: SettingGroup.misc,
  );

  /// Reader: keep the screen awake while reading.
  static const mangaKeepScreenOn = SettingKey<bool>(
    'mangaKeepScreenOn',
    false,
    group: SettingGroup.misc,
  );

  /// Reader: auto page turning interval in seconds (0 = off).
  static const mangaAutoPageSeconds = SettingKey<int>(
    'mangaAutoPageSeconds',
    0,
    group: SettingGroup.misc,
  );

  /// Manga source: include 'suggestive' rated titles in listings.
  static const mangaAllowSuggestive = SettingKey<bool>(
    'mangaAllowSuggestive',
    true,
    group: SettingGroup.misc,
  );

  /// How many entries the home history rail shows.
  static const mangaHistoryRailCount = SettingKey<int>(
    'mangaHistoryRailCount',
    10,
    group: SettingGroup.misc,
  );

  /// Grid columns on the manga explore / favorites tabs.
  static const mangaGridColumns = SettingKey<int>(
    'mangaGridColumns',
    3,
    group: SettingGroup.misc,
  );

  /// Chapter image quality: 'original' or 'saver' (MangaDex
  /// data-saver renditions).
  static const mangaImageQuality = SettingKey<String>(
    'mangaImageQuality',
    'original',
    group: SettingGroup.misc,
  );

  /// The active manga source id ('mangadex', 'zaimanhua',
  /// 'komiic', or an installed source's id).
  static const mangaActiveSource = SettingKey<String>(
    'mangaActiveSource',
    'mangadex',
    group: SettingGroup.misc,
  );

  /// Installed Venera JS manga sources: a JSON list of
  /// {key, name, version, fileName, code} entries. The code is
  /// the downloaded .js file, executed by the QuickJS runtime
  /// (the original Venera mechanism).
  static const mangaJsSourcesJson = SettingKey<String>(
    'mangaJsSourcesJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 47: user-pinned manga source ids (JSON array,
  /// pin order) — pinned sources lead the sources page and
  /// the explore tab's source chips.
  static const mangaPinnedSourceIds = SettingKey<String>(
    'mangaPinnedSourceIds',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 74: JS source keys with an account session the
  /// user opened through the manga login page (JSON array).
  /// Cookie-based sources keep no token in their KV, so the
  /// host tracks the session itself; token-based sources are
  /// detected from their KV as well.
  static const mangaAccountSessionsJson = SettingKey<String>(
    'mangaAccountSessionsJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 75: the user's pinned trio for cross-zone manga
  /// searches (JSON array of source ids, empty = automatic:
  /// active source + next installed).
  static const mangaCrossSearchSourceIds = SettingKey<String>(
    'mangaCrossSearchSourceIds',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 75: same pin for cross-zone novel searches.
  static const novelCrossSearchSourceIds = SettingKey<String>(
    'novelCrossSearchSourceIds',
    '',
    group: SettingGroup.misc,
  );

  /// Per-JS-source persisted data/settings (the KV mirror the
  /// Venera bridge's load_data / load_setting read): a JSON
  /// object mapping source key → {data: {...}, settings: {...}}.
  static const mangaJsDataJson = SettingKey<String>(
    'mangaJsDataJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 25: disk snapshots of per-source popular lists so
  /// the manga home paints instantly on entry (SWR): a JSON
  /// object mapping cache key → {ts, items}.
  static const mangaPopularSnapshotsJson = SettingKey<String>(
    'mangaPopularSnapshotsJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 15 manga extras: per-manga local ratings + notes.
  static const mangaRatingsJson = SettingKey<String>(
    'mangaRatingsJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 15: pinned favorite keys (JSON list of 'source:id').
  static const mangaPinnedJson = SettingKey<String>(
    'mangaPinnedJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 15: last known chapter counts per favorite key, for
  /// the 追新 update check.
  static const mangaKnownChaptersJson = SettingKey<String>(
    'mangaKnownChaptersJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 15: reading statistics (totals + per-day seconds).
  static const mangaReadingStatsJson = SettingKey<String>(
    'mangaReadingStatsJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 15: manga search history keywords (JSON list).
  static const mangaSearchHistoryJson = SettingKey<String>(
    'mangaSearchHistoryJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 15 (big features): global text scale factor.
  static const textScaleFactor = SettingKey<double>(
    'textScaleFactor',
    1,
    group: SettingGroup.theme,
  );

  /// Batch 84: user-imported font — display name of the
  /// picked file ('' = no custom font).
  static const customFontName = SettingKey<String>(
    'customFontName',
    '',
    group: SettingGroup.theme,
  );

  /// Batch 84: the FontLoader family the imported font is
  /// registered under ('' = none). The name carries a
  /// serial — see customFontSerial — because the engine
  /// caches a family once loaded.
  static const customFontFamily = SettingKey<String>(
    'customFontFamily',
    '',
    group: SettingGroup.theme,
  );

  /// Batch 84: bumped on every font import so each import
  /// registers under a fresh family name.
  static const customFontSerial = SettingKey<int>(
    'customFontSerial',
    0,
    group: SettingGroup.theme,
  );

  /// Batch 15: default start tab (0-5 shell tabs, 6 = manga).
  /// Batch 37: the shell grew to 8 tabs — indices were
  /// remapped once (see navTabsV2Migrated); 8 = manga now.
  static const startTabIndex = SettingKey<int>(
    'startTabIndex',
    0,
    group: SettingGroup.misc,
  );

  /// Batch 37: one-time remap marker for startTabIndex after
  /// the 工具箱 / 时光 tabs were inserted into the shell.
  static const navTabsV2Migrated = SettingKey<bool>(
    'navTabsV2Migrated',
    false,
    group: SettingGroup.misc,
  );

  /// Batch 62: the user-supplied rule repository base URL
  /// (restores the batch-59-deleted key of the same name;
  /// empty = no repository configured).
  static const ruleRepositoryUrl = SettingKey<String>(
    'ruleRepositoryUrl',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 55: one-time remap marker for startTabIndex after
  /// 工具箱 moved from the shell into Settings.
  static const navTabsV3Migrated = SettingKey<bool>(
    'navTabsV3Migrated',
    false,
    group: SettingGroup.misc,
  );

  /// Batch 15: scheduled dark mode (21:00-06:00).
  static const scheduledDark = SettingKey<bool>(
    'scheduledDark',
    false,
    group: SettingGroup.theme,
  );

  /// Batch 15: PIN app lock, sha256 hex ('' = off).
  static const pinLockHash = SettingKey<String>(
    'pinLockHash',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 15: per-anime playback speed overrides (JSON map).
  static const perAnimePlayJson = SettingKey<String>(
    'perAnimePlayJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 15: title filter keywords (JSON list).
  static const titleFilterJson = SettingKey<String>(
    'titleFilterJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 15: saved anime search keywords (JSON list).
  static const savedAnimeSearchesJson = SettingKey<String>(
    'savedAnimeSearchesJson',
    '',
    group: SettingGroup.misc,
  );

  /// Batch 15: smooth/power-save mode master switch.
  static const smoothMode = SettingKey<bool>(
    'smoothMode',
    false,
    group: SettingGroup.misc,
  );

  /// Glass level to restore when smooth mode turns off (-1 none).
  static const glassLevelBackup = SettingKey<int>(
    'glassLevelBackup',
    -1,
    group: SettingGroup.misc,
  );

  /// Batch 15: reader in-app dim level (0..0.7).
  static const mangaReaderDim = SettingKey<double>(
    'mangaReaderDim',
    0,
    group: SettingGroup.misc,
  );
  static const privateMode = SettingKey<bool>(
    _SettingBoxKey.privateMode,
    false,
    group: SettingGroup.player,
  );
  static const autoPlay = SettingKey<bool>(
    _SettingBoxKey.autoPlay,
    true,
    group: SettingGroup.player,
  );
  static const autoPlayNext = SettingKey<bool>(
    _SettingBoxKey.autoPlayNext,
    true,
    group: SettingGroup.player,
  );
  static const playResume = SettingKey<bool>(
    _SettingBoxKey.playResume,
    true,
    group: SettingGroup.player,
  );
  static const showPlayerError = SettingKey<bool>(
    _SettingBoxKey.showPlayerError,
    false,
    group: SettingGroup.player,
  );
  static const oledEnhance = SettingKey<bool>(
    _SettingBoxKey.oledEnhance,
    false,
    group: SettingGroup.theme,
  );
  static const displayMode = SettingKey<String?>(
    _SettingBoxKey.displayMode,
    null,
    group: SettingGroup.interface,
  );
  static const enableGitProxy = SettingKey<bool>(
    _SettingBoxKey.enableGitProxy,
    true,
    group: SettingGroup.proxy,
  );
  static const enableBangumiProxy = SettingKey<bool>(
    _SettingBoxKey.enableBangumiProxy,
    true,
    group: SettingGroup.proxy,
  );
  static const imageAcceleration = SettingKey<String>(
    'imageAcceleration',
    'ech',
    group: SettingGroup.proxy,
  );
  // Unset modes inherit the old mirror switches (enabled by default).
  static const bangumiAcceleration = SettingKey<String>(
    'bangumiAcceleration',
    '',
    group: SettingGroup.proxy,
  );
  static const enableSystemProxy = SettingKey<bool>(
    _SettingBoxKey.enableSystemProxy,
    false,
    group: SettingGroup.proxy,
  );
  static const defaultStartupPage = SettingKey<String>(
    _SettingBoxKey.defaultStartupPage,
    '/tab/popular/',
    group: SettingGroup.interface,
  );
  static const webDavEnable = SettingKey<bool>(
    _SettingBoxKey.webDavEnable,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavEnableHistory = SettingKey<bool>(
    _SettingBoxKey.webDavEnableHistory,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavEnableCollect = SettingKey<bool>(
    _SettingBoxKey.webDavEnableCollect,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavEnableDanmakuShield = SettingKey<bool>(
    'webDavEnableDanmakuShield',
    false,
    group: SettingGroup.webdav,
  );
  static const webDavSyncRootMigrated = SettingKey<bool>(
    'webDavSyncRootMigrated',
    false,
    group: SettingGroup.webdav,
  );
  static const danmakuShieldSyncDeviceId = SettingKey<String>(
    'danmakuShieldSyncDeviceId',
    '',
    group: SettingGroup.sync,
  );
  static const danmakuShieldSyncState = SettingKey<String>(
    'danmakuShieldSyncState',
    '',
    group: SettingGroup.sync,
  );
  static const danmakuShieldSyncCorruptState = SettingKey<String>(
    'danmakuShieldSyncCorruptState',
    '',
    group: SettingGroup.sync,
  );
  static const webDavURL = SettingKey<String>(
    _SettingBoxKey.webDavURL,
    '',
    group: SettingGroup.webdav,
  );
  static const webDavUsername = SettingKey<String>(
    _SettingBoxKey.webDavUsername,
    '',
    group: SettingGroup.webdav,
  );
  static const webDavPassword = SettingKey<String>(
    _SettingBoxKey.webDavPassword,
    '',
    group: SettingGroup.webdav,
  );
  static const lowMemoryMode = SettingKey<bool>(
    _SettingBoxKey.lowMemoryMode,
    false,
    group: SettingGroup.player,
  );
  // Null preserves the legacy lowMemoryMode choice until a policy is selected.
  static const lowMemoryPolicy = SettingKey<String?>(
    'lowMemoryPolicy',
    null,
    group: SettingGroup.player,
  );
  static const showWindowButton = SettingKey<bool>(
    _SettingBoxKey.showWindowButton,
    false,
    group: SettingGroup.theme,
  );
  static const useDynamicColor = SettingKey<bool>(
    _SettingBoxKey.useDynamicColor,
    false,
    group: SettingGroup.theme,
  );
  static const exitBehavior = SettingKey<int>(
    _SettingBoxKey.exitBehavior,
    2,
    group: SettingGroup.interface,
  );
  static const playerDebugMode = SettingKey<bool>(
    _SettingBoxKey.playerDebugMode,
    false,
    group: SettingGroup.player,
  );
  static const syncPlayEndPoint = SettingKey<String>(
    _SettingBoxKey.syncPlayEndPoint,
    defaultSyncPlayEndPoint,
    group: SettingGroup.player,
  );
  static const syncPlayUserName = SettingKey<String>(
    'syncPlayUserName',
    '',
    group: SettingGroup.player,
  );
  static const androidEnableOpenSLES = SettingKey<bool>(
    _SettingBoxKey.androidEnableOpenSLES,
    true,
    group: SettingGroup.player,
  );
  static const androidVideoRenderer = SettingKey<String>(
    _SettingBoxKey.androidVideoRenderer,
    'auto',
    group: SettingGroup.player,
  );
  static const androidAutoEnterPIP = SettingKey<bool>(
    _SettingBoxKey.androidAutoEnterPIP,
    false,
    group: SettingGroup.player,
  );
  static const defaultSuperResolutionMode = SettingKey<int>(
    _SettingBoxKey.defaultSuperResolutionMode,
    1,
    group: SettingGroup.player,
  );
  static const disableSuperResolutionWarning = SettingKey<bool>(
    _SettingBoxKey.disableSuperResolutionWarning,
    false,
    group: SettingGroup.player,
  );
  static const playerDisableAnimations = SettingKey<bool>(
    _SettingBoxKey.playerDisableAnimations,
    false,
    group: SettingGroup.player,
  );
  static const playerLogLevel = SettingKey<int>(
    _SettingBoxKey.playerLogLevel,
    2,
    group: SettingGroup.player,
  );
  static const timelineNotShowAbandonedBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineNotShowAbandonedBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const timelineNotShowWatchedBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineNotShowWatchedBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const timelineOnlyShowWatchingBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineOnlyShowWatchingBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const useSystemFont = SettingKey<bool>(
    _SettingBoxKey.useSystemFont,
    false,
    group: SettingGroup.theme,
  );
  static const forceAdBlocker = SettingKey<bool>(
    _SettingBoxKey.forceAdBlocker,
    false,
    group: SettingGroup.player,
  );
  static const backgroundPlayback = SettingKey<bool>(
    _SettingBoxKey.backgroundPlayback,
    false,
    group: SettingGroup.player,
  );
  static const proxyEnable = SettingKey<bool>(
    _SettingBoxKey.proxyEnable,
    false,
    group: SettingGroup.proxy,
  );
  static const proxyConfigured = SettingKey<bool>(
    _SettingBoxKey.proxyConfigured,
    false,
    group: SettingGroup.proxy,
  );
  static const proxyUrl = SettingKey<String>(
    _SettingBoxKey.proxyUrl,
    '',
    group: SettingGroup.proxy,
  );
  static const proxyTestUrl = SettingKey<String>(
    _SettingBoxKey.proxyTestUrl,
    '',
    group: SettingGroup.proxy,
  );
  static const showRating = SettingKey<bool>(
    _SettingBoxKey.showRating,
    true,
    group: SettingGroup.interface,
  );
  static const defaultCollectLayout = SettingKey<String>(
    'defaultCollectLayout',
    'list',
    group: SettingGroup.interface,
  );
  static const downloadParallelEpisodes = SettingKey<int>(
    _SettingBoxKey.downloadParallelEpisodes,
    2,
    group: SettingGroup.download,
  );
  static const downloadParallelSegments = SettingKey<int>(
    _SettingBoxKey.downloadParallelSegments,
    3,
    group: SettingGroup.download,
  );
  static const downloadDanmaku = SettingKey<bool>(
    _SettingBoxKey.downloadDanmaku,
    true,
    group: SettingGroup.download,
  );
  static const downloadDirectory = SettingKey<String>(
    _SettingBoxKey.downloadDirectory,
    '',
    group: SettingGroup.download,
  );
  // macOS only: security-scoped bookmark that keeps downloadDirectory
  // writable across app restarts under the sandbox.
  static const downloadDirectoryBookmark = SettingKey<String>(
    'downloadDirectoryBookmark',
    '',
    group: SettingGroup.download,
  );
  static const shortcutDialogShown = SettingKey<bool>(
    _SettingBoxKey.shortcutDialogShown,
    false,
    group: SettingGroup.misc,
  );
  static const onboardingCompleted = SettingKey<bool>(
    'onboardingCompleted',
    false,
    group: SettingGroup.misc,
  );
  static const bangumiSyncEnable = SettingKey<bool>(
    _SettingBoxKey.bangumiSyncEnable,
    false,
    group: SettingGroup.bangumi,
  );
  static const bangumiAccessToken = SettingKey<String>(
    _SettingBoxKey.bangumiAccessToken,
    '',
    group: SettingGroup.bangumi,
  );
  static const bangumiSyncPriority = SettingKey<int>(
    _SettingBoxKey.bangumiSyncPriority,
    0,
    group: SettingGroup.bangumi,
  );
  static const bangumiImmediateSyncToastEnable = SettingKey<bool>(
    _SettingBoxKey.bangumiImmediateSyncToastEnable,
    true,
    group: SettingGroup.bangumi,
  );
  static const brightnessVolumeGesture = SettingKey<bool>(
    _SettingBoxKey.brightnessVolumeGesture,
    true,
    group: SettingGroup.player,
  );
  static const historySyncDeviceId = SettingKey<String>(
    _SettingBoxKey.historySyncDeviceId,
    '',
    group: SettingGroup.sync,
  );
  static const historySyncSequence = SettingKey<int>(
    _SettingBoxKey.historySyncSequence,
    0,
    group: SettingGroup.sync,
  );
  static const historySyncSnapshotInitialized = SettingKey<bool>(
    _SettingBoxKey.historySyncSnapshotInitialized,
    false,
    group: SettingGroup.sync,
  );
  static const playerControllerLayerDisappearTime = SettingKey<int>(
    'playerControllerLayerDisappearTime',
    4000,
    group: SettingGroup.player,
  );
  static const defaultVolume = SettingKey<double>(
    'defaultVolume',
    100.0,
    group: SettingGroup.player,
  );
  static const playerMuted = SettingKey<bool>(
    'playerMuted',
    false,
    group: SettingGroup.player,
  );

  static final List<SettingKey<Object?>> all = [
    hAenable,
    hardwareDecoder,
    searchEnhanceEnable,
    autoUpdate,
    alwaysOntop,
    defaultPlaySpeed,
    defaultShortcutForwardPlaySpeed,
    defaultAspectRatioType,
    buttonSkipTime,
    arrowKeySkipTime,
    danmakuEnhance,
    pauseOnDanmakuEdit,
    danmakuBorder,
    danmakuBorderSize,
    danmakuOpacity,
    danmakuFontSize,
    danmakuTop,
    danmakuScroll,
    danmakuBottom,
    danmakuMassive,
    danmakuDeduplication,
    danmakuChConvert,
    danmakuArea,
    danmakuColor,
    danmakuDuration,
    danmakuLineHeight,
    danmakuTimeOffset,
    danmakuEnabledByDefault,
    danmakuBiliBiliSource,
    danmakuGamerSource,
    danmakuDanDanSource,
    danmakuFontWeight,
    danmakuFollowSpeed,
    themeMode,
    themeColor,
    privateMode,
    autoPlay,
    autoPlayNext,
    playResume,
    showPlayerError,
    oledEnhance,
    displayMode,
    enableGitProxy,
    enableBangumiProxy,
    imageAcceleration,
    bangumiAcceleration,
    enableSystemProxy,
    defaultStartupPage,
    webDavEnable,
    webDavEnableHistory,
    webDavEnableCollect,
    webDavEnableDanmakuShield,
    danmakuShieldSyncDeviceId,
    danmakuShieldSyncState,
    danmakuShieldSyncCorruptState,
    webDavURL,
    webDavUsername,
    webDavPassword,
    lowMemoryMode,
    lowMemoryPolicy,
    showWindowButton,
    useDynamicColor,
    exitBehavior,
    playerDebugMode,
    syncPlayEndPoint,
    syncPlayUserName,
    androidEnableOpenSLES,
    androidVideoRenderer,
    androidAutoEnterPIP,
    defaultSuperResolutionMode,
    disableSuperResolutionWarning,
    playerDisableAnimations,
    playerLogLevel,
    timelineNotShowAbandonedBangumis,
    timelineNotShowWatchedBangumis,
    timelineOnlyShowWatchingBangumis,
    useSystemFont,
    forceAdBlocker,
    backgroundPlayback,
    proxyEnable,
    proxyConfigured,
    proxyUrl,
    proxyTestUrl,
    showRating,
    defaultCollectLayout,
    downloadParallelEpisodes,
    downloadParallelSegments,
    downloadDanmaku,
    downloadDirectory,
    downloadDirectoryBookmark,
    shortcutDialogShown,
    onboardingCompleted,
    bangumiSyncEnable,
    bangumiAccessToken,
    bangumiSyncPriority,
    bangumiImmediateSyncToastEnable,
    brightnessVolumeGesture,
    historySyncDeviceId,
    historySyncSequence,
    historySyncSnapshotInitialized,
    playerControllerLayerDisappearTime,
    defaultVolume,
    playerMuted,
  ];

  static List<SettingKey<Object?>> byGroup(SettingGroup group) {
    return [
      for (final key in all)
        if (key.group == group) key
    ];
  }

  SettingsKeys._();
}

// Historical Hive key names used by settings created before the typed registry.
// Keep these strings stable so existing users keep their saved settings.
// New settings do not need to be added here unless they intentionally reuse an
// existing persisted key.
class _SettingBoxKey {
  static const String hAenable = 'hAenable',
      hardwareDecoder = 'hardwareDecoder',
      searchEnhanceEnable = 'searchEnhanceEnable',
      autoUpdate = 'autoUpdate',
      alwaysOntop = 'alwaysOntop',
      defaultPlaySpeed = 'defaultPlaySpeed',
      defaultShortcutForwardPlaySpeed = 'defaultShortcutForwardPlaySpeed',
      defaultAspectRatioType = 'defaultAspectRatioType',
      buttonSkipTime = 'buttonSkipTime',
      arrowKeySkipTime = 'arrowKeySkipTime',
      danmakuEnhance = 'danmakuEnhance',
      danmakuBorder = 'danmakuBorder',
      danmakuBorderSize = 'danmakuBorderSize',
      danmakuOpacity = 'danmakuOpacity',
      danmakuFontSize = 'danmakuFontSize',
      danmakuTop = 'danmakuTop',
      danmakuScroll = 'danmakuScroll',
      danmakuBottom = 'danmakuBottom',
      danmakuMassive = 'danmakuMassive',
      danmakuDeduplication = 'danmakuDeduplication',
      danmakuArea = 'danmakuArea',
      danmakuColor = 'danmakuColor',
      danmakuDuration = 'danmakuDuration',
      danmakuLineHeight = 'danmakuLineHeight',
      danmakuTimeOffset = 'danmakuTimeOffset',
      danmakuEnabledByDefault = 'danmakuEnabledByDefault',
      danmakuBiliBiliSource = 'danmakuBiliBiliSource',
      danmakuGamerSource = 'danmakuGamerSource',
      danmakuDanDanSource = 'danmakuDanDanSource',
      danmakuFontWeight = 'danmakuFontWeight',
      danmakuFollowSpeed = 'danmakuFollowSpeed',
      themeMode = 'themeMode',
      themeColor = 'themeColor',
      privateMode = 'privateMode',
      autoPlay = 'autoPlay',
      autoPlayNext = 'autoPlayNext',
      playResume = 'playResume',
      showPlayerError = 'showPlayerError',
      oledEnhance = 'oledEnhance',
      displayMode = 'displayMode',
      enableGitProxy = 'enableGitProxy',
      enableBangumiProxy = 'enableBangumiProxy',
      enableSystemProxy = 'enableSystemProxy',
      defaultStartupPage = 'defaultStartupPage',
      webDavEnable = 'webDavEnable',
      webDavEnableHistory = 'webDavEnableHistory',
      webDavEnableCollect = 'webDavEnableCollect',
      webDavURL = 'webDavURL',
      webDavUsername = 'webDavUsername',
      webDavPassword = 'webDavPasswd',
      lowMemoryMode = 'lowMemoryMode',
      showWindowButton = 'showWindowButton',
      useDynamicColor = 'useDynamicColor',
      exitBehavior = 'exitBehavior',
      playerDebugMode = 'playerDebugMode',
      syncPlayEndPoint = 'syncPlayEndPoint',
      androidEnableOpenSLES = 'androidEnableOpenSLES',
      androidVideoRenderer = 'androidVideoRenderer',
      androidAutoEnterPIP = 'androidAutoEnterPIP',
      defaultSuperResolutionMode = 'defaultSuperResolutionType',
      disableSuperResolutionWarning = 'superResolutionWarn',
      playerDisableAnimations = 'playerDisableAnimations',
      playerLogLevel = 'playerLogLevel',
      timelineNotShowAbandonedBangumis = 'timelineNotShowAbandonedBangumis',
      timelineNotShowWatchedBangumis = 'timelineNotShowWatchedBangumis',
      timelineOnlyShowWatchingBangumis = 'timelineOnlyShowWatchingBangumis',
      useSystemFont = 'useSystemFont',
      forceAdBlocker = 'forceAdBlocker',
      backgroundPlayback = 'backgroundPlayback',
      proxyEnable = 'proxyEnable',
      proxyConfigured = 'proxyConfigured',
      proxyUrl = 'proxyUrl',
      proxyTestUrl = 'proxyTestUrl',
      showRating = 'showRating',
      downloadParallelEpisodes = 'downloadParallelEpisodes',
      downloadParallelSegments = 'downloadParallelSegments',
      downloadDanmaku = 'downloadDanmaku',
      downloadDirectory = 'downloadDirectory',
      shortcutDialogShown = 'shortcutDialogShown',
      bangumiSyncEnable = 'bangumiSyncEnable',
      bangumiAccessToken = 'bangumiAccessToken',
      bangumiSyncPriority = 'bangumiSyncPriority',
      bangumiImmediateSyncToastEnable = 'bangumiImmediateSyncToastEnable',
      brightnessVolumeGesture = 'brightnessVolumeGesture',
      historySyncDeviceId = 'historySyncDeviceId',
      historySyncSequence = 'historySyncSequence',
      historySyncSnapshotInitialized = 'historySyncSnapshotInitialized';
}
