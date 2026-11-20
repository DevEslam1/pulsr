// test/data/audio/hrtf_binaural_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AudioEffectsChannel channel;
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/audio_effects'),
      (MethodCall call) async {
        log.add(call);
        switch (call.method) {
          case 'loadHrtfSofa':
            final args = call.arguments as Map?;
            final path = args?['path'] as String?;
            return path != null && path.endsWith('.sofa');
          case 'loadHrtfIr':
            return true;
          case 'getHrtfLatencyFrames':
            return 0;
          default:
            return true;
        }
      },
    );

    channel = AudioEffectsChannel();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/audio_effects'),
      null,
    );
  });

  group('HRTF Binaural channel tests', () {
    test('setHrtfBinauralEnabled dispatches correctly', () async {
      await channel.setHrtfBinauralEnabled(true);
      expect(log.length, equals(1));
      expect(log.first.method, equals('setHrtfBinauralEnabled'));
      expect(log.first.arguments, equals({'enabled': true}));

      await channel.setHrtfBinauralEnabled(false);
      expect(log.length, equals(2));
      expect(log.last.arguments, equals({'enabled': false}));
    });

    test('setHrtfAzimuth dispatches target angle', () async {
      await channel.setHrtfAzimuth(45.0);
      expect(log.length, equals(1));
      expect(log.first.method, equals('setHrtfAzimuth'));
      expect(log.first.arguments, equals({'azimuth': 45.0}));
    });

    test('setHrtfElevation dispatches target elevation', () async {
      await channel.setHrtfElevation(15.0);
      expect(log.length, equals(1));
      expect(log.first.method, equals('setHrtfElevation'));
      expect(log.first.arguments, equals({'elevation': 15.0}));
    });

    test('loadHrtfSofa invokes with valid path', () async {
      final ok = await channel.loadHrtfSofa('/path/to/test.sofa');
      expect(ok, isTrue);
      expect(log.length, equals(1));
      expect(log.first.method, equals('loadHrtfSofa'));
      expect(log.first.arguments, equals({'path': '/path/to/test.sofa'}));
    });

    test('loadHrtfIr invokes with quad IRs', () async {
      final ll = List<double>.filled(64, 0.5);
      final lr = List<double>.filled(64, 0.2);
      final rl = List<double>.filled(64, 0.2);
      final rr = List<double>.filled(64, 0.5);

      final ok = await channel.loadHrtfIr(
        ll: ll,
        lr: lr,
        rl: rl,
        rr: rr,
        taps: 64,
        sampleRate: 48000.0,
      );

      expect(ok, isTrue);
      expect(log.length, equals(1));
      expect(log.first.method, equals('loadHrtfIr'));
      expect((log.first.arguments as Map)['taps'], equals(64));
    });

    test('getHrtfLatencyFrames queries native latency', () async {
      final latency = await channel.getHrtfLatencyFrames();
      expect(latency, equals(0));
      expect(log.length, equals(1));
      expect(log.first.method, equals('getHrtfLatencyFrames'));
    });
  });
}
