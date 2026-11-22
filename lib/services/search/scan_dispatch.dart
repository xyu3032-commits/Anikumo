import 'package:anikumo/services/deep_links/anikumo_deep_link.dart';
import 'package:anikumo/services/sync/lan_transfer.dart';

/// Batch 284 (#19): what one scanned code means.
///
/// Dispatch order matters: our own payloads win over the
/// generic rules — a LAN transfer URL is an http URL, so
/// it must be recognized before the "links become search
/// terms" fallback.
sealed class ScanAction {
  const ScanAction();
}

/// An `anikumo://` deep link: hand it to the same landing
/// path OS-delivered links take (B276 work links included).
final class ScanOpenDeepLink extends ScanAction {
  const ScanOpenDeepLink(this.link);

  final AnikumoDeepLink link;
}

/// A LAN backup transfer payload (#33): the caller routes
/// to the backup page with this endpoint prefilled.
final class ScanLanReceive extends ScanAction {
  const ScanLanReceive(this.endpoint);

  final LanTransferEndpoint endpoint;
}

/// Anything else — a web link or plain text — becomes a
/// cross-zone search term. (Links are searched, not
/// opened: a QR found in the wild should never navigate
/// the app away without the user seeing the term first.)
final class ScanSearch extends ScanAction {
  const ScanSearch(this.query);

  final String query;
}

/// Nothing usable was scanned.
final class ScanIgnored extends ScanAction {
  const ScanIgnored();
}

ScanAction dispatchScanResult(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const ScanIgnored();
  final lan = parseLanEndpoint(text);
  if (lan != null) return ScanLanReceive(lan);
  final uri = Uri.tryParse(text);
  if (uri != null && uri.scheme == 'anikumo') {
    final link = AnikumoDeepLink.parse(uri);
    if (link != null) return ScanOpenDeepLink(link);
  }
  return ScanSearch(text);
}
