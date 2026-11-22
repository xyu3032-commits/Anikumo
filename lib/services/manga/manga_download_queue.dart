import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:anikumo/modules/manga/manga_item.dart';
import 'package:anikumo/services/download/download_gate.dart';
import 'package:anikumo/services/network/metered_network_service.dart';

import 'manga_downloads.dart';

/// Batch 271: the manga download queue. Chapter downloads
/// used to start the moment they were tapped — tapping ten
/// chapters meant ten unbounded concurrent downloads
/// fighting over the same source. Jobs now run at most
/// [maxConcurrent] at a time, in tap order, and the
/// downloads page can pause the queue, cancel waiting
/// jobs and clear finished ones.
///
/// Pausing stops NEW jobs from starting; a chapter already
/// downloading finishes (the store's downloader has no
/// mid-chapter cancel, and its .part resume makes a later
/// retry cheap). Completed chapters live in
/// [MangaDownloadStore]'s index as before — the queue is
/// the work list, not the library.
class MangaDownloadQueue extends ChangeNotifier {
  MangaDownloadQueue._() {
    // Batch 282 (#25): queued chapters start when the
    // network turns unmetered again.
    MeteredNetworkService.listenable.addListener(_onNetworkChanged);
  }

  static final MangaDownloadQueue instance = MangaDownloadQueue._();

  void _onNetworkChanged() {
    if (!MeteredNetworkService.isMetered) _pump();
  }

  static const int maxConcurrent = 2;

  final List<MangaDownloadJob> _jobs = [];
  bool _paused = false;
  int _running = 0;

  List<MangaDownloadJob> get jobs => List.unmodifiable(_jobs);

  bool get paused => _paused;

  bool get hasActiveWork =>
      _jobs.any((job) => !job.isFinished);

  /// Enqueues [chapter] of [manga], or returns the live
  /// job when the same chapter is already queued/running.
  MangaDownloadJob enqueue(MangaItem manga, MangaChapter chapter) {
    final key = '${manga.source}|${manga.id}|${chapter.id}';
    for (final job in _jobs) {
      if (job.key == key && !job.isFinished) return job;
    }
    final job = MangaDownloadJob(
      key: key,
      manga: manga,
      chapter: chapter,
    );
    _jobs.add(job);
    notifyListeners();
    _pump();
    return job;
  }

  /// Removes a job that has not started yet.
  void cancelQueued(MangaDownloadJob job) {
    if (job.status != MangaDownloadJobStatus.queued) return;
    job._status = MangaDownloadJobStatus.cancelled;
    _jobs.remove(job);
    notifyListeners();
  }

  void setPaused(bool value) {
    if (_paused == value) return;
    _paused = value;
    notifyListeners();
    if (!value) _pump();
  }

  void clearFinished() {
    _jobs.removeWhere((job) => job.isFinished);
    notifyListeners();
  }

  void _pump() {
    if (_paused) return;
    // Batch 282 (#25): the Wi-Fi-only gate holds new
    // chapter starts on metered networks; running
    // chapters are never interrupted.
    if (DownloadGate.blockedNow()) return;
    while (_running < maxConcurrent) {
      final next = _jobs
          .where((job) => job.status == MangaDownloadJobStatus.queued)
          .firstOrNull;
      if (next == null) return;
      _run(next);
    }
  }

  Future<void> _run(MangaDownloadJob job) async {
    _running++;
    job._status = MangaDownloadJobStatus.downloading;
    notifyListeners();
    try {
      final entry = await MangaDownloadStore.downloadChapter(
        manga: job.manga,
        chapter: job.chapter,
        onProgress: (done, total) {
          if (total > 0) {
            job._progress = done / total;
            notifyListeners();
          }
        },
      );
      job._status = entry != null
          ? MangaDownloadJobStatus.done
          : MangaDownloadJobStatus.failed;
    } catch (_) {
      job._status = MangaDownloadJobStatus.failed;
    }
    job._progress = job._status == MangaDownloadJobStatus.done ? 1 : job._progress;
    _running--;
    notifyListeners();
    _pump();
  }
}

enum MangaDownloadJobStatus { queued, downloading, done, failed, cancelled }

class MangaDownloadJob {
  MangaDownloadJob({
    required this.key,
    required this.manga,
    required this.chapter,
  });

  final String key;
  final MangaItem manga;
  final MangaChapter chapter;

  MangaDownloadJobStatus _status = MangaDownloadJobStatus.queued;
  double _progress = 0;

  MangaDownloadJobStatus get status => _status;

  double get progress => _progress;

  bool get isFinished =>
      _status == MangaDownloadJobStatus.done ||
      _status == MangaDownloadJobStatus.failed ||
      _status == MangaDownloadJobStatus.cancelled;
}
