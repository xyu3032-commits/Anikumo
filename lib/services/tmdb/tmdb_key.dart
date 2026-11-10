import 'dart:convert';

/// Batch 130: the built-in TMDB API key, obfuscated.
///
/// The open-source tree NEVER carries the real key: this
/// constant is empty in the repository, and the release
/// build injects the encoded value from a secrets file that
/// lives outside the source tree (see the packaging notes).
/// The encoding is obfuscation, not secrecy — it keeps the
/// key out of plaintext string dumps; anyone determined can
/// still extract it from a shipped binary, at which point
/// the key is simply rotated.
///
/// A key the user pastes in 设置 → 剧集图片 always wins
/// over this built-in one.
const String kTmdbEncodedKey = '';

const List<int> _mask = [
  0x41, 0x6e, 0x69, 0x6b, 0x75, 0x6d, 0x6f, 0x2d, 0x31, 0x33, 0x30,
];

String _xor(List<int> bytes) {
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i++)
      bytes[i] ^ _mask[i % _mask.length] ^ (i & 0xff),
  ]);
}

/// Encodes a raw key for injection (used by the packaging
/// script; kept beside the decoder so they cannot drift).
String encodeTmdbKey(String raw) {
  if (raw.isEmpty) return '';
  final mixed = _xor(utf8.encode(raw));
  return base64Encode(mixed.codeUnits);
}

/// Decodes the injected value; '' when nothing is built in.
String decodeTmdbKey(String encoded) {
  if (encoded.isEmpty) return '';
  try {
    final bytes = base64Decode(encoded);
    return utf8.decode(_xor(bytes).codeUnits);
  } catch (_) {
    return '';
  }
}

/// The decoded built-in key, or '' when this build carries
/// none (the open-source default).
String get builtinTmdbKey => decodeTmdbKey(kTmdbEncodedKey);
