// test/data/audio/dsd_transport_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dsd_transport_resolver.dart';

void main() {
  DsdTransportPlan resolve({
    String mode = 'dop',
    bool bitPerfect = true,
    bool dop = true,
    bool native = true,
    int rate = 64,
  }) =>
      resolveDsdTransport(
        mode: mode,
        bitPerfectActive: bitPerfect,
        dopCapable: dop,
        nativeCapable: native,
        dsdRateMultiple: rate,
      );

  group('PCM request', () {
    test('always decodes to PCM regardless of capabilities', () {
      for (final bitPerfect in [true, false]) {
        for (final dop in [true, false]) {
          for (final native in [true, false]) {
            final plan = resolve(
              mode: 'pcm',
              bitPerfect: bitPerfect,
              dop: dop,
              native: native,
            );
            expect(plan.transport, DsdTransport.pcm);
            expect(plan.reason, DsdTransportReason.userPcm);
            expect(plan.isFallback, isFalse);
          }
        }
      }
    });

    test('unknown mode strings are treated as PCM', () {
      final plan = resolve(mode: 'something-else');
      expect(plan.transport, DsdTransport.pcm);
      expect(plan.requested, DsdTransport.pcm);
    });
  });

  group('DoP request', () {
    test('is honoured only with a bit-perfect pipeline and a carrier', () {
      final plan = resolve(mode: 'dop');
      expect(plan.transport, DsdTransport.dop);
      expect(plan.reason, DsdTransportReason.selected);
      expect(plan.isFallback, isFalse);
    });

    test('falls back to PCM when the DSP chain is not bypassed', () {
      final plan = resolve(mode: 'dop', bitPerfect: false);
      expect(plan.transport, DsdTransport.pcm);
      expect(plan.reason, DsdTransportReason.requiresBitPerfect);
      expect(plan.isFallback, isTrue);
    });

    test('falls back to PCM when the DAC advertises no DoP carrier', () {
      final plan = resolve(mode: 'dop', dop: false);
      expect(plan.transport, DsdTransport.pcm);
      expect(plan.reason, DsdTransportReason.deviceLacksDop);
    });

    test('never upgrades to Native DSD even when the DAC supports it', () {
      final plan = resolve(mode: 'dop', bitPerfect: false, native: true);
      expect(plan.transport, DsdTransport.pcm);
    });

    test('has no carrier above DSD256', () {
      final at256 = resolve(mode: 'dop', rate: 256);
      expect(at256.transport, DsdTransport.dop);

      final at512 = resolve(mode: 'dop', rate: 512, native: true);
      expect(at512.transport, DsdTransport.pcm);
      expect(at512.reason, DsdTransportReason.noDopCarrierAtRate);
    });

    test('an unreadable DSD rate decodes to PCM instead of guessing', () {
      final plan = resolve(mode: 'dop', rate: 0);
      expect(plan.transport, DsdTransport.pcm);
      expect(plan.reason, DsdTransportReason.unknownDsdRate);
    });
  });

  group('Native DSD request', () {
    test('is honoured on a native-capable DAC', () {
      final plan = resolve(mode: 'native');
      expect(plan.transport, DsdTransport.native);
      expect(plan.isNative, isTrue);
      expect(plan.isFallback, isFalse);
    });

    test('uses native above DSD256 where DoP has no carrier', () {
      final plan = resolve(mode: 'native', rate: 512);
      expect(plan.transport, DsdTransport.native);
    });

    test('falls back to DoP when the DAC is not named DSD-capable', () {
      final plan = resolve(mode: 'native', native: false, dop: true, rate: 128);
      expect(plan.transport, DsdTransport.dop);
      expect(plan.reason, DsdTransportReason.deviceLacksNativeDsd);
      expect(plan.isFallback, isTrue);
    });

    test('falls back to DoP when the pipeline is not bit-perfect', () {
      final plan = resolve(mode: 'native', bitPerfect: false, rate: 64);
      expect(plan.transport, DsdTransport.dop);
      expect(plan.reason, DsdTransportReason.requiresBitPerfect);
    });

    test('falls straight to PCM when neither native nor DoP is usable', () {
      final plan = resolve(mode: 'native', native: false, dop: false);
      expect(plan.transport, DsdTransport.pcm);
      expect(plan.reason, DsdTransportReason.deviceLacksNativeDsd);
    });

    test('falls to PCM when native fails and the rate has no DoP carrier', () {
      final plan = resolve(mode: 'native', native: false, rate: 512);
      expect(plan.transport, DsdTransport.pcm);
    });
  });
}
