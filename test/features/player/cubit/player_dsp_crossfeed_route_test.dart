// Unit + behavioural tests for route-gated crossfeed (fix #1) and codec-aware
// music compensation (fix #2) on PlayerDspController.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/player/cubit/controllers/player_dsp_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

import '../player_test_support.dart';

/// Records the crossfeed value actually pushed to the engine and reports it
/// back through [isCrossfeedEnabled] (the no-op dedup in the controller reads
/// that getter).
class CrossfeedHandler extends RecordingAudioHandler {
  bool _xfeed = false;
  bool _pref = false;
  bool? lastEnabled;
  bool? lastPref;

  @override
  bool get isCrossfeedEnabled => _xfeed;

  @override
  bool get crossfeedUserEnabled => _pref;

  @override
  bool get crossfeedEffectiveEnabled => _xfeed;

  @override
  Future<void> setCrossfeed(bool enabled,
      {double? delayUs,
      double? feedDb,
      double? fcut,
      int? mode,
      bool? preferenceEnabled}) async {
    calls.add('setCrossfeed');
    lastEnabled = enabled;
    lastPref = preferenceEnabled;
    _xfeed = enabled;
    if (preferenceEnabled != null) _pref = preferenceEnabled;
  }
}

/// Simulates a handler whose legacy [isCrossfeedEnabled] mirrors preference
/// while [crossfeedEffectiveEnabled] reflects the actual engine bypass state.
class _PrefSkewedCrossfeedHandler extends CrossfeedHandler {
  _PrefSkewedCrossfeedHandler(
      {required bool initialPref, required bool initialEffective}) {
    _pref = initialPref;
    _xfeed = initialEffective;
  }

  @override
  bool get isCrossfeedEnabled => _pref;

  @override
  bool get crossfeedEffectiveEnabled => _xfeed;
}

