import 'dart:convert';

/// Batch 257: the GitHub OAuth App client id used by the
/// device-code sign-in. A client id is public information
/// (it appears in the authorization URL), but the source
/// tree still carries none: local release builds inject
/// the registered id from a file outside the tree, the
/// same discipline as the TMDB key — one registration,
/// swappable without touching code.
///
/// The device-code flow needs NO client secret, which is
/// why it was chosen: nothing confidential ships in the
/// binary.
const String kGithubEncodedClientId = '';

const List<int> _mask = [
  0x41,
  0x6e,
  0x69,
  0x6b,
  0x75,
  0x6d,
  0x6f,
  0x2d,
  0x32,
  0x35,
  0x37,
];

String _xor(List<int> bytes) {
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i++)
      bytes[i] ^ _mask[i % _mask.length] ^ (i & 0xff),
  ]);
}

/// Encodes a raw client id for injection (packaging side).
String encodeGithubClientId(String raw) {
  if (raw.isEmpty) return '';
  final mixed = _xor(utf8.encode(raw));
  return base64Encode(mixed.codeUnits);
}

/// Decodes the injected value; '' when nothing is built in.
String decodeGithubClientId(String encoded) {
  if (encoded.isEmpty) return '';
  try {
    final bytes = base64Decode(encoded);
    return utf8.decode(_xor(bytes).codeUnits);
  } catch (_) {
    return '';
  }
}

/// The registered client id, or '' when this build has
/// none (the open-source default).
String get githubClientId => decodeGithubClientId(kGithubEncodedClientId);
