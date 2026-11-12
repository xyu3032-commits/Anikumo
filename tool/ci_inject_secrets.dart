// CI-only release tool — not part of the app.
//
// Injects the built-in TMDB key, danmaku token and
// DanDanPlay credential pair (obfuscated, same codec as
// the app-side key holders) from repository secrets into
// the key-holder sources before a release build:
//
//   TMDB_API_KEY=... DANMU_API_TOKEN=... \
//     dart tool/ci_inject_secrets.dart
//
// The raw values arrive as environment variables and
// are never printed. When a secret is absent (forks,
// PR builds), the corresponding constant stays empty
// and the app simply runs without that built-in key —
// the committed sources therefore never carry a key.
import 'dart:convert';
import 'dart:io';

const _tmdbMask = [
  0x41, 0x6e, 0x69, 0x6b, 0x75, 0x6d, 0x6f, 0x2d, 0x31, 0x33, 0x30,
];
const _danmuMask = [
  0x41, 0x6e, 0x69, 0x6b, 0x75, 0x6d, 0x6f, 0x2d, 0x31, 0x36, 0x33,
];
const _dandanMask = [
  0x41, 0x6e, 0x69, 0x6b, 0x75, 0x6d, 0x6f, 0x2d, 0x31, 0x39, 0x33,
];

String _encode(String raw, List<int> mask) {
  final bytes = utf8.encode(raw);
  final mixed = [
    for (var i = 0; i < bytes.length; i++)
      bytes[i] ^ mask[i % mask.length] ^ (i & 0xff),
  ];
  return base64Encode(mixed);
}

Future<void> _inject({
  required String envName,
  required List<int> mask,
  required String file,
  required String patternSource,
  required String declaration,
}) async {
  final raw = (Platform.environment[envName] ?? '').trim();
  if (raw.isEmpty) {
    stdout.writeln('$envName not set; leaving $file unchanged');
    return;
  }
  final target = File(file);
  final source = await target.readAsString();
  final pattern = RegExp(patternSource);
  if (!pattern.hasMatch(source)) {
    stderr.writeln('$declaration declaration not found in $file');
    exit(2);
  }
  await target.writeAsString(
    source.replaceFirst(
      pattern,
      "$declaration = '${_encode(raw, mask)}';",
    ),
  );
  stdout.writeln('injected $envName (obfuscated)');
}

Future<void> main() async {
  await _inject(
    envName: 'TMDB_API_KEY',
    mask: _tmdbMask,
    file: 'lib/services/tmdb/tmdb_key.dart',
    patternSource: r"const String kTmdbEncodedKey = '[^']*';",
    declaration: 'const String kTmdbEncodedKey',
  );
  await _inject(
    envName: 'DANMU_API_TOKEN',
    mask: _danmuMask,
    file: 'lib/services/danmaku/danmu_token.dart',
    patternSource: r"const String kBuiltinDanmuEncodedToken = '[^']*';",
    declaration: 'const String kBuiltinDanmuEncodedToken',
  );
  await _inject(
    envName: 'DANDAN_APPID',
    mask: _dandanMask,
    file: 'lib/services/danmaku/dandan_key.dart',
    patternSource: r"const String kDandanEncodedAppId = '[^']*';",
    declaration: 'const String kDandanEncodedAppId',
  );
  await _inject(
    envName: 'DANDAN_KEY',
    mask: _dandanMask,
    file: 'lib/services/danmaku/dandan_key.dart',
    patternSource: r"const String kDandanEncodedKey = '[^']*';",
    declaration: 'const String kDandanEncodedKey',
  );
}
