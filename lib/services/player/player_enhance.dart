import 'dart:async';

import 'package:anikumo/services/logging/logger.dart';
import 'package:anikumo/services/storage/storage.dart';
import 'package:media_kit/media_kit.dart';

/// Batch 16: playback enhancement profile — optimizations
/// and features that the stock player doesn't expose. Every
/// item resolves to concrete mpv properties (composed here as a
/// pure function, so the whole profile is unit-testable) and is
/// applied to each new player at initialization, mirroring how
/// PlaybackCachePolicy applies the demuxer cache size.
class PlayerEnhance {
  PlayerEnhance._();

  // ---- storage helpers (ad-hoc typed keys over the same box;
  // the px* names are this profile's own namespace) ----

  static SettingKey<bool> _flagKey(String key) =>
      SettingKey<bool>(key, false, group: SettingGroup.player);

  static SettingKey<double> _numKey(String key, double fallback) =>
      SettingKey<double>(key, fallback, group: SettingGroup.player);

  static SettingKey<String> _strKey(String key, String fallback) =>
      SettingKey<String>(key, fallback, group: SettingGroup.player);

  static bool flagOf(String key) {
    try {
      return GStorage.getSetting(_flagKey(key));
    } catch (_) {
      return false;
    }
  }

  static double numOf(String key, double fallback) {
    try {
      return GStorage.getSetting(_numKey(key, fallback));
    } catch (_) {
      return fallback;
    }
  }

  static String strOf(String key, String fallback) {
    try {
      final value = GStorage.getSetting(_strKey(key, fallback));
      return value.isNotEmpty ? value : fallback;
    } catch (_) {
      return fallback;
    }
  }

  static bool _flag(String key) => flagOf(key);

  /// Flag read with an explicit default (the smart-tuner
  /// switches default ON, unlike the profile flags).
  static bool flagDefault(String key, bool fallback) {
    try {
      return GStorage.getSetting(
        SettingKey<bool>(key, fallback, group: SettingGroup.player),
      );
    } catch (_) {
      return fallback;
    }
  }

  static bool get autoCacheSecsEnabled =>
      flagDefault(PlayerEnhanceKeys.autoCacheSecs, true);

  static bool get autoDropGuardEnabled =>
      flagDefault(PlayerEnhanceKeys.autoDropGuard, true);

  static double _num(String key, double fallback) => numOf(key, fallback);

  static String _str(String key, String fallback) => strOf(key, fallback);

  static Future<void> setFlag(String key, bool value) =>
      GStorage.putSetting(_flagKey(key), value);

  static Future<void> setNum(String key, double value) =>
      GStorage.putSetting(_numKey(key, value), value);

  static Future<void> setStr(String key, String value) =>
      GStorage.putSetting(_strKey(key, value), value);

  // ---- the profile → mpv property map (pure) ----

