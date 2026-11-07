// Bangumi mirror API credentials for the search signature flow.
// Release/PR CI injects them via --dart-define=ANIKUMO_APPID / ANIKUMO_KEY.
const Map<String, String> bangumiMirrorCredentials = {
  'id': String.fromEnvironment('ANIKUMO_APPID'),
  'value': String.fromEnvironment('ANIKUMO_KEY'),
};
