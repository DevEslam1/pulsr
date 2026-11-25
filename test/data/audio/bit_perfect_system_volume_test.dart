import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

void main() {
  test('aaudioTargetBufferMs defaults to 120 ms to prevent exclusive XRuns',
      () {
    const state = SettingsState();
    expect(state.aaudioTargetBufferMs, 120);
  });

  test(
      'shouldForwardSystemVolumeToOutput forwards only when OS mixer is bypassed',
      () {
    // Normal shared AudioTrack: OS STREAM_MUSIC already scales hardware output.
    expect(
      PulsrAudioHandler.shouldForwardSystemVolumeToOutput(
        bitPerfectBypass: false,
        aaudioOutputEnabled: false,
        directUsbStreaming: false,
      ),
      isFalse,
    );

    // Bit-perfect bypass (Android 14+ direct mixer / exclusive route).
    expect(
      PulsrAudioHandler.shouldForwardSystemVolumeToOutput(
        bitPerfectBypass: true,
        aaudioOutputEnabled: false,
        directUsbStreaming: false,
      ),
      isTrue,
    );

    // AAudio Exclusive output.
    expect(
      PulsrAudioHandler.shouldForwardSystemVolumeToOutput(
        bitPerfectBypass: false,
        aaudioOutputEnabled: true,
        directUsbStreaming: false,
      ),
      isTrue,
    );

    // Direct USB exclusive transfer.
    expect(
      PulsrAudioHandler.shouldForwardSystemVolumeToOutput(
        bitPerfectBypass: false,
        aaudioOutputEnabled: false,
        directUsbStreaming: true,
      ),
      isTrue,
    );
  });

  test('a mode transition seeds even before the preference is written', () {
    // The Bit-Perfect preference is saved after the native transition. The
    // seed decision must not read that stale "off" value and skip, or the new
    // sink starts at unity while the device volume is lower.
    expect(
      PulsrAudioHandler.shouldSeedSystemVolume(
        isAndroid: true,
        dvcEnabled: false,
        hardwareVolumeOwnsOutput: false,
        forwardSystemVolume: false,
        forceSeed: true,
      ),
      isTrue,
    );
    expect(
      PulsrAudioHandler.shouldSeedSystemVolume(
        isAndroid: true,
        dvcEnabled: false,
        hardwareVolumeOwnsOutput: true,
        forwardSystemVolume: true,
        externalHardwareVolumeSet: true,
        forceSeed: true,
      ),
      isTrue,
    );
  });

  test('a speaker volume reading cannot seed a live Direct USB stream', () {
    expect(
      PulsrAudioHandler.systemVolumeReadingBelongsToRoute(
        directUsbStreaming: true,
        routeKnown: true,
        isUsb: false,
      ),
      isFalse,
    );
    expect(
      PulsrAudioHandler.systemVolumeReadingBelongsToRoute(
        directUsbStreaming: true,
        routeKnown: true,
        isUsb: true,
      ),
      isTrue,
    );
    // Unknown route: keep the previous level rather than guessing.
    expect(
      PulsrAudioHandler.systemVolumeReadingBelongsToRoute(
        directUsbStreaming: true,
        routeKnown: false,
        isUsb: false,
      ),
      isTrue,
    );
    expect(
      PulsrAudioHandler.systemVolumeReadingBelongsToRoute(
        directUsbStreaming: false,
        routeKnown: true,
        isUsb: false,
      ),
      isTrue,
    );
  });

  test('route-tagged readings parse both the map and legacy scalar', () {
    final tagged = SystemMusicVolumeReading.fromNative(<String, Object?>{
      'ratio': 0.81,
      'routeKnown': true,
      'isUsb': true,
      'deviceId': 462,
    });
    expect(tagged.ratio, closeTo(0.81, 0.0001));
    expect(tagged.routeKnown, isTrue);
    expect(tagged.isUsb, isTrue);
    expect(tagged.deviceId, 462);
    expect(tagged.isKnown, isTrue);

    final legacy = SystemMusicVolumeReading.fromNative(0.5);
    expect(legacy.ratio, 0.5);
    expect(legacy.routeKnown, isFalse);

    final failed = SystemMusicVolumeReading.fromNative(null);
    expect(failed.isKnown, isFalse);
  });

  group('shouldSeedSystemVolume', () {
    test(
        'skips when not on Android, when DVC owns gain, or when OS mixer owns output',
        () {
      expect(
        PulsrAudioHandler.shouldSeedSystemVolume(
          isAndroid: false,
          dvcEnabled: false,
          hardwareVolumeOwnsOutput: false,
          forwardSystemVolume: true,
        ),
        isFalse,
      );
      expect(
        PulsrAudioHandler.shouldSeedSystemVolume(
          isAndroid: true,
          dvcEnabled: true,
          hardwareVolumeOwnsOutput: false,
          forwardSystemVolume: true,
        ),
        isFalse,
      );
      expect(
        PulsrAudioHandler.shouldSeedSystemVolume(
          isAndroid: true,
          dvcEnabled: false,
          hardwareVolumeOwnsOutput: false,
          forwardSystemVolume: false,
        ),
        isFalse,
      );
    });

    test(
        'seeds on Android when output bypasses OS mixer and DAC hardware volume does not own gain',
        () {
      expect(
        PulsrAudioHandler.shouldSeedSystemVolume(
          isAndroid: true,
          dvcEnabled: false,
          hardwareVolumeOwnsOutput: false,
          forwardSystemVolume: true,
        ),
        isTrue,
      );
    });

    test(
        'preserves external USB hardware slider across normal loads, but seeds fresh stream startup',
        () {
      expect(
        PulsrAudioHandler.shouldSeedSystemVolume(
          isAndroid: true,
          dvcEnabled: false,
          hardwareVolumeOwnsOutput: true,
          forwardSystemVolume: true,
        ),
        isFalse,
      );
      expect(
        PulsrAudioHandler.shouldSeedSystemVolume(
          isAndroid: true,
          dvcEnabled: false,
          hardwareVolumeOwnsOutput: true,
          forwardSystemVolume: true,
          forceUsbHardwareSeed: true,
          externalHardwareVolumeSet: false,
        ),
        isTrue,
      );
      expect(
        PulsrAudioHandler.shouldSeedSystemVolume(
          isAndroid: true,
          dvcEnabled: false,
          hardwareVolumeOwnsOutput: true,
          forwardSystemVolume: true,
          forceUsbHardwareSeed: true,
          externalHardwareVolumeSet: true,
        ),
        isFalse,
      );
    });
  });
}
