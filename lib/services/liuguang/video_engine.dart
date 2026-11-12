import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:liuguang_core/liuguang_core.dart';

import 'package:path_provider/path_provider.dart';

import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/liuguang/cms_api_source.dart';
import 'package:anikumo/services/liuguang/liuguang_hive_storage.dart';
import 'package:anikumo/services/liuguang/mediakit_player_engine.dart';

/// Batch 209: one persisted health-check outcome for an
/// installed interface source — the engine's [SourceHealth]
/// plus when it was measured, in a JSON-friendly shape.
class FilmSourceHealth {
  const FilmSourceHealth({
    required this.ok,
    required this.latencyMs,
    required this.message,
    required this.checkedAt,
  });

  final bool ok;
  final int latencyMs;
  final String message;
  final DateTime checkedAt;

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'latencyMs': latencyMs,
    'message': message,
    'atMs': checkedAt.millisecondsSinceEpoch,
  };

  static FilmSourceHealth? fromJson(Map<String, dynamic> json) {
    final atMs = json['atMs'];
    if (atMs is! num) return null;
    return FilmSourceHealth(
      ok: json['ok'] == true,
      latencyMs: json['latencyMs'] is num
          ? (json['latencyMs'] as num).toInt()
          : 0,
      message: json['message']?.toString() ?? '',
      checkedAt: DateTime.fromMillisecondsSinceEpoch(atMs.toInt()),
    );
  }
}

/// Batch 209: the sources tab's search filter — matches
/// the query against name, address and origin repository,
/// case-insensitively. An empty query keeps the full list.
List<VideoSourceEntry> filterFilmSources(
  List<VideoSourceEntry> sources,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return List.of(sources);
  return sources.where((s) {
    return s.name.toLowerCase().contains(q) ||
        s.api.toLowerCase().contains(q) ||
        s.fromRepository.toLowerCase().contains(q);
  }).toList();
}

/// Batch 209: human "when was this checked" phrasing for
/// the sources tab （刚刚 / N分钟前 / N小时前 / N天前）.
String filmCheckAgeText(DateTime checkedAt, DateTime now) {
  final diff = now.difference(checkedAt);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  return '${diff.inDays}天前';
}

/// Batch 203: one user-imported interface source of the
/// 影视 zone. [api] is the source's JSON interface base
/// address exactly as it appeared in the repository
/// configuration the user imported (or as typed by hand).
class VideoSourceEntry {
  const VideoSourceEntry({
    required this.id,
    required this.name,
    required this.api,
    this.enabled = true,
    this.fromRepository = '',
  });

  /// Stable id, derived from the api address (see
  /// [VideoSourceEntry.idForApi]).
  final String id;
  final String name;
  final String api;
  final bool enabled;

  /// Name of the repository this source came from, or ''
  /// when the user added it directly.
  final String fromRepository;

  VideoSourceEntry copyWith({bool? enabled, String? name}) => VideoSourceEntry(
    id: id,
    name: name ?? this.name,
    api: api,
    enabled: enabled ?? this.enabled,
    fromRepository: fromRepository,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'api': api,
    'enabled': enabled,
    'fromRepository': fromRepository,
  };

  factory VideoSourceEntry.fromJson(Map<String, dynamic> j) => VideoSourceEntry(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    api: j['api']?.toString() ?? '',
    enabled: j['enabled'] != false,
    fromRepository: j['fromRepository']?.toString() ?? '',
  );

  static String idForApi(String api) =>
      'cms_${api.hashCode.toUnsigned(32).toRadixString(16)}';
}

/// One user-added repository （仓库）: a name plus the URL of
/// a configuration document listing interface sources.
class VideoRepositoryEntry {
  const VideoRepositoryEntry({required this.name, required this.url});

  final String name;
  final String url;

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory VideoRepositoryEntry.fromJson(Map<String, dynamic> j) =>
      VideoRepositoryEntry(
        name: j['name']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
      );
}

