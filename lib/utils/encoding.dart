import 'dart:convert';

// Batch 53: rule share links are generated as anikumo://.
// The legacy kazumi:// prefix stays ACCEPTED (invisible
// data compatibility): links users shared before the
// rename must still import.
final RegExp _anikumoRuleLinkSchemePattern = RegExp(
  r'(?:anikumo|hunku|kazumi):(?://)?',
  caseSensitive: false,
);

Iterable<({String scheme, String rawPayload})> findAnikumoRuleLinkSegments(
  String input,
) sync* {
  final matches = _anikumoRuleLinkSchemePattern.allMatches(input).toList();
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final end = index + 1 < matches.length
        ? matches[index + 1].start
        : input.length;
    yield (
      scheme: match.group(0)!,
      rawPayload: input.substring(match.end, end),
    );
  }
}

String jsonToAnikumoBase64(String jsonStr) {
  final base64Str = base64Encode(utf8.encode(jsonStr));
  return 'anikumo://$base64Str';
}

String anikumoBase64ToJson(String anikumoBase64Str) {
  final input = anikumoBase64Str.trim();
  final schemeMatch = _anikumoRuleLinkSchemePattern.matchAsPrefix(input);
  if (schemeMatch == null) {
    throw const FormatException('Invalid Anikumo rule link');
  }

  var payload = input.substring(schemeMatch.end);
  try {
    payload = Uri.decodeComponent(payload);
  } on FormatException {
    throw const FormatException('Invalid encoding in Anikumo rule link');
  } on ArgumentError {
    throw const FormatException('Invalid encoding in Anikumo rule link');
  }
  payload = payload.replaceAll(RegExp(r'\s'), '');
  if (payload.isEmpty) {
    throw const FormatException('Anikumo rule link is empty');
  }

  // Accept both standard and URL-safe Base64, with or without padding. Links
  // are frequently wrapped by chat applications or percent-encoded by URI
  // handlers before they reach the import dialog.
  final normalized = base64.normalize(
    payload.replaceAll('-', '+').replaceAll('_', '/'),
  );
  try {
    return utf8.decode(base64.decode(normalized));
  } on FormatException {
    throw const FormatException('Invalid Anikumo rule link payload');
  }
}
