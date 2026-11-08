import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/player/player_enhance.dart';

Map<String, String> build({
  Map<String, bool> flags = const {},
  Map<String, double> nums = const {},
  Map<String, String> strs = const {},
}) =>
    PlayerEnhance.buildProperties(flags: flags, nums: nums, strs: strs);

void main() {
  group('batch114 dead enhance items removed', () {
    test('the retired filter keys produce nothing at all', () {
      // loudnorm / hqdn3d / dynaudnorm are not compiled into the
      // bundled libmpv; their switches were removed. Any stored
      // leftover values must stay inert.
      final props = build(flags: {
        'pxOptLoudnorm': true,
        'pxOptDenoise': true,
        'pxOptNightAudio': true,
      });
      expect(props, isEmpty);
      expect(PlayerEnhanceKeys.flagKeys, isNot(contains('pxOptLoudnorm')));
      expect(PlayerEnhanceKeys.flagKeys, isNot(contains('pxOptDenoise')));
      expect(PlayerEnhanceKeys.flagKeys, isNot(contains('pxOptNightAudio')));
    });

    test('no composed chain names a filter the build lacks', () {
      final props = build(
        flags: {
          PlayerEnhanceKeys.optSharpen: true,
          PlayerEnhanceKeys.featMirror: true,
        },
        strs: {
          PlayerEnhanceKeys.featEqualizer: 'voice',
          PlayerEnhanceKeys.featChannelMode: 'mono',
        },
      );
      final joined = props.values.join('|');
      for (final dead in [
        'hqdn3d',
        'unsharp',
        'loudnorm',
        'dynaudnorm',
        'hflip',
        'pan=',
        'bass=',
        'treble=',
      ]) {
        expect(joined, isNot(contains(dead)), reason: dead);
      }
    });
  });

  group('batch114 replacements are real properties/filters', () {
    test('equalizer presets use the peaking equalizer filter', () {
      expect(
        build(strs: {PlayerEnhanceKeys.featEqualizer: 'bass'})['af'],
        contains('equalizer=frequency=110:width_type=o:width=2:gain=10'),
      );
      expect(
        build(strs: {PlayerEnhanceKeys.featEqualizer: 'treble'})['af'],
        contains('equalizer=frequency=3500:width_type=o:width=2:gain=8'),
      );
      final voice = build(strs: {PlayerEnhanceKeys.featEqualizer: 'voice'});
      expect('equalizer'.allMatches(voice['af']!).length, 2);
    });

    test('mono is the audio-channels property and beats downmix stereo',
        () {
      final props = build(
        flags: {PlayerEnhanceKeys.optDownmix: true},
        strs: {PlayerEnhanceKeys.featChannelMode: 'mono'},
      );
      expect(props['audio-channels'], 'mono');
      expect(props['af'], isNull);
    });

    test('a stored swap value is inert now', () {
      final props =
          build(strs: {PlayerEnhanceKeys.featChannelMode: 'swap'});
      expect(props['audio-channels'], isNull);
      expect(props['af'], isNull);
    });

    test('mirror uses the internal mirror filter', () {
      expect(build(flags: {PlayerEnhanceKeys.featMirror: true})['vf'],
          'mirror');
    });
  });

  group('batch114 interpolation coupling', () {
    test('interpolation implies display-resample sync', () {
      final props = build(flags: {PlayerEnhanceKeys.optInterpolation: true});
      expect(props['interpolation'], 'yes');
      expect(props['video-sync'], 'display-resample');
      expect(props['tscale'], 'oversample');
    });

    test('display sync alone still sets the same sync mode', () {
      final props = build(flags: {PlayerEnhanceKeys.optDisplaySync: true});
      expect(props['video-sync'], 'display-resample');
      expect(props['interpolation'], isNull);
    });
  });
}
