import 'dart:convert';

/// Batch 163: the built-in danmaku service token,
/// obfuscated. Same arrangement as the TMDB key: the
/// open-source tree NEVER carries the real token — this
/// constant is empty in the repository, and the release
/// build injects the encoded value from a secrets file
/// outside the source tree. The encoding is obfuscation,
/// not secrecy.
///
/// There is deliberately no setting and no UI anywhere
/// for this service; nothing in the app displays it.
const String kBuiltinDanmuEncodedToken = '';

const List<int> _mask = [
  0x41, 0x6e, 0x69, 0x6b, 0x75, 0x6d, 0x6f, 0x2d, 0x31, 0x36, 0x33,
];

String _xor(List<int> bytes) {
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i++)
      bytes[i] ^ _mask[i % _mask.length] ^ (i & 0xff),
  ]);
}

/// Encodes a raw token for injection (used by the
/// packaging script; kept beside the decoder so they
/// cannot drift).
String encodeDanmuToken(String raw) {
  if (raw.isEmpty) return '';
  final mixed = _xor(utf8.encode(raw));
  return base64Encode(mixed.codeUnits);
}

/// Decodes the injected value; '' when nothing is built in.
String decodeDanmuToken(String encoded) {
  if (encoded.isEmpty) return '';
  try {
    final bytes = base64Decode(encoded);
    return utf8.decode(_xor(bytes).codeUnits);
  } catch (_) {
    return '';
  }
}

/// The decoded built-in token, or '' when this build
/// carries none (the open-source default).
String get builtinDanmuToken => decodeDanmuToken(kBuiltinDanmuEncodedToken);

