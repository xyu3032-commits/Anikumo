import 'dart:io';
import 'package:liuguang_player_api/liuguang_player_api.dart';

enum HostOs { android, windows, macos, linux, ios, unknown }

class PlatformInfo {
  final HostOs os;
  const PlatformInfo(this.os);
  bool get isMobile => os == HostOs.android || os == HostOs.ios;
  bool get isDesktop => os == HostOs.windows || os == HostOs.macos || os == HostOs.linux;
  static HostOs parseOs(String name) {
    switch (name.toLowerCase()) {
      case 'android': return HostOs.android;
      case 'windows': return HostOs.windows;
      case 'macos': return HostOs.macos;
      case 'linux': return HostOs.linux;
      case 'ios': return HostOs.ios;
      default: return HostOs.unknown;
    }
  }
  factory PlatformInfo.fromOsName(String name) => PlatformInfo(parseOs(name));
  factory PlatformInfo.current() => PlatformInfo(parseOs(Platform.operatingSystem));
  @override String toString() => 'PlatformInfo(${os.name})';
}

/// Conservative per-platform capability defaults. Hosts may override any
/// value via [copyWith] (e.g. a desktop build that does support PiP
/// through an in-app mini window). Linux hardware decode defaults to
/// false: too many distro/driver combinations lack a working path, and
/// claiming it would produce black screens instead of software decode.
class PlatformCapabilities {
  final bool pictureInPicture;
  final bool backgroundPlay;
  final bool hardwareDecode;
  final Set<String> formats;
  const PlatformCapabilities({this.pictureInPicture = false, this.backgroundPlay = false, this.hardwareDecode = false, this.formats = const {'mp4'}});
  PlatformCapabilities copyWith({bool? pictureInPicture, bool? backgroundPlay, bool? hardwareDecode, Set<String>? formats}) => PlatformCapabilities(
      pictureInPicture: pictureInPicture ?? this.pictureInPicture, backgroundPlay: backgroundPlay ?? this.backgroundPlay,
      hardwareDecode: hardwareDecode ?? this.hardwareDecode, formats: formats ?? this.formats);

  static PlatformCapabilities defaultsFor(PlatformInfo info) {
    switch (info.os) {
      case HostOs.android:
        return const PlatformCapabilities(pictureInPicture: true, backgroundPlay: true, hardwareDecode: true, formats: {'mp4', 'hls', 'dash', 'webm', 'mkv'});
      case HostOs.ios:
        return const PlatformCapabilities(pictureInPicture: true, backgroundPlay: true, hardwareDecode: true, formats: {'mp4', 'hls'});
      case HostOs.windows:
        return const PlatformCapabilities(pictureInPicture: false, backgroundPlay: true, hardwareDecode: true, formats: {'mp4', 'hls', 'dash', 'webm', 'mkv'});
      case HostOs.macos:
        return const PlatformCapabilities(pictureInPicture: false, backgroundPlay: true, hardwareDecode: true, formats: {'mp4', 'hls', 'dash', 'mkv'});
      case HostOs.linux:
        return const PlatformCapabilities(pictureInPicture: false, backgroundPlay: true, hardwareDecode: false, formats: {'mp4', 'hls', 'webm', 'mkv'});
      case HostOs.unknown:
        return const PlatformCapabilities();
    }
  }
}

/// Directories are owned by the host app; the engine never guesses
/// app-specific locations. The default implementation roots everything
/// under a temp `liuguang/` folder — fine for tools and tests, hosts are
/// expected to inject their own (e.g. app-documents based) paths.
abstract interface class HostPaths {
  String get cacheDir;
  String get dataDir;
  String get downloadDir;
}

class FixedHostPaths implements HostPaths {
  @override final String cacheDir;
  @override final String dataDir;
  @override final String downloadDir;
  const FixedHostPaths({required this.cacheDir, required this.dataDir, required this.downloadDir});
}

class IoHostPaths implements HostPaths {
  final String baseDir;
  IoHostPaths([String? baseDir]) : baseDir = baseDir ?? '${Directory.systemTemp.path}/liuguang';
  @override String get cacheDir => '$baseDir/cache';
  @override String get dataDir => '$baseDir/data';
  @override String get downloadDir => '$baseDir/downloads';
  Future<void> ensureCreated() async {
    for (final d in [cacheDir, dataDir, downloadDir]) {
      await Directory(d).create(recursive: true);
    }
  }
}

class EffectiveCapabilities {
  final bool pictureInPicture;
  final bool backgroundPlay;
  final bool hardwareDecode;
  final bool subtitles;
  final bool multiAudio;
  final Set<String> formats;
  const EffectiveCapabilities({required this.pictureInPicture, required this.backgroundPlay, required this.hardwareDecode,
      required this.subtitles, required this.multiAudio, required this.formats});
  bool supportsFormat(String f) => formats.contains(f.toLowerCase());
  @override String toString() => 'EffectiveCapabilities(pip=$pictureInPicture bg=$backgroundPlay hw=$hardwareDecode subs=$subtitles multiAudio=$multiAudio formats=$formats)';
}

/// What a playback session can actually use = what the player kernel
/// declares AND what the platform matrix allows. Format support is the
/// intersection of both format sets (case-insensitive).
EffectiveCapabilities mergeCapabilities({required PlayerCapabilities engine, required PlatformCapabilities platform}) {
  final engineFormats = engine.formats.map((f) => f.toLowerCase()).toSet();
  final platformFormats = platform.formats.map((f) => f.toLowerCase()).toSet();
  return EffectiveCapabilities(
    pictureInPicture: engine.pictureInPicture && platform.pictureInPicture,
    backgroundPlay: engine.backgroundPlay && platform.backgroundPlay,
    hardwareDecode: engine.hardwareDecode && platform.hardwareDecode,
    subtitles: engine.subtitles,
    multiAudio: engine.multiAudio,
    formats: engineFormats.intersection(platformFormats),
  );
}
