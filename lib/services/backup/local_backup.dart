import 'dart:convert';
import 'dart:io';

import 'package:anikumo/models/novel_item.dart';
import 'package:anikumo/modules/collect/collect_module.dart';
import 'package:anikumo/modules/download/download_module.dart';
import 'package:anikumo/modules/history/history_module.dart';
import 'package:anikumo/modules/history/history_sync.dart';
import 'package:anikumo/modules/search/search_history_module.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/services/manga/manga_downloads.dart';
import 'package:anikumo/services/manga/manga_library.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/services/novel/novel_library.dart';
import 'package:anikumo/services/novel/novel_sources.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:anikumo/services/ui/glass_style.dart';

/// A parsed local backup, ready to be previewed and applied.
class LocalBackupData {
  const LocalBackupData({
    required this.histories,
    required this.collectibles,
    required this.searchHistories,
    required this.userLists,
    required this.notes,
    required this.glassLevel,
    this.mangaFavorites = const [],
    this.mangaProgress = const {},
    this.novelFavorites = const [],
    this.novelProgress = const [],
    this.mangaDownloads = const [],
    this.animeDownloads = const [],
    this.mangaJsSourcesJson = '',
    this.novelSourcesJson = '',
  });

  final List<History> histories;
  final List<CollectedBangumi> collectibles;
  final List<SearchHistory> searchHistories;
  final List<UserList> userLists;
  final Map<int, String> notes;
  final int? glassLevel;

  // Batch 83: the manga / novel zones and the download
  // records. Format v1 backups simply leave these empty.
  final List<MangaFavorite> mangaFavorites;
  final Map<String, MangaProgress> mangaProgress;
  final List<NovelItem> novelFavorites;
  final List<NovelProgress> novelProgress;
  final List<MangaDownloadEntry> mangaDownloads;
  final List<DownloadRecord> animeDownloads;
  final String mangaJsSourcesJson;
  final String novelSourcesJson;
}

/// What a restore actually did, so the page can report
/// honestly — download records whose media files are not
/// on this device are skipped, not resurrected as zombies.
class LocalBackupApplyReport {
  const LocalBackupApplyReport({
    this.downloadsRestored = 0,
    this.downloadsSkipped = 0,
  });

  final int downloadsRestored;
  final int downloadsSkipped;
}

/// Local backup and restore for the user's own data.
///
/// Originally this covered only the anime zone (watch
/// history, collections, search history, custom lists,
/// bangumi notes, glass level). Batch 83 adds the manga
/// and novel libraries, both zones' source registries, and
/// the download RECORDS of both download systems. Media
/// files themselves never travel inside a JSON backup:
/// restoring on a device that still has the files revives
/// the downloads fully; records whose files are gone are
/// skipped and counted in the apply report.
///
/// History/bangumi serialization reuses [HistorySyncCodec],
/// the same codec the WebDAV sync already trusts, so the
/// two cannot drift apart. Restoring merges: same-key
/// records are overwritten, nothing is ever deleted.
class LocalBackup {
  LocalBackup._();

  static const int formatVersion = 2;

