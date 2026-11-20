// test/data/audio/native_dsd_session_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/native_dsd_producer.dart';
import 'package:pulsr/data/audio/native_dsd_session.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';

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
  UsbExclusiveStatus get lastStatus => const UsbExclusiveStatus(
        attached: true,
        permitted: true,
        streamingActive: true,
        hasVolumeControl: true,
        minVolumeDb: -60,
        maxVolumeDb: 0,
      );

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

Uint8List _dsfFixture({int blockSize = 8}) {
  final payloadLength = blockSize * 2;
  final total = 28 + 52 + 12 + payloadLength;
  final bytes = Uint8List(total);
  final data = ByteData.sublistView(bytes);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  ascii(0, 'DSD ');
  data.setUint64(4, 28, Endian.little);
  data.setUint64(12, total, Endian.little);
  data.setUint64(20, 0, Endian.little);

  const fmt = 28;
  ascii(fmt, 'fmt ');
  data.setUint64(fmt + 4, 52, Endian.little);
  data.setUint32(fmt + 12, 1, Endian.little);
  data.setUint32(fmt + 16, 0, Endian.little);
  data.setUint32(fmt + 20, 2, Endian.little);
  data.setUint32(fmt + 24, 2, Endian.little);
  data.setUint32(fmt + 28, 2822400, Endian.little);
  data.setUint32(fmt + 32, 1, Endian.little);
  data.setUint64(fmt + 36, blockSize * 8, Endian.little);
  data.setUint32(fmt + 44, blockSize, Endian.little);
  data.setUint32(fmt + 48, 0, Endian.little);

  final dataChunk = fmt + 52;
  ascii(dataChunk, 'data');
  data.setUint64(dataChunk + 4, 12 + payloadLength, Endian.little);
  for (var i = 0; i < payloadLength; i++) {
    bytes[dataChunk + 12 + i] = i.isEven ? 0x69 : 0x96;
  }
  return bytes;
}

const _nativeCaps = DsdDacCapabilities(
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

      // Hardware volume enabled: the 0..1 UI position is mapped linearly
      // across the DAC's real dB range (0 max, -60 min), never sent raw.
      session.setHardwareVolumeEnabled(true);
      await session.setVolume(0.75);
      expect(mockUsb.lastHardwareVolume, closeTo(-15.0, 0.01));

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

  group('NativeDsdSession lifecycle (§8.2)', () {
    late MockUsbExclusiveService mockUsb;
    late NativeDsdProducer producer;
    late NativeDsdSession session;
    late Directory tempDir;
    late String dsfPath;

    setUp(() async {
      AudioQualityInfo.dsdNativeActive = false;
      AudioQualityInfo.dsdDopActive = false;
      mockUsb = MockUsbExclusiveService();
      producer = NativeDsdProducer(
        service: mockUsb,
        backpressureDelay: Duration.zero,
      );
      session = NativeDsdSession(
        usb: mockUsb,
        producer: producer,
        capabilitiesProvider: () async => _nativeCaps,
      );
      tempDir = await Directory.systemTemp.createTemp('pulsr_dsd_session_');
      dsfPath = '${tempDir.path}${Platform.pathSeparator}track.dsf';
      await File(dsfPath).writeAsBytes(_dsfFixture(blockSize: 256));
    });

    tearDown(() async {
      await session.dispose();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
      AudioQualityInfo.dsdNativeActive = false;
      AudioQualityInfo.dsdDopActive = false;
    });

    test('prepare parses the header and holds the stream paused', () async {
      await session.preparePath(dsfPath, autoPlay: false);
      expect(session.isPrepared, isTrue);
      expect(mockUsb.isStreamingStarted, isTrue);
      expect(producer.activeTuple?.dsdRate, 64);
      expect(producer.state, NativeDsdProducerState.paused);
      expect(session.duration, greaterThan(Duration.zero));
      // No real block yet while loaded-paused.
      expect(producer.firstBlockWritten, isFalse);
      expect(AudioQualityInfo.dsdNativeActive, isFalse);
    });

    test('status flips only after the first real block and completes once', () async {
      final active = Completer<void>();
      final completed = Completer<void>();
      session.onNativeActive = () {
        if (!active.isCompleted) active.complete();
      };
      session.completedStream.listen((_) {
        if (!completed.isCompleted) completed.complete();
      });

      await session.preparePath(dsfPath, autoPlay: false);
      await session.play();
      await active.future.timeout(const Duration(seconds: 2));
      expect(producer.firstBlockWritten, isTrue);
      expect(AudioQualityInfo.dsdNativeActive, isTrue);
      await completed.future.timeout(const Duration(seconds: 2));
      expect(session.nativeStatusActive, isTrue);
    });

    test('stream death raises the fallback signal and clears the native claim', () async {
      mockUsb.failWrites = true;
      mockUsb.dsdActiveState = false;
      final fallback = Completer<Duration>();
      session.onFallbackRequired = (position) {
        if (!fallback.isCompleted) fallback.complete(position);
      };

      await session.preparePath(dsfPath, autoPlay: true);
      await fallback.future.timeout(const Duration(seconds: 3));
      expect(producer.fallbackRequested, isTrue);
      expect(AudioQualityInfo.dsdNativeActive, isFalse);
      expect(session.nativeStatusActive, isFalse);
    });

    test('a mismatched tuple is refused instead of played at the wrong rate', () async {
      final mismatched = NativeDsdSession(
        usb: mockUsb,
        producer: producer,
        capabilitiesProvider: () async => const DsdDacCapabilities(
          dsd64: true,
          dsd128: true,
          dsd256: false,
          dop: true,
          nativeDac: true,
          nativeDsd: true,
          nativeAltSettings: [
            DsdAltSettingTuple(
              interfaceNumber: 1,
              altSetting: 3,
              endpointAddress: 0x01,
              channels: 2,
              bytesPerSample: 4,
              framesPerSecond: 176400,
              dsdRate: 128,
            ),
          ],
        ),
      );
      await expectLater(
        mismatched.preparePath(dsfPath),
        throwsA(isA<DsdFallbackRequiredException>()),
      );
      await mismatched.dispose();
      expect(mockUsb.isStreamingStarted, isFalse);
    });

    test('stop releases the USB stream', () async {
      await session.preparePath(dsfPath, autoPlay: false);
      await session.stop();
      expect(mockUsb.isStreamingStopped, isTrue);
      expect(session.isPrepared, isFalse);
    });
  });
}
