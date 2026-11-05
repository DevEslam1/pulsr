// test/data/audio/dsp_gain_reduction_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.audioEffects);
  late List<String> requested;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    requested = [];
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void stub(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      requested.add('${call.method}:${call.arguments is Map ? call.arguments['band'] : ''}');
      return handler(call);
    });
  }

  group('live gain reduction telemetry', () {
    test('the limiter reads its value', () async {
      stub((_) async => -2.5);
      expect(await AudioEffectsChannel().getLimiterGrDb(), -2.5);
    });

    test('a whole-number reply still reads (typed double would throw)',
        () async {
      // The native side can deliver 0 as an int; invokeMethod<double> throws on
      // that and the catch used to hide it, so GR silently always read 0.0.
      stub((_) async => 0);
      expect(await AudioEffectsChannel().getLimiterGrDb(), 0.0);
    });

    test('a failing channel reads as idle, not as an exception', () async {
      stub((_) async => throw PlatformException(code: 'boom'));
      expect(await AudioEffectsChannel().getLimiterGrDb(), 0.0);
    });

    test('band meters report the loudest band, not the first', () async {
      stub((call) async {
        final band = (call.arguments as Map)['band'] as int;
        return [-0.1, -4.7, -2.0, -0.3][band];
      });
      expect(await AudioEffectsChannel().getMultibandGrDb(), -4.7);
      expect(requested.length, 4, reason: 'every band must be sampled');
    });

    test('dynamic EQ uses the same worst-of-bands rule', () async {
      stub((call) async {
        final band = (call.arguments as Map)['band'] as int;
        return band == 2 ? -6.25 : -0.05;
      });
      expect(await AudioEffectsChannel().getDynEqGrDb(bandCount: 3), -6.25);
      expect(requested, ['getDynEqGrDb:0', 'getDynEqGrDb:1', 'getDynEqGrDb:2']);
    });

    test('non-Android reports idle without touching the channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      stub((_) async => -3.0);
      expect(await AudioEffectsChannel().getLimiterGrDb(), 0.0);
      expect(requested, isEmpty);
    });
  });
}
