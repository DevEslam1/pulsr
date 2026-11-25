// test/data/audio/native_dsd_producer_test.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/native_dsd_producer.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';

class FakeUsbExclusiveService implements UsbExclusiveService {
  bool startDsdStreamingResult = true;
  DsdAltSettingTuple? lastStartedTuple;
  bool? lastStrict;

  int writeDsdCallCount = 0;
  List<Uint8List> writtenLeftChunks = [];
  List<Uint8List> writtenRightChunks = [];
  int backpressureFailCount = 0;
  bool isDsdActiveResult = true;
  bool stopStreamingCalled = false;

  @override
  Future<bool> startDsdStreaming(DsdAltSettingTuple tuple,
      {bool strict = true}) async {
    lastStartedTuple = tuple;
    lastStrict = strict;
    return startDsdStreamingResult;
  }

  @override
  Future<bool> writeDsd(Uint8List left, Uint8List right,
      {int producerId = 0}) async {
    writeDsdCallCount++;
    if (backpressureFailCount > 0) {
      backpressureFailCount--;
      return false;
    }
    writtenLeftChunks.add(Uint8List.fromList(left));
    writtenRightChunks.add(Uint8List.fromList(right));
    return true;
  }

  @override
  Future<bool> isDsdActive() async => isDsdActiveResult;