/// Batch 203: the 影视 zone's engine host. Owns the single
/// [LiuGuangMediaEngine] instance (process-in, no server —
/// the embedding shape the engine was built for), its Hive
/// storage, and the zone's installed-source registry.
///
/// Providers are created per installed entry by the source
/// factory the zone installs (Batch 204); every registry
/// change rebuilds the engine's registrations from the
/// persisted entries, so the engine state can always be
/// re-derived from settings alone.
class VideoEngineService extends ChangeNotifier {
  VideoEngineService._();

  static final VideoEngineService instance = VideoEngineService._();

  LiuGuangMediaEngine? _engine;
  Future<LiuGuangMediaEngine>? _booting;

  /// Creates the provider object for one installed entry.
  /// Installed by the zone's source layer (Batch 204); while
  /// null, entries are stored but not registered.
  MediaSourceProvider Function(VideoSourceEntry entry)? providerFactory;

  List<VideoSourceEntry> _sources = [];
  List<VideoRepositoryEntry> _repositories = [];
  bool _loaded = false;

  /// Last health check per source id (Batch 204; Batch 209
  /// made it a timestamped record and persisted it, so the
  /// sources tab opens with 上次检测 state intact).
  final Map<String, FilmSourceHealth> healthById = {};

  bool _healthLoaded = false;

  /// Batch 209: 全部检测 progress, read by the sources tab.
  bool checkingAll = false;
  int checkDone = 0;
  int checkTotal = 0;