  /// Builds the full property map for a profile given as plain
  /// values, so tests can verify composition (af/vf chains,
  /// stream-lavf-o merging) without a player or storage.
  static Map<String, String> buildProperties({
    required Map<String, bool> flags,
    required Map<String, double> nums,
    required Map<String, String> strs,
  }) {
    bool f(String key) => flags[key] ?? false;
    double n(String key, double fallback) => nums[key] ?? fallback;
    String s(String key, String fallback) => strs[key] ?? fallback;

    final props = <String, String>{};
    final af = <String>[];
    final vf = <String>[];
    final lavf = <String>[];

    // ——— optimizations ———
    if (f(PlayerEnhanceKeys.optDisplaySync)) {
      props['video-sync'] = 'display-resample';
    }
    if (f(PlayerEnhanceKeys.optInterpolation)) {
      props['interpolation'] = 'yes';
      props['tscale'] = 'oversample';
      // Batch 114: interpolation is inert unless the sync mode is
      // a display mode — enabling motion interpolation alone used
      // to do nothing at all. It now implies display-resample
      // (the same value the display-sync switch sets).
      props['video-sync'] = 'display-resample';
    }
    if (f(PlayerEnhanceKeys.optLowPowerDecode)) {
      props['vd-lavc-fast'] = 'yes';
      props['vd-lavc-skiploopfilter'] = 'all';
    }
    if (f(PlayerEnhanceKeys.optPrebuffer)) {
      props['cache-pause'] = 'yes';
      props['cache-pause-initial'] = 'yes';
      props['cache-pause-wait'] = '1';
    }
    if (f(PlayerEnhanceKeys.optReconnect)) {
      lavf.add('reconnect=1');
      lavf.add('reconnect_streamed=1');
      lavf.add('reconnect_delay_max=5');
    }
    if (f(PlayerEnhanceKeys.optSeekableCache)) {
      props['demuxer-seekable-cache'] = 'yes';
    }
    if (f(PlayerEnhanceKeys.optDeband)) {
      props['deband'] = 'yes';
    }
    if (f(PlayerEnhanceKeys.optSharpen)) {
      // Batch 114: the bundled libmpv ships a minimal libavfilter
      // (no unsharp/hqdn3d — verified against the shipped binary),
      // so the old vf filter was rejected wholesale and sharpening
      // never took effect. The renderer-native sharpen property
      // (libplacebo, gpu/gpu-next) does the same job for real.
      props['sharpen'] = '0.5';
    }
    if (f(PlayerEnhanceKeys.optFullRange)) {
      props['video-output-levels'] = 'full';
    }
    if (f(PlayerEnhanceKeys.optHdrToneMap)) {
      props['tone-mapping'] = 'reinhard';
      props['hdr-compute-peak'] = 'yes';
    }
    if (f(PlayerEnhanceKeys.optDownmix)) {
      props['audio-channels'] = 'stereo';
      props['ad-lavc-downmix'] = 'yes';
    }
    if (f(PlayerEnhanceKeys.optBlendSubs)) {
      props['blend-subtitles'] = 'yes';
    }
    if (f(PlayerEnhanceKeys.optFrameDrop)) {
      props['framedrop'] = 'vo';
    }
    if (f(PlayerEnhanceKeys.optVideoQueue)) {
      props['vd-queue-enable'] = 'yes';
      props['vd-queue-max-bytes'] = '64MiB';
    }
    if (f(PlayerEnhanceKeys.optAudioQueue)) {
      props['ad-queue-enable'] = 'yes';
      props['ad-queue-max-bytes'] = '16MiB';
    }
    if (f(PlayerEnhanceKeys.optNetTimeout)) {
      lavf.add('timeout=20000000');
    }
    if (f(PlayerEnhanceKeys.optReadahead)) {
      props['demuxer-readahead-secs'] = '30';
    }
    if (f(PlayerEnhanceKeys.optSamplerate)) {
      props['audio-samplerate'] = '48000';
    }
    if (f(PlayerEnhanceKeys.optSwapchain)) {
      props['swapchain-depth'] = '3';
    }
    if (f(PlayerEnhanceKeys.optFboFormat)) {
      props['fbo-format'] = 'rgba16f';
    }
    if (f(PlayerEnhanceKeys.optHrSeek)) {
      props['hr-seek'] = 'yes';
    }

    // ——— 12 features ———
    final aspect = s(PlayerEnhanceKeys.featAspect, 'auto');
    if (aspect == 'fill') {
      // Crop-to-fill keeps the source aspect and panscans.
      props['panscan'] = '1.0';
    } else if (aspect != 'auto') {
      props['video-aspect-override'] = aspect;
    }
    final rotate = s(PlayerEnhanceKeys.featRotate, '0');
    if (rotate != '0') props['video-rotate'] = rotate;
    if (f(PlayerEnhanceKeys.featMirror)) {
      // Batch 114: 'hflip' is a libavfilter name and is not in the
      // bundled build; mpv's internal 'mirror' filter is.
      vf.add('mirror');
    }
    if (f(PlayerEnhanceKeys.featLoopEpisode)) {
      props['loop-file'] = 'inf';
    }
    final audioDelay = n(PlayerEnhanceKeys.featAudioDelay, 0);
    if (audioDelay != 0) {
      props['audio-delay'] = audioDelay.toStringAsFixed(2);
    }
    final subDelay = n(PlayerEnhanceKeys.featSubDelay, 0);
    if (subDelay != 0) {
      props['sub-delay'] = subDelay.toStringAsFixed(2);
    }
    final aid = s(PlayerEnhanceKeys.featAudioTrack, 'auto');
    if (aid != 'auto') props['aid'] = aid;
    final sid = s(PlayerEnhanceKeys.featSubTrack, 'auto');
    if (sid != 'auto') {
      props['sid'] = sid;
      if (sid == 'no') props['sub-visibility'] = 'no';
    }
    final secondSid = s(PlayerEnhanceKeys.featSecondSubTrack, 'no');
    if (secondSid != 'no') props['secondary-sid'] = secondSid;
    final eq = s(PlayerEnhanceKeys.featEqualizer, 'off');
    // Batch 114: the bass/treble filters are not in the bundled
    // libavfilter either; the peaking 'equalizer' filter is, and
    // expresses the same three presets.
    if (eq == 'bass') {
      af.add('equalizer=frequency=110:width_type=o:width=2:gain=10');
    } else if (eq == 'treble') {
      af.add('equalizer=frequency=3500:width_type=o:width=2:gain=8');
    } else if (eq == 'voice') {
      af.add('equalizer=frequency=110:width_type=o:width=2:gain=-4');
      af.add('equalizer=frequency=3500:width_type=o:width=2:gain=4');
    }
    final channelMode = s(PlayerEnhanceKeys.featChannelMode, 'normal');
    if (channelMode == 'mono') {
      // Batch 114: the 'pan' filter is absent from the bundled
      // build; the audio-channels property is the native mono
      // path. Set in the features section on purpose: it wins
      // over the downmix optimization's 'stereo' when both are on.
      // (The old 'swap' preset had no native equivalent and is
      // gone; a stored 'swap' value now simply does nothing.)
      props['audio-channels'] = 'mono';
    }
    final brightness = n(PlayerEnhanceKeys.featBrightness, 0);
    if (brightness != 0) props['brightness'] = brightness.round().toString();
    final contrast = n(PlayerEnhanceKeys.featContrast, 0);
    if (contrast != 0) props['contrast'] = contrast.round().toString();
    final saturation = n(PlayerEnhanceKeys.featSaturation, 0);
    if (saturation != 0) {
      props['saturation'] = saturation.round().toString();
    }

    if (af.isNotEmpty) {
      // The app itself forces this chain at init (pitch-correct
      // speed changes); keep it as the head of any custom chain
      // so enabling an audio feature never strips it.
      props['af'] = ['scaletempo2=max-speed=8', ...af].join(',');
    }
    if (vf.isNotEmpty) props['vf'] = vf.join(',');
    if (lavf.isNotEmpty) props['stream-lavf-o'] = lavf.join(',');
    return props;
  }

