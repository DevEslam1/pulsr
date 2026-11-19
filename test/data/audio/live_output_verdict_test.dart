// test/data/audio/live_output_verdict_test.dart
//
// The shared live-chain fold. Its reason to exist is that the audio-quality
// sheet and the per-track session log each built these facts by hand and
// drifted: the log only consulted `dsp.isDspActive`, so a dithered, panned,
// ReplayGain-scaled or DVC-attenuated chain was recorded as a verified
// bit-perfect session while the sheet called the same stream unverified.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/live_output_verdict.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/bit_perfect_state.dart';

/// 96 kHz / 24-bit FLAC reaching an exclusive USB sink at the same format,
/// with an observed integer bypass. Every fact a verified chain needs holds
/// unless the test overrides it.
const AudioOutputInfo _usbDac = AudioOutputInfo(
  deviceName: 'Topping D90',
  isUsbDac: true,
  sampleRate: 96000,
  bitDepth: 24,
  isBitPerfectActive: true,
  sinkSampleRate: 96000,
  sinkBitDepth: 24,
  integerBypassActive: true,
);

LiveOutputObservation _observation({
  AudioOutputInfo? output = _usbDac,
  bool dspEffectsActive = false,
  bool channelBalanceActive = false,
  bool ditherActive = false,
  bool replayGainActive = false,
  bool dvcActive = false,
  bool bypassDspOnBitPerfect = true,
  bool strictBitPerfect = false,
  int taggedSampleRate = 96000,
  int taggedBitDepth = 24,
  String? codec = 'FLAC',
  String path = '/music/track.flac',
  bool isRadioSource = false,
  double? softwareGain = 1.0,
  bool transportSamplesModified = false,
  bool directStreamingActive = false,
  int streamingSampleRate = 0,
  int streamingBitDepth = 0,
  int rawPcmBitDepth = 0,
  bool rateVerified = true,
}) =>
    LiveOutputObservation(
      output: output,
      directStreamingActive: directStreamingActive,
      streamingSampleRate: streamingSampleRate,
      streamingBitDepth: streamingBitDepth,
      rawPcmBitDepth: rawPcmBitDepth,
      rateVerified: rateVerified,
      taggedSampleRate: taggedSampleRate,
      taggedBitDepth: taggedBitDepth,
      codec: codec,
      path: path,
      isRadioSource: isRadioSource,
      bitPerfectOutput: true,
      strictBitPerfect: strictBitPerfect,
      bypassDspOnBitPerfect: bypassDspOnBitPerfect,
      dspEffectsActive: dspEffectsActive,
      channelBalanceActive: channelBalanceActive,
      ditherActive: ditherActive,
      replayGainActive: replayGainActive,
      dvcActive: dvcActive,
      transportSamplesModified: transportSamplesModified,
      softwareGain: softwareGain,
    );

