import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'handler_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late FakeJustAudioPlatform platform;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  late List<double> directUsbGains;
  PulsrAudioHandler? handler;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platform = FakeJustAudioPlatform();
    JustAudioPlatform.instance = platform;
    installHandlerChannelStubs();
    directUsbGains = <double>[];
    repo = MockMusicRepository();
    stubDefaultRepository(repo);
    ytm = MockYtmService();
    stubDefaultYtm(ytm);
  });

  tearDown(() async {
    await handler?.dispose();
    handler = null;
    removeHandlerChannelStubs();
    JustAudioPlatform.instance = originalPlatform;
  });

  test('stopping Direct USB resets the native software gain to unity',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);

    // Record the direct-USB software gain after the harness has finished its
    // own init-time effects calls.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async {
        if (call.method == 'setDirectUsbVolume') {
          final args = call.arguments as Map?;
          final gain = (args?['gain'] as num?)?.toDouble();
          if (gain != null) directUsbGains.add(gain);
        }
        return true;
      },
    );

    UsbExclusiveService().debugPublishStatus(UsbExclusiveStatus.fromMap({
      'attached': true,
      'permitted': true,
      'streamingActive': true,
      'deviceId': 7,
    }));
    await pumpEventQueue();

    // Lower the volume while the direct stream owns output; the handler
    // forwards it to the native software gain.
    await handler!.setVolume(0.4);
    await pumpEventQueue();
    expect(directUsbGains, isNotEmpty,
        reason: 'a live direct USB stream applies the app volume');
    expect(directUsbGains.last, closeTo(0.4, 1e-6));

    // The native DSP also applies directUsbGain on the ordinary path, so a
    // stale 0.4 (or 0.0) would attenuate or mute playback after disabling
    // Bit-Perfect. Stopping the stream must push unity.
    UsbExclusiveService().debugPublishStatus(UsbExclusiveStatus.fromMap({
      'attached': true,
      'permitted': true,
      'streamingActive': false,
    }));
    await pumpEventQueue();

    expect(directUsbGains.last, 1.0);
  });
}
