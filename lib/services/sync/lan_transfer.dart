import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:anikumo/services/backup/local_backup.dart';
import 'package:anikumo/services/logging/logger.dart';

/// Batch 284 (#33): one-shot LAN backup transfer.
///
/// The sending device serves its full backup bundle from
/// a throwaway [HttpServer] on the local network. The
/// download URL carries a random one-time token and IS
/// the QR payload: the receiving device scans it with the
/// in-app scanner (#19), downloads the zip, checks the
/// bundle header and then flows into the normal backup
/// restore (with its usual confirmation dialog).
///
/// Safety rails: the token is single-use (the server
/// closes itself right after one successful download),
/// the server also dies after [kLanTransferLifetime]
/// even if nobody downloads, a wrong token gets a 403,
/// and only the one backup path is served at all.
const String kLanTransferPath = '/anikumo-backup';
const Duration kLanTransferLifetime = Duration(minutes: 5);

/// Where a receiver can fetch one backup bundle.
class LanTransferEndpoint {
  const LanTransferEndpoint({
    required this.host,
    required this.port,
    required this.token,
  });

  final String host;
  final int port;
  final String token;

  Uri get uri => buildLanDownloadUri(host: host, port: port, token: token);

  /// The QR-code payload: the download URL itself.
  String get payload => uri.toString();
}

/// A fresh one-time token (128 bits, URL-safe).
String generateLanToken([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Uri buildLanDownloadUri({
  required String host,
  required int port,
  required String token,
}) {
  return Uri(
    scheme: 'http',
    host: host,
    port: port,
    path: kLanTransferPath,
    queryParameters: {'token': token},
  );
}

/// Constant-work token comparison (no early exit on the
/// first mismatching character).
bool isValidLanToken(String? provided, String expected) {
  if (provided == null || provided.isEmpty || expected.isEmpty) return false;
  if (provided.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < provided.length; i++) {
    diff |= provided.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return diff == 0;
}

/// Parses a scanned/pasted LAN payload back into an
/// endpoint, or null when [raw] is not one of ours.
LanTransferEndpoint? parseLanEndpoint(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'http') return null;
  if (uri.path != kLanTransferPath) return null;
  if (uri.host.isEmpty || uri.port <= 0) return null;
  final token = uri.queryParameters['token'];
  if (token == null || token.isEmpty) return null;
  return LanTransferEndpoint(host: uri.host, port: uri.port, token: token);
}

/// Parses the manual receive form: [addressText] may be
/// the full payload URL, or a bare `host[:port]` combined
/// with a separately typed [tokenText].
LanTransferEndpoint? parseLanAddressInput(
  String addressText,
  String tokenText,
) {
  final fromPayload = parseLanEndpoint(addressText);
  if (fromPayload != null) return fromPayload;
  final token = tokenText.trim();
  if (token.isEmpty) return null;
  var hostPort = addressText.trim();
  if (hostPort.isEmpty) return null;
  // Tolerate a pasted URL without our path: strip scheme.
  if (hostPort.contains('://')) {
    final uri = Uri.tryParse(hostPort);
    if (uri == null || uri.host.isEmpty || uri.port <= 0) return null;
    return LanTransferEndpoint(host: uri.host, port: uri.port, token: token);
  }
  final colon = hostPort.lastIndexOf(':');
  var host = hostPort;
  var port = 0;
  if (colon > 0) {
    host = hostPort.substring(0, colon);
    port = int.tryParse(hostPort.substring(colon + 1)) ?? 0;
  }
  if (host.isEmpty || port <= 0) return null;
  return LanTransferEndpoint(host: host, port: port, token: token);
}

bool isPrivateIpv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}

/// Picks the address another device on the same LAN
/// should dial: first private IPv4 wins, then any
/// non-loopback IPv4; loopback-only yields null.
String? pickLanIpv4(List<String> addresses) {
  String? fallback;
  for (final address in addresses) {
    if (address.contains(':')) continue; // IPv6: not used.
    if (address == '127.0.0.1' || address.startsWith('127.')) continue;
    if (isPrivateIpv4(address)) return address;
    fallback ??= address;
  }
  return fallback;
}

/// Whether [bytes] carry the backup-bundle zip header.
bool looksLikeBackupBundle(List<int> bytes) => LocalBackup.isBundle(bytes);

class LanTransferException implements Exception {
  const LanTransferException(this.message);

  final String message;

  @override
  String toString() => 'LanTransferException: $message';
}

/// The one-shot sending server. Create with [start],
/// show [endpoint] to the user, and [close] when done —
/// it also closes itself after one download or when
/// [lifetime] runs out.
class LanTransferServer {
  LanTransferServer._(this._server, this.token, this.endpoint);

  final HttpServer _server;
  final String token;
  final LanTransferEndpoint endpoint;
  Timer? _timer;
  bool _closed = false;

  bool get isClosed => _closed;

  static Future<LanTransferServer> start({
    required Uint8List bytes,
    Duration lifetime = kLanTransferLifetime,
    InternetAddress? address,
    String? token,
  }) async {
    final effectiveToken = token ?? generateLanToken();
    final server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      0,
    );
    final boundToAny = address == null ||
        address.address == InternetAddress.anyIPv4.address ||
        address.address == InternetAddress.anyIPv6.address;
    final String host;
    if (!boundToAny) {
      host = address.address;
    } else {
      String? picked;
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        picked = pickLanIpv4([
          for (final iface in interfaces)
            for (final addr in iface.addresses) addr.address,
        ]);
      } catch (_) {
        picked = null;
      }
      host = picked ?? InternetAddress.loopbackIPv4.address;
    }
    final endpoint = LanTransferEndpoint(
      host: host,
      port: server.port,
      token: effectiveToken,
    );
    final transfer = LanTransferServer._(server, effectiveToken, endpoint);
    transfer._timer = Timer(lifetime, () {
      AnikumoLogger().i('LanTransfer: lifetime expired, closing');
      unawaited(transfer.close());
    });
    server.listen((request) {
      unawaited(transfer._handle(request, bytes));
    });
    return transfer;
  }

  Future<void> _handle(HttpRequest request, Uint8List bytes) async {
    try {
      if (request.method != 'GET' || request.uri.path != kLanTransferPath) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (!isValidLanToken(request.uri.queryParameters['token'], token)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.binary;
      request.response.headers.set(
        'Content-Disposition',
        'attachment; filename="anikumo-backup.zip"',
      );
      request.response.add(bytes);
      await request.response.close();
      // One-time: the token dies with this download.
      unawaited(close());
    } catch (e) {
      AnikumoLogger().w('LanTransfer: request failed', error: e);
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    try {
      await _server.close(force: true);
    } catch (_) {}
  }
}

abstract final class LanTransferClient {
  /// Downloads the bundle behind [endpoint] and verifies
  /// it really is a backup bundle before returning it.
  static Future<Uint8List> download(
    LanTransferEndpoint endpoint, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(endpoint.uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw LanTransferException('HTTP ${response.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (!looksLikeBackupBundle(bytes)) {
        throw const LanTransferException('not a backup bundle');
      }
      return bytes;
    } on LanTransferException {
      rethrow;
    } catch (e) {
      throw LanTransferException('$e');
    } finally {
      client.close(force: true);
    }
  }
}
