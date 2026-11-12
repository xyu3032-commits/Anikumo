import 'dart:convert';

/// Batch 193: the built-in DanDanPlay API credential pair,
/// obfuscated. Same arrangement as the TMDB key and the
/// danmaku service token: the open-source tree NEVER
/// carries the real pair — both constants are empty in the
/// repository, and the release build injects the encoded
/// values from a secrets file outside the source tree.
/// The encoding is obfuscation, not secrecy.
///
/// There is deliberately no settings entry for this pair
/// anywhere in the app (the manual AppId / AppKey entry was
/// removed in this batch); a pair a user stored earlier
/// still exists in their settings storage and still wins
/// over this built-in one — see DanmakuClient.
const String kDandanEncodedAppId = '';
const String kDandanEncodedKey = '';

const List<int> _mask = [
  0x41, 0x6e, 0x69, 0x6b, 0x75, 0x6d, 0x6f, 0x2d, 0x31, 0x39, 0x33,
];

String _xor(List<int> bytes) {
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i++)
      bytes[i] ^ _mask[i % _mask.length] ^ (i & 0xff),
  ]);
}

/// Encodes a raw value for injection (used by the
/// packaging script; kept beside the decoder so they
/// cannot drift).
String encodeDandanValue(String raw) {
  if (raw.isEmpty) return '';
  final mixed = _xor(utf8.encode(raw));
  return base64Encode(mixed.codeUnits);
}

/// Decodes an injected value; '' when nothing is built in.
String decodeDandanValue(String encoded) {
  if (encoded.isEmpty) return '';
  try {
    final bytes = base64Decode(encoded);
    return utf8.decode(_xor(bytes).codeUnits);
  } catch (_) {
    return '';
  }
}

/// The decoded built-in AppId, or '' when this build
/// carries none (the open-source default).
String get builtinDandanAppId => decodeDandanValue(kDandanEncodedAppId);

/// The decoded built-in AppKey, or '' when this build
/// carries none (the open-source default).
String get builtinDandanKey => decodeDandanValue(kDandanEncodedKey);
