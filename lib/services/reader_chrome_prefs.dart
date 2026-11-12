import 'storage/storage.dart';

/// Batch 252: the manga/novel reader chrome (UI)
/// auto-hide delay, shared by both readers. The user
/// asked for it adjustable: default 1.5 s, range
/// 0.5–5 s (batch 251 shipped a fixed 3.5 s). Readers
/// read [readerChromeHideDelay] every time they arm
/// the hide timer, so a change applies to the very
/// next idle period — no reader restart.
const double kReaderChromeHideMinSeconds = 0.5;
const double kReaderChromeHideMaxSeconds = 5.0;
const double kReaderChromeHideDefaultSeconds = 1.5;

double clampReaderChromeHideSeconds(num? raw) {
  final value = (raw ?? kReaderChromeHideDefaultSeconds).toDouble();
  if (value.isNaN) return kReaderChromeHideDefaultSeconds;
  return value
      .clamp(kReaderChromeHideMinSeconds, kReaderChromeHideMaxSeconds)
      .toDouble();
}

double readerChromeHideSeconds() => clampReaderChromeHideSeconds(
  GStorage.getSetting(SettingsKeys.readerChromeHideSeconds),
);

Duration readerChromeHideDelay() =>
    Duration(milliseconds: (readerChromeHideSeconds() * 1000).round());
