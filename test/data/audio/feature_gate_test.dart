// test/data/audio/feature_gate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/playback_backend.dart';
import 'package:pulsr/data/audio/feature_gate.dart';

void main() {
  group('FeatureGate (Section 5.2 & Conflict Matrix Section 9)', () {
    const gate = FeatureGate();

    test('Remote backend blocks local DSP stages', () {
      final decision = gate.evaluate(
        AudioFeature.dsp,
        backend: BackendCapabilities.cast,
      );
      expect(decision.isBlocked, isTrue);
      expect(decision.reason, equals(FeatureBlockReason.remoteBackend));
      expect(decision.userMessage, contains('not applied to remote'));
    });

    test('Remote backend allows seek when backend capability supports it', () {
      final decision = gate.evaluate(
        AudioFeature.crossfade,
        backend: BackendCapabilities.cast,
      );
      expect(decision.isBlocked, isTrue);
      expect(decision.reason, equals(FeatureBlockReason.capabilityMissing));
    });

    test('Direct DSD domain blocks DSP, crossfade, and software volume', () {
      final dspDecision = gate.evaluate(
        AudioFeature.dsp,
        backend: BackendCapabilities.localDsd,
        isDsdMode: true,
      );
      expect(dspDecision.isBlocked, isTrue);
      expect(dspDecision.reason, equals(FeatureBlockReason.dsdDomain));

      final crossfadeDecision = gate.evaluate(
        AudioFeature.crossfade,
        backend: BackendCapabilities.localDsd,
        isDsdMode: true,
      );
      expect(crossfadeDecision.isBlocked, isTrue);

      final volumeDecision = gate.evaluate(
        AudioFeature.softwareVolume,
        backend: BackendCapabilities.localDsd,
        isDsdMode: true,
      );
      expect(volumeDecision.isBlocked, isTrue);
      expect(volumeDecision.reason, equals(FeatureBlockReason.dsdDomain));
    });

    test('Bit-perfect exclusivity blocks DSP', () {
      final dspDecision = gate.evaluate(
        AudioFeature.dsp,
        backend: BackendCapabilities.localPcm,
        bitPerfectActive: true,
      );
      expect(dspDecision.isBlocked, isTrue);
      expect(dspDecision.reason, equals(FeatureBlockReason.bitPerfectExclusivity));
    });

    test('Low-power interlock blocks low-power when DSP is active, and vice versa', () {
      final lowPowerDecision = gate.evaluate(
        AudioFeature.lowPower,
        backend: BackendCapabilities.localPcm,
        dspActive: true,
      );
      expect(lowPowerDecision.isBlocked, isTrue);
      expect(lowPowerDecision.reason, equals(FeatureBlockReason.lowPowerInterlock));

      final dspDecision = gate.evaluate(
        AudioFeature.dsp,
        backend: BackendCapabilities.localPcm,
        lowPowerActive: true,
      );
      expect(dspDecision.isBlocked, isTrue);
      expect(dspDecision.reason, equals(FeatureBlockReason.lowPowerInterlock));
    });

    test('HRTF and Crossfeed are mutually exclusive', () {
      final hrtfDecision = gate.evaluate(
        AudioFeature.hrtf,
        backend: BackendCapabilities.localPcm,
        crossfeedActive: true,
      );
      expect(hrtfDecision.isBlocked, isTrue);
      expect(hrtfDecision.reason, equals(FeatureBlockReason.hrtfCrossfeedExclusivity));

      final crossfeedDecision = gate.evaluate(
        AudioFeature.crossfeed,
        backend: BackendCapabilities.localPcm,
        hrtfActive: true,
      );
      expect(crossfeedDecision.isBlocked, isTrue);
      expect(crossfeedDecision.reason, equals(FeatureBlockReason.hrtfCrossfeedExclusivity));
    });

    test('Multichannel > 2 channels blocked on AAudio route', () {
      final mchDecision = gate.evaluate(
        AudioFeature.multichannel,
        backend: BackendCapabilities.localPcm,
        channels: 6,
        isAAudio: true,
      );
      expect(mchDecision.isBlocked, isTrue);
      expect(mchDecision.reason, equals(FeatureBlockReason.unsupportedRoute));
    });

    test('Clean LocalPCM path allows standard controls without conflicts', () {
      final dspDecision = gate.evaluate(
        AudioFeature.dsp,
        backend: BackendCapabilities.localPcm,
      );
      expect(dspDecision.isAllowed, isTrue);

      final crossfadeDecision = gate.evaluate(
        AudioFeature.crossfade,
        backend: BackendCapabilities.localPcm,
      );
      expect(crossfadeDecision.isAllowed, isTrue);
    });
  });
}
