import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/interruption_state_machine.dart';
import 'package:pulsr/data/audio/native_dsd_producer.dart';
import 'package:pulsr/data/audio/native_dsd_session.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';

class _MockUsbExclusiveService extends UsbExclusiveService {
  _MockUsbExclusiveService() : super.forTest();
  bool isStreamingStarted = false;
  bool isStreamingStopped = false;
  final List<Uint8List> writtenLeft = [];
  final List<Uint8List> writtenRight = [];

  @override
  UsbExclusiveStatus get lastStatus => const UsbExclusiveStatus(
        attached: true,
        permitted: true,
        streamingActive: true,
      );

  @override
  Future<bool> startDsdStreaming(DsdAltSettingTuple tuple,
      {bool strict = true}) async {
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
  Future<bool> writeDsd(Uint8List left, Uint8List right,
      {int producerId = 0}) async {
    writtenLeft.add(left);
    writtenRight.add(right);
    return true;
  }

  @override
  Future<bool> isDsdActive() async => true;
}

Uint8List _createDsfFixture({int blockSize = 8}) {
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

  group('Native DSD Focus Loss & Becoming Noisy Pause', () {
    late _MockUsbExclusiveService mockUsb;
    late NativeDsdProducer producer;
    late NativeDsdSession session;
    late Directory tempDir;
    late String dsfPath;

    setUp(() async {
      mockUsb = _MockUsbExclusiveService();
      producer = NativeDsdProducer(
        service: mockUsb,
        backpressureDelay: Duration.zero,
      );
      session = NativeDsdSession(
        usb: mockUsb,
        producer: producer,
        capabilitiesProvider: () async => _nativeCaps,
      );
      tempDir = await Directory.systemTemp.createTemp('dsd_focus_noisy_');
      dsfPath = '${tempDir.path}${Platform.pathSeparator}sample.dsf';
      await File(dsfPath).writeAsBytes(_createDsfFixture(blockSize: 256));
    });

    tearDown(() async {
      await session.dispose();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
      DsdDecoderHelper.dsdNativeActive = false;
      DsdDecoderHelper.dsdDopActive = false;
    });

    test('session pauses and emits playing: false on pause request', () async {
      await session.preparePath(dsfPath, autoPlay: false);
      await session.play();

      final states = <bool>[];
      final sub = session.stateStream.listen((state) {
        states.add(state.playing);
      });

      // Session is currently playing
      expect(producer.isPaused, isFalse);

      // Audio focus loss / becomingNoisy triggers session.pause()
      await session.pause();

      expect(producer.isPaused, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(states, contains(false));

      await sub.cancel();
    });

    test(
        'InterruptionStateMachine accurately tracks interruption with effectivelyPlaying DSD',
        () {
      final machine = InterruptionStateMachine();

      // Native DSD is active & playing -> isEffectivelyPlaying is true
      const nativeDsdActive = true;
      const nativeDsdPlaying = true;
      const activePlayerPlaying =
          false; // standard player is idle because DSD bypasses it
      final isEffectivelyPlaying =
          activePlayerPlaying || (nativeDsdActive && nativeDsdPlaying);
      expect(isEffectivelyPlaying, isTrue);

      // 1. Audio focus interruption begins (phone call / pause interruption)
      machine.begin(InterruptionKind.pause, playing: isEffectivelyPlaying);

      expect(machine.isActive, isTrue);
      expect(machine.wasPlayingBeforeInterruption, isTrue,
          reason:
              'Must capture that Native DSD was actively playing before interruption');

      // 2. Interruption ends -> resume is approved
      final shouldResume = machine.end(InterruptionKind.pause);
      expect(shouldResume, isTrue);
      expect(machine.isActive, isFalse);
    });

    test(
        'Audio focus loss / pause does not approve resume if effectivelyPlaying was false',
        () {
      final machine = InterruptionStateMachine();

      const nativeDsdActive = true;
      const nativeDsdPlaying = false; // DSD already paused
      const activePlayerPlaying = false;
      final isEffectivelyPlaying =
          activePlayerPlaying || (nativeDsdActive && nativeDsdPlaying);
      expect(isEffectivelyPlaying, isFalse);

      machine.begin(InterruptionKind.pause, playing: isEffectivelyPlaying);
      expect(machine.wasPlayingBeforeInterruption, isFalse);
      expect(machine.end(InterruptionKind.pause), isFalse);
    });
  });
}