  /// Reads the stored profile.
  static Map<String, String> currentProperties() => buildProperties(
        flags: {
          for (final key in PlayerEnhanceKeys.flagKeys) key: _flag(key),
        },
        nums: {
          for (final key in PlayerEnhanceKeys.numKeys)
            key: _num(key, PlayerEnhanceKeys.numDefaults[key] ?? 0),
        },
        strs: {
          for (final key in PlayerEnhanceKeys.strKeys)
            key: _str(key, PlayerEnhanceKeys.strDefaults[key] ?? ''),
        },
      );

  /// Applies the stored profile to a freshly created player.
  static Future<void> applyTo(Player player) async {
    try {
      final platform = player.platform;
      if (platform is! NativePlayer) return;
      await platform.waitForPlayerInitialization;
      final props = currentProperties();
      // Batch 114: filter chains leave the bulk pass — they are
      // applied per filter below so one filter the bundled build
      // doesn't know can no longer reject its siblings (or, for
      // af, the pitch-correction baseline) along with itself.
      final afChain = props.remove('af');
      final vfChain = props.remove('vf');
      // Batch 19: issue the writes together instead of one
      // awaited round-trip per property — with the full
      // profile on this was ~40 sequential waits before the
      // first frame. Invocation order is preserved, and each
      // write still isolates its own rejection.
      await Future.wait([
        for (final entry in props.entries)
          () async {
            try {
              await platform.setProperty(entry.key, entry.value);
            } catch (e) {
              AnikumoLogger().w(
                'PlayerEnhance: property ${entry.key} rejected',
                error: e,
              );
            }
          }(),
      ]);
      await _applyFilterChain(
        platform,
        'af',
        afChain,
        baseline: 'scaletempo2=max-speed=8',
      );
      await _applyFilterChain(platform, 'vf', vfChain);
      if (props.isNotEmpty) {
        AnikumoLogger().i(
          'PlayerEnhance: applied ${props.length} properties',
        );
      }
    } catch (e) {
      AnikumoLogger().w('PlayerEnhance: apply failed', error: e);
    }
  }

  /// Resets the [kind] chain ('af'/'vf') to [baseline] (or empty)
  /// and re-adds each filter of [chain] individually, so a filter
  /// the build rejects is dropped alone with a log line instead of
  /// voiding the whole chain. Running this on every apply also
  /// makes turning a filter feature OFF take effect on the
  /// in-player re-apply, not only at the next playback start.
  static Future<void> _applyFilterChain(
    NativePlayer platform,
    String kind,
    String? chain, {
    String? baseline,
  }) async {
    final filters = chain
            ?.split(',')
            .where((entry) => entry.isNotEmpty)
            .toList() ??
        const <String>[];
    var start = 0;
    try {
      if (baseline != null) {
        await platform.setProperty(kind, baseline);
        if (filters.isNotEmpty && filters.first == baseline) {
          start = 1;
        }
      } else {
        await platform.setProperty(kind, '');
      }
    } catch (e) {
      AnikumoLogger().w(
        'PlayerEnhance: $kind chain reset rejected',
        error: e,
      );
    }
    for (final filter in filters.skip(start)) {
      try {
        await platform.command([kind, 'add', filter]);
      } catch (e) {
        AnikumoLogger().w(
          'PlayerEnhance: $kind filter "$filter" rejected',
          error: e,
        );
      }
    }
  }
}

