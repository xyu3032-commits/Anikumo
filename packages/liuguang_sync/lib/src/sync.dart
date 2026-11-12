import 'dart:async';
import 'dart:convert';
import 'package:liuguang_storage/liuguang_storage.dart';

/// One syncable record. [payloadJson] is the opaque serialized entity;
/// [deleted] is a tombstone so deletions propagate instead of resurrecting.
class SyncRecord {
  final String collection;
  final String key;
  final String payloadJson;
  final int revision;
  final DateTime updatedAt;
  final String deviceId;
  final bool deleted;
  const SyncRecord({required this.collection, required this.key, required this.payloadJson, this.revision = 1, required this.updatedAt, this.deviceId = '', this.deleted = false});
  SyncRecord copyWith({String? payloadJson, int? revision, DateTime? updatedAt, String? deviceId, bool? deleted}) => SyncRecord(
      collection: collection, key: key, payloadJson: payloadJson ?? this.payloadJson, revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt, deviceId: deviceId ?? this.deviceId, deleted: deleted ?? this.deleted);
  Map<String, dynamic> toJson() => {'collection': collection, 'key': key, 'payloadJson': payloadJson, 'revision': revision, 'updatedAt': updatedAt.toIso8601String(), 'deviceId': deviceId, 'deleted': deleted};
  factory SyncRecord.fromJson(Map<String, dynamic> j) => SyncRecord(
      collection: j['collection']?.toString() ?? '', key: j['key']?.toString() ?? '', payloadJson: j['payloadJson']?.toString() ?? '',
      revision: j['revision'] is num ? (j['revision'] as num).toInt() : 1,
      updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      deviceId: j['deviceId']?.toString() ?? '', deleted: j['deleted'] == true);
  @override bool operator ==(Object o) => o is SyncRecord && o.collection == collection && o.key == key && o.payloadJson == payloadJson && o.revision == revision && o.updatedAt == updatedAt && o.deviceId == deviceId && o.deleted == deleted;
  @override int get hashCode => Object.hash(collection, key, payloadJson, revision, updatedAt, deviceId, deleted);
  @override String toString() => 'SyncRecord($collection/$key rev=$revision deleted=$deleted)';
}

class SyncTransportException implements Exception {
  final String message;
  SyncTransportException(this.message);
  @override String toString() => 'SyncTransportException: $message';
}

/// Transport is host-provided (HTTP API, WebDAV, ...). The engine only
/// knows this interface; [pull] must return records changed since [since]
/// (inclusive watermark is fine — resolution is idempotent).
abstract interface class SyncTransport {
  Future<void> push(List<SyncRecord> records);
  Future<List<SyncRecord>> pull(String collection, {required DateTime since});
}

/// In-memory transport for tests and single-device loopback use.
/// Failure simulation: [online]=false makes every call throw;
/// [failNextCalls] makes that many next calls throw, then calls succeed.
class InMemorySyncTransport implements SyncTransport {
  final Map<String, SyncRecord> _store = {};
  bool online = true;
  int failNextCalls = 0;
  int pushCalls = 0;
  int pullCalls = 0;
  String _id(String c, String k) => '$c::$k';
  void _gate() {
    if (!online) throw SyncTransportException('transport offline');
    if (failNextCalls > 0) { failNextCalls--; throw SyncTransportException('simulated transport failure'); }
  }
  @override Future<void> push(List<SyncRecord> records) async {
    pushCalls++;
    _gate();
    for (final r in records) {
      final id = _id(r.collection, r.key);
      final cur = _store[id];
      // Last-writer-wins guard so a stale push cannot clobber newer state.
      if (cur == null || r.updatedAt.isAfter(cur.updatedAt) || (r.updatedAt.isAtSameMomentAs(cur.updatedAt) && r.revision >= cur.revision)) {
        _store[id] = r;
      }
    }
  }
  @override Future<List<SyncRecord>> pull(String collection, {required DateTime since}) async {
    pullCalls++;
    _gate();
    return _store.values.where((r) => r.collection == collection && !r.updatedAt.isBefore(since)).toList();
  }
  void seedRemote(SyncRecord r) => _store[_id(r.collection, r.key)] = r;
  SyncRecord? remoteRecord(String collection, String key) => _store[_id(collection, key)];
  List<SyncRecord> remoteSnapshot(String collection) => _store.values.where((r) => r.collection == collection).toList();
}

enum SyncStatus { idle, syncing, error, done }
enum SyncPriority { local, remote }

class SyncState {
  final SyncStatus status;
  final int pushed;
  final int pulled;
  final int conflicts;
  final int pending;
  final String? error;
  final DateTime at;
  const SyncState({required this.status, this.pushed = 0, this.pulled = 0, this.conflicts = 0, this.pending = 0, this.error, required this.at});
  @override String toString() => 'SyncState(${status.name} pushed=$pushed pulled=$pulled conflicts=$conflicts pending=$pending${error != null ? ' error=$error' : ''})';
}

