import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/player/player_enhance.dart';

Map<String, String> build({
  Map<String, bool> flags = const {},
  Map<String, double> nums = const {},
  Map<String, String> strs = const {},
}) =>
    PlayerEnhance.buildProperties(flags: flags, nums: nums, strs: strs);

void main() {
  group('player enhance profile (batch 16)', () {
    test('empty profile produces no properties (stock behavior)', () {
      expect(build(), isEmpty);
    });

    test('there are exactly 21 optimization flags and 12 features', () {
      const opts = [
        PlayerEnhanceKeys.optDisplaySync, PlayerEnhanceKeys.optInterpolation,
        PlayerEnhanceKeys.optLowPowerDecode, PlayerEnhanceKeys.optPrebuffer,
        PlayerEnhanceKeys.optReconnect, PlayerEnhanceKeys.optSeekableCache,
        PlayerEnhanceKeys.optDeband,
        PlayerEnhanceKeys.optSharpen,
        PlayerEnhanceKeys.optFullRange, PlayerEnhanceKeys.optHdrToneMap,
        PlayerEnhanceKeys.optDownmix,
        PlayerEnhanceKeys.optBlendSubs, PlayerEnhanceKeys.optFrameDrop,
        PlayerEnhanceKeys.optVideoQueue, PlayerEnhanceKeys.optAudioQueue,
        PlayerEnhanceKeys.optNetTimeout, PlayerEnhanceKeys.optReadahead,
        PlayerEnhanceKeys.optSamplerate, PlayerEnhanceKeys.optSwapchain,
        PlayerEnhanceKeys.optFboFormat, PlayerEnhanceKeys.optHrSeek,
      ];
      expect(opts.toSet().length, 21);
      expect(
        PlayerEnhanceKeys.flagKeys
            .where((k) => k.startsWith('pxOpt'))
            .length,
        21,
      );
      // 12 features: 7 string pickers + 2 switches + delay sliders
      // (2) + picture group (3 sliders, one feature surface).
      expect(PlayerEnhanceKeys.strKeys.length, 7);
      expect(PlayerEnhanceKeys.numKeys.length, 5);
    });

    test('af chain keeps the app scaletempo baseline at its head', () {
      final props =
          build(strs: {PlayerEnhanceKeys.featEqualizer: 'bass'});
      expect(props['af'], startsWith('scaletempo2=max-speed=8,'));
      expect(props['af'], contains('equalizer=frequency=110'));
    });

    test('vf features compose into one chain', () {
      final props = build(flags: {
        PlayerEnhanceKeys.featMirror: true,
      });
      expect(props['vf'], 'mirror');
    });

    test('sharpening is a renderer property, not a vf filter', () {
      final props = build(flags: {PlayerEnhanceKeys.optSharpen: true});
      expect(props['sharpen'], '0.5');
      expect(props['vf'], isNull);
    });

    test('stream-lavf-o entries merge into one option', () {
      final props = build(flags: {
        PlayerEnhanceKeys.optReconnect: true,
        PlayerEnhanceKeys.optNetTimeout: true,
      });
      expect(props['stream-lavf-o'], contains('reconnect=1'));
      expect(props['stream-lavf-o'], contains('timeout=20000000'));
    });

    test('feature values map to properties', () {
      final props = build(
        strs: {
          PlayerEnhanceKeys.featAspect: 'fill',
          PlayerEnhanceKeys.featRotate: '90',
          PlayerEnhanceKeys.featSubTrack: 'no',
          PlayerEnhanceKeys.featSecondSubTrack: '2',
        },
        nums: {PlayerEnhanceKeys.featAudioDelay: 0.25},
        flags: {PlayerEnhanceKeys.featLoopEpisode: true},
      );
      expect(props['panscan'], '1.0');
      expect(props['video-aspect-override'], isNull);
      expect(props['video-rotate'], '90');
      expect(props['sid'], 'no');
      expect(props['sub-visibility'], 'no');
      expect(props['secondary-sid'], '2');
      expect(props['audio-delay'], '0.25');
      expect(props['loop-file'], 'inf');
    });
  });
}