  void _loadHealth() {
    if (_healthLoaded) return;
    _healthLoaded = true;
    try {
      final raw = GStorage.getSetting(SettingsKeys.videoSourceHealthJson);
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v is Map) {
            final record = FilmSourceHealth.fromJson(
              Map<String, dynamic>.from(v),
            );
            if (record != null) healthById['$k'] = record;
          }
        });
      }
    } catch (_) {
      // Corrupt health cache degrades to "never checked".
    }
  }

  Future<void> _persistHealth() async {
    await GStorage.putSetting(
      SettingsKeys.videoSourceHealthJson,
      jsonEncode({for (final e in healthById.entries) e.key: e.value.toJson()}),
    );
  }

  /// Runs one entry's health check and remembers the
  /// outcome (with its time) for the sources tab.
  Future<SourceHealth> checkSourceHealth(VideoSourceEntry entry) async {
    _loadHealth();
    try {
      final health = await providerFor(entry).healthCheck();
      healthById[entry.id] = FilmSourceHealth(
        ok: health.healthy,
        latencyMs: health.latency.inMilliseconds,
        message: health.message,
        checkedAt: DateTime.now(),
      );
      await _persistHealth();
      return health;
    } catch (e) {
      final health = SourceHealth.fail(e.toString());
      healthById[entry.id] = FilmSourceHealth(
        ok: false,
        latencyMs: 0,
        message: health.message,
        checkedAt: DateTime.now(),
      );
      await _persistHealth();
      return health;
    } finally {
      notifyListeners();
    }
  }

  /// Batch 209: checks every installed source (enabled or
  /// not) with bounded concurrency, reporting progress on
  /// the service for the sources tab. Re-entrant calls are
  /// ignored while a sweep is running.
  Future<void> checkAllSources() async {
    if (checkingAll) return;
    loadRegistry();
    final targets = List<VideoSourceEntry>.of(_sources);
    checkingAll = true;
    checkDone = 0;
    checkTotal = targets.length;
    notifyListeners();
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < targets.length) {
        final entry = targets[cursor++];
        await checkSourceHealth(entry);
        checkDone++;
        notifyListeners();
      }
    }

    try {
      await Future.wait([worker(), worker(), worker()]);
    } finally {
      checkingAll = false;
      notifyListeners();
    }
  }

  List<VideoSourceEntry> get sources => List.unmodifiable(_sources);
  List<VideoRepositoryEntry> get repositories =>
      List.unmodifiable(_repositories);
  bool get hasSources => _sources.any((s) => s.enabled);

  /// The engine, booted on first use. Concurrent callers
  /// share the one boot future.
  Future<LiuGuangMediaEngine> engine() {
    final ready = _engine;
    if (ready != null) return Future.value(ready);
    return _booting ??= _boot();
  }

  Future<LiuGuangMediaEngine> _boot() async {
    // The zone's provider kind: direct JSON interface
    // sources (Batch 204). Installed here so the service is
    // self-contained; tests can substitute their own factory
    // before the first engine() call.
    providerFactory ??= (entry) => CmsApiSource(entry);
    loadRegistry();
    final engine = LiuGuangMediaEngine(
      config: LiuGuangEngineConfig(storage: AnikumoLiuguangStorage()),
    );
    await engine.initialize();
    // Batch 206: the real decode kernel — the app's
    // media_kit behind the engine's PlayerEngine interface.
    engine.registerPlayerKernel(
      'mediakit',
      () => MediaKitPlayerEngine(),
      const PlayerCapabilities(
        hardwareDecode: true,
        subtitles: true,
        multiAudio: true,
        formats: {'mp4', 'hls', 'dash', 'mkv', 'webm'},
      ),
    );
    // Batch 207: downloads ride the engine's own download
    // manager (HLS segment concatenation + Range resume),
    // persisted through the same Hive-backed storage.
    engine.registerDownloadManager(
      DownloadManager(storage: AnikumoLiuguangStorage()),
    );
    // Batch 207: downloads ride the engine's own download
    // manager (HLS segment concatenation + Range resume),
    // persisted through the same Hive-backed storage.
    engine.registerDownloadManager(
      DownloadManager(storage: AnikumoLiuguangStorage()),
    );
    _engine = engine;
    _syncProviders(engine);
    return engine;
  }

  bool _downloadsRestored = false;

  /// The engine's download manager with its persisted tasks
  /// restored (once). Task rows live in the engine storage's
  /// downloads table.
  Future<DownloadManager> downloads() async {
    final engine = await this.engine();
    final manager = engine.requireDownloads();
    if (!_downloadsRestored) {
      _downloadsRestored = true;
      await manager.restore();
    }
    return manager;
  }

  /// Where finished downloads are stored on this device.
  Future<Directory> downloadsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/liuguang_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Reads the persisted registry (idempotent). Storage
  /// failures degrade to an empty registry rather than
  /// crashing the zone.
  void loadRegistry() {
    if (_loaded) return;
    _loaded = true;
    _loadHealth();
    try {
      _sources = _decodeList(
        GStorage.getSetting(SettingsKeys.videoInstalledSourcesJson),
        VideoSourceEntry.fromJson,
      );
      _repositories = _decodeList(
        GStorage.getSetting(SettingsKeys.videoRepositoriesJson),
        VideoRepositoryEntry.fromJson,
      );
    } catch (_) {
      _sources = [];
      _repositories = [];
    }
  }

  List<T> _decodeList<T>(String raw, T Function(Map<String, dynamic>) from) {
    if (raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => from(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {
      // A corrupt registry reads as empty rather than
      // crashing the zone; the raw value stays untouched so
      // nothing is silently destroyed.
    }
    return [];
  }

  Future<void> _persistSources() async {
    await GStorage.putSetting(
      SettingsKeys.videoInstalledSourcesJson,
      jsonEncode(_sources.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _persistRepositories() async {
    await GStorage.putSetting(
      SettingsKeys.videoRepositoriesJson,
      jsonEncode(_repositories.map((e) => e.toJson()).toList()),
    );
  }

  /// Canonical provider instances by entry id. The engine's
  /// registrations and the zone UI (browse/categories) share
  /// these, so per-provider caches (category tree, detail
  /// cache, browse streams) exist exactly once per source.
  final Map<String, MediaSourceProvider> _providers = {};

  MediaSourceProvider providerFor(VideoSourceEntry entry) {
    final factory =
        providerFactory ?? (providerFactory = (e) => CmsApiSource(e));
    return _providers.putIfAbsent(entry.id, () => factory(entry));
  }

  /// Reconciles the engine's source registry with the
  /// persisted entries: registers new ones, unregisters
  /// removed ones, and mirrors each entry's enabled flag.
  /// Called after each registry mutation once booted.
  void _syncProviders(LiuGuangMediaEngine engine) {
    if (providerFactory == null) return;
    final registry = engine.sources;
    final wanted = {for (final e in _sources) e.id: e};
    final registered = registry.descriptors.map((d) => d.id).toSet();
    for (final id in registered.difference(wanted.keys.toSet())) {
      registry.unregister(id);
      _providers.remove(id);
    }
    for (final entry in _sources) {
      if (!registered.contains(entry.id)) {
        registry.register(providerFor(entry));
      }
      if (registry.isEnabled(entry.id) != entry.enabled) {
        registry.setEnabled(entry.id, entry.enabled);
      }
    }
  }

  Future<void> addSources(List<VideoSourceEntry> entries) async {
    loadRegistry();
    final known = _sources.map((s) => s.id).toSet();
    var changed = false;
    for (final entry in entries) {
      if (entry.api.trim().isEmpty || known.contains(entry.id)) continue;
      _sources.add(entry);
      known.add(entry.id);
      changed = true;
    }
    if (changed) {
      await _persistSources();
      final engine = _engine;
      if (engine != null) _syncProviders(engine);
      notifyListeners();
    }
  }

  Future<void> removeSource(String id) async {
    loadRegistry();
    final before = _sources.length;
    _sources = _sources.where((s) => s.id != id).toList();
    if (_sources.length != before) {
      if (healthById.remove(id) != null) await _persistHealth();
      await _persistSources();
      final engine = _engine;
      if (engine != null) _syncProviders(engine);
      notifyListeners();
    }
  }

  /// Batch 209: edits one installed source from its
  /// settings sheet — rename and/or new interface address.
  /// The address is the source's identity, so changing it
  /// re-ids the entry, drops the memoized provider (it holds
  /// the old entry) and clears the stale health record; the
  /// engine registrations are re-synced either way.
  /// Returns the resulting entry, or null when [id] is
  /// unknown or the new address is empty.
  Future<VideoSourceEntry?> updateSource(
    String id, {
    String? name,
    String? api,
  }) async {
    loadRegistry();
    final index = _sources.indexWhere((s) => s.id == id);
    if (index < 0) return null;
    final old = _sources[index];
    final newApi = (api ?? old.api).trim();
    if (newApi.isEmpty) return null;
    final newId = VideoSourceEntry.idForApi(newApi);
    if (newId != id && _sources.any((s) => s.id == newId)) {
      // Another installed source already owns that address.
      return null;
    }
    final trimmedName = name?.trim();
    final updated = VideoSourceEntry(
      id: newId,
      name: (trimmedName == null || trimmedName.isEmpty)
          ? old.name
          : trimmedName,
      api: newApi,
      enabled: old.enabled,
      fromRepository: old.fromRepository,
    );
    _sources[index] = updated;
    _providers.remove(id);
    _providers.remove(newId);
    if (newId != id && healthById.remove(id) != null) {
      await _persistHealth();
    }
    await _persistSources();
    final engine = _engine;
    if (engine != null) _syncProviders(engine);
    notifyListeners();
    return updated;
  }

  Future<void> setSourceEnabled(String id, bool enabled) async {
    loadRegistry();
    var changed = false;
    _sources = _sources.map((s) {
      if (s.id == id && s.enabled != enabled) {
        changed = true;
        return s.copyWith(enabled: enabled);
      }
      return s;
    }).toList();
    if (changed) {
      await _persistSources();
      final engine = _engine;
      if (engine != null) _syncProviders(engine);
      notifyListeners();
    }
  }

  Future<void> addRepository(VideoRepositoryEntry entry) async {
    loadRegistry();
    if (_repositories.any((r) => r.url == entry.url)) return;
    _repositories.add(entry);
    await _persistRepositories();
    notifyListeners();
  }

  Future<void> removeRepository(String url) async {
    loadRegistry();
    final before = _repositories.length;
    _repositories = _repositories.where((r) => r.url != url).toList();
    if (_repositories.length != before) {
      await _persistRepositories();
      notifyListeners();
    }
  }
}
