import 'package:anikumo/services/danmaku/dandan_key.dart';

// DanDanPlay API credentials for the client signature flow.
//
// Batch 193: the built-in pair is injected at packaging
// time into dandan_key.dart (obfuscated, empty in source).
// --dart-define values (DANDANAPI_APPID / DANDANAPI_KEY,
// the upstream arrangement) still work when present and
// rank above the injected pair. A pair the user stored in
// settings earlier ranks above both — DanmakuClient applies
// that final step, so this map is only the build-carried
// pair.
const String _envId = String.fromEnvironment('DANDANAPI_APPID');
const String _envKey = String.fromEnvironment('DANDANAPI_KEY');

final Map<String, String> dandanCredentials = {
  'id': _envId.isNotEmpty ? _envId : builtinDandanAppId,
  'value': _envKey.isNotEmpty ? _envKey : builtinDandanKey,
};