/// Sync engine.
///
/// Local truth lives in the `sync_records` table of a [StorageAdapter];
/// records that still need pushing are queued in `sync_outbox`, so a
/// restart keeps pending changes. Conflict policy per collection kind:
/// - history-like: newest [SyncRecord.updatedAt] wins (tie: higher revision, then remote)
/// - favorites-like: union — a live record always beats a tombstone; when
///   both are live, JSON-object payloads merge key-wise (newer side wins
///   shared keys)
/// - settings-like: the side chosen by [settingsPriority] wins
/// - anything else: same rule as history.
class SyncEngine {
  final StorageAdapter storage;
  final SyncTransport transport;
  final String deviceId;
  final SyncPriority settingsPriority;
  final int maxRetries;
  final Duration retryBaseDelay;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  static const recordsTable = 'sync_records';
  static const outboxTable = 'sync_outbox';
  static const stateTable = 'sync_state';
  static const defaultCollections = {'history', 'favorites', 'settings'};

  final _states = StreamController<SyncState>.broadcast();
  SyncState _current;
  SyncEngine({required this.storage, required this.transport, this.deviceId = '', this.settingsPriority = SyncPriority.remote,
      this.maxRetries = 3, this.retryBaseDelay = const Duration(milliseconds: 100), DateTime Function()? now, Future<void> Function(Duration)? sleeper})
      : _now = now ?? DateTime.now, _sleep = sleeper ?? ((d) => Future.delayed(d)),
        _current = SyncState(status: SyncStatus.idle, at: now?.call() ?? DateTime.now());

  Stream<SyncState> get states => _states.stream;
  SyncState get currentState => _current;
  void _emit(SyncState s) { _current = s; if (!_states.isClosed) _states.add(s); }
  String _id(String c, String k) => '$c::$k';

  /// Record a local change: bumps revision, stamps time/device, stores it
  /// as local truth and queues it in the outbox.
  Future<SyncRecord> applyLocal({required String collection, required String key, required String payloadJson, bool deleted = false}) async {
    final cur = await _readLocal(collection, key);
    final rec = SyncRecord(collection: collection, key: key, payloadJson: payloadJson,
        revision: (cur?.revision ?? 0) + 1, updatedAt: _now(), deviceId: deviceId, deleted: deleted);
    await storage.put(recordsTable, _id(collection, key), rec.toJson());
    await storage.put(outboxTable, _id(collection, key), {'collection': collection, 'key': key});
    return rec;
  }

  Future<SyncRecord?> _readLocal(String collection, String key) async {
    final j = await storage.get(recordsTable, _id(collection, key));
    return j == null ? null : SyncRecord.fromJson(j);
  }

  /// Local truth for a key; tombstones read as null unless [includeDeleted].
  Future<SyncRecord?> getLocal(String collection, String key, {bool includeDeleted = false}) async {
    final r = await _readLocal(collection, key);
    if (r == null || (r.deleted && !includeDeleted)) return null;
    return r;
  }

  Future<List<SyncRecord>> listLocal(String collection, {bool includeDeleted = false}) async {
    final rows = (await storage.all(recordsTable)).map(SyncRecord.fromJson).where((r) => r.collection == collection && (includeDeleted || !r.deleted)).toList();
    rows.sort((a, b) => a.key.compareTo(b.key));
    return rows;
  }

  Future<int> pendingCount() async => (await storage.all(outboxTable)).length;