  static Future<String> exportJson() async {
    final mangaDownloads = await MangaDownloadStore.loadIndex();
    final payload = <String, dynamic>{
      'app': 'anikumo',
      'formatVersion': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'histories':
          GStorage.histories.values.map(HistorySyncCodec.historyToJson).toList(),
      'collectibles': GStorage.collectibles.values
          .map((item) => <String, dynamic>{
                'bangumiItem':
                    HistorySyncCodec.bangumiItemToJson(item.bangumiItem),
                'time': item.time.toIso8601String(),
                'type': item.type,
              })
          .toList(),
      'searchHistories': GStorage.searchHistory.values
          .map((history) => <String, dynamic>{
                'keyword': history.keyword,
                'timestamp': history.timestamp,
              })
          .toList(),
      'userLists': UserListsStore.load().map((list) => list.toJson()).toList(),
      'notes': BangumiNotesStore.load()
          .map((id, text) => MapEntry(id.toString(), text)),
      'glassLevel': GlassStyle.level,
      'mangaFavorites': [
        for (final f in MangaLibraryStore.loadFavorites()) f.toJson(),
      ],
      'mangaProgress': MangaLibraryStore.loadProgressMap()
          .map((key, value) => MapEntry(key, value.toJson())),
      'novelFavorites': [
        for (final f in NovelLibraryStore.loadFavorites()) f.toJson(),
      ],
      'novelProgress': [
        for (final p in NovelLibraryStore.loadProgressList()) p.toJson(),
      ],
      'mangaDownloads': [for (final e in mangaDownloads) e.toJson()],
      'animeDownloads': [
        for (final r in GStorage.downloads.values) downloadRecordToJson(r),
      ],
      'mangaJsSourcesJson':
          GStorage.getSetting(SettingsKeys.mangaJsSourcesJson),
      'novelSourcesJson':
          GStorage.getSetting(SettingsKeys.novelInstalledSourcesJson),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static Map<String, dynamic> downloadRecordToJson(DownloadRecord record) {
    return <String, dynamic>{
      'bangumiId': record.bangumiId,
      'bangumiName': record.bangumiName,
      'bangumiCover': record.bangumiCover,
      'pluginName': record.pluginName,
      'createdAt': record.createdAt.toIso8601String(),
      'episodes': {
        for (final entry in record.episodes.entries)
          entry.key.toString(): _downloadEpisodeToJson(entry.value),
      },
    };
  }

  static Map<String, dynamic> _downloadEpisodeToJson(DownloadEpisode ep) {
    return <String, dynamic>{
      'episodeNumber': ep.episodeNumber,
      'episodeName': ep.episodeName,
      'road': ep.road,
      'status': ep.status,
      'progressPercent': ep.progressPercent,
      'totalSegments': ep.totalSegments,
      'downloadedSegments': ep.downloadedSegments,
      'localM3u8Path': ep.localM3u8Path,
      'downloadDirectory': ep.downloadDirectory,
      'networkM3u8Url': ep.networkM3u8Url,
      'completedAt': ep.completedAt?.toIso8601String(),
      'errorMessage': ep.errorMessage,
      'totalBytes': ep.totalBytes,
      'episodePageUrl': ep.episodePageUrl,
      'danmakuData': ep.danmakuData,
      'danDanBangumiID': ep.danDanBangumiID,
    };
  }

  static DownloadRecord? downloadRecordFromJson(Map<dynamic, dynamic> json) {
    final bangumiId = (json['bangumiId'] as num?)?.toInt();
    if (bangumiId == null) return null;
    final episodes = <int, DownloadEpisode>{};
    final episodesRaw = json['episodes'];
    if (episodesRaw is Map) {
      for (final entry in episodesRaw.entries) {
        final number = int.tryParse(entry.key.toString());
        if (number == null || entry.value is! Map) continue;
        final ep = Map<dynamic, dynamic>.from(entry.value as Map);
        episodes[number] = DownloadEpisode(
          (ep['episodeNumber'] as num?)?.toInt() ?? number,
          ep['episodeName']?.toString() ?? '',
          (ep['road'] as num?)?.toInt() ?? 0,
          (ep['status'] as num?)?.toInt() ?? 0,
          (ep['progressPercent'] as num?)?.toDouble() ?? 0,
          (ep['totalSegments'] as num?)?.toInt() ?? 0,
          (ep['downloadedSegments'] as num?)?.toInt() ?? 0,
          ep['localM3u8Path']?.toString() ?? '',
          ep['downloadDirectory']?.toString() ?? '',
          ep['networkM3u8Url']?.toString() ?? '',
          DateTime.tryParse(ep['completedAt']?.toString() ?? ''),
          ep['errorMessage']?.toString() ?? '',
          (ep['totalBytes'] as num?)?.toInt() ?? 0,
          ep['episodePageUrl']?.toString() ?? '',
          danmakuData: ep['danmakuData']?.toString() ?? '',
          danDanBangumiID: (ep['danDanBangumiID'] as num?)?.toInt() ?? 0,
        );
      }
    }
    return DownloadRecord(
      bangumiId,
      json['bangumiName']?.toString() ?? '',
      json['bangumiCover']?.toString() ?? '',
      json['pluginName']?.toString() ?? '',
      episodes,
      DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Parses [raw] backup text. Returns null when the content is not a
  /// recognizable backup (not JSON, wrong format version, or a record
  /// the sync codec cannot read). Format v1 files (anime zone only)
  /// still parse; their batch-83 sections read as empty.
  static LocalBackupData? parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final version = (map['formatVersion'] as num?)?.toInt();
      if (version == null || version < 1 || version > formatVersion) {
        return null;
      }
      final histories = ((map['histories'] as List?) ?? const [])
          .whereType<Map>()
          .map((entry) =>
              HistorySyncCodec.historyFromJson(Map<String, dynamic>.from(entry)))
          .toList();
      final collectibles = ((map['collectibles'] as List?) ?? const [])
          .whereType<Map>()
          .map((entry) {
        final item = Map<String, dynamic>.from(entry);
        return CollectedBangumi(
          HistorySyncCodec.bangumiItemFromJson(
            Map<String, dynamic>.from(item['bangumiItem'] as Map),
          ),
          DateTime.tryParse(item['time'] as String? ?? '') ?? DateTime.now(),
          (item['type'] as num?)?.toInt() ?? 1,
        );
      }).toList();
      final searchHistories = ((map['searchHistories'] as List?) ?? const [])
          .whereType<Map>()
          .map((entry) {
            final item = Map<String, dynamic>.from(entry);
            return SearchHistory(
              item['keyword'] as String? ?? '',
              (item['timestamp'] as num?)?.toInt() ?? 0,
            );
          })
          .where((history) => history.keyword.isNotEmpty)
          .toList();
      final userLists = ((map['userLists'] as List?) ?? const [])
          .whereType<Map>()
          .map((entry) => UserList.fromJson(Map<String, dynamic>.from(entry)))
          .where((list) => list.id.isNotEmpty)
          .toList();
      final notesRaw = map['notes'];
      final notes = notesRaw is Map
          ? BangumiNotesCodec.decode(
              jsonEncode(Map<String, dynamic>.from(notesRaw)),
            )
          : <int, String>{};
      final mangaFavorites = <MangaFavorite>[
        for (final entry in (map['mangaFavorites'] as List?) ?? const [])
          if (entry is Map) ?MangaFavorite.fromJson(entry),
      ];
      final mangaProgress = <String, MangaProgress>{};
      final mangaProgressRaw = map['mangaProgress'];
      if (mangaProgressRaw is Map) {
        for (final entry in mangaProgressRaw.entries) {
          if (entry.value is Map) {
            final parsed = MangaProgress.fromJson(
              (entry.value as Map).cast<dynamic, dynamic>(),
            );
            if (parsed != null) mangaProgress[parsed.key] = parsed;
          }
        }
      }
      final novelFavorites = <NovelItem>[
        for (final entry in (map['novelFavorites'] as List?) ?? const [])
          if (entry is Map)
            ?NovelItem.fromJson(entry.cast<dynamic, dynamic>()),
      ];
      final novelProgress = <NovelProgress>[
        for (final entry in (map['novelProgress'] as List?) ?? const [])
          if (entry is Map)
            NovelProgress.fromJson(Map<String, dynamic>.from(entry)),
      ];
      final mangaDownloads = <MangaDownloadEntry>[
        for (final entry in (map['mangaDownloads'] as List?) ?? const [])
          if (entry is Map) ?MangaDownloadEntry.fromJson(entry),
      ];
      final animeDownloads = <DownloadRecord>[
        for (final entry in (map['animeDownloads'] as List?) ?? const [])
          if (entry is Map) ?downloadRecordFromJson(entry),
      ];
      return LocalBackupData(
        histories: histories,
        collectibles: collectibles,
        searchHistories: searchHistories,
        userLists: userLists,
        notes: notes,
        glassLevel: (map['glassLevel'] as num?)?.toInt(),
        mangaFavorites: mangaFavorites,
        mangaProgress: mangaProgress,
        novelFavorites: novelFavorites,
        novelProgress: novelProgress,
        mangaDownloads: mangaDownloads,
        animeDownloads: animeDownloads,
        mangaJsSourcesJson: map['mangaJsSourcesJson']?.toString() ?? '',
        novelSourcesJson: map['novelSourcesJson']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Merges [data] into local storage. Existing records with the same
  /// key are overwritten; records absent from the backup are kept.
  static Future<LocalBackupApplyReport> apply(LocalBackupData data) async {
    for (final history in data.histories) {
      await GStorage.histories.put(history.key, history);
    }
    for (final item in data.collectibles) {
      await GStorage.collectibles.put(item.key, item);
    }
    for (final history in data.searchHistories) {
      await GStorage.searchHistory.put(history.timestamp.toString(), history);
    }
    if (data.userLists.isNotEmpty) {
      await UserListsStore.save(data.userLists);
    }
    if (data.notes.isNotEmpty) {
      final merged = BangumiNotesStore.load()..addAll(data.notes);
      await BangumiNotesStore.save(merged);
    }
    final glassLevel = data.glassLevel;
    if (glassLevel != null) {
      await GlassStyle.setLevel(glassLevel);
    }
    await MangaLibraryStore.mergeBackup(
      favorites: data.mangaFavorites,
      progress: data.mangaProgress,
    );
    await NovelLibraryStore.mergeBackup(
      favorites: data.novelFavorites,
      progress: data.novelProgress,
    );
    var downloadsRestored = 0;
    var downloadsSkipped = 0;
    final mangaResult =
        await MangaDownloadStore.mergeIndexEntries(data.mangaDownloads);
    downloadsRestored += mangaResult.$1;
    downloadsSkipped += mangaResult.$2;
    for (final record in data.animeDownloads) {
      // Only completed episodes whose local playlist file
      // is still on this device come back; anything else
      // would list as a download that cannot play.
      final kept = <int, DownloadEpisode>{};
      for (final entry in record.episodes.entries) {
        final episode = entry.value;
        if (episode.status == DownloadStatus.completed &&
            episode.localM3u8Path.isNotEmpty &&
            File(episode.localM3u8Path).existsSync()) {
          kept[entry.key] = episode;
        }
      }
      if (kept.isEmpty) {
        if (record.episodes.isNotEmpty) downloadsSkipped++;
        continue;
      }
      record.episodes
        ..clear()
        ..addAll(kept);
      await GStorage.downloads.put(record.key, record);
      downloadsRestored++;
    }
    if (data.mangaJsSourcesJson.isNotEmpty) {
      await GStorage.putSetting(
        SettingsKeys.mangaJsSourcesJson,
        data.mangaJsSourcesJson,
      );
      MangaSources.notifyRegistryChanged();
    }
    if (data.novelSourcesJson.isNotEmpty) {
      await GStorage.putSetting(
        SettingsKeys.novelInstalledSourcesJson,
        data.novelSourcesJson,
      );
      NovelSources.invalidateImportedCache();
    }
    return LocalBackupApplyReport(
      downloadsRestored: downloadsRestored,
      downloadsSkipped: downloadsSkipped,
    );
  }
}