void main() {
  group('resolveLiveOutputVerdict', () {
    test('a clean integer route is the only active tier', () {
      final verdict = resolveLiveOutputVerdict(_observation());

      expect(verdict.state.tier, BitPerfectTier.active);
      expect(verdict.state.isVerified, isTrue);
      expect(verdict.sourceSampleRate, 96000);
      expect(verdict.sourceBitDepth, 24);
      expect(verdict.dspBypassed, isTrue);
    });

    test('dither is a sample edit, never a verified chain', () {
      final verdict = resolveLiveOutputVerdict(_observation(
        ditherActive: true,
        bypassDspOnBitPerfect: false,
      ));

      expect(verdict.state.tier, isNot(BitPerfectTier.active));
      expect(verdict.state.reasonCode, 'samples_modified');
    });

    test('a channel balance or mono fold is a sample edit', () {
      final verdict = resolveLiveOutputVerdict(_observation(
        channelBalanceActive: true,
        bypassDspOnBitPerfect: false,
      ));

      expect(verdict.state.tier, isNot(BitPerfectTier.active));
      expect(verdict.state.reasonCode, 'samples_modified');
    });

    test('ReplayGain is a sample edit, never a verified chain', () {
      final verdict = resolveLiveOutputVerdict(_observation(
        replayGainActive: true,
        bypassDspOnBitPerfect: false,
      ));

      expect(verdict.state.tier, isNot(BitPerfectTier.active));
      expect(verdict.state.reasonCode, 'samples_modified');
    });

    test('a DVC gain stage is a sample edit, never a verified chain', () {
      final verdict = resolveLiveOutputVerdict(_observation(
        dvcActive: true,
        bypassDspOnBitPerfect: false,
      ));

      expect(verdict.state.tier, isNot(BitPerfectTier.active));
      expect(verdict.state.reasonCode, 'samples_modified');
    });

    test('stages the Bit-Perfect guardrail bypassed are not edits', () {
      // Bit-Perfect + bypass ON mutes every stage, so an enabled EQ, dither or
      // DVC is not in the audible path. Bypass OFF puts them back in.
      final bypassed = resolveLiveOutputVerdict(_observation(
        dspEffectsActive: true,
        ditherActive: true,
        dvcActive: true,
      ));
      expect(bypassed.state.tier, BitPerfectTier.active);
      expect(bypassed.dspBypassed, isTrue);

      final live = resolveLiveOutputVerdict(_observation(
        dspEffectsActive: true,
        bypassDspOnBitPerfect: false,
      ));
      expect(live.state.tier, isNot(BitPerfectTier.active));
      expect(live.state.reasonCode, 'samples_modified');
    });

    test('the wider of tag and decoder probe is the source depth', () {
      final verdict = resolveLiveOutputVerdict(_observation(
        taggedBitDepth: 16,
        output: const AudioOutputInfo(
          deviceName: 'Topping D90',
          isUsbDac: true,
          sampleRate: 96000,
          bitDepth: 24,
          isBitPerfectActive: true,
          sinkSampleRate: 96000,
          sinkBitDepth: 24,
          integerBypassActive: true,
          decodedSampleRate: 96000,
          decodedBitDepth: 24,
        ),
      ));

      // A 16-bit tag on a 24-bit decoder grid must be judged at 24, or a
      // 16-bit output would report a verified match it never achieved.
      expect(verdict.sourceBitDepth, 24);
    });

    test('an unreadable gain never becomes unity', () {
      final verdict =
          resolveLiveOutputVerdict(_observation(softwareGain: null));

      expect(verdict.state.tier, isNot(BitPerfectTier.active));
      expect(verdict.state.reasonCode, 'software_gain_unknown');
    });

    test('a lossy source can never verify', () {
      final verdict = resolveLiveOutputVerdict(_observation(
        codec: 'MP3',
        path: '/music/track.mp3',
      ));

      expect(verdict.state.isVerified, isFalse);
      expect(verdict.sourceLossy, isTrue);
      expect(verdict.state.reasonCode, 'source_lossy');
    });

    test('the direct UAC2 sink reports the format it negotiated', () {
      final verdict = resolveLiveOutputVerdict(_observation(
        directStreamingActive: true,
        streamingSampleRate: 96000,
        streamingBitDepth: 24,
        rawPcmBitDepth: 24,
        output: const AudioOutputInfo(
          deviceName: 'Topping D90',
          isUsbDac: true,
          sampleRate: 96000,
          bitDepth: 24,
          // The HAL feed is not evidence while the direct sink owns the DAC.
          isBitPerfectActive: false,
          sinkSampleRate: 48000,
          sinkBitDepth: 16,
        ),
      ));

      expect(verdict.directUsbActive, isTrue);
      expect(verdict.state.assessment.outputSampleRate, 96000);
      expect(verdict.state.assessment.outputBitDepth, 24);
      expect(verdict.state.isVerified, isTrue);
    });

    test('an unverified rate readback keeps the chain unverified', () {
      final verdict = resolveLiveOutputVerdict(_observation(
        directStreamingActive: true,
        rawPcmBitDepth: 24,
        rateVerified: false,
      ));

      expect(verdict.state.isVerified, isFalse);
      expect(verdict.state.reasonCode, 'rate_not_verified');
    });
  });
}
