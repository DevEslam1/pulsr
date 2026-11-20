// test/data/audio/native_dsd_session_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/native_dsd_producer.dart';
import 'package:pulsr/data/audio/native_dsd_session.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';

class MockUsbExclusiveService extends UsbExclusiveService {
  MockUsbExclusiveService() : super.forTest();
  bool isStreamingStarted = false;
  bool isStreamingStopped = false;
  double? lastHardwareVolume;
  final List<Uint8List> writtenLeft = [];
  final List<Uint8List> writtenRight = [];
  bool failWrites = false;
  bool dsdActiveState = true;

  @override
  Future<bool> startDsdStreaming(DsdAltSettingTuple tuple, {bool strict = true}) async {
    isStreamingStarted = true;
    return true;
  }

  @override
  Future<bool> stopStreaming() async {
    isStreamingStopped = true;
    isStreamingStarted = false;
    return true;
  }

  @override
  Future<bool> writeDsd(Uint8List left, Uint8List right, {int producerId = 0}) async {
    if (failWrites) return false;
    writtenLeft.add(left);
    writtenRight.add(right);
    return true;
  }

  @override
  Future<bool> isDsdActive() async => dsdActiveState;

  @override
  Future<bool> setHardwareVolume(double position) async {
    lastHardwareVolume = position;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Native DSD Session & Producer (§8.2)', () {
    late MockUsbExclusiveService mockUsb;
    late NativeDsdProducer producer;

    setUp(() {
      mockUsb = MockUsbExclusiveService();
      producer = NativeDsdProducer(
        service: mockUsb,
        backpressureDelay: Duration.zero,
      );
    });

    test('exact tuple selection rejects non-matching rates without first-tuple fallback', () {
      const caps = DsdDacCapabilities(
        dsd64: true,
        dsd128: false,
        dsd256: false,
        dop: true,
        nativeDac: true,
        nativeDsd: true,
        nativeAltSettings: [
          DsdAltSettingTuple(
            interfaceNumber: 1,
            altSetting: 2,
            endpointAddress: 0x01,
            channels: 2,
            bytesPerSample: 4,
            framesPerSecond: 88200,
            dsdRate: 64,
          ),
        ],
      );

      // DSD64 matches exactly
      final tuple64 = NativeDsdProducer.selectProbedTuple(caps, 64);
      expect(tuple64, isNotNull);
      expect(tuple64?.dsdRate, 64);

      // DSD128 has NO exact tuple: must return null instead of falling back to DSD64
      final tuple128 = NativeDsdProducer.selectProbedTuple(caps, 128);
      expect(tuple128, isNull, reason: 'Must not use first-tuple fallback for mismatched DSD rate');

      // Zero or invalid rate returns null
      expect(NativeDsdProducer.selectProbedTuple(caps, 0), isNull);
      expect(NativeDsdProducer.selectProbedTuple(caps, -1), isNull);
    });

    test('seek alignment enforces 4-byte boundaries for 32-bit DSD_U32 words', () {
      final left = Uint8List(1000);
      final right = Uint8List(1000);
      producer.prepare(left: left, right: right, dsdRate: 64);

      // Seek to 10 ms (at DSD64 = 2,822,400 bits/sec = 352,800 bytes/sec -> 3,528 bytes)
      producer.seek(const Duration(milliseconds: 10));
      expect(producer.currentByteOffset % 4, 0, reason: 'Must align to 4-byte boundary');

      // Seek to 33 ms -> 11,642.4 bytes -> must be floored to multiple of 4
      producer.seek(const Duration(milliseconds: 33));
      expect(producer.currentByteOffset % 4, 0, reason: 'Must align to 4-byte boundary');
    });

    test('pause feeds DC-neutral DSD silence pattern (alternating 0x69/0x96)', () async {
      final left = Uint8List(100000);
      final right = Uint8List(100000);
      producer.prepare(left: left, right: right, dsdRate: 64);

      // Start pumping and pause
      final pumping = producer.startPumping(chunkSize: 512);
      producer.pause();

      expect(producer.isPaused, isTrue);
      expect(mockUsb.writtenLeft, isNotEmpty);

      // Verify DC-neutral DSD silence block generation
      final silence = NativeDsdProducer.dsdSilenceBlock(64);
      expect(silence.length, 64);
      expect(silence[0], 0x69);
      expect(silence[1], 0x96);
      expect(silence[2], 0x69);
      expect(silence[3], 0x96);

      await producer.stop();
      await pumping;
    });

    test('xrun counter increments and triggers fallback halt after max retries', () async {
      mockUsb.failWrites = true; // force backpressure / write failure
      mockUsb.dsdActiveState = true;
      final left = Uint8List(4096);
      final right = Uint8List(4096);
      producer.prepare(left: left, right: right, dsdRate: 64);

      // Start pumping with failed writes
      await producer.startPumping(chunkSize: 512);

      expect(producer.state, NativeDsdProducerState.stopped);
      expect(producer.xrunCount, greaterThanOrEqualTo(NativeDsdProducer.kMaxXrunsBeforeFallback));
    });

    test('volume policy delegates to hardware volume only when enabled', () async {
      final session = NativeDsdSession(usb: mockUsb, producer: producer);
      expect(session.capabilities.canSoftwareVolume, isFalse);

      // Hardware volume disabled: setVolume is a no-op
      session.setHardwareVolumeEnabled(false);
      await session.setVolume(0.5);
      expect(mockUsb.lastHardwareVolume, isNull);

      // Hardware volume enabled: setVolume delegates to USB service
      session.setHardwareVolumeEnabled(true);
      await session.setVolume(0.75);
      expect(mockUsb.lastHardwareVolume, 0.75);

      await session.dispose();
      expect(mockUsb.isStreamingStopped, isTrue);
    });

    test('bit reversal accurately swaps MSB-first DFF bits to LSB-first DSF order', () {
      // 0b10000000 (0x80) -> 0b00000001 (0x01)
      // 0b11000000 (0xC0) -> 0b00000011 (0x03)
      // 0b10101010 (0xAA) -> 0b01010101 (0x55)
      final input = Uint8List.fromList([0x80, 0xC0, 0xAA, 0x0F]);
      final reversed = NativeDsdProducer.reverseBits(input);
      expect(reversed[0], 0x01);
      expect(reversed[1], 0x03);
      expect(reversed[2], 0x55);
      expect(reversed[3], 0xF0);
    });
  });
}