/// Storage keys for the batch-16 playback profile. Values live
/// in the same settings box as everything else; defaults keep
/// the stock behavior until the user opts in.
class PlayerEnhanceKeys {
  // Batch 19: runtime tuner switches (not mpv properties —
  // they gate PlaybackTunerSession; both default ON).
  static const autoCacheSecs = 'pxAutoCacheSecs';
  static const autoDropGuard = 'pxAutoDropGuard';

  PlayerEnhanceKeys._();

  // 24 optimizations (all default off)
  static const optDisplaySync = 'pxOptDisplaySync';
  static const optInterpolation = 'pxOptInterpolation';
  static const optLowPowerDecode = 'pxOptLowPowerDecode';
  static const optPrebuffer = 'pxOptPrebuffer';
  static const optReconnect = 'pxOptReconnect';
  static const optSeekableCache = 'pxOptSeekableCache';
  static const optDeband = 'pxOptDeband';
  static const optSharpen = 'pxOptSharpen';
  static const optFullRange = 'pxOptFullRange';
  static const optHdrToneMap = 'pxOptHdrToneMap';
  static const optDownmix = 'pxOptDownmix';
  static const optBlendSubs = 'pxOptBlendSubs';
  static const optFrameDrop = 'pxOptFrameDrop';
  static const optVideoQueue = 'pxOptVideoQueue';
  static const optAudioQueue = 'pxOptAudioQueue';
  static const optNetTimeout = 'pxOptNetTimeout';
  static const optReadahead = 'pxOptReadahead';
  static const optSamplerate = 'pxOptSamplerate';
  static const optSwapchain = 'pxOptSwapchain';
  static const optFboFormat = 'pxOptFboFormat';
  static const optHrSeek = 'pxOptHrSeek';

  // 12 features
  static const featAspect = 'pxFeatAspect'; // str
  static const featRotate = 'pxFeatRotate'; // str
  static const featMirror = 'pxFeatMirror'; // flag
  static const featLoopEpisode = 'pxFeatLoopEpisode'; // flag
  static const featAudioDelay = 'pxFeatAudioDelay'; // num seconds
  static const featSubDelay = 'pxFeatSubDelay'; // num seconds
  static const featAudioTrack = 'pxFeatAudioTrack'; // str
  static const featSubTrack = 'pxFeatSubTrack'; // str
  static const featSecondSubTrack = 'pxFeatSecondSubTrack'; // str
  static const featEqualizer = 'pxFeatEqualizer'; // str
  static const featChannelMode = 'pxFeatChannelMode'; // str
  static const featBrightness = 'pxFeatBrightness'; // num -100..100
  static const featContrast = 'pxFeatContrast'; // num
  static const featSaturation = 'pxFeatSaturation'; // num

  // Batch 114: optLoudnorm / optDenoise / optNightAudio were
  // removed — their filters (loudnorm, hqdn3d, dynaudnorm) are not
  // compiled into the bundled libmpv, so the switches could never
  // do anything. Stored values for the old keys are inert leftovers.
  static const flagKeys = [
    optDisplaySync, optInterpolation, optLowPowerDecode, optPrebuffer,
    optReconnect, optSeekableCache, optDeband,
    optSharpen, optFullRange, optHdrToneMap,
    optDownmix, optBlendSubs, optFrameDrop,
    optVideoQueue, optAudioQueue, optNetTimeout, optReadahead,
    optSamplerate, optSwapchain, optFboFormat, optHrSeek,
    featMirror, featLoopEpisode,
  ];

  static const numKeys = [
    featAudioDelay, featSubDelay, featBrightness, featContrast,
    featSaturation,
  ];

  static const numDefaults = <String, double>{
    featAudioDelay: 0,
    featSubDelay: 0,
    featBrightness: 0,
    featContrast: 0,
    featSaturation: 0,
  };

  static const strKeys = [
    featAspect, featRotate, featAudioTrack, featSubTrack,
    featSecondSubTrack, featEqualizer, featChannelMode,
  ];

  static const strDefaults = <String, String>{
    featAspect: 'auto',
    featRotate: '0',
    featAudioTrack: 'auto',
    featSubTrack: 'auto',
    featSecondSubTrack: 'no',
    featEqualizer: 'off',
    featChannelMode: 'normal',
  };
}