AudioOutputInfo device({
  String type = 'builtin',
  bool bluetooth = false,
  bool leAudio = false,
  bool usbDac = false,
  String? btCodecName,
}) =>
    AudioOutputInfo(
      deviceName: 'test-$type',
      isUsbDac: usbDac,
      sampleRate: 48000,
      bitDepth: 16,
      isBitPerfectActive: false,
      activeDeviceType: type,
      isBluetooth: bluetooth,
      isLeAudio: leAudio,
      btCodecName: btCodecName,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CrossfeedHandler handler;
  late MockSettingsCubit settings;
  late PlayerState state;
  late PlayerDspController controller;

  PlayerDspController build() => PlayerDspController(
        audioHandler: handler,
        settingsCubit: settings,
        getState: () => state,
        emit: (s) => state = s,
        syncAudioEffects: ({bool force = false}) {},
        isClosed: () => false,
      );

  void useDevice(AudioOutputInfo? d) {
    when(() => settings.state)
        .thenReturn(SettingsState(currentOutputDevice: d));
  }

  setUp(() {
    handler = CrossfeedHandler();
    settings = MockSettingsCubit();
    when(() => settings.state).thenReturn(const SettingsState());
    state = const PlayerState();
    controller = build();
  });

  group('routeWantsCrossfeed predicate', () {
    test('null route honours the preference', () {
      expect(PlayerDspController.routeWantsCrossfeed(null), isTrue);
    });
    test('bluetooth / le-audio / usb are headphone-like', () {
      expect(PlayerDspController.routeWantsCrossfeed(device(bluetooth: true)),
          isTrue);
      expect(
          PlayerDspController.routeWantsCrossfeed(
              device(type: 'ble', leAudio: true)),
          isTrue);
      expect(
          PlayerDspController.routeWantsCrossfeed(
              device(type: 'usb', usbDac: true)),
          isTrue);
    });
    test('wired headset is headphone-like', () {
      expect(PlayerDspController.routeWantsCrossfeed(device(type: 'wired')),
          isTrue);
    });
    test('built-in speaker / car / hdmi are bypassed', () {
      expect(PlayerDspController.routeWantsCrossfeed(device(type: 'builtin')),
          isFalse);
      expect(PlayerDspController.routeWantsCrossfeed(device(type: 'car')),
          isFalse);
      expect(PlayerDspController.routeWantsCrossfeed(device(type: 'hdmi')),
          isFalse);
    });
  });

  group('crossfeed route gating', () {
    test('speaker route: preference preserved, engine push gated off',
        () async {
      useDevice(device(type: 'builtin'));
      await controller.setCrossfeed(true, delayUs: 300, feedDb: -8.0, mode: 1);
      expect(state.isCrossfeedEnabled, isTrue); // stored preference kept
      expect(handler.lastEnabled, isFalse); // engine bypassed
    });

    test('headphone route: engine receives the enabled value', () async {
      useDevice(device(bluetooth: true));
      await controller.setCrossfeed(true);
      expect(state.isCrossfeedEnabled, isTrue);
      expect(handler.lastEnabled, isTrue);
    });

    test(
        'reevaluateCrossfeedForRoute bypasses then restores without touching '
        'the stored preference', () async {
      useDevice(device(bluetooth: true));
      await controller.setCrossfeed(true);
      expect(handler.lastEnabled, isTrue);

      await controller.reevaluateCrossfeedForRoute(device(type: 'builtin'));
      expect(state.isCrossfeedEnabled, isTrue); // preference untouched
      expect(handler.lastEnabled, isFalse); // engine bypassed on speaker

      await controller.reevaluateCrossfeedForRoute(device(bluetooth: true));
      expect(handler.lastEnabled, isTrue); // restored on headphones
    });

    test(
        'P1-10: reevaluateCrossfeedForRoute compares against crossfeedEffectiveEnabled '
        'even when isCrossfeedEnabled reflects preference', () async {
      final skewed = _PrefSkewedCrossfeedHandler(
        initialPref: true,
        initialEffective: false,
      );
      state = const PlayerState(dsp: DspSlice(isCrossfeedEnabled: true));
      final localController = PlayerDspController(
        audioHandler: skewed,
        settingsCubit: settings,
        getState: () => state,
        emit: (s) => state = s,
        syncAudioEffects: ({bool force = false}) {},
        isClosed: () => false,
      );
      addTearDown(localController.dispose);

      // Speaker route: effective wanted is false; engine is already bypassed
      // (crossfeedEffectiveEnabled == false), so do NOT push redundantly even
      // though isCrossfeedEnabled (preference) is true.
      await localController
          .reevaluateCrossfeedForRoute(device(type: 'builtin'));
      expect(skewed.calls, isEmpty);
      expect(state.isCrossfeedEnabled, isTrue);

      // Headphone route: effective wanted is true, engine is false -> MUST
      // push restore with preferenceEnabled: true!
      await localController
          .reevaluateCrossfeedForRoute(device(bluetooth: true));
      expect(skewed.calls, ['setCrossfeed']);
      expect(skewed.lastEnabled, isTrue);
      expect(skewed.lastPref, isTrue);
      expect(skewed.crossfeedEffectiveEnabled, isTrue);

      // Returning to speaker now sees effectiveEngine == true != false -> bypasses
      // while keeping preferenceEnabled == true.
      skewed.calls.clear();
      await localController
          .reevaluateCrossfeedForRoute(device(type: 'builtin'));
      expect(skewed.calls, ['setCrossfeed']);
      expect(skewed.lastEnabled, isFalse);
      expect(skewed.lastPref, isTrue);
      expect(state.isCrossfeedEnabled, isTrue);
    });
  });

  group('codec-aware music compensation', () {
    test('SBC lifts HF presence and LDAC reverses it', () async {
      state = PlayerState(
        dsp: const DspSlice().copyWith(
          eqPreset: flatPreset,
          isEqEnabled: false,
        ),
      );
      useDevice(device(bluetooth: true, btCodecName: 'SBC'));
      await controller.applyCodecAwareMusicCompensation();
      expect(state.isEqEnabled, isTrue); // forced on for the overlay
      expect(state.eqPreset.gains[7], closeTo(0.5, 1e-9)); // 4 kHz
      expect(state.eqPreset.gains[8], closeTo(0.5, 1e-9)); // 8 kHz
      // Other bands untouched.
      expect(state.eqPreset.gains[0], closeTo(0.0, 1e-9));

      // Switch to an ultra-high-quality codec: compensation is fully reversed.
      useDevice(device(bluetooth: true, btCodecName: 'LDAC'));
      await controller.applyCodecAwareMusicCompensation();
      expect(state.eqPreset.gains[7], closeTo(0.0, 1e-9));
      expect(state.eqPreset.gains[8], closeTo(0.0, 1e-9));
      expect(state.isEqEnabled, isFalse); // forced-on EQ handed back off
    });

    test('wired route applies no compensation', () async {
      state = PlayerState(
        dsp: const DspSlice().copyWith(
          eqPreset: flatPreset,
          isEqEnabled: false,
        ),
      );
      useDevice(device(type: 'wired'));
      await controller.applyCodecAwareMusicCompensation();
      expect(state.isEqEnabled, isFalse);
      expect(state.eqPreset.gains[7], closeTo(0.0, 1e-9));
    });

    test('preserves a user EQ edit while overlaying codec compensation',
        () async {
      state = PlayerState(
        dsp: const DspSlice().copyWith(
          eqPreset: flatPreset.copyWith(
            gains: const [3, 0, 0, 0, 0, 0, 0, 2, 0, 0],
          ),
          isEqEnabled: true,
        ),
      );
      useDevice(device(bluetooth: true, btCodecName: 'SBC'));
      await controller.applyCodecAwareMusicCompensation();
      expect(state.eqPreset.gains[0], closeTo(3.0, 1e-9)); // user edit kept
      expect(state.eqPreset.gains[7], closeTo(2.5, 1e-9)); // 2.0 + 0.5 comp
      expect(state.eqPreset.gains[8], closeTo(0.5, 1e-9));
    });
  });
}