  @override
  Future<bool> stopStreaming() async {
    stopStreamingCalled = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('DsdAltSettingTuple', () {
    test('fromList parses 3, 5, and 7-element lists', () {
      final t3 = DsdAltSettingTuple.fromList([1, 2, 0x81]);
      expect(t3.interfaceNumber, 1);
      expect(t3.altSetting, 2);
      expect(t3.endpointAddress, 0x81);
      expect(t3.channels, 2);
      expect(t3.bytesPerSample, 4);
      expect(t3.framesPerSecond, 0);
      expect(t3.dsdRate, 0);

      final t7 = DsdAltSettingTuple.fromList([2, 3, 0x02, 2, 4, 176400, 128]);
      expect(t7.interfaceNumber, 2);
      expect(t7.altSetting, 3);
      expect(t7.endpointAddress, 0x02);
      expect(t7.channels, 2);
      expect(t7.bytesPerSample, 4);
      expect(t7.framesPerSecond, 176400);
      expect(t7.dsdRate, 128);
    });

    test('toMap produces complete map', () {
      const tuple = DsdAltSettingTuple(
        interfaceNumber: 1,
        altSetting: 2,
        endpointAddress: 0x01,
        channels: 2,
        bytesPerSample: 4,
        framesPerSecond: 88200,
        dsdRate: 64,
      );
      final map = tuple.toMap();
      expect(map['interfaceNumber'], 1);
      expect(map['altSetting'], 2);
      expect(map['endpoint'], 0x01);
      expect(map['channels'], 2);
      expect(map['bytesPerSample'], 4);
      expect(map['framesPerSecond'], 88200);
      expect(map['dsdRate'], 64);
    });
  });

  group('NativeDsdProducer.reverseBits', () {
    test('reverses bits within each byte accurately', () {
      final input = Uint8List.fromList([
        0x01, // 00000001 -> 10000000 = 0x80
        0x80, // 10000000 -> 00000001 = 0x01
        0xAA, // 10101010 -> 01010101 = 0x55
        0x55, // 01010101 -> 10101010 = 0xAA
        0xF0, // 11110000 -> 00001111 = 0x0F
        0x0F, // 00001111 -> 11110000 = 0xF0
        0xC3, // 11000011 -> 11000011 = 0xC3
        0x00, // 00000000 -> 00000000 = 0x00
        0xFF, // 11111111 -> 11111111 = 0xFF
      ]);
      final reversed = NativeDsdProducer.reverseBits(input);
      expect(reversed, [
        0x80,
        0x01,
        0x55,
        0xAA,
        0x0F,
        0xF0,
        0xC3,
        0x00,
        0xFF,
      ]);
    });
  });

  group('NativeDsdProducer.selectProbedTuple', () {
    const tuple64 = DsdAltSettingTuple(
      interfaceNumber: 1,
      altSetting: 1,
      endpointAddress: 1,
      framesPerSecond: 88200,
      dsdRate: 64,
    );
    const tuple128 = DsdAltSettingTuple(
      interfaceNumber: 1,
      altSetting: 2,
      endpointAddress: 1,
      framesPerSecond: 176400,
      dsdRate: 128,
    );
    const tupleFallback = DsdAltSettingTuple(
      interfaceNumber: 1,
      altSetting: 3,
      endpointAddress: 1,
      framesPerSecond: 352800,
      dsdRate: 0,
    );

    test('returns null when canUseNativeDsd is false', () {
      const caps = DsdDacCapabilities(
        dsd64: true,
        dsd128: false,
        dsd256: false,
        dop: true,
        nativeDac: false,
        nativeDsd: true,
        nativeAltSettings: [tuple64],
      );
      expect(NativeDsdProducer.selectProbedTuple(caps, 64), isNull);
    });

    test('returns null when nativeAltSettings is empty', () {
      const caps = DsdDacCapabilities(
        dsd64: true,
        dsd128: false,
        dsd256: false,
        dop: true,
        nativeDac: true,
        nativeDsd: true,
        nativeAltSettings: [],
      );
      expect(NativeDsdProducer.selectProbedTuple(caps, 64), isNull);
    });

    test('selects exact matching rate tuple', () {
      const caps = DsdDacCapabilities(
        dsd64: true,
        dsd128: true,
        dsd256: false,
        dop: true,
        nativeDac: true,
        nativeDsd: true,
        nativeAltSettings: [tuple64, tuple128],
      );
      final selected = NativeDsdProducer.selectProbedTuple(caps, 128);
      expect(selected, isNotNull);
      expect(selected!.altSetting, 2);
      expect(selected.dsdRate, 128);
    });

    test('never falls back to a mismatched tuple', () {
      const caps = DsdDacCapabilities(
        dsd64: true,
        dsd128: false,
        dsd256: false,
        dop: true,
        nativeDac: true,
        nativeDsd: true,
        nativeAltSettings: [tupleFallback],
      );
      // A DSD64 tuple must not play a DSD256 file at one quarter of its rate.
      expect(NativeDsdProducer.selectProbedTuple(caps, 256), isNull);
    });
  });

  group('NativeDsdProducer preparation & bit-order', () {
    late FakeUsbExclusiveService service;
    late NativeDsdProducer producer;

    setUp(() {
      service = FakeUsbExclusiveService();
      producer = NativeDsdProducer(service: service);
    });

    test('prepare with msbFirst=false leaves DSF LSB data untouched', () {
      final left = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final right = Uint8List.fromList([0x10, 0x20, 0x30, 0x40]);
      producer.prepare(
        left: left,
        right: right,
        dsdRate: 64,
        msbFirst: false,
      );

      expect(producer.totalBytes, 4);
      expect(producer.dsdRate, 64);
      expect(producer.currentByteOffset, 0);
      expect(producer.state, NativeDsdProducerState.idle);
      // Duration at DSD64: 4 bytes = 32 bits. 32 / (64 * 44100) = 32 / 2822400 s = ~11.33 us
      expect(producer.totalDuration.inMicroseconds, 11);
    });

    test('prepare with msbFirst=true reverses DFF MSB bits to LSB', () {
      final left = Uint8List.fromList([0x01, 0xAA]);
      final right = Uint8List.fromList([0x80, 0x55]);
      producer.prepare(
        left: left,
        right: right,
        dsdRate: 64,
        msbFirst: true,
      );

      // Now start streaming to observe the written chunks
      unawaited(producer.startPumping(chunkSize: 2));
      expect(service.writtenLeftChunks.isNotEmpty, isTrue);
      expect(service.writtenLeftChunks.first, [0x80, 0x55]);
      expect(service.writtenRightChunks.first, [0x01, 0xAA]);
    });

    test('prepare clamps channels to equal length', () {
      final left = Uint8List.fromList([1, 2, 3, 4, 5]);
      final right = Uint8List.fromList([1, 2, 3]);
      producer.prepare(
        left: left,
        right: right,
        dsdRate: 64,
      );
      expect(producer.totalBytes, 3);
    });
  });

  group('NativeDsdProducer openStream', () {
    late FakeUsbExclusiveService service;
    late NativeDsdProducer producer;

    setUp(() {
      service = FakeUsbExclusiveService();
      producer = NativeDsdProducer(service: service);
    });

    const tuple = DsdAltSettingTuple(
      interfaceNumber: 1,
      altSetting: 2,
      endpointAddress: 0x01,
      framesPerSecond: 88200,
      dsdRate: 64,
    );

    test('records activeTuple on success', () async {
      service.startDsdStreamingResult = true;
      final ok = await producer.openStream(tuple, strict: true);
      expect(ok, isTrue);
      expect(producer.activeTuple, tuple);
      expect(service.lastStartedTuple, tuple);
      expect(service.lastStrict, isTrue);
    });

    test('does not record activeTuple on failure', () async {
      service.startDsdStreamingResult = false;
      final ok = await producer.openStream(tuple, strict: false);
      expect(ok, isFalse);
      expect(producer.activeTuple, isNull);
    });
  });

  group('NativeDsdProducer pumping & backpressure', () {
    late FakeUsbExclusiveService service;
    late NativeDsdProducer producer;

    setUp(() {
      service = FakeUsbExclusiveService();
      producer = NativeDsdProducer(service: service);
    });

    test('pumps multiple chunks in order and completes', () async {
      final left = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final right = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      producer.prepare(
        left: left,
        right: right,
        dsdRate: 64,
      );

      await producer.startPumping(chunkSize: 4);

      expect(producer.state, NativeDsdProducerState.completed);
      expect(producer.currentByteOffset, 8);
      expect(service.writtenLeftChunks.length, 2);
      expect(service.writtenLeftChunks[0], [1, 2, 3, 4]);
      expect(service.writtenLeftChunks[1], [5, 6, 7, 8]);
      expect(service.writtenRightChunks[0], [10, 20, 30, 40]);
      expect(service.writtenRightChunks[1], [50, 60, 70, 80]);
    });

    test('retries on backpressure without losing data', () async {
      final left = Uint8List.fromList([1, 2, 3, 4]);
      final right = Uint8List.fromList([10, 20, 30, 40]);
      producer.prepare(
        left: left,
        right: right,
        dsdRate: 64,
      );

      // Simulate 2 backpressure rejections before success
      service.backpressureFailCount = 2;

      await producer.startPumping(chunkSize: 4);

      expect(service.writeDsdCallCount, 3); // 2 fails + 1 success
      expect(producer.state, NativeDsdProducerState.completed);
      expect(service.writtenLeftChunks.length, 1);
      expect(service.writtenLeftChunks[0], [1, 2, 3, 4]);
    });

    test('aborts when backpressure exceeds retry threshold and sink is dead',
        () async {
      final left = Uint8List.fromList(List.filled(100, 1));
      final right = Uint8List.fromList(List.filled(100, 2));
      producer.prepare(left: left, right: right, dsdRate: 64);

      service.backpressureFailCount = 250;
      service.isDsdActiveResult = false; // sink became inactive

      await producer.startPumping(chunkSize: 50);

      expect(producer.state, NativeDsdProducerState.stopped);
    });
  });

  group('NativeDsdProducer transport controls', () {
    late FakeUsbExclusiveService service;
    late NativeDsdProducer producer;

    setUp(() {
      service = FakeUsbExclusiveService();
      producer = NativeDsdProducer(service: service);
    });

    test('seek clamps to bounds and aligns to 4-byte DSD_U32 boundary', () {
      final left = Uint8List.fromList(List.filled(1000, 1));
      final right = Uint8List.fromList(List.filled(1000, 2));
      producer.prepare(
        left: left,
        right: right,
        dsdRate: 64, // 2,822,400 Hz = 352,800 bytes/sec
      );

      // Seek to 1 ms: targetBits = 1000 * 2822400 / 1000000 = 2822.4 bits = 352 bytes
      producer.seek(const Duration(milliseconds: 1));
      expect(producer.currentByteOffset % 4, 0);
      expect(producer.currentByteOffset, greaterThan(0));
      expect(producer.currentByteOffset, lessThanOrEqualTo(1000));

      // Seek past duration clamps to totalBytes
      producer.seek(const Duration(seconds: 100));
      expect(producer.currentByteOffset, 1000);

      // Seek before start clamps to 0
      producer.seek(const Duration(seconds: -1));
      expect(producer.currentByteOffset, 0);
    });

    test('pause and resume correctly pause and continue pumping', () async {
      final left = Uint8List.fromList(List.filled(200, 1));
      final right = Uint8List.fromList(List.filled(200, 2));
      producer.prepare(
        left: left,
        right: right,
        dsdRate: 64,
      );

      // Pause immediately
      producer.pause();
      expect(
          producer.state,
          NativeDsdProducerState
              .idle); // was idle, pause only affects streaming

      // Start pumping in background
      final pumpFuture = producer.startPumping(chunkSize: 20);
      expect(producer.isRunning, isTrue);

      producer.pause();
      expect(producer.isPaused, isTrue);
      expect(producer.state, NativeDsdProducerState.paused);

      // Resume
      producer.resume();
      expect(producer.isPaused, isFalse);

      await pumpFuture;
      expect(producer.state, NativeDsdProducerState.completed);
      expect(producer.currentByteOffset, 200);
    });

    test('stop terminates pumping and calls service.stopStreaming', () async {
      final left = Uint8List.fromList(List.filled(1000, 1));
      final right = Uint8List.fromList(List.filled(1000, 2));
      producer.prepare(
        left: left,
        right: right,
        dsdRate: 64,
      );

      final pumpFuture = producer.startPumping(chunkSize: 20);
      await producer.stop();
      await pumpFuture;

      expect(producer.state, NativeDsdProducerState.stopped);
      expect(service.stopStreamingCalled, isTrue);
    });
  });
}