  Future<T> _withRetry<T>(Future<T> Function() op) async {
    Object? last;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try { return await op(); } catch (e) {
        last = e;
        if (attempt < maxRetries) await _sleep(retryBaseDelay * (1 << attempt));
      }
    }
    throw SyncTransportException('operation failed after ${maxRetries + 1} attempts: $last');
  }

  Future<DateTime> _lastPull(String collection) async {
    final j = await storage.get(stateTable, collection);
    return DateTime.tryParse(j?['lastPullAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Runs one push+pull round. Transport failures are retried with
  /// exponential backoff; if they persist, the returned state has
  /// status=error and the outbox is left untouched for the next round.
  Future<SyncState> sync() async {
    var pushed = 0, pulled = 0, conflicts = 0;
    _emit(SyncState(status: SyncStatus.syncing, pending: await pendingCount(), at: _now()));
    try {
      // ---- push phase
      final outbox = await storage.all(outboxTable);
      final toPush = <SyncRecord>[];
      for (final row in outbox) {
        final rec = await _readLocal(row['collection']?.toString() ?? '', row['key']?.toString() ?? '');
        if (rec != null) toPush.add(rec);
      }
      if (toPush.isNotEmpty) {
        await _withRetry(() => transport.push(toPush));
        for (final r in toPush) { await storage.delete(outboxTable, _id(r.collection, r.key)); }
        pushed = toPush.length;
      }
      // ---- pull phase
      final collections = {...defaultCollections};
      for (final r in (await storage.all(recordsTable)).map(SyncRecord.fromJson)) { collections.add(r.collection); }
      for (final r in toPush) { collections.add(r.collection); }
      for (final collection in collections) {
        final since = await _lastPull(collection);
        final remote = await _withRetry(() => transport.pull(collection, since: since));
        for (final rr in remote) {
          final res = await _resolve(collection, rr);
          if (res.applied) pulled++;
          if (res.conflict) conflicts++;
        }
        await storage.put(stateTable, collection, {'lastPullAt': _now().toIso8601String()});
      }
      final done = SyncState(status: SyncStatus.done, pushed: pushed, pulled: pulled, conflicts: conflicts, pending: await pendingCount(), at: _now());
      _emit(done);
      return done;
    } catch (e) {
      final err = SyncState(status: SyncStatus.error, pushed: pushed, pulled: pulled, conflicts: conflicts, pending: await pendingCount(), error: e.toString(), at: _now());
      _emit(err);
      return err;
    }
  }

  Future<({bool applied, bool conflict})> _resolve(String collection, SyncRecord remote) async {
    final local = await _readLocal(collection, remote.key);
    if (local == null) {
      await storage.put(recordsTable, _id(collection, remote.key), remote.toJson());
      return (applied: true, conflict: false);
    }
    if (local == remote) return (applied: false, conflict: false);
    final isConflict = local.payloadJson != remote.payloadJson || local.deleted != remote.deleted || local.revision != remote.revision;
    SyncRecord winner;
    var winnerIsRemote = false;
    if (collection == 'favorites') {
      winner = _mergeFavorites(local, remote);
      winnerIsRemote = winner == remote;
    } else if (collection == 'settings') {
      if (settingsPriority == SyncPriority.remote) { winner = remote; winnerIsRemote = true; } else { winner = local; }
    } else {
      // history & default: newest wins; tie -> higher revision; tie -> remote.
      if (remote.updatedAt.isAfter(local.updatedAt)) { winner = remote; winnerIsRemote = true; }
      else if (local.updatedAt.isAfter(remote.updatedAt)) { winner = local; }
      else if (remote.revision >= local.revision) { winner = remote; winnerIsRemote = true; }
      else { winner = local; }
    }
    if (winnerIsRemote) {
      await storage.put(recordsTable, _id(collection, remote.key), remote.toJson());
      await storage.delete(outboxTable, _id(collection, remote.key));
      return (applied: true, conflict: isConflict);
    }
    if (winner != local) {
      // Merged record (favorites union) counts as a new local truth that
      // still has to be pushed so both sides converge.
      await storage.put(recordsTable, _id(collection, remote.key), winner.toJson());
    }
    if (winner.payloadJson != remote.payloadJson || winner.deleted != remote.deleted) {
      await storage.put(outboxTable, _id(collection, remote.key), {'collection': collection, 'key': remote.key});
    }
    return (applied: winner != local, conflict: isConflict);
  }

  SyncRecord _mergeFavorites(SyncRecord local, SyncRecord remote) {
    // Union semantics: existence wins over deletion on either side.
    if (local.deleted != remote.deleted) {
      final live = local.deleted ? remote : local;
      return live.copyWith(revision: local.revision > remote.revision ? local.revision : remote.revision,
          updatedAt: local.updatedAt.isAfter(remote.updatedAt) ? local.updatedAt : remote.updatedAt);
    }
    if (local.deleted && remote.deleted) {
      return local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
    }
    // Both live: merge JSON-object payloads key-wise, newer side wins
    // shared keys; non-object payloads fall back to the newer record.
    Map<String, dynamic>? lm, rm;
    try { final d = jsonDecode(local.payloadJson); if (d is Map<String, dynamic>) lm = d; } catch (_) {}
    try { final d = jsonDecode(remote.payloadJson); if (d is Map<String, dynamic>) rm = d; } catch (_) {}
    if (lm == null || rm == null) return local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
    final newerFirst = local.updatedAt.isAfter(remote.updatedAt) ? [lm, rm] : [rm, lm];
    final merged = <String, dynamic>{...newerFirst[1], ...newerFirst[0]};
    final base = local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
    return base.copyWith(payloadJson: jsonEncode(merged),
        revision: local.revision > remote.revision ? local.revision : remote.revision,
        updatedAt: local.updatedAt.isAfter(remote.updatedAt) ? local.updatedAt : remote.updatedAt);
  }

  Future<void> dispose() async { await _states.close(); }
}
