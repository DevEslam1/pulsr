# Audio Architecture: Bit-Perfect, Modded just_audio & Audio Pipeline Wiring

Complete source code bundle for Pulsr's bit-perfect audio subsystem, modded `just_audio` Android ExoPlayer sink/DSP engine, and audio routing/wiring services for AI models.

---

## Table of Contents

- [lib/domain/boundaries.dart](#lib-domain-boundaries-dart)
- [lib/domain/services/hires_audio_service.dart](#lib-domain-services-hires-audio-service-dart)
- [lib/core/services/hires_audio_service.dart](#lib-core-services-hires-audio-service-dart)
- [lib/data/audio/collaborators/aaudio_output_controller.dart](#lib-data-audio-collaborators-aaudio-output-controller-dart)
- [lib/data/audio/output_format_negotiation.dart](#lib-data-audio-output-format-negotiation-dart)
- [lib/data/audio/dop_encoder.dart](#lib-data-audio-dop-encoder-dart)
- [lib/data/audio/dsd_decoder_helper.dart](#lib-data-audio-dsd-decoder-helper-dart)
- [third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/AAudioAudioSink.java](#third-party-just-audio-android-src-main-java-com-ryanheise-just-audio-aaudioaudiosink-java)
- [third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/AaudioNativeBridge.java](#third-party-just-audio-android-src-main-java-com-ryanheise-just-audio-aaudionativebridge-java)
- [third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/NativeDspAudioProcessor.java](#third-party-just-audio-android-src-main-java-com-ryanheise-just-audio-nativedspaudioprocessor-java)
- [third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/FloatDspAudioSink.java](#third-party-just-audio-android-src-main-java-com-ryanheise-just-audio-floatdspaudiosink-java)
- [third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/Pcm16Quantizer.java](#third-party-just-audio-android-src-main-java-com-ryanheise-just-audio-pcm16quantizer-java)
- [third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/PulsrOutputRouting.java](#third-party-just-audio-android-src-main-java-com-ryanheise-just-audio-pulsroutputrouting-java)
- [third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/AudioPlayer.java](#third-party-just-audio-android-src-main-java-com-ryanheise-just-audio-audioplayer-java)
- [third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/JustAudioPlugin.java](#third-party-just-audio-android-src-main-java-com-ryanheise-just-audio-justaudioplugin-java)
- [lib/core/di/injection.dart](#lib-core-di-injection-dart)
- [lib/data/audio/audio_handler.dart](#lib-data-audio-audio-handler-dart)
- [lib/data/audio/audio_handler_dsp_bridge.dart](#lib-data-audio-audio-handler-dsp-bridge-dart)
- [lib/data/audio/audio_session_id_router.dart](#lib-data-audio-audio-session-id-router-dart)
- [lib/data/audio/multi_output_router.dart](#lib-data-audio-multi-output-router-dart)
- [lib/data/audio/collaborators/float_output_controller.dart](#lib-data-audio-collaborators-float-output-controller-dart)
- [lib/data/audio/collaborators/playback_volume_controller.dart](#lib-data-audio-collaborators-playback-volume-controller-dart)

---

## `lib/domain/boundaries.dart`

```dart
// lib/domain/boundaries.dart
// FIX-A3: Bounded Context Map documenting cross-feature boundaries and typed communication

import 'package:flutter/foundation.dart';
import '../data/db/app_database.dart';
import 'models/audio_output_info.dart';

/// Bounded Context Map:
/// Defines typed interfaces and contracts between distinct feature modules in Pulsr,
/// preventing ad-hoc, untyped or direct coupling between cubits.
///
/// 1. Player -> Settings (reads outputDevice, replayGain, bitPerfect)
/// 2. Player -> Library (toggleFavorite)
/// 3. Downloads -> Player (swapReconciledSong)
/// 4. Settings -> Player (crossfade duration push, DSP bypass)

/// Boundary contract: Player reading hardware output & DSP preferences from Settings.
abstract class IPlayerSettingsBoundary {
  /// Currently selected audio output device, or null for system default.
  AudioOutputInfo? get outputDevice;

  /// Whether bit-perfect output mode is active.
  bool get bitPerfectEnabled;

  /// Whether DSP should be bypassed when bit-perfect mode is active.
  bool get bypassDspOnBitPerfect;

  /// Preamp gain in dB to apply for ReplayGain.
  double get replayGainPreamp;
}

/// Boundary contract: Player triggering library favorite status changes.
abstract class IPlayerLibraryBoundary {
  /// Toggles the favorite status of [song] in the user's library.
  Future<void> toggleFavorite(SongsTableData song);
}

/// Boundary contract: Downloads notifying player of completed offline reconciliation.
abstract class IDownloadPlayerBoundary {
  /// Swaps an in-memory stream track with its local downloaded counterpart [localSong].
  void swapReconciledSong(int oldSongId, SongsTableData localSong);
}

/// Boundary contract: Settings pushing audio transport & DSP settings to Player.
abstract class ISettingsPlayerBoundary {
  /// Updates the crossfade duration for track transitions.
  void setCrossfadeDuration(Duration duration);

  /// Notifies the audio engine of an output device change.
  void notifyOutputDeviceChanged(AudioOutputInfo? device);
}

/// Typed event representing an audio device change across feature contexts.
@immutable
class AudioDeviceChangedEvent {
  /// The newly connected or configured audio output device.
  final AudioOutputInfo? device;

  /// Monotonic or wall-clock creation timestamp.
  final DateTime timestamp;

  AudioDeviceChangedEvent(this.device) : timestamp = DateTime.now();
}

/// Typed event representing completed download reconciliation.
@immutable
class SongReconciledEvent {
  /// Identifier of the remote track prior to download.
  final int originalId;

  /// Reconciled local song record in the database.
  final SongsTableData localSong;

  const SongReconciledEvent(
      {required this.originalId, required this.localSong});
}
```

---

## `lib/domain/services/hires_audio_service.dart`

```dart
// lib/core/services/hires_audio_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import '../../domain/models/audio_output_info.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/platform_capabilities.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of a media-route change request.
class OutputRouteResult {
  final bool success;
  final String? error;
  final bool requiresSystemPicker;

  const OutputRouteResult({
    required this.success,
    this.error,
    this.requiresSystemPicker = false,
  });
}

@lazySingleton
class HiResAudioService {
  static const MethodChannel _methodChannel =
      MethodChannel(PulsrChannels.hiresDac);
  static const EventChannel _eventChannel =
      EventChannel(PulsrChannels.hiresDacEvents);

  final StreamController<AudioOutputInfo> _deviceController =
      StreamController<AudioOutputInfo>.broadcast();

  Stream<AudioOutputInfo> get outputDeviceStream => _deviceController.stream;
  StreamSubscription<dynamic>? _eventSubscription;
  AudioOutputInfo? _cachedOutputInfo;

  AudioOutputInfo? get currentOutputInfo => _cachedOutputInfo;

  /// Sample rates accepted by the native `setTargetOutputFormat` (0 = auto).
  /// The native side performs no validation of its own, so this set is the
  /// single gate that keeps an unsupported rate from being requested silently.
  static const Set<int> validTargetSampleRates = <int>{
    0,
    44100,
    48000,
    88200,
    96000,
    176400,
    192000,
    352800,
    384000,
    705600,
    768000,
  };

  /// Bit depths accepted by the native `setTargetOutputFormat` (0 = auto).
  /// 8.24 packed is deliberately absent: the native layer does not report it,
  /// so it is not offered rather than faked.
  static const Set<int> validTargetBitDepths = <int>{0, 16, 24, 32};

  /// The widest first-class sample-rate envelope Pulsr can request (T5).
  static const List<int> envelopeSampleRateLadder = <int>[
    44100,
    48000,
    88200,
    96000,
    176400,
    192000,
    352800,
    384000,
    705600,
    768000,
  ];

  /// T5 pure filter: only rates the current output actually reports as
  /// supported survive. [deviceSampleRates] comes from [AudioOutputInfo] while
  /// [directFormats] comes from Android's `isDirectPlaybackSupported` probe;
  /// either can carry a rate the other misses. No rate is ever invented.
  static List<int> supportedSampleRateOptions({
    required List<int> deviceSampleRates,
    required List<AudioDirectFormat> directFormats,
    List<int> ladder = envelopeSampleRateLadder,
  }) {
    final reported = <int>{
      ...deviceSampleRates.where((r) => r > 0),
      ...directFormats.where((f) => f.supported).map((f) => f.sampleRate),
    };
    final supported = ladder.where((rate) => reported.contains(rate)).toList()
      ..sort();
    return supported;
  }

  /// T2 pure decision: the track rate that should be pushed to the native
  /// output, or null when nothing should be sent. De-dupes against the last
  /// requested rate and never fights AVRCP on a Bluetooth route.
  static int? followTrackRateToApply({
    required int? trackSampleRate,
    required int? lastRequestedSampleRate,
    required bool isBluetooth,
    required bool followTrackEnabled,
  }) {
    if (!followTrackEnabled) return null;
    if (isBluetooth) return null;
    final rate = trackSampleRate;
    if (rate == null || rate <= 0) return null;
    if (rate == lastRequestedSampleRate) return null;
    if (!validTargetSampleRates.contains(rate)) return null;
    return rate;
  }

  HiResAudioService() {
    _init();
  }

  static bool _isSameOutputInfo(AudioOutputInfo a, AudioOutputInfo b) => a == b;

  void _init() {
    if (!PlatformCapabilities.isAndroid) return;
    try {
      _eventSubscription = _eventChannel
          .receiveBroadcastStream()
          .handleError((Object e, StackTrace st) {
        if (e is! MissingPluginException) {
          ErrorLogger.log('HiRes DAC event stream error',
              error: e, stackTrace: st, category: 'HiResAudio');
        }
      }).listen(
        (data) {
          if (data is Map) {
            final info = AudioOutputInfo.fromMap(data);
            // Deduplicate consecutive identical emissions. Compare every field a
            // consumer can observe: deduping on only name/rate/bit-perfect hid
            // route changes (Bluetooth codec, LE Audio, USB class) from device
            // profiles and the earbud/automation UI.
            if (_cachedOutputInfo != null &&
                _isSameOutputInfo(_cachedOutputInfo!, info)) {
              return;
            }
            _cachedOutputInfo = info;
            if (!_deviceController.isClosed) _deviceController.add(info);
          }
        },
        cancelOnError: false,
      );
      // Eagerly query current status
      unawaited(getAudioOutputInfo());
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize HiRes DAC listener',
          error: e, stackTrace: st, category: 'HiResAudio');
    }
  }

  Future<AudioOutputInfo> getAudioOutputInfo() async {
    if (!PlatformCapabilities.isAndroid) {
      const fb = AudioOutputInfo(
          deviceName: 'Default Audio Output',
          isUsbDac: false,
          sampleRate: 0,
          bitDepth: 0,
          isBitPerfectActive: false);
      _cachedOutputInfo = fb;
      return fb;
    }
    try {
      final Map<dynamic, dynamic>? res = await _methodChannel
          .invokeMapMethod<dynamic, dynamic>('getAudioOutputInfo')
          .timeout(const Duration(seconds: 3));
      if (res != null) {
        final info = AudioOutputInfo.fromMap(res);
        // Avoid duplicate stream emission if same as cached. Compare every
        // observable field via the same predicate the event listener uses, so
        // a force-refresh cannot republish a route change that only differs in
        // Bluetooth codec / LE Audio / USB class.
        final cached = _cachedOutputInfo;
        if (cached == null || !_isSameOutputInfo(cached, info)) {
          _cachedOutputInfo = info;
          if (!_deviceController.isClosed) _deviceController.add(info);
        } else {
          _cachedOutputInfo = info;
        }
        return info;
      }
    } catch (e, st) {
      if (e is! MissingPluginException || kDebugMode) {
        ErrorLogger.log('Failed to getAudioOutputInfo',
            error: e, stackTrace: st, category: 'HiResAudio');
      }
    }

    const fallback = AudioOutputInfo(
      deviceName: 'Default Audio Output',
      isUsbDac: false,
      sampleRate: 0,
      bitDepth: 0,
      isBitPerfectActive: false,
    );
    _cachedOutputInfo = fallback;
    return fallback;
  }

  /// Phase 4: per-format direct-playback capability probe (API 29+; older
  /// Android levels report every entry as unsupported - no fabricated claims).
  Future<List<AudioDirectFormat>> getDirectCapabilities() async {
    if (!PlatformCapabilities.isAndroid) return const [];
    try {
      final Map<dynamic, dynamic>? res = await _methodChannel
          .invokeMapMethod<dynamic, dynamic>('getDirectCapabilities')
          .timeout(const Duration(seconds: 3));
      final raw = res?['directFormats'];
      final out = <AudioDirectFormat>[];
      if (raw is List) {
        for (final d in raw) {
          if (d is Map) out.add(AudioDirectFormat.fromMap(d));
        }
      }
      return out;
    } catch (e, st) {
      ErrorLogger.log('Failed to getDirectCapabilities',
          error: e, stackTrace: st, category: 'HiResAudio');
      return const [];
    }
  }

  /// Phase 4: USB DAC diagnostics (advertised UAC version + label).
  /// Returns null when no audio USB device is present or off Android.
  Future<Map<String, Object?>?> getUsbDacCapabilities() async {
    if (!PlatformCapabilities.isAndroid) return null;
    try {
      return await _methodChannel
          .invokeMapMethod<String, Object?>('getUsbDacCapabilities')
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      ErrorLogger.log('Failed to getUsbDacCapabilities',
          error: e, stackTrace: st, category: 'HiResAudio');
      return null;
    }
  }

  Future<bool> isBitPerfectSupported() async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? supported = await _methodChannel
          .invokeMethod<bool>('isBitPerfectSupported')
          .timeout(const Duration(seconds: 2));
      return supported ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Why the last [setBitPerfectMode] enable attempt was rejected (native
  /// `lastBitPerfectReason`), or null when it succeeded. Captured BEFORE the
  /// rollback call below, which resets the native reason.
  String? lastBitPerfectFailureReason;

  Future<bool> setBitPerfectMode(bool enabled) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final Map<dynamic, dynamic>? res = await _methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('setBitPerfectModeDetailed',
              {'enabled': enabled}).timeout(const Duration(seconds: 8));
      final success = res?['success'] == true;
      lastBitPerfectFailureReason =
          success ? null : (res?['reason'] as String?);
      await getAudioOutputInfo();
      if (!success && enabled) {
        // Unsupported hardware: fall back to DSP path and refresh state so
        // the UI never shows bit-perfect as active when it isn't.
        ErrorLogger.log(
            'Bit-perfect rejected by device (${lastBitPerfectFailureReason ?? 'unknown'}) — falling back to DSP path',
            category: 'HiResAudio');
        try {
          await _methodChannel
              .invokeMethod<bool>('setBitPerfectMode', {'enabled': false});
        } catch (_) {}
        await getAudioOutputInfo();
        return false;
      }
      return success;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBitPerfectMode($enabled)',
          error: e, stackTrace: st, category: 'HiResAudio');
      lastBitPerfectFailureReason = 'channel_error';
      // Device may have disconnected mid-call — refresh so stale
      // bit-perfect state is never displayed.
      try {
        await getAudioOutputInfo();
      } catch (_) {}
      return false;
    }
  }

  /// Asks the platform to route media to [deviceId].
  ///
  /// Forcing the media route needs MODIFY_AUDIO_ROUTING, which only privileged
  /// builds hold, so `requiresSystemPicker` is the normal outcome on retail
  /// devices — hand the user [openOutputSwitcher] instead of reporting success.
  Future<OutputRouteResult> selectOutputDevice(int deviceId) async {
    if (!PlatformCapabilities.isAndroid) {
      return const OutputRouteResult(
          success: false, error: 'unsupported_platform');
    }
    try {
      final dynamic res = await _methodChannel.invokeMethod<dynamic>(
          'setOutputDevice',
          {'deviceId': deviceId}).timeout(const Duration(seconds: 8));
      await getAudioOutputInfo();
      if (res is Map) {
        return OutputRouteResult(
          success: (res['success'] as bool?) ?? false,
          error: res['error'] as String?,
          requiresSystemPicker: (res['requiresSystemPicker'] as bool?) ?? false,
        );
      }
      if (res is bool) return OutputRouteResult(success: res);
      return const OutputRouteResult(success: false, error: 'unknown_response');
    } catch (e, st) {
      ErrorLogger.log('Failed to selectOutputDevice($deviceId)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return const OutputRouteResult(success: false, error: 'channel_error');
    }
  }

  /// Opens Android's media output switcher — the sanctioned way for an
  /// unprivileged app to move the route.
  Future<bool> openOutputSwitcher() async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? ok = await _methodChannel
          .invokeMethod<bool>('openOutputSwitcher')
          .timeout(const Duration(seconds: 5));
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to openOutputSwitcher',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> clearOutputDevice() async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? success = await _methodChannel
          .invokeMethod<bool>('clearOutputDevice')
          .timeout(const Duration(seconds: 8));
      await getAudioOutputInfo();
      return success ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to clearOutputDevice',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> setTargetOutputFormat(
      {int sampleRate = 0, int bitDepth = 0}) async {
    if (!PlatformCapabilities.isAndroid) return false;
    // Validate before hitting native: 0 = auto, otherwise must be a sane
    // rate; bit depth must be 0 (auto), 16, 24 or 32.
    if (!validTargetSampleRates.contains(sampleRate)) {
      ErrorLogger.log('Rejected invalid sample rate $sampleRate',
          category: 'HiResAudio');
      return false;
    }
    if (!validTargetBitDepths.contains(bitDepth)) {
      ErrorLogger.log('Rejected invalid bit depth $bitDepth',
          category: 'HiResAudio');
      return false;
    }
    try {
      final bool? success = await _methodChannel.invokeMethod<bool>(
          'setTargetOutputFormat', {
        'sampleRate': sampleRate,
        'bitDepth': bitDepth
      }).timeout(const Duration(seconds: 8));
      await getAudioOutputInfo();
      return success ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setTargetOutputFormat($sampleRate, $bitDepth)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<void> requestBluetoothPermission() async {
    if (!PlatformCapabilities.isAndroid) return;
    try {
      // Android 12+: BLUETOOTH_CONNECT is a runtime permission. Try the
      // standard system dialog first; fall back to the native handler
      // (opens App Settings) when denied or permanently denied.
      var status = await Permission.bluetoothConnect.status;
      if (!status.isGranted) {
        status = await Permission.bluetoothConnect.request();
      }
      if (status.isGranted) return;
      await _methodChannel
          .invokeMethod<void>('requestBluetoothPermission')
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('requestBluetoothPermission failed',
          error: e, stackTrace: st, category: 'HiResAudio');
    }
  }

  Future<void> openBluetoothDevOptions() async {
    if (!PlatformCapabilities.isAndroid) return;
    try {
      await _methodChannel
          .invokeMethod<void>('openBluetoothDevOptions')
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('openBluetoothDevOptions failed',
          error: e, stackTrace: st, category: 'HiResAudio');
    }
  }

  // -- Bluetooth codec control --

  Future<bool> setBluetoothCodec(String codec) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? ok = await _methodChannel.invokeMethod<bool>(
          'setBluetoothCodec',
          {'codec': codec}).timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await getAudioOutputInfo();
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBluetoothCodec($codec)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> setBluetoothSampleRate(int hz) async {
    if (!PlatformCapabilities.isAndroid) return false;
    const validBtRates = <int>{44100, 48000, 88200, 96000, 176400, 192000};
    if (!validBtRates.contains(hz)) {
      ErrorLogger.log('Rejected invalid BT sample rate $hz',
          category: 'HiResAudio');
      return false;
    }
    try {
      final bool? ok = await _methodChannel.invokeMethod<bool>(
          'setBluetoothSampleRate',
          {'sampleRate': hz}).timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await getAudioOutputInfo();
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBluetoothSampleRate($hz)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> setBluetoothBitDepth(int bits) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? ok = await _methodChannel.invokeMethod<bool>(
          'setBluetoothBitDepth',
          {'bitDepth': bits}).timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await getAudioOutputInfo();
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBluetoothBitDepth($bits)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  Future<bool> setBluetoothLdacQuality(int mode) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      final bool? ok = await _methodChannel.invokeMethod<bool>(
          'setBluetoothLdacQuality',
          {'mode': mode}).timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await getAudioOutputInfo();
      return ok ?? false;
    } catch (e, st) {
      ErrorLogger.log('Failed to setBluetoothLdacQuality($mode)',
          error: e, stackTrace: st, category: 'HiResAudio');
      return false;
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    if (!_deviceController.isClosed) _deviceController.close();
  }
}
```

---

## `lib/core/services/hires_audio_service.dart`

```dart
﻿export '../../domain/services/hires_audio_service.dart';
```

---

## `lib/data/audio/collaborators/aaudio_output_controller.dart`

```dart
import 'package:just_audio/just_audio.dart';

/// Pushes the opt-in AAudio "Direct" output preference to every playback
/// player.
///
/// Default OFF: callers pass `false`, which keeps today's DefaultAudioSink
/// path (with the native DSP chain) untouched. When on, newly built sinks use
/// the native AAudio stream (bit-perfect; the DSP processor chain is
/// bypassed). Each [AudioPlayer.dspSetAaudioOutput] call is best-effort - a
/// player or platform that cannot honour the mode keeps the historical sink,
/// and this function never throws so a fan-out failure can never interrupt
/// playback.
Future<bool> pushAaudioOutputToPlayers(
  bool enabled, {
  bool preferExclusive = true,
  int targetBufferMs = 150,
  Iterable<AudioPlayer> players = const [],
}) async {
  var applied = true;
  for (final player in players) {
    try {
      final accepted = await player.dspSetAaudioOutput(
        enabled,
        preferExclusive: preferExclusive,
        targetBufferMs: targetBufferMs,
      );
      applied = accepted && applied;
    } catch (_) {
      applied = false;
    }
  }
  return applied;
}
```

---

## `lib/data/audio/output_format_negotiation.dart`

```dart
// lib/data/audio/output_format_negotiation.dart
//
// Pure, side-effect-free decision for the output format the engine should
// request for a track. Extracted from the manual, device-global setting so the
// policy can be unit-tested without a device, a platform channel or a player.
//
// Guarantees enforced here (and proven by the table test):
//   * the chosen format never exceeds the device's advertised caps;
//   * when there is no explicit user request, the track's native rate is
//     requested whenever the device supports it — a higher available tier is
//     never silently traded for a lower one;
//   * when the request cannot be honoured, the highest supported tier below it
//     is chosen and a machine-readable `reasonCode` is returned.
//
// The caller owns the side effect (calling `setTargetOutputFormat`); this file
// only decides.
import 'dart:math' as math;

import '../../domain/models/audio_output_info.dart';

/// Output route class the format is negotiated for.
enum OutputRoute {
  speaker,
  wired,
  bluetooth;

  /// Classifies an [AudioOutputInfo] the same way the session telemetry does.
  static OutputRoute fromOutputInfo(AudioOutputInfo? info) {
    if (info == null) return OutputRoute.speaker;
    final type = info.activeDeviceType.toLowerCase();
    if (info.isBluetooth ||
        info.isLeAudio ||
        type.contains('blue') ||
        type.contains('ble') ||
        type.contains('hearing')) {
      return OutputRoute.bluetooth;
    }
    if (info.isUsbDac ||
        type.contains('usb') ||
        type.contains('wired') ||
        type.contains('headphone') ||
        type.contains('headset')) {
      return OutputRoute.wired;
    }
    return OutputRoute.speaker;
  }
}

/// Stable reason codes for a negotiation outcome (safe to persist/log).
enum OutputFormatReason {
  /// Exclusive/bit-perfect output owns the format; the caller must not override.
  bitPerfectExclusive,

  /// No track or user preference known — take the device's best tier.
  autoDeviceDefault,

  /// The track's own rate was requested and the device supports it exactly.
  exactTrackMatch,

  /// An explicit user-selected rate was honoured.
  userRequested,

  /// The requested tier is not supported; the highest supported lower tier was
  /// chosen instead (never a lower one than necessary).
  deviceRateLimited,

  /// The user explicitly asked for a rate below the track's native rate.
  userRequestedBelowTrack,
}

/// Inputs for [negotiateOutputFormat].
class OutputFormatRequest {
  /// Native sample rate of the track; 0 when unknown.
  final int trackSampleRate;

  /// Native bit depth of the track; 0 when unknown.
  final int trackBitDepth;

  /// Explicit user target rate; 0 means "auto" (follow the track).
  final int requestedSampleRate;

  /// Explicit user target depth; 0 means "auto" (follow the track/caps).
  final int requestedBitDepth;

  const OutputFormatRequest({
    this.trackSampleRate = 0,
    this.trackBitDepth = 0,
    this.requestedSampleRate = 0,
    this.requestedBitDepth = 0,
  });
}

/// Result of a negotiation. [applied] is false only when the exclusive
/// bit-perfect path owns the format.
class OutputFormatDecision {
  final int sampleRate;
  final int bitDepth;
  final bool applied;
  final bool isBelowTrackRate;
  final bool isBelowTrackDepth;
  final OutputFormatReason reason;

  const OutputFormatDecision({
    required this.sampleRate,
    required this.bitDepth,
    required this.reason,
    this.applied = true,
    this.isBelowTrackRate = false,
    this.isBelowTrackDepth = false,
  });

  /// Stable machine name for logs / telemetry.
  String get reasonCode => reason.name;

  @override
  String toString() => 'OutputFormatDecision(${sampleRate}Hz/${bitDepth}bit, '
      'applied: $applied, reason: $reasonCode, '
      'belowTrackRate: $isBelowTrackRate, belowTrackDepth: $isBelowTrackDepth)';
}

/// Fallback caps when the platform reports no usable device information.
const List<int> kFallbackOutputSampleRates = <int>[44100, 48000];

/// Lossy Bluetooth transports top out at 96 kHz (LDAC); anything above is a
/// platform echo, not a sink the A2DP stack can actually feed.
const int kBluetoothMaxSampleRate = 96000;

/// Decides the output format to request. Pure: no I/O, no platform calls.
OutputFormatDecision negotiateOutputFormat({
  required OutputFormatRequest request,
  required List<int> deviceSampleRates,
  required int deviceMaxBitDepth,
  required OutputRoute route,
  required bool bitPerfectActive,
}) {
  final trackRate = request.trackSampleRate > 0 ? request.trackSampleRate : 0;
  final trackDepth = request.trackBitDepth > 0 ? request.trackBitDepth : 0;
  final explicitRate =
      request.requestedSampleRate > 0 ? request.requestedSampleRate : 0;
  final explicitDepth =
      request.requestedBitDepth > 0 ? request.requestedBitDepth : 0;

  // Bit-perfect / exclusive output negotiates its own mixer attributes; asking
  // the shared output format would fight it. Report the intent, applied:false.
  if (bitPerfectActive) {
    return OutputFormatDecision(
      sampleRate: explicitRate > 0 ? explicitRate : trackRate,
      bitDepth: explicitDepth > 0 ? explicitDepth : trackDepth,
      reason: OutputFormatReason.bitPerfectExclusive,
      applied: false,
    );
  }

  // Sanitize device caps (never trust 0 / out-of-range values).
  var rates = deviceSampleRates.where((r) => r > 0).toSet().toList()..sort();
  if (routesThroughBluetooth(route)) {
    rates = rates.where((r) => r <= kBluetoothMaxSampleRate).toList();
  }
  if (rates.isEmpty) {
    rates = List<int>.of(kFallbackOutputSampleRates);
  }
  var maxDepth = deviceMaxBitDepth;
  if (maxDepth != 16 && maxDepth != 24 && maxDepth != 32) maxDepth = 16;

  final desiredRate = explicitRate > 0 ? explicitRate : trackRate;
  int chosenRate;
  OutputFormatReason reason;
  if (desiredRate <= 0) {
    chosenRate = rates.last;
    reason = OutputFormatReason.autoDeviceDefault;
  } else if (rates.contains(desiredRate)) {
    chosenRate = desiredRate;
    if (explicitRate > 0) {
      reason = (trackRate > 0 && explicitRate < trackRate)
          ? OutputFormatReason.userRequestedBelowTrack
          : OutputFormatReason.userRequested;
    } else {
      reason = OutputFormatReason.exactTrackMatch;
    }
  } else {
    // Highest supported rate that does not exceed the request; if the request
    // is below every supported rate, the device cannot go lower.
    final atOrBelow = rates.where((r) => r <= desiredRate).toList();
    chosenRate = atOrBelow.isNotEmpty ? atOrBelow.last : rates.first;
    if (trackRate > 0 &&
        chosenRate < trackRate &&
        explicitRate > 0 &&
        explicitRate <= trackRate) {
      reason = OutputFormatReason.userRequestedBelowTrack;
    } else {
      reason = OutputFormatReason.deviceRateLimited;
    }
  }

  final desiredDepth = explicitDepth > 0 ? explicitDepth : trackDepth;
  var chosenDepth =
      desiredDepth <= 0 ? maxDepth : math.min(desiredDepth, maxDepth);
  if (chosenDepth != 16 && chosenDepth != 24 && chosenDepth != 32) {
    chosenDepth = 16;
  }

  return OutputFormatDecision(
    sampleRate: chosenRate,
    bitDepth: chosenDepth,
    reason: reason,
    isBelowTrackRate: trackRate > 0 && chosenRate < trackRate,
    isBelowTrackDepth: trackDepth > 0 && chosenDepth < trackDepth,
  );
}

/// True when the route's transport is lossy Bluetooth (rate-capped).
bool routesThroughBluetooth(OutputRoute route) =>
    route == OutputRoute.bluetooth;
```

---

## `lib/data/audio/dop_encoder.dart`

```dart
// lib/data/audio/dop_encoder.dart
import 'dart:typed_data';

/// Implements the DoP open standard (DSD over PCM v1.1 specification).
/// Wraps 16 bits of 1-bit DSD audio into 24-bit/32-bit PCM frames with alternating
/// 0x05 / 0xFA marker headers so that standard USB Audio Class 2.0 DACs can detect
/// and natively stream DSD without PCM conversion.
class DopEncoder {
  static const int dopMarkerA = 0x05;
  static const int dopMarkerB = 0xFA;

  /// The PCM carrier rate for a DSD file expressed as a multiple of 44.1 kHz
  /// (DSD64 = 64, DSD128 = 128, DSD256 = 256). DoP packs 16 DSD bits into one
  /// 24-bit PCM sample, so the carrier runs at `dsdRate * 44100 / 16`:
  /// DSD64 (2.8224 MHz) → 176.4 kHz, DSD128 → 352.8 kHz, DSD256 → 705.6 kHz.
  ///
  /// Returns 0 for rates DoP cannot carry (anything above DSD256), so callers
  /// fall back to PCM instead of inventing an unsupported carrier rate.
  static int dopPcmSampleRate(int dsdRate) {
    if (dsdRate <= 0) return 0;
    if (dsdRate <= 64) return 176400;
    if (dsdRate <= 128) return 352800;
    if (dsdRate <= 256) return 705600;
    return 0;
  }

  /// Encodes 1-bit DSD stereo stream (left & right byte channels) into 24-bit packed PCM or 32-bit aligned PCM.
  /// [dsdLeft] and [dsdRight] must have equal length (in bytes).
  /// Every 2 bytes of DSD (16 bits) are combined with an 8-bit alternating marker to form one 24-bit PCM sample per channel.
  static Uint8List encodeToDopPcm24({
    required Uint8List dsdLeft,
    required Uint8List dsdRight,
  }) {
    if (dsdLeft.length != dsdRight.length) {
      throw ArgumentError(
        'DSD channels must have equal length '
        '(left=${dsdLeft.length}, right=${dsdRight.length}). '
        'Refusing to silently truncate.',
      );
    }
    if (dsdLeft.length.isOdd) {
      throw ArgumentError('DSD byte length must be even (16-bit pairs).');
    }
    final int byteCount = dsdLeft.length;
    // Each 2 bytes of DSD yields 1 24-bit PCM sample (3 bytes) per channel (6 bytes per stereo frame).
    final int numSamplesPerChannel = byteCount ~/ 2;
    final Uint8List dopBuffer = Uint8List(numSamplesPerChannel * 6);

    int outOffset = 0;
    for (int i = 0; i < numSamplesPerChannel; i++) {
      final int marker = (i % 2 == 0) ? dopMarkerA : dopMarkerB;
      final int inOffset = i * 2;

      // DoP 1.1: the 24-bit word is [marker | older DSD byte | newer DSD
      // byte] (marker = bits 23..16, oldest DSD bit = MSB). Stored
      // little-endian that is: newer byte, older byte, marker. The previous
      // order (older, newer) swapped the two DSD bytes in every word, which a
      // DoP-capable DAC decodes as noise.
      dopBuffer[outOffset++] = dsdLeft[inOffset + 1];
      dopBuffer[outOffset++] = dsdLeft[inOffset];
      dopBuffer[outOffset++] = marker;

      dopBuffer[outOffset++] = dsdRight[inOffset + 1];
      dopBuffer[outOffset++] = dsdRight[inOffset];
      dopBuffer[outOffset++] = marker;
    }

    return dopBuffer;
  }

  /// Encodes into 32-bit PCM containers (LSB 0 padded). Input DSD bytes must be
  /// MSB-first (oldest bit in bit 7); reverse DSF (LSB-first) data beforehand.
  static Uint8List encodeToDopPcm32({
    required Uint8List dsdLeft,
    required Uint8List dsdRight,
  }) {
    if (dsdLeft.length != dsdRight.length) {
      throw ArgumentError(
        'DSD channels must have equal length '
        '(left=${dsdLeft.length}, right=${dsdRight.length}).',
      );
    }
    if (dsdLeft.length.isOdd) {
      throw ArgumentError('DSD byte length must be even (16-bit pairs).');
    }
    final int byteCount = dsdLeft.length;
    final int numSamplesPerChannel = byteCount ~/ 2;
    final Uint8List dopBuffer = Uint8List(numSamplesPerChannel * 8);

    int outOffset = 0;
    for (int i = 0; i < numSamplesPerChannel; i++) {
      final int marker = (i % 2 == 0) ? dopMarkerA : dopMarkerB;
      final int inOffset = i * 2;

      // 32-bit container, little-endian: pad, newer, older, marker (same
      // byte significance as the 24-bit form, see encodeToDopPcm24).
      dopBuffer[outOffset++] = 0x00;
      dopBuffer[outOffset++] = dsdLeft[inOffset + 1];
      dopBuffer[outOffset++] = dsdLeft[inOffset];
      dopBuffer[outOffset++] = marker;

      dopBuffer[outOffset++] = 0x00;
      dopBuffer[outOffset++] = dsdRight[inOffset + 1];
      dopBuffer[outOffset++] = dsdRight[inOffset];
      dopBuffer[outOffset++] = marker;
    }

    return dopBuffer;
  }
}
```

---

## `lib/data/audio/dsd_decoder_helper.dart`

```dart
// lib/data/audio/dsd_decoder_helper.dart
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../db/app_database.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/platform_capabilities.dart';
import '../../domain/models/audio_quality_info.dart';
import 'audio_effects_channel.dart';
import 'dop_encoder.dart';

/// Thrown when a DSD (DSF/DFF) file is played on a platform/build with no
/// native DSD decoder — most notably iOS, where the `decodeDsd` channel method
/// returns null. Callers must catch this and fail the track gracefully instead
/// of letting a raw [UnsupportedError] escape.
class DsdUnsupportedException implements Exception {
  final String message;

  const DsdUnsupportedException([
    this.message = 'DSD playback is not supported on this platform',
  ]);

  @override
  String toString() => 'DsdUnsupportedException: $message';
}

typedef DsdDecodeFunction = Future<List<double>?> Function(
  List<int> dsdL,
  List<int> dsdR, {
  int dsdRate,
  int targetSampleRate,
  int bitOrder,
});

/// What the output device can accept for DSD playback, probed natively.
///
/// [dop] is the single gate for framing DSD as DSD-over-PCM. Android exposes no
/// true "supports native DSD" flag, so the native side reports [dop] only when a
/// USB DAC is physically connected (UAC2 devices may accept DoP); otherwise
/// every flag is false and playback stays on the PCM path.
class DsdDacCapabilities {
  final bool dsd64;
  final bool dsd128;
  final bool dsd256;
  final bool dop;
  final bool nativeDac;

  const DsdDacCapabilities({
    required this.dsd64,
    required this.dsd128,
    required this.dsd256,
    required this.dop,
    required this.nativeDac,
  });

  static const DsdDacCapabilities none = DsdDacCapabilities(
    dsd64: false,
    dsd128: false,
    dsd256: false,
    dop: false,
    nativeDac: false,
  );

  /// True when DoP is possible on this output path: a USB DAC is present and it
  /// advertises at least one carrier rate DoP can use. A DAC that exposes none
  /// of the carrier rates cannot carry DoP, so the UI must not enable it.
  bool get canUseDop => dop && (dsd64 || dsd128 || dsd256);

  /// Whether this device advertises the DoP carrier rate for [dsdRate]
  /// (the DSD multiple of 44.1 kHz: 64, 128 or 256). Rates above DSD256 have no
  /// standard DoP carrier and always report false.
  bool supportsRate(int dsdRate) {
    if (dsdRate <= 0) return false;
    if (dsdRate <= 64) return dsd64;
    if (dsdRate <= 128) return dsd128;
    if (dsdRate <= 256) return dsd256;
    return false;
  }

  @override
  String toString() =>
      'DsdDacCapabilities(dsd64: $dsd64, dsd128: $dsd128, dsd256: $dsd256, '
      'dop: $dop, nativeDac: $nativeDac)';
}

/// Streams in-memory WAV data produced by decoding DSD (DSF/DFF) files.
class DsdPcmStreamAudioSource extends StreamAudioSource {
  final Uint8List wavBytes;

  DsdPcmStreamAudioSource(this.wavBytes, {super.tag});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    // Clamp the requested byte range to the buffer so a hostile/over-long
    // Range header cannot trigger an out-of-bounds sublist RangeError.
    final from = (start ?? 0).clamp(0, wavBytes.length);
    final to = (end ?? wavBytes.length).clamp(from, wavBytes.length);
    // sublistView, not sublist: every seek used to copy up to hundreds of MB.
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: wavBytes.length,
      contentLength: to - from,
      offset: from,
      contentType: 'audio/wav',
      stream: Stream.value(Uint8List.sublistView(wavBytes, from, to)),
    );
  }
}

/// Helper for parsing Sony DSF and Philips/EA DFF audio files and feeding
/// them into the native DSD-to-PCM decoder.
class DsdDecoderHelper {
  /// Injected decoder for tests when running outside of the Android runtime.
  static DsdDecodeFunction? testDecoder;

  static const MethodChannel _hiresChannel =
      MethodChannel(PulsrChannels.hiresDac);

  /// Probes the native output path for DSD-over-PCM capability.
  ///
  /// Calls the `HiResDacPlugin.getDopCapabilities` channel method directly (the
  /// facade lives here so `HiResAudioService` stays untouched). Any error — no
  /// plugin, non-Android platform, timeout — reports [DsdDacCapabilities.none],
  /// so DoP can never be claimed when the probe is unavailable.
  static Future<DsdDacCapabilities> probeDopCapabilities() async {
    if (!PlatformCapabilities.isAndroid) return DsdDacCapabilities.none;
    try {
      final map = await _hiresChannel
          .invokeMapMethod<String, dynamic>('getDopCapabilities')
          .timeout(const Duration(seconds: 2));
      if (map == null) return DsdDacCapabilities.none;
      return DsdDacCapabilities(
        dsd64: map['dsd64'] == true,
        dsd128: map['dsd128'] == true,
        dsd256: map['dsd256'] == true,
        dop: map['dop'] == true,
        nativeDac: map['nativeDac'] == true,
      );
    } catch (_) {
      return DsdDacCapabilities.none;
    }
  }

  /// Parses a DSF or DFF file, decodes DSD frames via the native C++ decoder or
  /// wraps the raw bitstream into DoP (DSD over PCM) frames, and packages the
  /// resulting audio into an [AudioSource].
  ///
  /// [forceDop] is set by the router only when the user selected DoP output and
  /// the native probe confirmed a compatible USB DAC. Even then it is honored
  /// only when the file's DSD rate has a standard DoP carrier and
  /// [dopCapabilities] (when supplied) advertises it; otherwise playback falls
  /// back to the PCM decode path and [AudioQualityInfo.dsdDopActive] stays false.
  ///
  /// [dopContainerBits] selects the PCM container width: 24 (standard DoP
  /// packing, default) or 32 (zero-padded 32-bit frames for DACs that require
  /// 32-bit USB frames). Any other value falls back to 24.
  /// Maximum allowed file size for in-memory DSD decoding (300 MB) (Bug 6 & 18).
  static const int kMaxInMemoryDecodeBytes = 300 * 1024 * 1024;

  static Future<AudioSource> decodeDsdFile(
    SongsTableData song,
    MediaItem tag, {
    bool forceDop = false,
    DsdDacCapabilities? dopCapabilities,
    int dopContainerBits = 24,
  }) async {
    final file = File(song.path);
    if (!await file.exists()) {
      throw FileSystemException('DSD file not found', song.path);
    }
    final fileSize = await file.length();
    if (fileSize > kMaxInMemoryDecodeBytes) {
      throw DsdUnsupportedException(
        'DSD file exceeds max in-memory decode size of 300 MB (${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB)',
      );
    }
    final bytes = await file.readAsBytes();
    final ext = song.path.split('.').last.toLowerCase();

    final Uint8List dsdL;
    final Uint8List dsdR;
    final int dsdRate;
    final int bitOrder;

    if (ext == 'dsf') {
      final parsed = parseDsfBytes(bytes);
      dsdL = parsed.dsdL;
      dsdR = parsed.dsdR;
      dsdRate = parsed.dsdRate;
      // DSF declares its bit order in the fmt chunk (1 = LSB first, 8 = MSB).
      bitOrder = parsed.msbFirst ? 1 : 0;
    } else {
      final parsed = parseDffBytes(bytes);
      dsdL = parsed.dsdL;
      dsdR = parsed.dsdR;
      dsdRate = parsed.dsdRate;
      bitOrder = 1; // MSB first (Philips DFF)
    }

    final int dopSampleRate = DopEncoder.dopPcmSampleRate(dsdRate);
    final bool useDop = forceDop &&
        dopSampleRate > 0 &&
        (dopCapabilities == null || dopCapabilities.supportsRate(dsdRate));
    // Only claim DoP once the framing has actually been built (set below);
    // a decode failure must not leave the global flag stuck on true.
    AudioQualityInfo.dsdDopActive = false;
    if (useDop) {
      // DoP framing (DSD over PCM v1.1): pack 16-bit DSD chunks with alternating 0x05/0xFA markers
      var left = dsdL;
      var right = dsdR;
      if (left.length != right.length) {
        final minLen = math.min(left.length, right.length);
        left = Uint8List.sublistView(left, 0, minLen);
        right = Uint8List.sublistView(right, 0, minLen);
      }
      if (left.length.isOdd) {
        // 0x69 is DSD digital silence; a 0x00 pad is a DC/noise byte.
        left = Uint8List.fromList([...left, 0x69]);
        right = Uint8List.fromList([...right, 0x69]);
      }
      // DoP wants the oldest DSD bit in the MSB. DSF is LSB-first, so reverse
      // the bits of every byte first (the decoder-bound PCM path is unaffected,
      // it takes bitOrder explicitly).
      if (bitOrder == 0) {
        left = _reverseBits(left);
        right = _reverseBits(right);
      }

      final use32Bit = dopContainerBits == 32;
      final dopBytes = use32Bit
          ? DopEncoder.encodeToDopPcm32(dsdLeft: left, dsdRight: right)
          : DopEncoder.encodeToDopPcm24(dsdLeft: left, dsdRight: right);

      final wavBytes = buildDopWavContainer(
        dopPcmBytes: dopBytes,
        sampleRate: dopSampleRate,
        channels: 2,
        bitsPerSample: use32Bit ? 32 : 24,
      );

      AudioQualityInfo.dsdDopActive = true;
      return DsdPcmStreamAudioSource(wavBytes, tag: tag);
    }

    final targetSampleRate = switch (dsdRate) {
      >= 256 => 705600, // DSD256 and above
      >= 128 => 352800, // DSD128
      _ => 176400, // DSD64
    };

    final decoder = testDecoder ?? AudioEffectsChannel().decodeDsd;
    final pcmFloats = await decoder(
      dsdL,
      dsdR,
      dsdRate: dsdRate,
      targetSampleRate: targetSampleRate,
      bitOrder: bitOrder,
    );

    if (pcmFloats == null || pcmFloats.isEmpty) {
      // Non-Android has no native decoder at all (the channel returns null);
      // Android can still fail when libpulsr_dsp is absent. Both are handled,
      // user-visible failures — never a raw UnsupportedError.
      throw DsdUnsupportedException(
        PlatformCapabilities.isAndroid
            ? 'The native DSD decoder is unavailable or returned an empty PCM stream.'
            : 'DSD playback is not supported on this platform.',
      );
    }

    final wavBytes = buildWavContainer(
      pcmFloatSamples: pcmFloats,
      sampleRate: targetSampleRate,
      channels: 2,
    );

    return DsdPcmStreamAudioSource(wavBytes, tag: tag);
  }

  static final Uint8List _bitReverseTable = () {
    final table = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      var v = i, r = 0;
      for (var b = 0; b < 8; b++) {
        r = (r << 1) | (v & 1);
        v >>= 1;
      }
      table[i] = r;
    }
    return table;
  }();

  /// Returns a copy of [src] with the bits of every byte reversed.
  static Uint8List _reverseBits(Uint8List src) {
    final out = Uint8List(src.length);
    for (var i = 0; i < src.length; i++) {
      out[i] = _bitReverseTable[src[i]];
    }
    return out;
  }

  /// Parses DSF header and demuxes planar channel data blocks.
  static ({Uint8List dsdL, Uint8List dsdR, int dsdRate, bool msbFirst})
      parseDsfBytes(Uint8List bytes) {
    if (bytes.length < 52) {
      throw const FormatException(
          'DSF file too small to contain valid headers');
    }
    final byteData = ByteData.sublistView(bytes);

    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != 'DSD ') {
      throw FormatException('Not a valid DSF file: magic is $magic');
    }

    int pos = 28;
    int dsdRate = 64;
    int channels = 2;
    int blockSize = 4096;
    int samplingFrequency = 2822400;
    int bitsPerSample = 1;
    int sampleCount = 0;
    int dataOffset = -1;
    int dataSize = -1;

    while (pos + 12 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final chunkSize = byteData.getUint64(pos + 4, Endian.little);
      // A uint64 >= 2^63 reads back negative; treat as corrupt.
      if (chunkSize < 0) break;

      if (chunkId == 'fmt ' && pos + 52 <= bytes.length) {
        channels = byteData.getUint32(pos + 24, Endian.little);
        samplingFrequency = byteData.getUint32(pos + 28, Endian.little);
        bitsPerSample = byteData.getUint32(pos + 32, Endian.little);
        sampleCount = byteData.getUint64(pos + 36, Endian.little);
        blockSize = byteData.getUint32(pos + 44, Endian.little);
        dsdRate = samplingFrequency ~/ 44100;
      } else if (chunkId == 'data') {
        dataOffset = pos + 12;
        dataSize = chunkSize - 12;
        break;
      }

      if (chunkSize <= 0) break;
      pos += chunkSize;
    }

    if (dataOffset == -1 || dataOffset + dataSize > bytes.length) {
      dataOffset = pos + 12;
      dataSize = bytes.length - dataOffset;
    }

    if (dataSize <= 0 || dataOffset >= bytes.length) {
      throw const FormatException('DSF file contains no audio data');
    }
    if (channels != 1 && channels != 2) {
      throw DsdUnsupportedException(
          'DSF with $channels channels is not supported (mono/stereo only)');
    }

    final payload = Uint8List.sublistView(
        bytes, dataOffset, (dataOffset + dataSize).clamp(0, bytes.length));

    if (blockSize <= 0) {
      blockSize = 4096;
    }
    final stride = blockSize * channels;
    // BytesBuilder(copy: false) keeps views and concatenates once at the end;
    // the previous List<int>.addAll() boxed every byte (8 B/byte), which blew
    // up memory on large DSD files.
    final left = BytesBuilder(copy: false);
    final right = BytesBuilder(copy: false);
    for (int offset = 0; offset < payload.length; offset += stride) {
      final leftEnd = (offset + blockSize).clamp(0, payload.length);
      if (offset < leftEnd) {
        left.add(Uint8List.sublistView(payload, offset, leftEnd));
      }
      if (channels == 2) {
        final rightStart = offset + blockSize;
        final rightEnd = (rightStart + blockSize).clamp(0, payload.length);
        if (rightStart < rightEnd) {
          right.add(Uint8List.sublistView(payload, rightStart, rightEnd));
        }
      }
    }

    var dsdL = left.takeBytes();
    var dsdR = channels == 2 ? right.takeBytes() : Uint8List.fromList(dsdL);

    // The last block of every channel is zero-padded; sampleCount (bits per
    // channel) tells us where real audio ends. Trim so padding is not played,
    // and so L/R lengths agree on truncated files.
    var valid = math.min(dsdL.length, dsdR.length);
    if (sampleCount > 0) valid = math.min(valid, (sampleCount + 7) ~/ 8);
    if (valid != dsdL.length) dsdL = Uint8List.sublistView(dsdL, 0, valid);
    if (valid != dsdR.length) dsdR = Uint8List.sublistView(dsdR, 0, valid);

    return (
      dsdL: dsdL,
      dsdR: dsdR,
      dsdRate: dsdRate > 0 ? dsdRate : 64,
      msbFirst: bitsPerSample == 8,
    );
  }

  /// Parses DFF header and demuxes interleaved audio bytes.
  static ({Uint8List dsdL, Uint8List dsdR, int dsdRate}) parseDffBytes(
      Uint8List bytes) {
    if (bytes.length < 32) {
      throw const FormatException(
          'DFF file too small to contain valid headers');
    }
    final byteData = ByteData.sublistView(bytes);

    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != 'FRM8') {
      throw FormatException('Not a valid DFF file: magic is $magic');
    }

    // Bytes 0-3 = 'FRM8', 4-11 = chunk size, 12-15 = form type ('DSD ');
    // the first real sub-chunk begins at offset 16.
    int pos = 16;
    int dsdRate = 64;
    int channels = 2;
    int dataOffset = -1;
    int dataSize = -1;

    while (pos + 12 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final chunkSize = byteData.getUint64(pos + 4, Endian.big);
      if (chunkSize < 0) break;

      if (chunkId == 'PROP') {
        // FS / CHNL / CMPR live INSIDE the PROP chunk (after its 4-byte 'SND '
        // property type). The old loop only looked at top-level chunks, so it
        // never saw 'FS  ' and every DFF was treated as DSD64.
        final end = math.min(pos + 12 + chunkSize, bytes.length);
        var sub = pos + 16;
        while (sub + 12 <= end) {
          final subId = String.fromCharCodes(bytes.sublist(sub, sub + 4));
          final subSize = byteData.getUint64(sub + 4, Endian.big);
          if (subSize < 0) break;
          if (subId == 'FS  ' && subSize >= 4 && sub + 16 <= end) {
            dsdRate = byteData.getUint32(sub + 12, Endian.big) ~/ 44100;
          } else if (subId == 'CHNL' && subSize >= 2 && sub + 14 <= end) {
            channels = byteData.getUint16(sub + 12, Endian.big);
          } else if (subId == 'CMPR' && subSize >= 4 && sub + 16 <= end) {
            final type =
                String.fromCharCodes(bytes.sublist(sub + 12, sub + 16));
            if (type != 'DSD ') {
              throw DsdUnsupportedException(
                  'Compressed DFF ($type) is not supported');
            }
          }
          sub += 12 + subSize + (subSize & 1);
        }
      } else if (chunkId == 'FS  ') {
        if (chunkSize >= 4 && pos + 16 <= bytes.length) {
          dsdRate = byteData.getUint32(pos + 12, Endian.big) ~/ 44100;
        }
      } else if (chunkId == 'DSD ') {
        dataOffset = pos + 12;
        dataSize = chunkSize.clamp(0, bytes.length - dataOffset);
        break;
      }

      // IFF chunks are padded to an even size.
      pos += 12 + chunkSize + (chunkSize & 1);
    }

    if (dataOffset == -1 || dataOffset >= bytes.length) {
      throw const FormatException('DFF file contains no DSD audio chunk');
    }
    if (channels != 1 && channels != 2) {
      throw DsdUnsupportedException(
          'DFF with $channels channels is not supported (mono/stereo only)');
    }

    final payload = Uint8List.sublistView(
        bytes, dataOffset, (dataOffset + dataSize).clamp(0, bytes.length));

    // Byte-interleaved across channels. Preallocated typed buffers instead of
    // a boxed List<int>.add() per byte.
    final Uint8List dsdL;
    final Uint8List dsdR;
    if (channels == 1) {
      dsdL = Uint8List.fromList(payload);
      dsdR = Uint8List.fromList(payload);
    } else {
      final frames = payload.length ~/ 2;
      dsdL = Uint8List(frames);
      dsdR = Uint8List(frames);
      for (int i = 0; i < frames; i++) {
        dsdL[i] = payload[i * 2];
        dsdR[i] = payload[i * 2 + 1];
      }
    }

    return (
      dsdL: dsdL,
      dsdR: dsdR,
      dsdRate: dsdRate > 0 ? dsdRate : 64,
    );
  }

  /// Builds a standard 44-byte WAV container for decoded DSD PCM. Defaults to
  /// 24-bit so the hi-res resolution produced by the native DSD decoder
  /// (176.4/352.8/705.6 kHz) is preserved instead of being truncated to 16-bit.
  static Uint8List buildWavContainer({
    required List<double> pcmFloatSamples,
    required int sampleRate,
    int channels = 2,
    int bitsPerSample = 24,
  }) {
    final int bytesPerSample = bitsPerSample ~/ 8;
    final int numFrames = pcmFloatSamples.length ~/ channels;
    final int byteCount = numFrames * channels * bytesPerSample;
    final ByteData byteData = ByteData(44 + byteCount);

    // RIFF header
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, 36 + byteCount, Endian.little);
    byteData.setUint8(8, 0x57); // 'W'
    byteData.setUint8(9, 0x41); // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size
    byteData.setUint16(20, 1, Endian.little); // AudioFormat 1 = PCM
    byteData.setUint16(22, channels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    final int byteRate = sampleRate * channels * bytesPerSample;
    byteData.setUint32(28, byteRate, Endian.little);
    final int blockAlign = channels * bytesPerSample;
    byteData.setUint16(32, blockAlign, Endian.little);
    byteData.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, byteCount, Endian.little);

    int offset = 44;
    for (int i = 0; i < pcmFloatSamples.length; i++) {
      // NaN/Inf from the native decoder would make .round() throw
      // UnsupportedError and kill the whole load; write silence instead.
      final double raw = pcmFloatSamples[i];
      final double sample =
          raw.isFinite ? raw.clamp(-1.0, 1.0).toDouble() : 0.0;
      if (bytesPerSample == 2) {
        final int pcm16 = (sample * 32767.0).round().clamp(-32768, 32767);
        byteData.setInt16(offset, pcm16, Endian.little);
        offset += 2;
      } else {
        // 24-bit packed little-endian
        final int pcm24 = (sample * 8388607.0).round().clamp(-8388608, 8388607);
        byteData.setUint8(offset, pcm24 & 0xFF);
        byteData.setUint8(offset + 1, (pcm24 >> 8) & 0xFF);
        byteData.setUint8(offset + 2, (pcm24 >> 16) & 0xFF);
        offset += 3;
      }
    }

    return byteData.buffer.asUint8List();
  }

  /// Builds a 44-byte WAV header containing 24-bit stereo packed DoP PCM frames.
  static Uint8List buildDopWavContainer({
    required Uint8List dopPcmBytes,
    required int sampleRate,
    int channels = 2,
    int bitsPerSample = 24,
  }) {
    if (sampleRate != 176400 && sampleRate != 352800 && sampleRate != 705600) {
      throw ArgumentError(
        'Invalid DoP sample rate: $sampleRate. '
        'DoP requires exact 176.4 kHz, 352.8 kHz, or 705.6 kHz carrier rate.',
      );
    }
    final int byteCount = dopPcmBytes.length;
    final ByteData byteData = ByteData(44 + byteCount);

    // RIFF header
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, 36 + byteCount, Endian.little);
    byteData.setUint8(8, 0x57); // 'W'
    byteData.setUint8(9, 0x41); // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size
    byteData.setUint16(20, 1, Endian.little); // AudioFormat 1 = PCM
    byteData.setUint16(22, channels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    final int bytesPerSample = bitsPerSample ~/ 8;
    final int blockAlign = channels * bytesPerSample;
    final int byteRate = sampleRate * blockAlign;
    byteData.setUint32(28, byteRate, Endian.little);
    byteData.setUint16(32, blockAlign, Endian.little);
    byteData.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, byteCount, Endian.little);

    final Uint8List outBytes = byteData.buffer.asUint8List();
    outBytes.setRange(44, 44 + byteCount, dopPcmBytes);
    return outBytes;
  }
}
```

---

## `third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/AAudioAudioSink.java`

```java
package com.ryanheise.just_audio;

import android.util.Log;
import android.media.AudioDeviceInfo;
import android.media.AudioFormat;

import androidx.media3.common.AudioAttributes;
import androidx.media3.common.AuxEffectInfo;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.exoplayer.audio.AudioSink;

import java.nio.ByteBuffer;

/**
 * Pulsr fork: Media3 {@link AudioSink} backed by a native AAudio stream.
 *
 * <p>Direct output requests the source sample rate through AAudio. Exclusive
 * requests fail if unavailable and lock PCM volume to unity. Explicit shared
 * mode permits software volume and makes no downstream bit-perfect guarantee. The DSP
 * processor chain is bypassed in this mode by design - this sink is the
 * bit-perfect alternative path, not a DSP replacement.
 *
 * <p>v1 scope (documented limitations): PCM 16-bit / float / 24-bit packed,
 * 1-2 channels, speed &amp; pitch pinned to 1.0 (requests are ignored with a
 * log), no silence skipping, no tunneling/offload/aux effects. Any stream the
 * sink cannot honour must be declined via {@link #supportsFormat} so the
 * player keeps using the DefaultAudioSink path.
 */
@androidx.media3.common.util.UnstableApi
public final class AAudioAudioSink implements AudioSink {
    private static final String TAG = "PulsrAAudioSink";

    private Listener listener;
    private Format configuredFormat;
    private int targetBufferMs;
    private final boolean preferExclusive;

    private long handle = 0L;
    private int sampleRate;
    private int channelCount;

    private float volume = 1.0f;
    private PlaybackParameters playbackParameters = PlaybackParameters.DEFAULT;
    private AudioAttributes audioAttributes = AudioAttributes.DEFAULT;
    private boolean skipSilenceEnabled = false;
    private int audioSessionId = C.AUDIO_SESSION_ID_UNSET;

    private volatile boolean playing = false;
    private volatile int[] measuredStream = new int[] {0, 0, 0};
    private int preferredDeviceId = 0;
    private int openedDeviceId = 0;
    private boolean routePending = false;

    int[] measuredStream() { return measuredStream; }
    boolean isPlaying() { return playing; }

    @Override
    public void setPreferredDevice(AudioDeviceInfo device) {
        int id = device == null ? 0 : device.getId();
        if (id == preferredDeviceId) return;
        preferredDeviceId = id;
        routePending = handle != 0L;
    }

    private boolean eosWritten = false;
    private boolean handledEndOfStream = false;
    // Position base: the presentation time of the first buffer written after
    // the last (re)configuration/discontinuity, per the AudioSink contract.
    private boolean pendingBasePosition = true;
    private long basePositionUs = 0L;

    public AAudioAudioSink(boolean preferExclusive, int targetBufferMs) {
        this.preferExclusive = preferExclusive;
        this.targetBufferMs = targetBufferMs;
    }

    @Override
    public void setListener(Listener listener) {
        this.listener = listener;
    }

    @Override
    public boolean supportsFormat(Format format) {
        return getFormatSupport(format) != SINK_FORMAT_UNSUPPORTED;
    }

    @Override
    public int getFormatSupport(Format format) {
        if (format.sampleRate <= 0 || format.channelCount <= 0
                || format.channelCount > 2) {
            return SINK_FORMAT_UNSUPPORTED;
        }
        switch (format.pcmEncoding) {
            case C.ENCODING_PCM_16BIT:
            case C.ENCODING_PCM_FLOAT:
            case C.ENCODING_PCM_24BIT:
                return SINK_FORMAT_SUPPORTED_DIRECTLY;
            default:
                // Compressed/encoded and exotic PCM stay on DefaultAudioSink.
                return SINK_FORMAT_UNSUPPORTED;
        }
    }

    @Override
    public long getCurrentPositionUs(boolean sourceEnded) {
        if (handle == 0L || sampleRate <= 0) {
            return CURRENT_POSITION_NOT_SET;
        }
        long framesRead = AaudioNativeBridge.nativeGetFramesRead(handle);
        long positionUs = basePositionUs
                + (long) (framesRead * (1_000_000.0 / sampleRate));
        if (!sourceEnded) {
            // Never report beyond what the app has actually written.
            long framesWritten = AaudioNativeBridge.nativeGetFramesWritten(handle);
            long maxUs = basePositionUs
                    + (long) (framesWritten * (1_000_000.0 / sampleRate));
            if (positionUs > maxUs) positionUs = maxUs;
        }
        return positionUs;
    }

    @Override
    public void configure(Format inputFormat, int specifiedBufferSizeSize,
            int[] outputChannels) throws ConfigurationException {
        if (outputChannels != null) {
            throw new ConfigurationException(
                "AAudio sink does not support channel remapping", inputFormat);
        }
        if (getFormatSupport(inputFormat) == SINK_FORMAT_UNSUPPORTED) {
            throw new ConfigurationException(
                "Unsupported PCM format for AAudio sink", inputFormat);
        }
        int encoding;
        if (inputFormat.pcmEncoding == C.ENCODING_PCM_16BIT) {
            encoding = AaudioNativeBridge.ENCODING_PCM_I16;
        } else if (inputFormat.pcmEncoding == C.ENCODING_PCM_FLOAT) {
            encoding = AaudioNativeBridge.ENCODING_PCM_FLOAT;
        } else {
            encoding = AaudioNativeBridge.ENCODING_PCM_I24_PACKED;
        }
        // Close any stream from a previous configuration before reopening.
        closeHandle();
        long newHandle;
        try {
            newHandle = AaudioNativeBridge.nativeOpenForDevice(inputFormat.sampleRate,
                    inputFormat.channelCount, encoding, preferExclusive,
                    targetBufferMs, preferredDeviceId);
        } catch (UnsatisfiedLinkError e) {
            throw new ConfigurationException(e, inputFormat);
        }
        if (newHandle == 0L) {
            throw new ConfigurationException(
                "AAudio stream could not be opened for "
                    + inputFormat.sampleRate + "Hz/" + inputFormat.channelCount
                    + "ch", inputFormat);
        }
        handle = newHandle;
        openedDeviceId = preferredDeviceId;
        routePending = false;
        measuredStream = new int[] {AaudioNativeBridge.nativeGetDeviceId(handle),
                inputFormat.sampleRate, inputFormat.pcmEncoding == C.ENCODING_PCM_24BIT
                    ? AudioFormat.ENCODING_PCM_24BIT_PACKED : inputFormat.pcmEncoding};
        configuredFormat = inputFormat;
        sampleRate = inputFormat.sampleRate;
        channelCount = inputFormat.channelCount;
        eosWritten = false;
        handledEndOfStream = false;
        pendingBasePosition = true;
        AaudioNativeBridge.nativeSetVolume(handle, volume);
        if (!playing) AaudioNativeBridge.nativePause(handle);
        Log.i(TAG, "AAudio sink configured: " + sampleRate + "Hz/" + channelCount
                + "ch exclusive=" + AaudioNativeBridge.nativeIsExclusive(handle));
    }

    @Override
    public void play() {
        playing = true;
        if (handle != 0L) AaudioNativeBridge.nativePlay(handle);
    }

    @Override
    public void handleDiscontinuity() {
        // The next handleBuffer re-bases the position timeline.
        pendingBasePosition = true;
    }

    @Override
    public boolean handleBuffer(ByteBuffer buffer, long presentationStartUs,
            int encodedAccessUnitCount) throws InitializationException,
            WriteException {
        if (routePending && configuredFormat != null) {
            Format previousFormat = configuredFormat;
            int previousDevice = openedDeviceId;
            try {
                configure(previousFormat, 0, null);
            } catch (ConfigurationException refused) {
                preferredDeviceId = previousDevice;
                try { configure(previousFormat, 0, null); }
                catch (ConfigurationException restoreFailed) { /* existing initialization error below */ }
                if (listener != null) listener.onAudioSinkError(refused);
            }
        }
        if (handle == 0L) {
            throw new InitializationException(0,
                    configuredFormat != null ? configuredFormat.sampleRate : 0,
                    configuredFormat != null ? configuredFormat.channelCount : 0,
                    configuredFormat != null ? configuredFormat.pcmEncoding : 0,
                    configuredFormat, /* isRecoverable= */ false,
                    /* audioTrackException= */ null);
        }
        if (pendingBasePosition) {
            basePositionUs = presentationStartUs;
            pendingBasePosition = false;
        }
        int remaining = buffer.remaining();
        if (remaining == 0) {
            return true;
        }
        if (!buffer.isDirect()) {
            // Media3 hands the sink direct buffers; be defensive anyway.
            ByteBuffer direct = ByteBuffer.allocateDirect(remaining);
            direct.put(buffer.duplicate());
            direct.flip();
            int written = AaudioNativeBridge.nativeWrite(handle, direct, 0,
                    remaining);
            if (written <= 0 || written > remaining) {
                throw new WriteException(-1, configuredFormat,
                        /* isRecoverable= */ false);
            }
            updateMeasuredRoute();
            buffer.position(buffer.position() + written);
            return !buffer.hasRemaining();
        }
        int offset = buffer.position();
        int written = AaudioNativeBridge.nativeWrite(handle, buffer, offset,
                remaining);
        if (written <= 0 || written > remaining) {
            throw new WriteException(-1, configuredFormat,
                    /* isRecoverable= */ false);
        }
        updateMeasuredRoute();
        buffer.position(offset + written);
        return !buffer.hasRemaining();
    }

    @Override
    public void playToEndOfStream() throws WriteException {
        if (handle == 0L || eosWritten) {
            return;
        }
        eosWritten = true;
        // Block until the device has consumed everything written.
        long deadline = android.os.SystemClock.elapsedRealtime() + 5000;
        while (handle != 0L
                && AaudioNativeBridge.nativeGetFramesRead(handle)
                        < AaudioNativeBridge.nativeGetFramesWritten(handle)) {
            if (android.os.SystemClock.elapsedRealtime() > deadline) {
                Log.w(TAG, "playToEndOfStream timed out waiting for drain");
                break;
            }
            android.os.SystemClock.sleep(10);
        }
        handledEndOfStream = true;
    }

    @Override
    public boolean isEnded() {
        return handledEndOfStream && handle != 0L
                && AaudioNativeBridge.nativeGetFramesRead(handle)
                        >= AaudioNativeBridge.nativeGetFramesWritten(handle);
    }

    @Override
    public boolean hasPendingData() {
        return handle != 0L
                && AaudioNativeBridge.nativeGetFramesRead(handle)
                        < AaudioNativeBridge.nativeGetFramesWritten(handle);
    }

    @Override
    public void setPlaybackParameters(PlaybackParameters playbackParameters) {
        if (playbackParameters.speed != 1.0f
                || playbackParameters.pitch != 1.0f) {
            Log.w(TAG, "AAudio sink v1 ignores speed/pitch changes; "
                    + "playback continues at 1.0x");
        }
        this.playbackParameters = PlaybackParameters.DEFAULT;
    }

    @Override
    public PlaybackParameters getPlaybackParameters() {
        return playbackParameters;
    }

    @Override
    public void setSkipSilenceEnabled(boolean skipSilenceEnabled) {
        this.skipSilenceEnabled = false;
        if (listener != null) {
            listener.onSkipSilenceEnabledChanged(false);
        }
    }

    @Override
    public boolean getSkipSilenceEnabled() {
        return skipSilenceEnabled;
    }

    @Override
    public void setAudioAttributes(AudioAttributes audioAttributes) {
        this.audioAttributes = audioAttributes;
    }

    @Override
    public AudioAttributes getAudioAttributes() {
        return audioAttributes;
    }

    @Override
    public void setAudioSessionId(int audioSessionId) {
        this.audioSessionId = audioSessionId;
    }

    @Override
    public void setAuxEffectInfo(AuxEffectInfo auxEffectInfo) {
        // No aux effects on the native path.
    }

    @Override
    public void enableTunnelingV21() {
        // Tunneling is incompatible with the direct PCM path; no-op.
    }

    @Override
    public void disableTunneling() {
        // No-op.
    }

    @Override
    public void setVolume(float volume) {
        this.volume = volume;
        if (handle != 0L) {
            AaudioNativeBridge.nativeSetVolume(handle, volume);
        }
    }

    @Override
    public void pause() {
        playing = false;
        if (handle != 0L) AaudioNativeBridge.nativePause(handle);
    }

    @Override
    public void flush() {
        eosWritten = false;
        handledEndOfStream = false;
        pendingBasePosition = true;
        if (handle != 0L) AaudioNativeBridge.nativeFlush(handle);
        if (playing && handle != 0L) AaudioNativeBridge.nativePlay(handle);
    }

    @Override
    public void reset() {
        closeHandle();
        eosWritten = false;
        handledEndOfStream = false;
        pendingBasePosition = true;
        configuredFormat = null;
        sampleRate = 0;
        channelCount = 0;
    }

    @Override
    public void release() {
        closeHandle();
    }

    private void updateMeasuredRoute() {
        int device = AaudioNativeBridge.nativeGetDeviceId(handle);
        int[] previous = measuredStream;
        if (previous[0] != device) measuredStream = new int[] {device, previous[1], previous[2]};
    }

    private void closeHandle() {
        measuredStream = new int[] {0, 0, 0};
        if (handle != 0L) {
            long toClose = handle;
            handle = 0L;
            try {
                AaudioNativeBridge.nativeClose(toClose);
            } catch (UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeClose failed: " + e.getMessage());
            }
        }
    }
}
```

---

## `third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/AaudioNativeBridge.java`

```java
package com.ryanheise.just_audio;

import java.nio.ByteBuffer;

/**
 * JNI surface to Pulsr's native AAudio output sink (libpulsr_dsp.so).
 *
 * <p>Values mirror the AAudio enums: encoding 1 = PCM_I16, 2 = PCM_FLOAT,
 * 3 = PCM_I24_PACKED (the DoP carrier). All calls are cheap wrappers; the
 * write call blocks on the caller's thread until the stream accepts the
 * buffer. The library is loaded lazily by {@link #ensureAvailable()} so a
 * missing native library degrades to "unavailable" instead of crashing.
 */
public final class AaudioNativeBridge {
    public static final int ENCODING_PCM_I16 = 1;
    public static final int ENCODING_PCM_FLOAT = 2;
    public static final int ENCODING_PCM_I24_PACKED = 3;

    private static volatile boolean loadAttempted = false;
    private static boolean available = false;

    private AaudioNativeBridge() {}

    /** Returns true when libpulsr_dsp is present and loadable (once). */
    public static synchronized boolean ensureAvailable() {
        if (!loadAttempted) {
            loadAttempted = true;
            try {
                System.loadLibrary("pulsr_dsp");
                available = true;
            } catch (UnsatisfiedLinkError | SecurityException e) {
                available = false;
            }
        }
        return available;
    }

    /** Opens a stream; returns a native handle or 0 on failure. */
    public static native long nativeOpen(int sampleRate, int channelCount,
            int encoding, boolean preferExclusive, int targetBufferMs);

    public static native long nativeOpenForDevice(int sampleRate, int channelCount,
            int encoding, boolean preferExclusive, int targetBufferMs, int deviceId);
    public static native int nativeGetDeviceId(long handle);

    /** Releases the stream and the native object. Idempotent with 0. */
    public static native void nativeClose(long handle);

    /**
     * Writes exactly {@code length} bytes from {@code buffer} starting at
     * {@code offset} (blocking). Returns bytes consumed, or -1 on failure.
     */
    public static native int nativeWrite(long handle, ByteBuffer buffer,
            int offset, int length);

    public static native void nativePlay(long handle);

    public static native void nativePause(long handle);

    public static native void nativeFlush(long handle);

    public static native long nativeGetFramesRead(long handle);

    public static native long nativeGetFramesWritten(long handle);

    public static native int nativeGetXRunCount(long handle);

    public static native boolean nativeIsExclusive(long handle);

    public static native void nativeSetVolume(long handle, float volume);
 
    public static native double nativeGetOutputLatencyMs(long handle);

    public static native int nativeGetFramesPerBurst(long handle);
}
```

---

## `third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/NativeDspAudioProcessor.java`

```java
package com.ryanheise.just_audio;

import android.os.Build;
import android.util.Log;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;

/**
 * Feeds ExoPlayer's PCM stream through Pulsr's native DSP chain (libpulsr_dsp).
 *
 * <p>Default (16-bit) mode: DefaultAudioSink inserts ToInt16PcmAudioProcessor
 * ahead of the chain, so this processor reads {@code ENCODING_PCM_16BIT},
 * expands it to float for the native engine and re-quantises the result back to
 * 16-bit — exactly the historical behaviour.
 *
 * <p>Float mode (opt-in, off by default): when {@link #setFloatOutput(boolean)}
 * is enabled and the sink offers {@code ENCODING_PCM_FLOAT}, the decoded float
 * samples go straight to the native engine (it already processes arbitrary
 * float blocks) and are emitted as float again, avoiding the per-sample 16-bit
 * re-quantisation at the end of the chain. If the sink still delivers 16-bit,
 * the processor transparently keeps the 16-bit behaviour so playback is never
 * interrupted.
 */
public class NativeDspAudioProcessor extends BaseAudioProcessor {
    private static final String TAG = "NativeDspAudioProcessor";
    private static final boolean NATIVE_AVAILABLE = loadNativeLibrary();

    private static boolean loadNativeLibrary() {
        try {
            System.loadLibrary("pulsr_dsp");
            return true;
        } catch (UnsatisfiedLinkError | SecurityException e) {
            Log.w(TAG, "libpulsr_dsp unavailable, native DSP stays bypassed: " + e.getMessage());
            return false;
        }
    }

    private static native long nativeCreateEngine();
    private static native void nativeDestroyEngine(long engineHandle);
    private static native void nativeResetEngine(long engineHandle);
    private static native int nativeProcessDirectFloatBuffer(
            long engineHandle, ByteBuffer buffer, int offsetBytes, int frameCount, int channels);
    private static native void nativeResyncForTrack(
            long engineHandle, double sampleRate, int channels);

    private long nativeEngineHandle = 0;

    // Pulsr fork: opt-in 24/32-bit float path. Off by default so the sink
    // pipeline (and therefore the audible result) is byte-identical to the
    // historical 16-bit-only behaviour unless the user enables it.
    private volatile boolean floatOutputEnabled = false;

    /**
     * Enables/disables the float32 DSP path. Safe to call before or after the
     * sink is configured; a change after configuration only takes effect when
     * the sink is rebuilt (the media3 pipeline fixes its encodings at
     * configure time).
     */
    public void setFloatOutput(boolean enabled) {
        // Float AudioTrack output exists from API 21; minSdk is well above it,
        // but degrading to 16-bit is cheaper than risking a silent sink.
        this.floatOutputEnabled = enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP;
    }

    public boolean isFloatOutputEnabled() {
        return floatOutputEnabled;
    }

    public NativeDspAudioProcessor() {
        if (NATIVE_AVAILABLE) {
            try {
                nativeEngineHandle = nativeCreateEngine();
            } catch (UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeCreateEngine failed: " + e.getMessage());
                nativeEngineHandle = 0;
            }
        }
    }

    public void release() {
        if (NATIVE_AVAILABLE && nativeEngineHandle != 0) {
            long handle = nativeEngineHandle;
            nativeEngineHandle = 0;
            try {
                nativeDestroyEngine(handle);
            } catch (UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeDestroyEngine failed: " + e.getMessage());
            }
        }
    }

    @Override
    protected void finalize() throws Throwable {
        try {
            release();
        } finally {
            super.finalize();
        }
    }

    // ---- Pulsr fork: sample-accurate gain ramp ----
    // Per-instance state (one processor per AudioPlayer) so the two crossfade
    // players ramp independently. Applied AFTER the native DSP chain so the
    // limiter/EQ still see the un-attenuated signal and the ramp can only
    // attenuate (gains are clamped to [0, 1]).
    private final Object rampLock = new Object();
    private float[] rampGains = null;   // null => no ramp armed (transparent unity)
    private int rampSegmentFrames = 0;  // frames covered by one curve segment
    private long rampPosFrames = 0;     // frames consumed since the curve started
    private float staticGain = 1.0f;    // gain applied when no curve is armed

    /**
     * Arms a piecewise-linear gain curve applied per-sample from the next
     * queued buffer. The first gain takes effect immediately, one gain per
     * {@code segmentMs}, and the last gain is held once the curve is exhausted
     * (it becomes the static gain until {@link #clearGainCurve()} is called).
     *
     * @return true if the curve was armed (native DSP chain active), false if
     *         the caller must fall back to stepped setVolume().
     */
    public boolean setGainCurve(double[] gains, int segmentMs) {
        if (!NATIVE_AVAILABLE || gains == null || gains.length == 0 || segmentMs <= 0) {
            return false;
        }
        double sampleRate = inputAudioFormat.sampleRate;
        if (sampleRate <= 0) sampleRate = 48000.0; // sink not configured yet; close enough
        int segFrames = Math.max(1, (int) Math.round(sampleRate * segmentMs / 1000.0));
        float[] curve = new float[gains.length];
        for (int i = 0; i < gains.length; i++) {
            float g = (float) gains[i];
            curve[i] = Math.max(0.0f, Math.min(1.0f, g));
        }
        synchronized (rampLock) {
            rampGains = curve;
            rampSegmentFrames = segFrames;
            rampPosFrames = 0;
            staticGain = curve[0]; // first curve gain applies immediately
        }
        return true;
    }

    /**
     * Drops any armed curve and restores transparent unity gain.
     *
     * @return true if the state was reset (native DSP chain active).
     */
    public boolean clearGainCurve() {
        if (!NATIVE_AVAILABLE) {
            return false;
        }
        synchronized (rampLock) {
            rampGains = null;
            rampSegmentFrames = 0;
            rampPosFrames = 0;
            staticGain = 1.0f;
        }
        return true;
    }

    private ByteBuffer scratch;
    // Independent of the sleep/crossfade curve: profile edits may temporarily
    // fade the complete chain without replacing another owner's envelope.
    private volatile boolean transitionMuted;
    private volatile float transitionGain = 1.0f;
    public boolean setTransitionMuted(boolean muted) {
        transitionMuted = muted;
        return NATIVE_AVAILABLE;
    }
    public float getTransitionGain() { return transitionGain; }
    private FloatBuffer scratchFloats;

    @Override
    protected AudioFormat onConfigure(AudioFormat inputAudioFormat) {
        if (!NATIVE_AVAILABLE) {
            return AudioFormat.NOT_SET;
        }
        // 16-bit is the historical path and stays accepted unconditionally.
        if (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT) {
            return inputAudioFormat;
        }
        // Float is only accepted when the opt-in float path is enabled; when it
        // is off this returns NOT_SET exactly as before, so ExoPlayer inserts
        // ToInt16PcmAudioProcessor ahead of the chain.
        if (floatOutputEnabled && inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT) {
            return inputAudioFormat;
        }
        return AudioFormat.NOT_SET;
    }

    @Override
    public void queueInput(ByteBuffer inputBuffer) {
        int position = inputBuffer.position();
        int limit = inputBuffer.limit();
        int frameCount = (limit - position) / inputAudioFormat.bytesPerFrame;
        if (frameCount <= 0) {
            inputBuffer.position(limit);
            return;
        }

        final int channelCount = inputAudioFormat.channelCount;
        final boolean inputIsFloat = inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT;
        FloatBuffer floats = ensureScratch(frameCount * channelCount);

        if (inputIsFloat) {
            for (int i = 0; i < frameCount * channelCount; i++) {
                floats.put(i, inputBuffer.getFloat(position + i * 4));
            }
        } else {
            for (int i = 0; i < frameCount * channelCount; i++) {
                floats.put(i, inputBuffer.getShort(position + i * 2) / 32768f);
            }
        }

        int processed = frameCount;
        boolean bitPerfect = false;
        if (NATIVE_AVAILABLE && nativeEngineHandle != 0) {
            try {
                processed = nativeProcessDirectFloatBuffer(
                        nativeEngineHandle, scratch, 0, frameCount, channelCount);
                bitPerfect = processed < 0;
                if (bitPerfect) processed = -processed;
            } catch (UnsatisfiedLinkError e) {
                processed = frameCount;
            }
        }
        if (processed <= 0 || processed > frameCount) {
            // Engine declined the block; scratch still holds the untouched input.
            processed = frameCount;
            bitPerfect = false;
        }

        if (bitPerfect) {
            clearGainCurve();
            ByteBuffer output = replaceOutputBuffer(processed * outputAudioFormat.bytesPerFrame);
            ByteBuffer original = inputBuffer.duplicate();
            original.limit(position + processed * inputAudioFormat.bytesPerFrame);
            output.put(original);
            output.flip();
            inputBuffer.position(limit);
            return;
        }

        // Snapshot ramp state and consume the frames we are about to emit.
        // When the curve is exhausted it transitions into a static gain equal
        // to its last value, so a fade-out stays silent and a fade-in becomes
        // transparent instead of leaving a stale curve behind.
        float[] curve;
        int segFrames;
        long startPos;
        float idleGain;
        synchronized (rampLock) {
            curve = rampGains;
            segFrames = rampSegmentFrames;
            startPos = rampPosFrames;
            idleGain = staticGain;
            if (curve != null) {
                rampPosFrames += processed;
                if (rampPosFrames >= (long) (curve.length - 1) * segFrames) {
                    staticGain = curve[curve.length - 1];
                    rampGains = null;
                    rampSegmentFrames = 0;
                    rampPosFrames = 0;
                }
            }
        }

        final int lastIdx = curve == null ? 0 : curve.length - 1;
        final boolean outputIsFloat = outputAudioFormat.encoding == C.ENCODING_PCM_FLOAT;
        ByteBuffer output = replaceOutputBuffer(processed * outputAudioFormat.bytesPerFrame);
        float profileGain = transitionGain;
        final float profileTarget = transitionMuted ? 0.0f : 1.0f;
        final float profileStep = 1.0f / Math.max(1, inputAudioFormat.sampleRate * 0.04f);
        for (int i = 0; i < processed * channelCount; i++) {
            if (i % channelCount == 0) {
                profileGain = profileTarget < profileGain
                        ? Math.max(profileTarget, profileGain - profileStep)
                        : Math.min(profileTarget, profileGain + profileStep);
            }
            float gain = idleGain;
            if (curve != null) {
                // Piecewise-linear interpolation between curve points, per frame.
                long frame = i / channelCount;
                double exact = (startPos + frame) / (double) segFrames;
                int seg = (int) exact;
                if (seg >= lastIdx) {
                    gain = curve[lastIdx];
                } else {
                    float frac = (float) (exact - seg);
                    gain = curve[seg] + (curve[seg + 1] - curve[seg]) * frac;
                }
            }
            float value = floats.get(i) * gain * profileGain;
            if (outputIsFloat) {
                // Emit straight float32: no 16-bit re-quantisation after DSP.
                output.putFloat(value);
            } else {
                output.putShort(Pcm16Quantizer.fromFloat(value));
            }
        }
        transitionGain = profileGain;
        inputBuffer.position(limit);
        output.flip();
    }

    @Override
    protected void onFlush() {
        if (NATIVE_AVAILABLE && nativeEngineHandle != 0 && inputAudioFormat.sampleRate > 0) {
            try {
                nativeResyncForTrack(nativeEngineHandle, inputAudioFormat.sampleRate, inputAudioFormat.channelCount);
            } catch (UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeResyncForTrack failed: " + e.getMessage());
            }
        }
        synchronized (rampLock) {
            if (rampGains == null) {
                staticGain = 1.0f;
            }
        }
        // Media3/ExoPlayer flushes on ordinary seeks within the same stream,
        // not only on genuinely new sources. Do NOT reset an in-flight curve
        // (rampPosFrames > 0), otherwise a seek snaps an active fade-out back
        // to full volume (rampGains[0]). A newly armed curve already sets
        // rampPosFrames = 0 and staticGain = rampGains[0] in setGainCurve().
    }

    @Override
    protected void onReset() {
        transitionMuted = false;
        transitionGain = 1.0f;
        scratch = null;
        scratchFloats = null;
        synchronized (rampLock) {
            rampGains = null;
            rampSegmentFrames = 0;
            rampPosFrames = 0;
            staticGain = 1.0f;
        }
        if (NATIVE_AVAILABLE && nativeEngineHandle != 0) {
            try {
                nativeResetEngine(nativeEngineHandle);
            } catch (UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeResetEngine failed: " + e.getMessage());
            }
        }
    }

    private FloatBuffer ensureScratch(int sampleCount) {
        if (scratch == null || scratch.capacity() < sampleCount * 4) {
            scratch = ByteBuffer.allocateDirect(sampleCount * 4).order(ByteOrder.nativeOrder());
            scratchFloats = scratch.asFloatBuffer();
        }
        return scratchFloats;
    }
}
```

---

## `third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/FloatDspAudioSink.java`

```java
package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** Media3 omits custom processors on float output; tap high-resolution PCM here. */
@androidx.media3.common.util.UnstableApi
final class FloatDspAudioSink extends ForwardingAudioSink {
    private final NativeDspAudioProcessor processor;
    private boolean processFloat;
    private int inputEncoding;
    private ByteBuffer converted;
    private ByteBuffer pendingOutput;
    private ByteBuffer pendingInput;

    FloatDspAudioSink(AudioSink delegate, NativeDspAudioProcessor processor) {
        super(delegate);
        this.processor = processor;
    }

    @Override
    public void configure(Format format, int bufferSize, int[] outputChannels)
            throws ConfigurationException {
        pendingOutput = null;
        pendingInput = null;
        inputEncoding = format.pcmEncoding;
        processFloat = inputEncoding == C.ENCODING_PCM_FLOAT
                || inputEncoding == C.ENCODING_PCM_24BIT
                || inputEncoding == C.ENCODING_PCM_32BIT;
        if (processFloat) {
            try {
                processor.configure(new AudioProcessor.AudioFormat(
                        format.sampleRate, format.channelCount, C.ENCODING_PCM_FLOAT));
                processor.flush();
                processFloat = processor.isActive();
            } catch (AudioProcessor.UnhandledAudioFormatException e) {
                throw new ConfigurationException(e, format);
            }
        }
        super.configure(processFloat
                ? format.buildUpon().setPcmEncoding(C.ENCODING_PCM_FLOAT).build()
                : format, bufferSize, outputChannels);
    }

    @Override
    public boolean handleBuffer(ByteBuffer input, long presentationTimeUs, int accessUnits)
            throws InitializationException, WriteException {
        if (!processFloat) return super.handleBuffer(input, presentationTimeUs, accessUnits);
        if (pendingOutput == null) {
            ByteBuffer pcm = input.duplicate().order(ByteOrder.nativeOrder());
            if (inputEncoding != C.ENCODING_PCM_FLOAT) {
                int sampleBytes = inputEncoding == C.ENCODING_PCM_24BIT ? 3 : 4;
                int samples = pcm.remaining() / sampleBytes;
                int outputBytes = samples * 4;
                if (converted == null || converted.capacity() < outputBytes) {
                    converted = ByteBuffer.allocateDirect(outputBytes).order(ByteOrder.nativeOrder());
                }
                converted.clear();
                for (int i = 0; i < samples; i++) {
                    int value = inputEncoding == C.ENCODING_PCM_24BIT
                            ? ((pcm.get() & 0xff) << 8) | ((pcm.get() & 0xff) << 16) | (pcm.get() << 24)
                            : pcm.getInt();
                    converted.putFloat((float) (value / 2147483648.0));
                }
                converted.flip();
                pcm = converted;
            }
            processor.queueInput(pcm);
            pendingOutput = processor.getOutput();
            pendingInput = input;
        } else if (pendingInput != input) {
            throw new IllegalStateException("Retry the same PCM buffer until the sink consumes it");
        }
        if (!super.handleBuffer(pendingOutput, presentationTimeUs, accessUnits)) return false;
        input.position(input.limit());
        pendingOutput = null;
        pendingInput = null;
        return true;
    }

    @Override
    public boolean hasPendingData() {
        return pendingOutput != null || super.hasPendingData();
    }

    @Override
    public boolean isEnded() {
        return pendingOutput == null && super.isEnded();
    }

    @Override
    public void flush() {
        pendingOutput = null;
        pendingInput = null;
        if (processFloat) processor.flush();
        super.flush();
    }

    @Override
    public void reset() {
        pendingOutput = null;
        pendingInput = null;
        converted = null;
        if (processFloat) processor.reset();
        processFloat = false;
        super.reset();
    }
}
```

---

## `third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/Pcm16Quantizer.java`

```java
package com.ryanheise.just_audio;

/** Symmetric PCM16 conversion: every short survives a unity float round trip. */
final class Pcm16Quantizer {
    private Pcm16Quantizer() {}

    static short fromFloat(float value) {
        int sample = Math.round(value * 32768f);
        return (short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, sample));
    }
}
```

---

## `third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/PulsrOutputRouting.java`

```java
package com.ryanheise.just_audio;

import android.media.AudioDeviceInfo;
import android.media.AudioTrack;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.audio.DefaultAudioSink;
import java.lang.reflect.Field;
import java.util.Map;
import java.util.WeakHashMap;

/** App-owned media routing. Preferences and measured routes are deliberately separate. */
@androidx.media3.common.util.UnstableApi
public final class PulsrOutputRouting {
    private static final Map<ExoPlayer, Boolean> players = new WeakHashMap<>();
    private static final Map<DefaultAudioSink, Boolean> sinks = new WeakHashMap<>();
    private static final Map<AAudioAudioSink, Boolean> nativeSinks = new WeakHashMap<>();
    private static AudioDeviceInfo preferred;
    private PulsrOutputRouting() {}

    public static synchronized void register(ExoPlayer player, boolean aaudio) {
        players.put(player, aaudio);
        player.setPreferredAudioDevice(preferred);
    }

    public static synchronized void unregister(ExoPlayer player) { players.remove(player); }

    public static synchronized void observe(DefaultAudioSink sink) { sinks.put(sink, true); }

    public static synchronized void observe(AAudioAudioSink sink) { nativeSinks.put(sink, true); }

    public static synchronized boolean select(AudioDeviceInfo device) {
        try {
            for (ExoPlayer player : players.keySet()) player.setPreferredAudioDevice(device);
            preferred = device;
            return true;
        } catch (RuntimeException failure) { return false; }
    }

    /** [device ID, app AudioTrack rate, PCM encoding]. Zero means unverified.
     * This describes the app stream, not a claim about the downstream DAC/mixer.
     */
    public static synchronized boolean isPlaying() {
        for (AAudioAudioSink sink : nativeSinks.keySet()) {
            if (sink.isPlaying() && sink.measuredStream()[1] > 0) return true;
        }
        try {
            Field field = DefaultAudioSink.class.getDeclaredField("audioTrack");
            field.setAccessible(true);
            for (DefaultAudioSink sink : sinks.keySet()) {
                AudioTrack track = (AudioTrack) field.get(sink);
                if (track != null && track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) return true;
            }
        } catch (ReflectiveOperationException | RuntimeException ignored) {}
        return false;
    }

    public static synchronized int[] snapshot() {
        int[] nativeFallback = null;
        for (AAudioAudioSink sink : nativeSinks.keySet()) {
            int[] measured = sink.measuredStream();
            if (measured[1] == 0) continue;
            nativeFallback = measured;
            if (sink.isPlaying()) return measured;
        }
        try {
            Field field = DefaultAudioSink.class.getDeclaredField("audioTrack");
            field.setAccessible(true);
            AudioTrack fallback = null;
            for (DefaultAudioSink sink : sinks.keySet()) {
                AudioTrack track = (AudioTrack) field.get(sink);
                if (track == null || track.getState() != AudioTrack.STATE_INITIALIZED) continue;
                fallback = track;
                if (track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) return snapshot(track);
            }
            if (fallback != null) return snapshot(fallback);
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            // Media3 internals may change. Unknown is safer than an invented format.
        }
        return nativeFallback != null ? nativeFallback : new int[] {0, 0, 0};
    }

    private static int[] snapshot(AudioTrack track) {
        AudioDeviceInfo routed = track.getRoutedDevice();
        return new int[] {routed == null ? 0 : routed.getId(), track.getSampleRate(), track.getAudioFormat()};
    }
}
```

---

## `third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/AudioPlayer.java`

```java
package com.ryanheise.just_audio;

import android.content.Context;
import android.media.audiofx.AudioEffect;
import android.media.audiofx.Equalizer;
import android.media.audiofx.LoudnessEnhancer;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.DefaultAudioSink;
import androidx.media3.exoplayer.DefaultLivePlaybackSpeedControl;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlaybackException;
import androidx.media3.exoplayer.LivePlaybackSpeedControl;
import androidx.media3.exoplayer.LoadControl;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.Player;
import androidx.media3.common.Player.PositionInfo;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.common.Timeline;
import androidx.media3.common.Tracks;
import androidx.media3.common.TrackSelectionParameters;
import androidx.media3.common.TrackSelectionParameters.AudioOffloadPreferences;
import androidx.media3.common.AudioAttributes;
import androidx.media3.exoplayer.NoSampleRenderer;
import androidx.media3.exoplayer.Renderer;
import androidx.media3.exoplayer.RenderersFactory;
import androidx.media3.extractor.DefaultExtractorsFactory;
import androidx.media3.common.Metadata;
import androidx.media3.exoplayer.metadata.MetadataOutput;
import androidx.media3.extractor.metadata.icy.IcyHeaders;
import androidx.media3.extractor.metadata.icy.IcyInfo;
import androidx.media3.exoplayer.source.ClippingMediaSource; // Deprecated
// For some reason, this import triggers the [deprecation] warning, despite the
// warnings being suppressed at each use.
// import androidx.media3.exoplayer.source.ConcatenatingMediaSource; // Deprecated
import androidx.media3.exoplayer.source.MediaSource; // Deprecated
import androidx.media3.exoplayer.source.ProgressiveMediaSource; // Deprecated
import androidx.media3.exoplayer.source.ShuffleOrder;
import androidx.media3.exoplayer.source.ShuffleOrder.DefaultShuffleOrder;
import androidx.media3.exoplayer.source.SilenceMediaSource; // Deprecated
import androidx.media3.common.TrackGroup;
import androidx.media3.exoplayer.dash.DashMediaSource; // Deprecated
import androidx.media3.exoplayer.hls.HlsMediaSource; // Deprecated
import androidx.media3.exoplayer.trackselection.TrackSelectionArray;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.util.Util;
import io.flutter.Log;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.EventChannel.EventSink;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Random;

public class AudioPlayer implements MethodCallHandler, Player.Listener, MetadataOutput {
    public static final int ERROR_ABORT = 10000000;

    static final String TAG = "AudioPlayer";

    private static Random random = new Random();

    private final Context context;
    private final MethodChannel methodChannel;
    private final BetterEventChannel eventChannel;
    private final BetterEventChannel dataEventChannel;

    private ProcessingState processingState;
    private long updatePosition;
    private long updateTime;
    private long bufferedPosition;
    private Long seekPos;
    private Result prepareResult;
    private Result playResult;
    private Result seekResult;
    private Map<String, MediaSource> mediaSources = new HashMap<String, MediaSource>();
    private final List<MediaSource> loadedSources = new ArrayList<>();
    private ShuffleOrder outputShuffleOrder = new ShuffleOrder.DefaultShuffleOrder(0);
    private IcyInfo icyInfo;
    private IcyHeaders icyHeaders;
    private AudioAttributes pendingAudioAttributes;
    private LoadControl loadControl;
    private boolean offloadSchedulingEnabled;
    private AudioOffloadPreferences audioOffloadPreferences;
    private boolean useLazyPreparation;
    private LivePlaybackSpeedControl livePlaybackSpeedControl;
    private List<Object> rawAudioEffects;
    private List<AudioEffect> audioEffects = new ArrayList<AudioEffect>();
    private Map<String, AudioEffect> audioEffectsMap = new HashMap<String, AudioEffect>();
    private int lastPlaylistLength = 0;
    private Map<String, Object> pendingPlaybackEvent;

    private ExoPlayer player;
    private Integer audioSessionId;
    // Pulsr fork: per-player DSP processor handle for the sample-accurate
    // gain-ramp API (dspSetGainCurve / dspClearGainCurve).
    private NativeDspAudioProcessor dspAudioProcessor;
    // Pulsr fork: opt-in 24/32-bit float output path. Off by default so the
    // audio sink is built exactly as before (16-bit) unless Dart enables it.
    private boolean floatOutputEnabled = false;
    // Pulsr fork: opt-in AAudio "Direct" output path. Off by default so the
    // sink is built exactly as before (DefaultAudioSink + DSP chain). When
    // enabled, the whole Media3 sink is replaced by AAudioAudioSink
    // (bit-perfect; the DSP processor chain is bypassed in this mode).
    private volatile boolean aaudioOutputEnabled = false;
    private boolean aaudioPreferExclusive = true;
    private int aaudioTargetBufferMs = 150;
    private Integer errorCode;
    private String errorMessage;
    private Integer currentIndex;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable bufferWatcher = new Runnable() {
        @Override
        public void run() {
            if (player == null) {
                return;
            }

            long newBufferedPosition = player.getBufferedPosition();
            if (newBufferedPosition != bufferedPosition) {
                // This method updates bufferedPosition.
                broadcastImmediatePlaybackEvent();
            }
            switch (player.getPlaybackState()) {
            case Player.STATE_BUFFERING:
                handler.postDelayed(this, 200);
                break;
            case Player.STATE_READY:
                if (player.getPlayWhenReady()) {
                    handler.postDelayed(this, 500);
                } else {
                    handler.postDelayed(this, 1000);
                }
                break;
            default:
                // Stop watching buffer
            }
        }
    };

    public AudioPlayer(
        final Context applicationContext,
        final BinaryMessenger messenger,
        final String id,
        Map<?, ?> audioLoadConfiguration,
        List<Object> rawAudioEffects,
        Map<?, ?> audioOffloadPreferences,
        Boolean offloadSchedulingEnabled,
        Boolean useLazyPreparation
    ) {
        this.context = applicationContext;
        this.rawAudioEffects = rawAudioEffects;
        this.offloadSchedulingEnabled = offloadSchedulingEnabled != null ? offloadSchedulingEnabled : false;
        this.useLazyPreparation = useLazyPreparation != null ? useLazyPreparation : false;

        if (audioOffloadPreferences != null) {
            this.audioOffloadPreferences = new AudioOffloadPreferences.Builder()
                .setIsGaplessSupportRequired((Boolean)audioOffloadPreferences.get("isGaplessSupportRequired"))
                .setIsSpeedChangeSupportRequired((Boolean)audioOffloadPreferences.get("isSpeedChangeSupportRequired"))
                .setAudioOffloadMode((Integer)audioOffloadPreferences.get("audioOffloadMode"))
                .build();
        } else {
            final int offloadMode = offloadSchedulingEnabled
                ? AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_ENABLED
                : AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_DISABLED;
            this.audioOffloadPreferences = new AudioOffloadPreferences.Builder()
                .setIsGaplessSupportRequired(!offloadSchedulingEnabled)
                .setIsSpeedChangeSupportRequired(!offloadSchedulingEnabled)
                .setAudioOffloadMode(offloadMode)
                .build();
        }

        methodChannel = new MethodChannel(messenger, "com.ryanheise.just_audio.methods." + id);
        methodChannel.setMethodCallHandler(this);
        eventChannel = new BetterEventChannel(messenger, "com.ryanheise.just_audio.events." + id);
        dataEventChannel = new BetterEventChannel(messenger, "com.ryanheise.just_audio.data." + id);
        processingState = ProcessingState.idle;
        if (audioLoadConfiguration != null) {
            Map<?, ?> loadControlMap = (Map<?, ?>)audioLoadConfiguration.get("androidLoadControl");
            if (loadControlMap != null) {
                DefaultLoadControl.Builder builder = new DefaultLoadControl.Builder()
                    .setBufferDurationsMs(
                        (int)((getLong(loadControlMap.get("minBufferDuration")))/1000),
                        (int)((getLong(loadControlMap.get("maxBufferDuration")))/1000),
                        (int)((getLong(loadControlMap.get("bufferForPlaybackDuration")))/1000),
                        (int)((getLong(loadControlMap.get("bufferForPlaybackAfterRebufferDuration")))/1000)
                    )
                    .setPrioritizeTimeOverSizeThresholds((Boolean)loadControlMap.get("prioritizeTimeOverSizeThresholds"))
                    .setBackBuffer((int)((getLong(loadControlMap.get("backBufferDuration")))/1000), false);
                if (loadControlMap.get("targetBufferBytes") != null) {
                    builder.setTargetBufferBytes((Integer)loadControlMap.get("targetBufferBytes"));
                }
                loadControl = builder.build();
            }
            Map<?, ?> livePlaybackSpeedControlMap = (Map<?, ?>)audioLoadConfiguration.get("androidLivePlaybackSpeedControl");
            if (livePlaybackSpeedControlMap != null) {
                DefaultLivePlaybackSpeedControl.Builder builder = new DefaultLivePlaybackSpeedControl.Builder()
                    .setFallbackMinPlaybackSpeed((float)((double)((Double)livePlaybackSpeedControlMap.get("fallbackMinPlaybackSpeed"))))
                    .setFallbackMaxPlaybackSpeed((float)((double)((Double)livePlaybackSpeedControlMap.get("fallbackMaxPlaybackSpeed"))))
                    .setMinUpdateIntervalMs(((getLong(livePlaybackSpeedControlMap.get("minUpdateInterval")))/1000))
                    .setProportionalControlFactor((float)((double)((Double)livePlaybackSpeedControlMap.get("proportionalControlFactor"))))
                    .setMaxLiveOffsetErrorMsForUnitSpeed(((getLong(livePlaybackSpeedControlMap.get("maxLiveOffsetErrorForUnitSpeed")))/1000))
                    .setTargetLiveOffsetIncrementOnRebufferMs(((getLong(livePlaybackSpeedControlMap.get("targetLiveOffsetIncrementOnRebuffer")))/1000))
                    .setMinPossibleLiveOffsetSmoothingFactor((float)((double)((Double)livePlaybackSpeedControlMap.get("minPossibleLiveOffsetSmoothingFactor"))));
                livePlaybackSpeedControl = builder.build();
            }
        }
    }

    private void startWatchingBuffer() {
        handler.removeCallbacks(bufferWatcher);
        handler.post(bufferWatcher);
    }

    private void setAudioSessionId(int audioSessionId) {
        if (audioSessionId == C.AUDIO_SESSION_ID_UNSET) {
            this.audioSessionId = null;
        } else {
            this.audioSessionId = audioSessionId;
        }
        clearAudioEffects();
        if (this.audioSessionId != null && rawAudioEffects != null) {
            for (Object rawAudioEffect : rawAudioEffects) {
                Map<?, ?> json = (Map<?, ?>)rawAudioEffect;
                AudioEffect audioEffect = decodeAudioEffect(rawAudioEffect, this.audioSessionId);
                if ((Boolean)json.get("enabled")) {
                    audioEffect.setEnabled(true);
                }
                audioEffects.add(audioEffect);
                audioEffectsMap.put((String)json.get("type"), audioEffect);
            }
        }
        enqueuePlaybackEvent();
    }

    @Override
    public void onAudioSessionIdChanged(int audioSessionId) {
        setAudioSessionId(audioSessionId);
        broadcastPendingPlaybackEvent();
    }

    @Override
    public void onMetadata(Metadata metadata) {
        for (int i = 0; i < metadata.length(); i++) {
            final Metadata.Entry entry = metadata.get(i);
            if (entry instanceof IcyInfo) {
                icyInfo = (IcyInfo) entry;
                broadcastImmediatePlaybackEvent();
            }
        }
    }

    @Override
    public void onTracksChanged(Tracks tracks) {
        for (int i = 0; i < tracks.getGroups().size(); i++) {
            TrackGroup trackGroup = tracks.getGroups().get(i).getMediaTrackGroup();

            for (int j = 0; j < trackGroup.length; j++) {
                Metadata metadata = trackGroup.getFormat(j).metadata;

                if (metadata != null) {
                    for (int k = 0; k < metadata.length(); k++) {
                        final Metadata.Entry entry = metadata.get(k);
                        if (entry instanceof IcyHeaders) {
                            icyHeaders = (IcyHeaders) entry;
                            broadcastImmediatePlaybackEvent();
                        }
                    }
                }
            }
        }
    }

    private boolean updatePositionIfChanged() {
        if (player == null) return false;
        if (!player.getPlayWhenReady() || processingState != ProcessingState.ready) {
            if (getCurrentPosition() == updatePosition) return false;
        }
        updatePosition = getCurrentPosition();
        updateTime = System.currentTimeMillis();
        return true;
    }

    private void updatePosition() {
        updatePosition = getCurrentPosition();
        updateTime = System.currentTimeMillis();
    }

    @Override
    public void onPositionDiscontinuity(PositionInfo oldPosition, PositionInfo newPosition, int reason) {
        updatePosition();
        switch (reason) {
        case Player.DISCONTINUITY_REASON_AUTO_TRANSITION:
        case Player.DISCONTINUITY_REASON_SEEK:
            updateCurrentIndex();
            break;
        }
        broadcastImmediatePlaybackEvent();
    }

    @Override
    public void onTimelineChanged(Timeline timeline, int reason) {
        if (processingState == ProcessingState.loading) {
            return;
        }
        if (updateCurrentIndex()) {
            broadcastImmediatePlaybackEvent();
        }
        if (player.getPlaybackState() == Player.STATE_ENDED) {
            try {
                if (player.getPlayWhenReady()) {
                    if (lastPlaylistLength == 0 && player.getMediaItemCount() > 0) {
                        player.seekTo(0, 0L);
                    } else if (player.hasNextMediaItem()) {
                        player.seekToNextMediaItem();
                    }
                } else {
                    if (player.getCurrentMediaItemIndex() < player.getMediaItemCount()) {
                        player.seekTo(player.getCurrentMediaItemIndex(), 0L);
                    }
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        lastPlaylistLength = player.getMediaItemCount();
    }

    private boolean updateCurrentIndex() {
        if (processingState == ProcessingState.loading) {
            return false;
        }
        Integer newIndex = player.getCurrentMediaItemIndex();
        // newIndex is never null.
        // currentIndex is sometimes null.
        if (!newIndex.equals(currentIndex)) {
            currentIndex = newIndex;
            return true;
        }
        return false;
    }

    @Override
    public void onPlaybackStateChanged(int playbackState) {
        switch (playbackState) {
        case Player.STATE_READY:
            if (player.getPlayWhenReady())
                updatePosition();
            processingState = ProcessingState.ready;
            errorCode = null;
            errorMessage = null;
            broadcastImmediatePlaybackEvent();
            if (prepareResult != null) {
                Map<String, Object> response = new HashMap<>();
                response.put("duration", getDuration() == C.TIME_UNSET ? null : (1000 * getDuration()));
                prepareResult.success(response);
                prepareResult = null;
                if (pendingAudioAttributes != null) {
                    player.setAudioAttributes(pendingAudioAttributes, false);
                    pendingAudioAttributes = null;
                }
            }
            if (seekResult != null) {
                completeSeek();
            }
            break;
        case Player.STATE_BUFFERING:
            updatePositionIfChanged();
            if (processingState != ProcessingState.buffering && processingState != ProcessingState.loading) {
                processingState = ProcessingState.buffering;
                errorCode = null;
                errorMessage = null;
                broadcastImmediatePlaybackEvent();
            }
            startWatchingBuffer();
            break;
        case Player.STATE_ENDED:
            if (processingState != ProcessingState.completed) {
                updatePosition();
                processingState = ProcessingState.completed;
                errorCode = null;
                errorMessage = null;
                broadcastImmediatePlaybackEvent();
            }
            if (prepareResult != null) {
                Map<String, Object> response = new HashMap<>();
                response.put("duration", getDuration() == C.TIME_UNSET ? null : (1000 * getDuration()));
                prepareResult.success(response);
                prepareResult = null;
                if (pendingAudioAttributes != null) {
                    player.setAudioAttributes(pendingAudioAttributes, false);
                    pendingAudioAttributes = null;
                }
            }
            if (playResult != null) {
                playResult.success(new HashMap<String, Object>());
                playResult = null;
            }
            break;
        }
    }

    @Override
    public void onPlayerError(PlaybackException error) {
        if (aaudioOutputEnabled && error instanceof ExoPlaybackException
                && ((ExoPlaybackException) error).type == ExoPlaybackException.TYPE_RENDERER) {
            Throwable cause = ((ExoPlaybackException) error).getRendererException();
            while (cause != null) {
                if (cause instanceof AudioSink.ConfigurationException
                        || cause instanceof AudioSink.InitializationException
                        || cause instanceof AudioSink.WriteException) {
                    // A stream can be refused after the setting was accepted
                    // (a new song or device). Recover once with the mixed sink;
                    // never label this fallback as exclusive output.
                    Log.w(TAG, "AAudio output refused; restoring AudioTrack", error);
                    aaudioOutputEnabled = false;
                    handler.post(() -> {
                        if (player == null) return;
                        rebuildPlayerForOutput();
                        if (!loadedSources.isEmpty()) player.prepare();
                    });
                    return;
                }
                cause = cause.getCause();
            }
        }
        if (error instanceof ExoPlaybackException) {
            final ExoPlaybackException exoError = (ExoPlaybackException)error;
            switch (exoError.type) {
            case ExoPlaybackException.TYPE_SOURCE:
                Log.e(TAG, "TYPE_SOURCE: " + exoError.getSourceException().getMessage());
                break;

            case ExoPlaybackException.TYPE_RENDERER:
                Log.e(TAG, "TYPE_RENDERER: " + exoError.getRendererException().getMessage());
                break;

            case ExoPlaybackException.TYPE_UNEXPECTED:
                Log.e(TAG, "TYPE_UNEXPECTED: " + exoError.getUnexpectedException().getMessage());
                break;

            default:
                Log.e(TAG, "default ExoPlaybackException: " + exoError.getUnexpectedException().getMessage());
            }
            // TODO: send both errorCode and type
            sendError(exoError.type, exoError.getMessage(), mapOf("index", currentIndex));
        } else {
            Log.e(TAG, "default PlaybackException: " + error.getMessage());
            sendError(error.errorCode, error.getMessage(), mapOf("index", currentIndex));
        }
    }

    private void completeSeek() {
        seekPos = null;
        seekResult.success(new HashMap<String, Object>());
        seekResult = null;
    }

    @Override
    public void onMethodCall(final MethodCall call, final Result result) {
        // Pulsr fork: the float-output preference must reach the player BEFORE
        // the sink is built, so handle it without forcing initialization. Once
        // the player exists this only updates the stored flag; an already
        // configured sink keeps its encodings until it is rebuilt.
        if ("dspSetFloatOutput".equals(call.method)) {
            Boolean requested = call.argument("enabled");
            boolean enabled = requested != null && requested;
            result.success(applyFloatOutput(enabled));
            return;
        }

        // Pulsr fork: AAudio Direct output preference must reach the player
        // BEFORE the sink is built, so handle it without forcing
        // initialization (same pattern as dspSetFloatOutput).
        if ("dspSetAaudioOutput".equals(call.method)) {
            Boolean requested = call.argument("enabled");
            Boolean exclusive = call.argument("preferExclusive");
            Integer bufferMs = call.argument("targetBufferMs");
            boolean enabled = requested != null && requested;
            boolean changed = false;
            if (exclusive != null) {
                changed |= aaudioPreferExclusive != exclusive;
                aaudioPreferExclusive = exclusive;
            }
            if (bufferMs != null && bufferMs >= 20 && bufferMs <= 1000) {
                changed |= aaudioTargetBufferMs != bufferMs;
                aaudioTargetBufferMs = bufferMs;
            }
            boolean effective = enabled && Build.VERSION.SDK_INT >= 28 && AaudioNativeBridge.ensureAvailable();
            if (effective && !aaudioOutputEnabled) {
                // Library availability alone says nothing about whether this
                // device grants the requested sharing mode. Probe a real stream
                // before accepting/persisting the preference.
                androidx.media3.common.Format format = player == null ? null : player.getAudioFormat();
                int rate = format != null && format.sampleRate > 0 ? format.sampleRate : 48000;
                int channels = format != null && format.channelCount > 0 ? format.channelCount : 2;
                long probe = 0L;
                try {
                    probe = AaudioNativeBridge.nativeOpen(rate, channels,
                            AaudioNativeBridge.ENCODING_PCM_I16, aaudioPreferExclusive,
                            aaudioTargetBufferMs);
                    effective = probe != 0L;
                } catch (LinkageError | RuntimeException refused) {
                    effective = false;
                    Log.w(TAG, "AAudio output probe refused", refused);
                } finally {
                    if (probe != 0L) AaudioNativeBridge.nativeClose(probe);
                }
            }
            changed = aaudioOutputEnabled != effective || (effective && changed);
            aaudioOutputEnabled = effective;
            if (changed) rebuildPlayerForOutput();
            result.success(effective == enabled);
            return;
        }

        ensurePlayerInitialized();

        try {
            switch (call.method) {
            case "load":
                Long initialPosition = getLong(call.argument("initialPosition"));
                Integer initialIndex = call.argument("initialIndex");
                Map<?, ?> audioSourceMap = call.argument("audioSource");
                MediaSource[] children = getAudioSourcesArray(audioSourceMap.get("children"));
                ShuffleOrder shuffleOrder = decodeShuffleOrder(mapGet(audioSourceMap, "shuffleOrder"));
                load(Arrays.asList(children), shuffleOrder,
                        initialPosition == null ? C.TIME_UNSET : initialPosition / 1000,
                        initialIndex, result);
                break;
            case "play":
                play(result);
                break;
            case "pause":
                pause();
                result.success(new HashMap<String, Object>());
                break;
            case "setVolume":
                setVolume((float) ((double) ((Double) call.argument("volume"))));
                result.success(new HashMap<String, Object>());
                break;
            case "dspSetGainCurve": {
                // Pulsr fork: arm a sample-accurate piecewise-linear gain ramp
                // on this player's NativeDspAudioProcessor. Responds false when
                // unsupported so Dart falls back to stepped setVolume().
                boolean applied = false;
                try {
                    // AAudio Direct replaces the whole sink and bypasses the
                    // processor chain, so the curve would never be applied.
                    // Report unsupported so callers fall back to stepped
                    // volume instead of silently not fading at all.
                    if (aaudioOutputEnabled) {
                        result.success(false);
                        break;
                    }
                    List<?> gains = call.argument("gains");
                    Integer segmentMs = call.argument("segmentMs");
                    if (dspAudioProcessor != null && gains != null && !gains.isEmpty()) {
                        double[] curve = new double[gains.size()];
                        boolean valid = true;
                        for (int i = 0; i < curve.length; i++) {
                            Object g = gains.get(i);
                            if (!(g instanceof Number)) {
                                valid = false;
                                break;
                            }
                            curve[i] = ((Number) g).doubleValue();
                        }
                        if (valid) {
                            applied = dspAudioProcessor.setGainCurve(curve,
                                    segmentMs == null ? 20 : segmentMs);
                        }
                    }
                } catch (Exception e) {
                    Log.w(TAG, "dspSetGainCurve failed: " + e.getMessage());
                    applied = false;
                }
                result.success(applied);
                break;
            }
            case "dspClearGainCurve":
                result.success(dspAudioProcessor != null && dspAudioProcessor.clearGainCurve());
                break;
            case "dspSetTransitionMuted":
                result.success(!aaudioOutputEnabled && dspAudioProcessor != null &&
                        dspAudioProcessor.setTransitionMuted(Boolean.TRUE.equals(call.argument("muted"))));
                break;
            case "dspGetTransitionGain":
                result.success(!aaudioOutputEnabled && dspAudioProcessor != null
                        ? (double) dspAudioProcessor.getTransitionGain() : null);
                break;
            case "setSpeed":
                setSpeed((float) ((double) ((Double) call.argument("speed"))));
                result.success(new HashMap<String, Object>());
                break;
            case "setPitch":
                setPitch((float) ((double) ((Double) call.argument("pitch"))));
                result.success(new HashMap<String, Object>());
                break;
            case "setSkipSilence":
                setSkipSilenceEnabled((Boolean) call.argument("enabled"));
                result.success(new HashMap<String, Object>());
                break;
            case "setLoopMode":
                setLoopMode((Integer) call.argument("loopMode"));
                result.success(new HashMap<String, Object>());
                break;
            case "setShuffleMode":
                setShuffleModeEnabled((Integer) call.argument("shuffleMode") == 1);
                result.success(new HashMap<String, Object>());
                break;
            case "setShuffleOrder":
                setShuffleOrder(call.argument("audioSource"));
                result.success(new HashMap<String, Object>());
                break;
            case "setAutomaticallyWaitsToMinimizeStalling":
                result.success(new HashMap<String, Object>());
                break;
            case "setCanUseNetworkResourcesForLiveStreamingWhilePaused":
                result.success(new HashMap<String, Object>());
                break;
            case "setPreferredPeakBitRate":
                result.success(new HashMap<String, Object>());
                break;
            case "seek":
                Long position = getLong(call.argument("position"));
                Integer index = call.argument("index");
                seek(position == null ? C.TIME_UNSET : position / 1000, index, result);
                break;
            case "concatenatingInsertAll":
                if (((String)call.argument("id")).length() == 0) {
                    List<MediaSource> inserted = getAudioSources(call.argument("children"));
                    player.addMediaSources(call.argument("index"), inserted);
                    loadedSources.addAll(call.argument("index"), inserted);
                    applyShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                    result.success(new HashMap<String, Object>());
                } else {
                    concatenating(call.argument("id"))
                        .addMediaSources(call.argument("index"), getAudioSources(call.argument("children")), handler, () -> result.success(new HashMap<String, Object>()));
                    concatenating(call.argument("id"))
                        .setShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                }
                break;
            case "concatenatingRemoveRange":
                if (((String)call.argument("id")).length() == 0) {
                    player.removeMediaItems(call.argument("startIndex"), call.argument("endIndex"));
                    loadedSources.subList(call.argument("startIndex"), call.argument("endIndex")).clear();
                    applyShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                    result.success(new HashMap<String, Object>());
                } else {
                    concatenating(call.argument("id"))
                        .removeMediaSourceRange(call.argument("startIndex"), call.argument("endIndex"), handler, () -> result.success(new HashMap<String, Object>()));
                    concatenating(call.argument("id"))
                        .setShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                }
                break;
            case "concatenatingMove":
                if (((String)call.argument("id")).length() == 0) {
                    player.moveMediaItem(call.argument("currentIndex"), call.argument("newIndex"));
                    MediaSource moved = loadedSources.remove((int) call.argument("currentIndex"));
                    loadedSources.add(call.argument("newIndex"), moved);
                    applyShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                    result.success(new HashMap<String, Object>());
                } else {
                    concatenating(call.argument("id"))
                        .moveMediaSource(call.argument("currentIndex"), call.argument("newIndex"), handler, () -> result.success(new HashMap<String, Object>()));
                    concatenating(call.argument("id"))
                        .setShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                }
                break;
            case "setAndroidAudioAttributes":
                setAudioAttributes(call.argument("contentType"), call.argument("flags"), call.argument("usage"));
                result.success(new HashMap<String, Object>());
                break;
            case "audioEffectSetEnabled":
                audioEffectSetEnabled(call.argument("type"), call.argument("enabled"));
                result.success(new HashMap<String, Object>());
                break;
            case "androidLoudnessEnhancerSetTargetGain":
                loudnessEnhancerSetTargetGain(call.argument("targetGain"));
                result.success(new HashMap<String, Object>());
                break;
            case "androidEqualizerGetParameters":
                result.success(equalizerAudioEffectGetParameters());
                break;
            case "androidEqualizerBandSetGain":
                equalizerBandSetGain(call.argument("bandIndex"), call.argument("gain"));
                result.success(new HashMap<String, Object>());
                break;
            default:
                result.notImplemented();
                break;
            }
        } catch (IllegalStateException e) {
            e.printStackTrace();
            result.error("Illegal state: " + e.getMessage(), e.toString(), null);
        } catch (Exception e) {
            e.printStackTrace();
            result.error("Error: " + e, e.toString(), null);
        } finally {
            broadcastPendingPlaybackEvent();
        }
    }

    private ShuffleOrder decodeShuffleOrder(List<Integer> indexList) {
        int[] shuffleIndices = new int[indexList.size()];
        for (int i = 0; i < shuffleIndices.length; i++) {
            shuffleIndices[i] = indexList.get(i);
        }
        return new DefaultShuffleOrder(shuffleIndices, random.nextLong());
    }

    @SuppressWarnings("deprecation")
    private androidx.media3.exoplayer.source.ConcatenatingMediaSource concatenating(final Object index) {
        return (androidx.media3.exoplayer.source.ConcatenatingMediaSource)mediaSources.get((String)index);
    }

    @SuppressWarnings("deprecation")
    private void setShuffleOrder(final Object json) {
        Map<?, ?> map = (Map<?, ?>)json;
        String id = mapGet(map, "id");
        MediaSource mediaSource = mediaSources.get(id);
        if (mediaSource == null) return;
        switch ((String)mapGet(map, "type")) {
        case "concatenating":
            androidx.media3.exoplayer.source.ConcatenatingMediaSource concatenatingMediaSource = (androidx.media3.exoplayer.source.ConcatenatingMediaSource)mediaSource;
            concatenatingMediaSource.setShuffleOrder(decodeShuffleOrder(mapGet(map, "shuffleOrder")));
            List<Object> children = mapGet(map, "children");
            for (Object child : children) {
                setShuffleOrder(child);
            }
            break;
        case "looping":
            setShuffleOrder(mapGet(map, "child"));
            break;
        }
    }

    private MediaSource getAudioSource(final Object json) {
        Map<?, ?> map = (Map<?, ?>)json;
        String id = (String)map.get("id");
        MediaSource mediaSource = mediaSources.get(id);
        if (mediaSource == null) {
            mediaSource = decodeAudioSource(map);
            mediaSources.put(id, mediaSource);
        }
        return mediaSource;
    }

    private DefaultExtractorsFactory buildExtractorsFactory(Map<?, ?> options) {
        DefaultExtractorsFactory extractorsFactory = new DefaultExtractorsFactory();
        boolean constantBitrateSeekingEnabled = true;
        boolean constantBitrateSeekingAlwaysEnabled = false;
        int mp3Flags = 0;
        if (options != null) {
            Map<?, ?> androidExtractorOptions = (Map<?, ?>)options.get("androidExtractorOptions");
            if (androidExtractorOptions != null) {
                constantBitrateSeekingEnabled = (Boolean)androidExtractorOptions.get("constantBitrateSeekingEnabled");
                constantBitrateSeekingAlwaysEnabled = (Boolean)androidExtractorOptions.get("constantBitrateSeekingAlwaysEnabled");
                mp3Flags = (Integer)androidExtractorOptions.get("mp3Flags");
            }
        }
        extractorsFactory.setConstantBitrateSeekingEnabled(constantBitrateSeekingEnabled);
        extractorsFactory.setConstantBitrateSeekingAlwaysEnabled(constantBitrateSeekingAlwaysEnabled);
        extractorsFactory.setMp3ExtractorFlags(mp3Flags);
        return extractorsFactory;
    }

    @SuppressWarnings("deprecation")
    private MediaSource decodeAudioSource(final Object json) {
        Map<?, ?> map = (Map<?, ?>)json;
        String id = (String)map.get("id");
        switch ((String)map.get("type")) {
        case "progressive":
            return new ProgressiveMediaSource.Factory(buildDataSourceFactory(mapGet(map, "headers")), buildExtractorsFactory(mapGet(map, "options")))
                    .createMediaSource(new MediaItem.Builder()
                            .setUri(Uri.parse((String)map.get("uri")))
                            .setTag(id)
                            .build());
        case "dash":
            return new DashMediaSource.Factory(buildDataSourceFactory(mapGet(map, "headers")))
                    .createMediaSource(new MediaItem.Builder()
                            .setUri(Uri.parse((String)map.get("uri")))
                            .setMimeType(MimeTypes.APPLICATION_MPD)
                            .setTag(id)
                            .build());
        case "hls":
            return new HlsMediaSource.Factory(buildDataSourceFactory(mapGet(map, "headers")))
                    .createMediaSource(new MediaItem.Builder()
                            .setUri(Uri.parse((String)map.get("uri")))
                            .setMimeType(MimeTypes.APPLICATION_M3U8)
                            .build());
        case "silence":
            return new SilenceMediaSource.Factory()
                    .setDurationUs(getLong(map.get("duration")))
                    .setTag(id)
                    .createMediaSource();
        case "concatenating":
            return new androidx.media3.exoplayer.source.ConcatenatingMediaSource(
                    false, // isAtomic
                    (Boolean)map.get("useLazyPreparation"),
                    decodeShuffleOrder(mapGet(map, "shuffleOrder")),
                    getAudioSourcesArray(map.get("children")));
        case "clipping":
            Long start = getLong(map.get("start"));
            Long end = getLong(map.get("end"));
            return new ClippingMediaSource(getAudioSource(map.get("child")),
                    start != null ? start : 0,
                    end != null ? end : C.TIME_END_OF_SOURCE);
        case "looping":
            Integer count = (Integer)map.get("count");
            MediaSource looperChild = getAudioSource(map.get("child"));
            MediaSource[] looperChildren = new MediaSource[count];
            for (int i = 0; i < looperChildren.length; i++) {
                looperChildren[i] = looperChild;
            }
            return new androidx.media3.exoplayer.source.ConcatenatingMediaSource(looperChildren);
        default:
            throw new IllegalArgumentException("Unknown AudioSource type: " + map.get("type"));
        }
    }

    private MediaSource[] getAudioSourcesArray(final Object json) {
        List<MediaSource> mediaSources = getAudioSources(json);
        MediaSource[] mediaSourcesArray = new MediaSource[mediaSources.size()];
        mediaSources.toArray(mediaSourcesArray);
        return mediaSourcesArray;
    }

    private List<MediaSource> getAudioSources(final Object json) {
        if (!(json instanceof List)) throw new RuntimeException("List expected: " + json);
        List<?> audioSources = (List<?>)json;
        List<MediaSource> mediaSources = new ArrayList<MediaSource>();
        for (int i = 0 ; i < audioSources.size(); i++) {
            mediaSources.add(getAudioSource(audioSources.get(i)));
        }
        return mediaSources;
    }

    private AudioEffect decodeAudioEffect(final Object json, int audioSessionId) {
        Map<?, ?> map = (Map<?, ?>)json;
        String type = (String)map.get("type");
        switch (type) {
        case "AndroidLoudnessEnhancer":
            if (Build.VERSION.SDK_INT < 19)
                throw new RuntimeException("AndroidLoudnessEnhancer requires minSdkVersion >= 19");
            int targetGain = (int)Math.round((((Double)map.get("targetGain")) * 100.0)); // target gain needs to be provided in milliBel, the user provides the value in deciBel
            LoudnessEnhancer loudnessEnhancer = new LoudnessEnhancer(audioSessionId);
            loudnessEnhancer.setTargetGain(targetGain);
            return loudnessEnhancer;
        case "AndroidEqualizer":
            Equalizer equalizer = new Equalizer(0, audioSessionId);
            return equalizer;
        default:
            throw new IllegalArgumentException("Unknown AudioEffect type: " + map.get("type"));
        }
    }

    private void clearAudioEffects() {
        for (Iterator<AudioEffect> it = audioEffects.iterator(); it.hasNext();) {
            AudioEffect audioEffect = it.next();
            audioEffect.release();
            it.remove();
        }
        audioEffectsMap.clear();
    }

    private DataSource.Factory buildDataSourceFactory(Map<?, ?> headers) {
        final Map<String, String> stringHeaders = castToStringMap(headers);
        String userAgent = null;
        if (stringHeaders != null) {
            userAgent = stringHeaders.remove("User-Agent");
            if (userAgent == null) {
                userAgent = stringHeaders.remove("user-agent");
            }
        }
        if (userAgent == null) {
            userAgent = Util.getUserAgent(context, "just_audio");
        }
        DefaultHttpDataSource.Factory httpDataSourceFactory = new DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true);
        if (stringHeaders != null && stringHeaders.size() > 0) {
            httpDataSourceFactory.setDefaultRequestProperties(stringHeaders);
        }
        return new DefaultDataSource.Factory(context, httpDataSourceFactory);
    }

    private void load(final List<MediaSource> mediaSources, ShuffleOrder shuffleOrder, final long initialPosition, final Integer initialIndex, final Result result) {
        if (dspAudioProcessor != null) {
            dspAudioProcessor.clearGainCurve();
        }
        currentIndex = initialIndex != null ? initialIndex : 0;
        final ProcessingState oldState = processingState;
        processingState = ProcessingState.loading;
        switch (oldState) {
        case idle:
            break;
        case loading:
            abortExistingConnection(false);
            player.stop();
            break;
        default:
            player.stop();
            break;
        }
        prepareResult = result;
        updatePosition();
        errorCode = null;
        errorMessage = null;
        enqueuePlaybackEvent();
        int windowIndex = initialIndex != null ? initialIndex : 0;
        player.setMediaSources(mediaSources, windowIndex, initialPosition);
        loadedSources.clear();
        loadedSources.addAll(mediaSources);
        applyShuffleOrder(shuffleOrder);
        player.prepare();
    }

    /**
     * Pulsr fork: stores the 24/32-bit float-output preference and applies it
     * to the DSP processor when one already exists. Returns true when the
     * request was honoured exactly, false when the platform forced a safe
     * degradation to the existing 16-bit path.
     */
    private boolean applyFloatOutput(boolean enabled) {
        boolean supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP;
        boolean effective = enabled && supported;
        boolean changed = floatOutputEnabled != effective;
        floatOutputEnabled = effective;
        if (dspAudioProcessor != null) {
            dspAudioProcessor.setFloatOutput(effective);
        }
        if (changed) rebuildPlayerForOutput();
        return effective == enabled;
    }

    /** Rebuild the renderer when an output switch changes its sink contract. */
    private void rebuildPlayerForOutput() {
        if (player == null) return;
        int index = player.getCurrentMediaItemIndex();
        long position = player.getCurrentPosition();
        boolean playWhenReady = player.getPlayWhenReady();
        boolean prepare = player.getPlaybackState() != Player.STATE_IDLE;
        float volume = player.getVolume();
        int repeat = player.getRepeatMode();
        boolean shuffle = player.getShuffleModeEnabled();
        boolean skipSilence = player.getSkipSilenceEnabled();
        PlaybackParameters params = player.getPlaybackParameters();
        AudioAttributes attributes = player.getAudioAttributes();
        player.removeListener(this);
        PulsrOutputRouting.unregister(player);
        player.release();
        player = null;
        if (dspAudioProcessor != null) {
            dspAudioProcessor.release();
            dspAudioProcessor = null;
        }
        ensurePlayerInitialized();
        player.setVolume(volume);
        player.setRepeatMode(repeat);
        player.setShuffleModeEnabled(shuffle);
        player.setSkipSilenceEnabled(skipSilence);
        player.setPlaybackParameters(params);
        player.setAudioAttributes(attributes, false);
        if (!loadedSources.isEmpty()) {
            player.setMediaSources(new ArrayList<>(loadedSources),
                    Math.min(index, loadedSources.size() - 1), position);
            player.setShuffleOrder(outputShuffleOrder);
            if (prepare) player.prepare();
        }
        player.setPlayWhenReady(playWhenReady);
    }

    private void applyShuffleOrder(ShuffleOrder order) {
        outputShuffleOrder = order;
        player.setShuffleOrder(order);
    }

    private void ensurePlayerInitialized() {
        if (player == null) {
            // Pulsr fork: the audio sink carries NativeDspAudioProcessor so the
            // native DSP chain sees the decoded PCM stream. The instance is
            // kept around so the gain-ramp method-channel API can reach it.
            NativeDspAudioProcessor dspProcessor = new NativeDspAudioProcessor();
            // Apply the opt-in float preference before the sink is configured.
            dspProcessor.setFloatOutput(floatOutputEnabled);
            dspAudioProcessor = dspProcessor;
            DefaultRenderersFactory renderersFactoryImpl = new DefaultRenderersFactory(context) {
                @Override
                protected AudioSink buildAudioSink(Context context, boolean enableFloatOutput,
                        boolean enableAudioTrackPlaybackParams) {
                    // Pulsr fork: opt-in AAudio Direct output (bit-perfect,
                    // DSP chain bypassed). Falls back to DefaultAudioSink on
                    // any construction failure so playback is never broken.
                    if (aaudioOutputEnabled) {
                        try {
                            AAudioAudioSink nativeSink = new AAudioAudioSink(aaudioPreferExclusive,
                                aaudioTargetBufferMs);
                            PulsrOutputRouting.observe(nativeSink);
                            return nativeSink;
                        } catch (Throwable t) {
                            Log.w(TAG, "AAudio sink unavailable, using DefaultAudioSink: "
                                + t.getMessage());
                        }
                    }
                    DefaultAudioSink sink = new DefaultAudioSink.Builder(context)
                        .setEnableFloatOutput(enableFloatOutput)
                        .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                        .setAudioProcessors(new AudioProcessor[] { dspProcessor })
                        .build();
                    PulsrOutputRouting.observe(sink);
                    return enableFloatOutput ? new FloatDspAudioSink(sink, dspProcessor) : sink;
                }
            };
            // DefaultRenderersFactory forwards this into buildAudioSink(). Enabling
            // it is what lets the sink negotiate/emit float PCM; leaving it false
            // keeps the historical 16-bit-only sink.
            renderersFactoryImpl.setEnableAudioFloatOutput(
                floatOutputEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP);
            RenderersFactory renderersFactory = (eventHandler, videoListener, audioListener, textOutput, metadataOutput) -> {
                Renderer[] defaultRenderers = renderersFactoryImpl
                    .createRenderers(eventHandler, videoListener, audioListener, textOutput, metadataOutput);
                Renderer[] allRenderers = Arrays.copyOf(defaultRenderers, defaultRenderers.length + 1);
                allRenderers[defaultRenderers.length] = new ObserverRenderer();
                return allRenderers;
            };
            ExoPlayer.Builder builder = new ExoPlayer.Builder(context, renderersFactory);
            builder.setUseLazyPreparation(useLazyPreparation);
            if (loadControl != null) {
                builder.setLoadControl(loadControl);
            }
            if (livePlaybackSpeedControl != null) {
                builder.setLivePlaybackSpeedControl(livePlaybackSpeedControl);
            }
            player = builder.build();
            PulsrOutputRouting.register(player, aaudioOutputEnabled);
            // Pulsr fork: sample-accurate seeking. EXACT forces the decoder to
            // pre-roll from the previous sync point and discard up to the
            // requested sample, giving frame-accurate (0-sample error) seeks
            // on local formats - the Poweramp playback-engine behaviour.
            player.setSeekParameters(androidx.media3.exoplayer.SeekParameters.EXACT);

            player.setTrackSelectionParameters(
                player.getTrackSelectionParameters()
                    .buildUpon()
                    .setAudioOffloadPreferences(audioOffloadPreferences)
                    .build()
            );
            setAudioSessionId(player.getAudioSessionId());
            player.addListener(this);
        }
    }

    private void setAudioAttributes(int contentType, int flags, int usage) {
        AudioAttributes.Builder builder = new AudioAttributes.Builder();
        builder.setContentType(contentType);
        builder.setFlags(flags);
        builder.setUsage(usage);
        //builder.setAllowedCapturePolicy((Integer)json.get("allowedCapturePolicy"));
        AudioAttributes audioAttributes = builder.build();
        if (processingState == ProcessingState.loading) {
            // audio attributes should be set either before or after loading to
            // avoid an ExoPlayer glitch.
            pendingAudioAttributes = audioAttributes;
        } else {
            player.setAudioAttributes(audioAttributes, false);
        }
    }

    private void audioEffectSetEnabled(String type, boolean enabled) {
        audioEffectsMap.get(type).setEnabled(enabled);
    }

    private void loudnessEnhancerSetTargetGain(double targetGain) {
        int targetGainMillibels = (int)Math.round(targetGain * 100.0); // target gain needs to be provided in milliBel, the user provides the value in deciBel
        ((LoudnessEnhancer)audioEffectsMap.get("AndroidLoudnessEnhancer")).setTargetGain(targetGainMillibels);
    }

    private Map<String, Object> equalizerAudioEffectGetParameters() {
        Equalizer equalizer = (Equalizer)audioEffectsMap.get("AndroidEqualizer");
        ArrayList<Object> rawBands = new ArrayList<>();
        for (short i = 0; i < equalizer.getNumberOfBands(); i++) {
            rawBands.add(mapOf(
                "index", i,
                "lowerFrequency", (double)equalizer.getBandFreqRange(i)[0] / 1000.0, // returns a value in milliHertz, we want Hertz
                "upperFrequency", (double)equalizer.getBandFreqRange(i)[1] / 1000.0, // returns a value in milliHertz, we want Hertz
                "centerFrequency", (double)equalizer.getCenterFreq(i) / 1000.0, // returns a value in milliHertz, we want Hertz
                "gain", equalizer.getBandLevel(i) / 100.0 // returns a value in milliBel, we want deciBel
            ));
        }
        return mapOf(
            "parameters", mapOf(
                "minDecibels", equalizer.getBandLevelRange()[0] / 100.0, // returns a value in milliBel, we want deciBel
                "maxDecibels", equalizer.getBandLevelRange()[1] / 100.0, // returns a value in milliBel, we want deciBel
                "bands", rawBands
            )
        );
    }

    private void equalizerBandSetGain(int bandIndex, double gain) {
        ((Equalizer)audioEffectsMap.get("AndroidEqualizer")).setBandLevel((short)bandIndex, (short)(Math.round(gain * 100.0))); // target gain needs to be provided in milliBel, the user provides the value in deciBel
    }

    /// Creates an event based on the current state.
    private Map<String, Object> createPlaybackEvent() {
        final Map<String, Object> event = new HashMap<String, Object>();
        Long duration = getDuration() == C.TIME_UNSET ? null : (1000 * getDuration());
        bufferedPosition = player != null ? player.getBufferedPosition() : 0L;
        event.put("processingState", processingState.ordinal());
        event.put("updatePosition", 1000 * updatePosition);
        event.put("updateTime", updateTime);
        event.put("bufferedPosition", 1000 * Math.max(updatePosition, bufferedPosition));
        event.put("icyMetadata", collectIcyMetadata());
        event.put("duration", duration);
        event.put("currentIndex", currentIndex);
        event.put("androidAudioSessionId", audioSessionId);
        event.put("errorCode", errorCode);
        event.put("errorMessage", errorMessage);
        return event;
    }

    // Broadcast the pending playback event if it was set.
    private void broadcastPendingPlaybackEvent() {
        if (pendingPlaybackEvent != null) {
            eventChannel.success(pendingPlaybackEvent);
            pendingPlaybackEvent = null;
        }
    }

    // Set a pending playback event that should be broadcast at
    // a later time. If we're in a Flutter method call, it will
    // be broadcast just before that method call returns. If
    // we're in an asynchronous callback, it is up to the caller
    // to eventually broadcast that event via
    // broadcastPendingPlaybackEvent.
    //
    // If this is called multiple times before
    // broadcastPendingPlaybackEvent, only the last event is
    // broadcast.
    private void enqueuePlaybackEvent() {
        pendingPlaybackEvent = createPlaybackEvent();
    }

    // Broadcasts a new event immediately.
    private void broadcastImmediatePlaybackEvent() {
        enqueuePlaybackEvent();
        broadcastPendingPlaybackEvent();
    }

    private Map<String, Object> collectIcyMetadata() {
        final Map<String, Object> icyData = new HashMap<>();
        if (icyInfo != null) {
            final Map<String, String> info = new HashMap<>();
            info.put("title", icyInfo.title);
            info.put("url", icyInfo.url);
            icyData.put("info", info);
        }
        if (icyHeaders != null) {
            final Map<String, Object> headers = new HashMap<>();
            headers.put("bitrate", icyHeaders.bitrate);
            headers.put("genre", icyHeaders.genre);
            headers.put("name", icyHeaders.name);
            headers.put("metadataInterval", icyHeaders.metadataInterval);
            headers.put("url", icyHeaders.url);
            headers.put("isPublic", icyHeaders.isPublic);
            icyData.put("headers", headers);
        }
        return icyData;
    }

    private long getCurrentPosition() {
        if (processingState == ProcessingState.idle || processingState == ProcessingState.loading) {
            long pos = player.getCurrentPosition();
            if (pos < 0) pos = 0;
            return pos;
        } else if (seekPos != null && seekPos != C.TIME_UNSET) {
            return seekPos;
        } else {
            return player.getCurrentPosition();
        }
    }

    private long getDuration() {
        if (processingState == ProcessingState.idle || processingState == ProcessingState.loading || player == null) {
            return C.TIME_UNSET;
        } else {
            return player.getDuration();
        }
    }

    private void sendError(int errorCode, String errorMsg, Object details) {
        sendError(errorCode, errorMsg, details, true);
    }

    private void sendError(int errorCode, String errorMsg, Object details, boolean switchToIdle) {
        eventChannel.error(String.valueOf(errorCode), errorMsg, details);
        this.errorCode = errorCode;
        this.errorMessage = errorMsg;
        if (switchToIdle) {
            processingState = ProcessingState.idle;
        }
        broadcastImmediatePlaybackEvent();
        if (prepareResult != null) {
            prepareResult.error(String.valueOf(errorCode), errorMsg, details);
            prepareResult = null;
        }
    }

    private String getLowerCaseExtension(Uri uri) {
        // Until ExoPlayer provides automatic detection of media source types, we
        // rely on the file extension. When this is absent, as a temporary
        // workaround we allow the app to supply a fake extension in the URL
        // fragment. e.g.  https://somewhere.com/somestream?x=etc#.m3u8
        String fragment = uri.getFragment();
        String filename = fragment != null && fragment.contains(".") ? fragment : uri.getPath();
        return filename.replaceAll("^.*\\.", "").toLowerCase();
    }

    public void play(Result result) {
        if (player.getPlayWhenReady()) {
            result.success(new HashMap<String, Object>());
            return;
        }
        if (playResult != null) {
            playResult.success(new HashMap<String, Object>());
        }
        playResult = result;
        player.setPlayWhenReady(true);
        updatePosition();
        if (processingState == ProcessingState.completed && playResult != null) {
            playResult.success(new HashMap<String, Object>());
            playResult = null;
        }
    }

    public void pause() {
        if (!player.getPlayWhenReady()) return;
        player.setPlayWhenReady(false);
        updatePosition();
        enqueuePlaybackEvent();
        if (playResult != null) {
            playResult.success(new HashMap<String, Object>());
            playResult = null;
        }
    }

    public void setVolume(final float volume) {
        player.setVolume(volume);
    }

    public void setSpeed(final float speed) {
        PlaybackParameters params = player.getPlaybackParameters();
        if (params.speed == speed) return;
        player.setPlaybackParameters(new PlaybackParameters(speed, params.pitch));
        if (player.getPlayWhenReady())
            updatePosition();
        enqueuePlaybackEvent();
    }

    public void setPitch(final float pitch) {
        PlaybackParameters params = player.getPlaybackParameters();
        if (params.pitch == pitch) return;
        player.setPlaybackParameters(new PlaybackParameters(params.speed, pitch));
        enqueuePlaybackEvent();
    }

    public void setSkipSilenceEnabled(final boolean enabled) {
        player.setSkipSilenceEnabled(enabled);
    }

    public void setLoopMode(final int mode) {
        player.setRepeatMode(mode);
    }

    public void setShuffleModeEnabled(final boolean enabled) {
        player.setShuffleModeEnabled(enabled);
    }

    public void seek(final long position, final Integer index, final Result result) {
        if (processingState == ProcessingState.idle || processingState == ProcessingState.loading) {
            result.success(new HashMap<String, Object>());
            return;
        }
        abortSeek();
        seekPos = position;
        seekResult = result;
        try {
            int windowIndex = index != null ? index : player.getCurrentMediaItemIndex();
            player.seekTo(windowIndex, position);
        } catch (RuntimeException e) {
            seekResult = null;
            seekPos = null;
            throw e;
        }
    }

    public void dispose() {
        if (processingState == ProcessingState.loading) {
            abortExistingConnection(true);
        }
        if (playResult != null) {
            playResult.success(new HashMap<String, Object>());
            playResult = null;
        }
        mediaSources.clear();
        loadedSources.clear();
        clearAudioEffects();
        if (player != null) {
            PulsrOutputRouting.unregister(player);
        player.release();
            player = null;
            processingState = ProcessingState.idle;
            broadcastImmediatePlaybackEvent();
        }
        if (dspAudioProcessor != null) {
            dspAudioProcessor.clearGainCurve();
            dspAudioProcessor.release();
            dspAudioProcessor = null;
        }
        eventChannel.endOfStream();
        dataEventChannel.endOfStream();
    }

    private void abortSeek() {
        if (seekResult != null) {
            try {
                seekResult.success(new HashMap<String, Object>());
            } catch (RuntimeException e) {
                // Result already sent
            }
            seekResult = null;
            seekPos = null;
        }
    }

    private void abortExistingConnection(boolean switchToIdle) {
        sendError(ERROR_ABORT, "Connection aborted", null, switchToIdle);
    }

    // Dart can't distinguish between int sizes so
    // Flutter may send us a Long or an Integer
    // depending on the number of bits required to
    // represent it.
    public static Long getLong(Object o) {
        return (o == null || o instanceof Long) ? (Long)o : Long.valueOf(((Integer)o).intValue());
    }

    @SuppressWarnings("unchecked")
    static <T> T mapGet(Object o, String key) {
        if (o instanceof Map) {
            return (T) ((Map<?, ?>)o).get(key);
        } else {
            return null;
        }
    }

    static Map<String, Object> mapOf(Object... args) {
        Map<String, Object> map = new HashMap<>();
        for (int i = 0; i < args.length; i += 2) {
            map.put((String)args[i], args[i + 1]);
        }
        return map;
    }

    static Map<String, String> castToStringMap(Map<?, ?> map) {
        if (map == null) return null;
        Map<String, String> map2 = new HashMap<>();
        for (Object key : map.keySet()) {
            map2.put((String)key, (String)map.get(key));
        }
        return map2;
    }

    enum ProcessingState {
        idle,
        loading,
        buffering,
        ready,
        completed
    }

    public class ObserverRenderer extends NoSampleRenderer {
        private long lastPosUs = 0L;
        private int consecutivePosCount = 0;

        @Override
        public void render(long positionUs, long elapsedRealtimeUs) {
            if (positionUs == lastPosUs) {
                consecutivePosCount++;
            } else {
                if (consecutivePosCount >= 3) {
                    handler.post(() -> {
                        if (updatePositionIfChanged()) {
                            broadcastImmediatePlaybackEvent();
                        }
                    });
                }
                consecutivePosCount = 0;
            }
            lastPosUs = positionUs;
        }

        @Override
        public String getName() {
            return "ObserverRenderer";
        }
    }
}
```

---

## `third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/JustAudioPlugin.java`

```java
package com.ryanheise.just_audio;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngine.EngineLifecycleListener;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * JustAudioPlugin
 */
public class JustAudioPlugin implements FlutterPlugin {
    private MethodChannel channel;
    private MainMethodCallHandler methodCallHandler;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        Context applicationContext = binding.getApplicationContext();
        BinaryMessenger messenger = binding.getBinaryMessenger();
        methodCallHandler = new MainMethodCallHandler(applicationContext, messenger);

        channel = new MethodChannel(messenger, "com.ryanheise.just_audio.methods");
        channel.setMethodCallHandler(methodCallHandler);
        @SuppressWarnings("deprecation")
        FlutterEngine engine = binding.getFlutterEngine();
        engine.addEngineLifecycleListener(new EngineLifecycleListener() {
            @Override
            public void onPreEngineRestart() {
                methodCallHandler.dispose();
            }

            @Override
            public void onEngineWillDestroy() {
            }
        });
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        methodCallHandler.dispose();
        methodCallHandler = null;

        channel.setMethodCallHandler(null);
    }
}
```

---

## `lib/core/di/injection.dart`

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import 'package:pulsr/core/services/file_intent_handler.dart';
import 'package:pulsr/core/utils/error_logger.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/per_song_eq_store.dart';
import 'package:pulsr/data/audio/per_song_volume_store.dart';
import 'package:pulsr/data/audio/song_rating_store.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

final Completer<void> _initializationReady = Completer<void>();

/// Completes when [configureDependencies] has finished (or failed). The splash
/// gates its routing on this real signal instead of an arbitrary delay (I25).
Future<void> get initializationReady => _initializationReady.future;

@InjectableInit()
Future<void> configureDependencies() async {
  try {
    getIt.init();
    // Pre-warm async singletons so sync getIt<T>() in main.dart never throws
    // StateError (audio handler -> player cubit -> download cubit -> intents).
    try {
      await getIt
          .getAsync<PulsrAudioHandler>()
          .timeout(const Duration(seconds: 12));
    } catch (e, st) {
      ErrorLogger.log('PulsrAudioHandler DI warm-up timed out or failed',
          error: e, stackTrace: st, category: 'DI');
    }
    try {
      await getIt.getAsync<PlayerCubit>().timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('PlayerCubit DI warm-up timed out or failed',
          error: e, stackTrace: st, category: 'DI');
    }
    try {
      await getIt
          .getAsync<YtmDownloadCubit>()
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('YtmDownloadCubit DI warm-up timed out or failed',
          error: e, stackTrace: st, category: 'DI');
    }
    try {
      await getIt
          .getAsync<FileIntentHandler>()
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('FileIntentHandler DI warm-up timed out or failed',
          error: e, stackTrace: st, category: 'DI');
    }
    // Per-song override stores load their SharedPreferences map asynchronously
    // in their constructors; sync getters (player cubit per-track sync, smart
    // playlist filters, song-info sheet) must never observe the empty pre-load
    // map. Await their `ready` futures so the first UI read is authoritative.
    try {
      await Future.wait<void>([
        getIt<SongRatingStore>().ready,
        getIt<PerSongEqStore>().ready,
        getIt<PerSongVolumeStore>().ready,
      ]).timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('Per-song override store warm-up timed out or failed',
          error: e, stackTrace: st, category: 'DI');
    }
    try {
      await getIt.allReady().timeout(const Duration(seconds: 5));
    } catch (e, st) {
      ErrorLogger.log('getIt.allReady() warm-up timed out or failed',
          error: e, stackTrace: st, category: 'DI');
    }
    validateDependencies(getIt);
  } finally {
    if (!_initializationReady.isCompleted) _initializationReady.complete();
  }
}

void validateDependencies(GetIt getIt) {
  // `assert` is stripped in release builds, so a missing eager singleton only
  // surfaced as a mysterious launch crash (or a null lookup deep in the UI).
  // Throw an explicit [StateError] that survives `--release`.
  void require<T extends Object>() {
    if (!getIt.isRegistered<T>()) {
      throw StateError('${T.toString()} must be registered in DI');
    }
  }

  require<AppDatabase>();
  require<PulsrAudioHandler>();
  require<PlayerCubit>();
  require<DownloadsCubit>();
  require<YtmDownloadCubit>();
}

FutureOr<void> disposeHttpClient(HttpClient client) {
  client.close(force: false);
}

FutureOr<void> disposePkgHttpClient(http.Client client) {
  client.close();
}

@module
abstract class NetworkModule {
  @Singleton(dispose: disposeHttpClient)
  HttpClient get httpClient => HttpClient()
    ..maxConnectionsPerHost = 5
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 90);

  @Singleton(dispose: disposePkgHttpClient)
  http.Client get pkgHttpClient => http.Client();
}

@module
abstract class StorageModule {
  @lazySingleton
  FlutterSecureStorage get secureStorage => const FlutterSecureStorage(
        aOptions: AndroidOptions(
          resetOnError: true,
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
      );
}
```

---

## `lib/data/audio/audio_handler.dart`

```dart
// lib/data/audio/audio_handler.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/channels.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/di/injection.dart';
import '../../core/errors/ytm_error_classifier.dart';
import '../../core/services/battery_optimization_service.dart';
import '../../core/services/hires_audio_service.dart';
import '../../core/services/ytm_service.dart';
import '../../core/telemetry/playback_latency_tracker.dart';
import '../../core/telemetry/audio_session_log.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/audio_effects_config.dart';
import '../../domain/models/audio_output_info.dart';
import '../../domain/models/eq_preset.dart';
import '../../domain/models/genre_item.dart';
import '../../domain/models/headphone_profile.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import 'package:drift/drift.dart' show Value;
import '../db/app_database.dart';
import 'artwork_uri_resolver.dart';
import 'audio_effects_channel.dart';
import 'audio_session_id_router.dart';
import 'crossfade_manager.dart';
import 'interruption_state_machine.dart';
import 'equalizer_manager.dart';
import 'sleep_timer_manager.dart';
import 'position_crash_guard.dart';
import 'ytm_resolving_source.dart';
import '../../core/services/ytm_cache_manager.dart';
import 'adaptive_buffer_engine.dart';
import 'audio_memory_manager.dart';
import 'battery_aware_playback.dart';
import 'format_aware_decoder.dart';
import 'gapless_trim_handler.dart';
import 'optimized_dsp_pipeline.dart';
import 'playback_analytics.dart';
import 'replay_gain_math.dart';
import '../../domain/models/audio_quality_info.dart';
import 'smart_preload_scheduler.dart';
import 'stream_pre_resolver.dart';
import 'triple_buffer_pipeline.dart';
import 'dsd_decoder_helper.dart';
import '../../core/services/ytm_url_cache.dart';
import 'collaborators/float_output_controller.dart';
import 'collaborators/aaudio_output_controller.dart';
import 'collaborators/playback_volume_controller.dart';
import 'collaborators/stream_resolution_pipeline.dart';
import 'playback_queue_state_machine.dart';
import 'ab_loop_manager.dart';
import 'adaptive_quality_manager.dart';
import 'bpm_override_store.dart';
import 'per_song_volume_store.dart';
import 'per_song_playback_store.dart';
import 'dsp_snapshot_store.dart';
import 'ducking_controller.dart';
import 'multi_output_router.dart';
import 'playback_bookmark_store.dart';
import 'silence_skip_controller.dart';
import 'track_delay_manager.dart';
import 'audio_handler_lifecycle_observer.dart';
import 'headset_control_config.dart';
part 'audio_handler_dsp_bridge.dart';
part 'audio_handler_sleep_bridge.dart';
part 'audio_handler_streaming.dart';
part 'audio_handler_queue_engine.dart';
part 'audio_handler_transport.dart';
part 'audio_handler_media_browser.dart';
part 'audio_handler_playback_extras.dart';

@singleton
class PulsrAudioHandler extends BaseAudioHandler
    with
        WidgetsBindingObserver,
        QueueHandler,
        SeekHandler,
        PulsrAudioDspBridge,
        PulsrAudioSleepBridge,
        PulsrAudioStreaming,
        PulsrAudioQueueEngine,
        PulsrAudioTransport,
        PulsrAudioMediaBrowser,
        PulsrAudioPlaybackExtras {
  @factoryMethod
  static Future<PulsrAudioHandler> create(
      IMusicRepository repository, YtmService ytmService) async {
    // The instance is captured so that if AudioService.init times out we can
    // reuse the very instance its builder produced. A late completion of the
    // in-flight init then binds THIS handler instead of creating and binding a
    // second, state-less one (B-2).
    PulsrAudioHandler? built;
    // If the platform handshake times out before `builder` runs, this holds the
    // degraded-mode instance the app has already fallen back to. The builder
    // adopts it instead of constructing a second, unbound handler, so a late
    // init success binds the very instance the UI drives (B-2/B-6).
    PulsrAudioHandler? fallback;
    // User preference: keep the media notification after pause so playback
    // can be resumed from the shade. AudioServiceConfig is init-time only,
    // so this takes effect on the next cold start after the toggle changes.
    // Default TRUE: a paused player must keep its notification (standard
    // music-player behavior). With stopForegroundOnPause=true the OS drops
    // the notification on every pause — including end-of-queue Next — which
    // users report as "notification disappearing with no action".
    bool keepOnPause = true;
    String channelName = 'Pulsr Audio Playback';
    String channelDesc =
        'Playback controls and now-playing information for Pulsr Music.';
    try {
      final prefs = await SharedPreferences.getInstance();
      keepOnPause = prefs.getBool(PrefsKeys.keepNotificationOnPause) ?? true;
      final langCode = prefs.getString(PrefsKeys.languageCode) ??
          prefs.getString('setting_language') ??
          Platform.localeName.split(RegExp(r'[_-]')).first.toLowerCase();
      if (langCode == 'ar') {
        channelName = 'تشغيل الصوت Pulsr';
        channelDesc =
            'عناصر التحكم في التشغيل ومعلومات التشغيل الحالي لتطبيق Pulsr.';
      } else if (langCode == 'es') {
        channelName = 'Reproducción de Audio Pulsr';
        channelDesc =
            'Controles de reproducción e información de reproducción actual para Pulsr.';
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to read notification channel preferences',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    try {
      final initFuture = AudioService.init(
        builder: () {
          built = fallback ?? PulsrAudioHandler(repository, ytmService);
          return built!;
        },
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.pulsr.music.audio',
          androidNotificationChannelName: channelName,
          androidNotificationChannelDescription: channelDesc,
          androidNotificationOngoing: false,
          androidNotificationClickStartsActivity: true,
          androidStopForegroundOnPause: !keepOnPause,
          androidResumeOnClick: true,
          androidNotificationIcon: 'drawable/ic_notification',
        ),
      );
      return await initFuture.timeout(const Duration(seconds: 10));
    } catch (e, st) {
      ErrorLogger.log(
          'AudioService.init failed or timed out: running in degraded audio '
          'mode (playback works, but there is no media notification / '
          'foreground service)',
          error: e,
          stackTrace: st,
          category: 'AudioHandler');
      // Fall back to the instance the builder created (if it got that far);
      // otherwise adopt this one so a late init success binds the same handler
      // the app is already using instead of orphaning it (B-2/B-6).
      fallback = built ?? PulsrAudioHandler(repository, ytmService);
      fallback.platformBridgeDegraded.value = true;
      return fallback;
    }
  }

  static final controlFavorite = MediaControl.custom(
    androidIcon: 'drawable/ic_favorite',
    label: 'Unfavorite',
    name: 'toggleFavorite',
  );
  static final controlUnfavorite = MediaControl.custom(
    androidIcon: 'drawable/ic_favorite_border',
    label: 'Favorite',
    name: 'toggleFavorite',
  );
  static final controlShuffleOn = MediaControl.custom(
    androidIcon: 'drawable/ic_shuffle_on',
    label: 'Shuffle',
    name: 'toggleShuffle',
  );
  static final controlShuffleOff = MediaControl.custom(
    androidIcon: 'drawable/ic_shuffle',
    label: 'Shuffle',
    name: 'toggleShuffle',
  );
  static final controlRepeatOne = MediaControl.custom(
    androidIcon: 'drawable/ic_repeat_one',
    label: 'Repeat',
    name: 'cycleRepeat',
  );
  static final controlRepeatAll = MediaControl.custom(
    androidIcon: 'drawable/ic_repeat_all',
    label: 'Repeat',
    name: 'cycleRepeat',
  );
  static final controlRepeatOff = MediaControl.custom(
    androidIcon: 'drawable/ic_repeat',
    label: 'Repeat',
    name: 'cycleRepeat',
  );

  @override
  final AudioPlayer _playerA;
  @override
  final AudioPlayer _playerB;
  @override
  final AudioPlayer _prefetchPlayer;
  @override
  bool _isPlayerAActive = true;
  @override
  int _generationCounter = 0;
  int get generationCounter => _generationCounter;
  @override
  AudioPlayer get _activePlayer => _isPlayerAActive ? _playerA : _playerB;
  @override
  AudioPlayer get _inactivePlayer => _isPlayerAActive ? _playerB : _playerA;
  AudioPlayer get prefetchPlayer => _prefetchPlayer;

  /// Returns playback position compensated for native and DSP pipeline latency.
  @override
  Duration get compensatedPosition =>
      _dspPipeline.getCompensatedPosition(_activePlayer.position);

  @override
  final IMusicRepository _repository;
  @override
  final YtmService _ytmService;
  @override
  final CrossfadeManager _crossfadeManager = CrossfadeManager();
  @override
  final SleepTimerManager _sleepTimerManager = SleepTimerManager();
  @override
  late final EqualizerManager _equalizerManager;
  @override
  late final AudioSessionIdRouter _audioSessionIdRouter;
  @override
  int? _playerASessionId;
  @override
  int? _playerBSessionId;

  /// Pure, testable playback queue state machine (P2).
  @override
  final PlaybackQueueStateMachine _queueStateMachine =
      PlaybackQueueStateMachine();

  PlaybackQueueStateMachine get queueStateMachine => _queueStateMachine;

  @override
  List<SongsTableData> get _songs => _queueStateMachine.songs;
  @override
  set _songs(List<SongsTableData> value) => _queueStateMachine.setQueue(value);

  @override
  int get _currentIndex => _queueStateMachine.currentIndex;
  @override
  set _currentIndex(int value) => _queueStateMachine.setCurrentIndex(value);

  bool get _queueDirty => _queueStateMachine.isQueueDirty;
  @override
  set _queueDirty(bool value) {
    if (value) {
      _queueStateMachine.markQueueDirty();
    } else {
      _queueStateMachine.markQueueClean(_queueStateMachine.currentIndex);
    }
  }

  int get _savedQueueIndex => _queueStateMachine.savedQueueIndex;
  @override
  set _savedQueueIndex(int value) =>
      _queueStateMachine.setSavedQueueIndex(value);

  HeadsetControlConfig? _cachedHeadsetConfig;
  @override
  HeadsetControlConfig? get cachedHeadsetConfig => _cachedHeadsetConfig;
  @override
  set cachedHeadsetConfig(HeadsetControlConfig? value) =>
      _cachedHeadsetConfig = value;
  double? _preDuckVolume;
  double? _preDuckInactiveVolume;
  // Captured at duck-begin so duck-end can tell whether the track or its
  // ReplayGain target changed during the duck and, if not, restore the exact
  // pre-duck level instead of snapping to the RG target (preserves a mid-fade).
  int? _preDuckSongId;
  double? _preDuckRgTarget;
  bool _duckActive = false;
  int _duckDepthCounter = 0;
  Timer? _duckSafetyTimer;
  // Single sleep-fade multiplier (0..1; 1.0 = not fading) owned by the handler
  // so the three volume paths (ducking, sleep-fade, crossfade) stop clobbering
  // each other. The SleepTimerManager reports its stepped fade progress here
  // (via its onFadeFactor hook) instead of writing the player volume directly;
  // the handler then composes it with the duck-aware ReplayGain/user target in
  // [_reapplyActiveVolume] / [setVolume]. The native sample-accurate gain-curve
  // fade path leaves this at 1.0 (that curve multiplies the player's base
  // volume inside the sink, so it already composes).
  double _sleepFadeFactor = 1.0;
  // Transient system-sound duck restore timer; tracked so dispose() can cancel
  // it (previously it was an untracked Timer that could fire after dispose).
  Timer? _systemSoundTimer;
  // When a gapless load is suppressing broadcasts, the time it started, so the
  // suppression is bounded and a stalled/failed load cannot freeze the
  // notification forever (see _broadcastState).
  @override
  DateTime? _gaplessSuppressionSince;

  /// Pure, testable interruption bookkeeping (B-1). Replaces the previous pair
  /// of loose booleans whose begin/end bookkeeping was asymmetric.
  @override
  final InterruptionStateMachine _interruption = InterruptionStateMachine();
  DateTime? _lastNoisyTime;
  // Auto-resume bookkeeping: a becoming-noisy pause arms a one-shot resume
  // window; a reconnect on a headset/BT/USB route within the timeout resumes.
  DateTime? _noisyPauseTime;
  @override
  bool _pausedForNoisy = false;
  @override
  int _consecutiveFailures = 0;
  // Last time a track-completion was reported to the sleep timer. Gapless
  // playback reports one boundary through two independent signals (the native
  // `ProcessingState.completed` event and the `currentIndexStream` advance), so
  // this debounce collapses the duplicate. See [_notifySleepTrackCompleted].
  @override
  DateTime? _lastSleepTrackCompletedAt;
  @override
  List<int> get _shuffleHistory => _queueStateMachine.shuffleHistory;
  @override
  DateTime? _lastPreviousTapTime;
  @override
  bool _isManualSkip = false;

  // Bumped on every playSongAt/play entry so a slow async resolve from a
  // superseded call cannot load its source into the player.
  @override
  int _playGeneration = 0;
  // Seek throttling: optimistic UI + debounced backend seeks.
  @override
  int _lastSeekMs = 0;
  @override
  Duration? _pendingSeekPosition;
  @override
  Timer? _seekDebounceTimer;
  @override
  int _lastSmartPrefetchMs = 0;
  @override
  String? _lastSmartPrefetchKey;
  @override
  Timer? _crossfadeSwitchDebounce;
  AudioHandlerLifecycleObserver? _lifecycleObserver;
  // Set when a restored YouTube session is left idle; play() resolves it lazily.
  @override
  Duration? _pendingLazyPosition;
  // Memoized stream URLs, keyed by video id. Never persisted — they expire.
  @override
  final LinkedHashMap<String,
          ({String url, DateTime expires, String? userAgent, String? cookies})>
      _streamCache = LinkedHashMap();
  // Active stream URL resolutions, keyed by videoId-quality. Deduplicates concurrent
  // requests (e.g. background pre-warm and YtmResolvingSource.request()).
  @override
  final Map<
      String,
      Future<
          ({
            String url,
            String? userAgent,
            String? cookies,
            String quality
          })>> _inFlightResolves = {};
  // Video ids with an in-flight prefetch, so we resolve each at most once.
  @override
  final Set<String> _prefetching = {};

  @override
  String _currentStreamingQuality() {
    if (adaptiveQualityManager.enabled) {
      return adaptiveQualityManager.currentQuality;
    }
    return _cachedPrefs?.getString('setting_streaming_quality') ?? 'high';
  }

  final AdaptiveBufferEngine _adaptiveBufferEngine = AdaptiveBufferEngine();
  final OptimizedDspPipeline _dspPipeline = OptimizedDspPipeline();
  late final PlaybackAnalytics _playbackAnalytics;
  late final AudioMemoryManager _memoryManager;
  @override
  late final SmartPreloadScheduler _preloadScheduler;
  @override
  late final FormatAwareDecoder _formatDecoder;
  @override
  late final TripleBufferPipeline _tripleBufferPipeline;
  @override
  late final BatteryAwarePlayback _batteryAwarePlayback;
  @override
  late final StreamPreResolver _streamPreResolver;
  bool _disposed = false;
  bool get isDisposed => _disposed;
  Future<void> _dspTransitionTail = Future<void>.value();

  /// Change a complete DSP profile while the rendered signal is faded out.
  /// Poll the actual gain so buffered playback cannot outrun a timed delay.
  Future<T> withSmoothDspTransition<T>(Future<T> Function() action) async {
    final previous = _dspTransitionTail;
    final released = Completer<void>();
    _dspTransitionTail = released.future;
    await previous;
    final muted = <AudioPlayer>[];
    try {
      if (_disposed) throw StateError('Audio handler disposed');
      for (final player in [_playerA, _playerB]) {
        if (!player.playing) continue;
        if (await player.dspSetTransitionMuted(true)) muted.add(player);
      }
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      for (final player in muted) {
        while (player.playing &&
            player.processingState != ProcessingState.completed) {
          final gain = await player.dspGetTransitionGain();
          if (gain == null) {
            // The native side cannot report the gain, so polling can never
            // succeed. Give the fade a short fixed window instead of spinning
            // until the 3s deadline and then aborting the profile change.
            await Future<void>.delayed(const Duration(milliseconds: 60));
            break;
          }
          if (gain <= 0.0001) break;
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('DSP profile fade did not reach silence');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      final result = await action();
      if (muted.isNotEmpty) {
        if (!await AudioEffectsChannel().awaitControlUpdates()) {
          throw StateError('DSP profile preparation did not complete');
        }
        // Let reset filters and lookahead buffers settle before fading back in.
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      return result;
    } finally {
      for (final player in muted) {
        try {
          await player.dspSetTransitionMuted(false);
        } catch (_) {}
      }
      released.complete();
    }
  }

  // FIX B9 & C-01: Initialized immediately in constructor to prevent cold-start races.
  PlaybackVolumeController? _volumeController;
  @override
  late final StreamResolutionPipeline _streamResolutionPipeline;
  // ── F1–F11 feature managers ──────────────────────────────────────────
  @override
  final AbLoopManager abLoopManager = AbLoopManager();
  @override
  final TrackDelayManager trackDelayManager = TrackDelayManager();
  @override
  final AdaptiveQualityManager adaptiveQualityManager =
      AdaptiveQualityManager();
  @override
  final DuckingController duckingController = DuckingController();
  @override
  final MultiOutputRouter multiOutputRouter = MultiOutputRouter();
  @override
  final DspSnapshotStore dspSnapshotStore = DspSnapshotStore();
  @override
  final SilenceSkipController silenceSkipController = SilenceSkipController();
  @override
  final BpmOverrideStore bpmOverrideStore = BpmOverrideStore();
  @override
  final PlaybackBookmarkStore bookmarkStore = PlaybackBookmarkStore();
  @override
  final PerSongPlaybackStore perSongPlaybackStore = PerSongPlaybackStore();
  @override
  bool hedgedResolutionEnabled = true;
  DateTime? _lastBookmarkSave;
  DateTime? _lastHealthyReport;
  final GaplessTransitionMonitor _gaplessMonitor = GaplessTransitionMonitor();
  int get gapEventCount => _gaplessMonitor.gapEventCount;
  int get crossfadeGlitchCount => _crossfadeManager.crossfadeGlitchCount;

  // Gapless engine: when crossfade is off, AudioPlayer's built-in playlist on the
  // active player is the source of truth for track order/advance, and just_audio
  // joins consecutive items seamlessly. False while crossfade (duration > 0) is
  // active, which keeps the manual dual-player path below.
  @override
  bool _gaplessLoaded = false;
  // Last index reacted to from currentIndexStream, to drop duplicate emits.
  @override
  int _lastGaplessIndex = -1;

  // Target index for current gapless load; used to filter transient ExoPlayer index 0 emits
  @override
  int? _gaplessTargetIndex;
  @override
  final Stopwatch _gaplessStopwatch = Stopwatch();
  @override
  bool _gaplessTargetReached = false;
  @override
  int _gaplessLoadGeneration = 0;

  /// User-facing gapless toggle (persisted as `setting_gapless`). Gapless is
  /// the default engine but is mutually exclusive with crossfade.
  @override
  bool _gaplessEnabled = true;
  bool get isGaplessEnabled => _gaplessEnabled;

  /// Gapless is the default engine. Enabling crossfade (duration > 0) switches
  /// to the overlapping dual-player engine, which cannot also produce a seamless
  /// join, so the two are mutually exclusive by construction. An explicit
  /// gapless OFF also falls back to per-track playback when crossfade is 0.
  @override
  bool get _gaplessMode =>
      _gaplessEnabled && _crossfadeManager.duration <= Duration.zero;

  final StreamController<SongsTableData> _onTrackChangedSubject =
      StreamController<SongsTableData>.broadcast();
  Stream<SongsTableData> get onTrackChanged => _onTrackChangedSubject.stream;

  // T10: CUE sub-track boundaries. Both flags reset on track change so each
  // virtual track seeks once to its start and advances once at its end.
  bool _cueStartSeeked = false;
  bool _cueAdvanceTriggered = false;

  bool _positionDirty = false;
  Timer? _positionSaveTimer;
  Timer? _fadeInGuardTimer; // FIX-#12: tracked for disposal
  @override
  final StreamController<Duration> _positionSubject =
      StreamController<Duration>.broadcast();
  Stream<Duration> get positionStream => _positionSubject.stream;

  final StreamController<Duration> _highRatePositionSubject =
      StreamController<Duration>.broadcast();

  /// High-rate stream (~16ms granularity, 60fps) for fluid waveform seeks.
  Stream<Duration> get highRatePositionStream =>
      _highRatePositionSubject.stream;
  int _lastHighRatePositionEmitMs = 0;

  /// High-rate stream compensated for DSP and native hardware latency (B-11).
  Stream<Duration> get compensatedHighRatePositionStream =>
      _highRatePositionSubject.stream
          .map((pos) => _dspPipeline.getCompensatedPosition(pos));

  /// Stream of playback positions compensated for DSP and native hardware latency.
  Stream<Duration> get compensatedPositionStream => _positionSubject.stream
      .map((pos) => _dspPipeline.getCompensatedPosition(pos));

  @override
  final StreamController<String> _errorSubject =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorSubject.stream;
  int? _currentAudioSessionId;
  final StreamController<int?> _audioSessionIdSubject =
      StreamController<int?>.broadcast();

  /// The Android audio session id of the active player, or null when the
  /// platform has not yet assigned one (or on non-Android). Consumers such as
  /// the visualizer attach to this real session instead of the global mix.
  int? get currentAudioSessionId => _currentAudioSessionId;
  Stream<int?> get audioSessionIdStream => _audioSessionIdSubject.stream;
  @override
  SongsTableData? get currentSong => _queueStateMachine.currentSong;

  @override
  PlaybackLatencyTracker? get _latencyTracker =>
      getIt.isRegistered<PlaybackLatencyTracker>()
          ? getIt<PlaybackLatencyTracker>()
          : null;
  int _lastPositionEmitMs = 0;
  @override
  double? _preCrossfadeVolume;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  PulsrAudioHandler._({
    required IMusicRepository repository,
    required YtmService ytmService,
    required AudioPlayer playerA,
    required AudioPlayer playerB,
    AudioPlayer? prefetchPlayer,
    AndroidLoudnessEnhancer? loudnessEnhancerA,
    AndroidLoudnessEnhancer? loudnessEnhancerB,
  })  : _repository = repository,
        _ytmService = ytmService,
        _playerA = playerA,
        _playerB = playerB,
        _prefetchPlayer = prefetchPlayer ?? AudioPlayer() {
    _equalizerManager = EqualizerManager(
      loudnessEnhancerA: loudnessEnhancerA,
      loudnessEnhancerB: loudnessEnhancerB,
    );
    _audioSessionIdRouter = AudioSessionIdRouter(
      onSessionChanged: (sessionId) {
        _equalizerManager.reapplyToSession(sessionId);
        _equalizerManager.syncNativeLatency(assumedOutputSampleRate);
        _currentAudioSessionId = sessionId;
        _audioSessionIdSubject.add(sessionId);
      },
      onRouteChanged: () {
        _syncBluetoothRouteFromCache();
        _equalizerManager.resyncActiveEffects();
        _equalizerManager.syncNativeLatency(assumedOutputSampleRate);
        unawaited(_refreshBluetoothRoute());
        unawaited(_recordSessionRouteChange());
      },
    );
    if (getIt.isRegistered<EqualizerManager>()) {
      getIt.unregister<EqualizerManager>();
    }
    getIt.registerSingleton<EqualizerManager>(_equalizerManager);
    if (getIt.isRegistered<AdaptiveBufferEngine>()) {
      getIt.unregister<AdaptiveBufferEngine>();
    }
    getIt.registerSingleton<AdaptiveBufferEngine>(_adaptiveBufferEngine);
    _volumeController = PlaybackVolumeController(
      getActivePlayer: () => _activePlayer,
      getInactivePlayer: () => _inactivePlayer,
    );
    // Volume coordination: the sleep fade reports its progress as a FACTOR
    // instead of writing the active player's volume itself, so it composes with
    // ducking (and defers to the crossfade manager) through the handler's
    // single [_reapplyActiveVolume] re-apply point. [baseVolumeProvider] gives
    // the manager the clean (un-faded) target for its fallback path so it never
    // snapshots a ducked level as its fade baseline.
    _sleepTimerManager.baseVolumeProvider =
        () => _calculateReplayGainVolume(currentSong);
    _sleepTimerManager.onFadeFactor = (factor) {
      _sleepFadeFactor = factor.isFinite ? factor.clamp(0.0, 1.0) : 1.0;
      unawaited(_reapplyActiveVolume());
    };
    // Backstop: if _init() throws before reaching its restore block, the
    // effects-ready signal must still fire so listeners aren't left waiting.
    _init().catchError((Object e, StackTrace st) {
      // Without this, the Future returned by whenComplete() below re-throws the
      // error with no listener and it surfaces as an unhandled async error.
      ErrorLogger.log('PulsrAudioHandler._init failed',
          error: e, stackTrace: st, category: 'AudioHandler');
    }).whenComplete(() {
      if (!_effectsReadyCompleter.isCompleted) {
        _effectsReadyCompleter.complete();
      }
      // Restore a persisted sleep timer (process death / background kill).
      // Fire-and-forget: re-arms only duration timers still in the future.
      unawaited(_sleepTimerManager.restorePersistedState(
        onTimerExpired: () async => pause(),
        getActivePlayer: () => _activePlayer,
      ));
    });
  }

  EqualizerManager get equalizerManager => _equalizerManager;
  AudioSessionIdRouter get audioSessionIdRouter => _audioSessionIdRouter;
  AdaptiveBufferEngine get adaptiveBufferEngine => _adaptiveBufferEngine;
  OptimizedDspPipeline get dspPipeline => _dspPipeline;
  PlaybackAnalytics get playbackAnalytics => _playbackAnalytics;
  AudioMemoryManager get memoryManager => _memoryManager;
  SmartPreloadScheduler get preloadScheduler => _preloadScheduler;
  FormatAwareDecoder get formatDecoder => _formatDecoder;
  TripleBufferPipeline get tripleBufferPipeline => _tripleBufferPipeline;
  BatteryAwarePlayback get batteryAwarePlayback => _batteryAwarePlayback;
  StreamPreResolver get streamPreResolver => _streamPreResolver;
  PlaybackVolumeController? get volumeController => _volumeController;
  StreamResolutionPipeline get streamResolutionPipeline =>
      _streamResolutionPipeline;

  /// Observable degraded-mode flag (B-2): true when [AudioService.init] failed
  /// or timed out, so playback runs without a platform media bridge (no
  /// notification / mediaPlayback foreground service). The UI can read this to
  /// surface the condition; it is never set on a healthy start-up.
  final ValueNotifier<bool> platformBridgeDegraded = ValueNotifier<bool>(false);

  /// Mirrors the cached output route's Bluetooth flag into the effects layer.
  /// Synchronous (uses the HiResAudioService cache) so a route-change resync
  /// sees the new route immediately instead of hardcoding a wired route.
  void _syncBluetoothRouteFromCache() {
    try {
      if (!getIt.isRegistered<HiResAudioService>()) return;
      final info = getIt<HiResAudioService>().currentOutputInfo;
      if (info != null) _equalizerManager.isBluetoothRoute = info.isBluetooth;
    } catch (_) {}
  }

  /// Refreshes the cached output info from native, then mirrors the route.
  Future<void> _refreshBluetoothRoute() async {
    try {
      if (!getIt.isRegistered<HiResAudioService>()) return;
      final wasBluetooth = _equalizerManager.isBluetoothRoute;
      final info = await getIt<HiResAudioService>().getAudioOutputInfo();
      _equalizerManager.isBluetoothRoute = info.isBluetooth;
      if (wasBluetooth != info.isBluetooth) {
        await _equalizerManager.resyncActiveEffects();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to refresh Bluetooth route and sync effects',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// One-shot auto-resume after a becoming-noisy pause.
  /// Fires only when the user opted in, the pause was noisy-triggered, the
  /// timeout has not elapsed, the player is still paused, and the new route
  /// is a headset-like output (BT / wired / USB / HDMI).
  Future<void> _maybeAutoResumeOnReconnect() async {
    if (!_pausedForNoisy) return;
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      if (!(prefs.getBool(PrefsKeys.autoResumeOnReconnect) ?? false)) {
        _pausedForNoisy = false;
        return;
      }
      final timeoutSec = prefs.getInt(PrefsKeys.autoResumeTimeoutSec) ?? 90;
      final pausedAt = _noisyPauseTime;
      if (pausedAt == null ||
          DateTime.now().difference(pausedAt).inSeconds > timeoutSec) {
        _pausedForNoisy = false;
        return;
      }
      if (_activePlayer.playing || _songs.isEmpty) {
        _pausedForNoisy = false;
        return;
      }
      final info = getIt.isRegistered<HiResAudioService>()
          ? getIt<HiResAudioService>().currentOutputInfo
          : null;
      if (info == null) return;
      final type = info.activeDeviceType.trim().toLowerCase();
      final isHeadsetLike = info.isBluetooth ||
          info.isUsbDac ||
          type == 'wired' ||
          type == 'wired_headset' ||
          type == 'headset' ||
          type == 'usb' ||
          type == 'aux' ||
          type == 'line_out' ||
          type == 'hdmi' ||
          type == 'hearing_aid' ||
          type == 'ble';
      if (!isHeadsetLike) return;
      _pausedForNoisy = false;
      await play();
    } catch (_) {
      _pausedForNoisy = false;
    }
  }

  // ── Per-session audio telemetry (pure Dart, best-effort) ───────────────
  // One record per playback session: route/codec/negotiated format plus any
  // route change, interruption and underrun/dropout count. Every call is
  // fire-and-forget; the service never throws and is a no-op when disabled.

  Future<AudioOutputInfo?> _currentOutputInfo() async {
    try {
      if (!getIt.isRegistered<HiResAudioService>()) return null;
      return await getIt<HiResAudioService>().getAudioOutputInfo();
    } catch (_) {
      return null;
    }
  }

  Future<void> _recordSessionRouteChange() async {
    try {
      if (!AudioSessionLog.instance.hasActiveSession) return;
      final info = await _currentOutputInfo();
      if (info == null) return;
      await AudioSessionLog.instance.updateOutputInfo(
        routeType: AudioSessionLog.routeTypeForInfo(info),
        bluetoothCodec: info.btCodecName,
        sampleRate: info.sampleRate,
        bitDepth: info.bitDepth,
      );
    } catch (_) {}
  }

  factory PulsrAudioHandler(
      IMusicRepository repository, YtmService ytmService) {
    if (Platform.isAndroid) {
      final loadConfig = _loadConfigForBucket(BufferBucket.standard);

      final playerA = AudioPlayer(
        audioLoadConfiguration: loadConfig,
        useLazyPreparation: true,
      );
      final playerB = AudioPlayer(
        audioLoadConfiguration: loadConfig,
        useLazyPreparation: true,
      );
      final prefetchPlayer = AudioPlayer(
        audioLoadConfiguration: loadConfig,
        useLazyPreparation: true,
      );
      return PulsrAudioHandler._(
        repository: repository,
        ytmService: ytmService,
        playerA: playerA,
        playerB: playerB,
        prefetchPlayer: prefetchPlayer,
      );
    } else {
      return PulsrAudioHandler._(
        repository: repository,
        ytmService: ytmService,
        playerA: AudioPlayer(useLazyPreparation: true),
        playerB: AudioPlayer(useLazyPreparation: true),
        prefetchPlayer: AudioPlayer(useLazyPreparation: true),
      );
    }
  }

  static MediaItem _songToMediaItem(SongsTableData song, [Uri? artUri]) {
    Uri? finalArtUri = (artUri != null &&
            artUri.hasScheme &&
            (artUri.host.isNotEmpty || artUri.path.isNotEmpty))
        ? artUri
        : null;

    if (finalArtUri == null) {
      final artString = (song.artworkUri != null && song.artworkUri!.isNotEmpty)
          ? song.artworkUri!
          : (song.remoteArtworkUrl != null && song.remoteArtworkUrl!.isNotEmpty)
              ? song.remoteArtworkUrl!
              : null;
      if (artString != null) {
        final parsed = Uri.tryParse(artString);
        if (parsed != null &&
            parsed.hasScheme &&
            (parsed.host.isNotEmpty ||
                parsed.scheme == 'file' ||
                parsed.scheme == 'content')) {
          finalArtUri = parsed;
        }
      }
      finalArtUri ??= ArtworkUriResolver.getCachedArtworkUri(song.id) ??
          (song.albumId != null
              ? ArtworkUriResolver.getCachedAlbumArtUri(song.albumId!)
              : null);
      if (finalArtUri == null && song.albumId != null && song.albumId! > 0) {
        finalArtUri = Uri.parse(
            'content://media/external/audio/albumart/${song.albumId}');
      } else if (finalArtUri == null && song.id > 0) {
        finalArtUri = Uri.parse(
            'content://media/external/audio/media/${song.id}/albumart');
      }
    }

    return MediaItem(
      id: song.id.toString(),
      album: song.album,
      title: song.title,
      artist: song.artist,
      // 0 means "unknown" (streams); null lets the platform show an indeterminate
      // bar until the player's durationStream reports the real length.
      duration:
          song.durationMs > 0 ? Duration(milliseconds: song.durationMs) : null,
      artUri: finalArtUri,
      extras: {
        'path': song.path,
        'uri': song.uri,
        'albumId': song.albumId,
        'artistId': song.artistId,
        'isFavorite': song.isFavorite,
        'trackNumber': song.trackNumber,
        'discNumber': song.discNumber,
        'year': song.year,
        'genre': song.genre,
        'playCount': song.playCount,
        'remoteId': song.remoteId,
        'source': song.source,
        'isDownloaded': song.isDownloaded,
        'remoteArtworkUrl': song.remoteArtworkUrl,
      },
    );
  }

  @override
  SharedPreferences? _cachedPrefs;

  Future<void> _initPrefs() async {
    try {
      _cachedPrefs = await SharedPreferences.getInstance();
    } catch (e, st) {
      ErrorLogger.log('SharedPreferences init failed, retrying once...',
          error: e, stackTrace: st, category: 'AudioHandler');
      try {
        _cachedPrefs = await SharedPreferences.getInstance();
      } catch (e2, st2) {
        ErrorLogger.log('SharedPreferences init failed permanently',
            error: e2, stackTrace: st2, category: 'AudioHandler');
        _cachedPrefs = null;
      }
    }
  }

  @override
  double _volume = 1.0;
  double get volume => _volume;

  /// Direct Volume Control: when true the composed gain is applied in the
  /// native float DSP path and player volume stays at unity.
  bool _dvcEnabled = false;
  bool get isDvcEnabled => _dvcEnabled;

  /// True when the native DSP ReplayGain pre-gain stage is carrying the
  /// current track's gain (bit-transparent, 20ms-smoothed, clipping-safe).
  /// When true the Dart mixer carries only user volume + per-song offset so
  /// the same gain is never applied twice. Falls back to false on non-Android,
  /// bit-perfect bypass, DoP, or native-bridge failure (Dart math then owns RG).
  bool _nativeRgActive = false;
  bool get isNativeRgActive => _nativeRgActive;

  /// Assumed Android mixer rate until the real output rate is known. The HAL
  /// only reports it after the first AudioTrack opens, so cold-start DSP
  /// coefficient init uses this; per-track [AudioEffectsChannel.resyncForTrack]
  /// in [_notifyTrackChanged] corrects it once real header rates arrive.
  static const double assumedOutputSampleRate = 48000.0;

  void _syncVolumeControllerSettings() {
    final prefs = _cachedPrefs;
    final bitPerfect = (prefs?.getBool(PrefsKeys.bitPerfectOutput) ?? false) &&
        (prefs?.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true);
    _volumeController?.updateSettings(
      userVolume: _volume,
      replayGainMode: prefs?.getString(PrefsKeys.replayGainMode) ?? 'track',
      preampWithRg: prefs?.getDouble(PrefsKeys.replayGainPreampWithRg) ?? 0.0,
      preampWithoutRg:
          prefs?.getDouble(PrefsKeys.replayGainPreampWithoutRg) ?? 0.0,
      duckFactor: duckingController.duckFactor,
      isDucked: _duckActive,
      nativeRgActive: _nativeRgActive && Platform.isAndroid,
      dvcEnabled: _dvcEnabled,
      isDopActive: AudioQualityInfo.dsdDopActive,
      bitPerfectBypass: bitPerfect,
    );
  }

  @override
  double _calculateReplayGainVolume(SongsTableData? song) {
    _syncVolumeControllerSettings();
    final controller = _volumeController;
    if (controller != null) {
      final perSongDb = song != null ? _perSongVolumeDbFor(song) : 0.0;
      final target = controller.calculateTargetVolume(
        song,
        albumContext: _isConsecutiveAlbumPlayback(),
        perSongOffsetDb: perSongDb,
      );
      if (_dvcEnabled && (song == null || song.id == currentSong?.id)) {
        unawaited(_pushDvcGain(_volume));
      }
      return target;
    }

    if (AudioQualityInfo.dsdDopActive) return 1.0;
    if (song == null) {
      if (_dvcEnabled) {
        unawaited(_pushDvcGain(_volume));
        return 1.0;
      }
      return _volume;
    }
    final prefs = _cachedPrefs;
    if (prefs == null) return _volume;
    final bitPerfect = (prefs.getBool(PrefsKeys.bitPerfectOutput) ?? false) &&
        (prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true);
    if (bitPerfect) return _volume;
    if (_nativeRgActive && Platform.isAndroid) {
      final perSongDb = _perSongVolumeDbFor(song);
      if (_dvcEnabled) {
        if (song.id == currentSong?.id) {
          unawaited(_pushDvcGain(_volume));
        }
        if (perSongDb == 0.0) return 1.0;
        return math.pow(10, perSongDb / 20).toDouble().clamp(0.0, 1.0);
      }
      var base = _volume;
      if (perSongDb != 0.0) {
        base = (base * math.pow(10, perSongDb / 20).toDouble()).clamp(0.0, 1.0);
      }
      return base;
    }
    final dvc = _dvcEnabled;
    var scaled = ReplayGainMath.apply(
      mode: prefs.getString(PrefsKeys.replayGainMode) ?? 'track',
      volume: dvc ? 1.0 : _volume,
      trackGainDb: song.replayGainTrack,
      trackPeak: song.replayGainTrackPeak,
      albumGainDb: song.replayGainAlbum,
      albumPeak: song.replayGainAlbumPeak,
      albumContext: _isConsecutiveAlbumPlayback(),
      preampWithRg: prefs.getDouble(PrefsKeys.replayGainPreampWithRg) ?? 0.0,
      preampWithoutRg:
          prefs.getDouble(PrefsKeys.replayGainPreampWithoutRg) ?? 0.0,
    );
    try {
      final perSongDb = _perSongVolumeDbFor(song);
      if (perSongDb != 0.0) {
        final factor = math.pow(10, perSongDb / 20).toDouble();
        scaled = (scaled * factor).clamp(0.0, 1.0);
      }
    } catch (_) {}
    if (dvc && song.id == currentSong?.id) {
      unawaited(_pushDvcGain(_volume));
    }
    return scaled;
  }

  /// Pushes the user-volume component to the native Direct Volume Control
  /// stage (applied in the float DSP path). ReplayGain/per-song/fades stay in
  /// the player mixer.
  Future<void> _pushDvcGain(double gain) async {
    try {
      await AudioEffectsChannel().setDvcGain(gain.clamp(0.0, 4.0));
    } catch (e, st) {
      ErrorLogger.log('Failed to push DVC gain to native channel',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Reads the per-song volume override without a hard DI dependency so unit
  /// test doubles of the handler keep working.
  double _perSongVolumeDbFor(SongsTableData song) {
    try {
      final store = getIt.isRegistered<PerSongVolumeStore>()
          ? getIt<PerSongVolumeStore>()
          : null;
      if (store == null) return 0.0;
      final key = song.id.toString();
      return store.getGainDbForTrack(key);
    } catch (_) {
      return 0.0;
    }
  }

  /// Pushes ReplayGain tags to the native DSP pre-gain stage (bit-transparent,
  /// 20ms-smoothed, clipping-safe). On success [_nativeRgActive] is set so
  /// [_calculateReplayGainVolume] skips the Dart RG math (no double-apply):
  /// native owns RG, Dart mixer owns user volume + per-song offset.
  /// Falls back to Dart math on non-Android, bit-perfect bypass, DoP, mode
  /// off, or bridge failure — the mixer then applies RG as before.
  void _syncNativeRgFlag() {
    _volumeController?.setNativeRgActive(_nativeRgActive);
  }

  Future<void> _pushNativeReplayGain(SongsTableData? song) async {
    Future<void> disableNative() async {
      _nativeRgActive = false;
      _syncNativeRgFlag();
      try {
        await AudioEffectsChannel().setReplayGainEnabled(false);
      } catch (e, st) {
        ErrorLogger.log(
          'Failed to disable native ReplayGain stage',
          error: e,
          stackTrace: st,
          category: 'PulsrAudioHandler',
        );
      }
    }

    if (!Platform.isAndroid) {
      _nativeRgActive = false;
      _syncNativeRgFlag();
      return;
    }
    if (AudioQualityInfo.dsdDopActive) {
      await disableNative();
      return;
    }
    final prefs = _cachedPrefs;
    if (prefs == null || song == null) {
      await disableNative();
      return;
    }
    final bitPerfect = (prefs.getBool(PrefsKeys.bitPerfectOutput) ?? false) &&
        (prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true);
    if (bitPerfect) {
      await disableNative();
      return;
    }
    final mode = prefs.getString(PrefsKeys.replayGainMode) ?? 'track';
    if (mode == 'off') {
      await disableNative();
      return;
    }
    try {
      final albumContext = _isConsecutiveAlbumPlayback();
      final applied = await AudioEffectsChannel().setReplayGainParams(
        mode: ReplayGainMath.nativeModeFor(mode, albumContext: albumContext),
        // ReplayGain tags come from arbitrary file metadata / the scanner and
        // can be corrupt (NaN, ±inf, absurd magnitudes). The Dart mixer maths
        // sanitizes them, but the native pre-gain stage consumes the raw
        // doubles: one NaN poisons its smoothed gain for the rest of the
        // session, turning every following track into noise. Sanitize here.
        trackGainDb: ReplayGainMath.sanitizeGainDb(song.replayGainTrack),
        albumGainDb: ReplayGainMath.sanitizeGainDb(song.replayGainAlbum),
        trackPeak: ReplayGainMath.sanitizePeak(song.replayGainTrackPeak),
        albumPeak: ReplayGainMath.sanitizePeak(song.replayGainAlbumPeak),
        preAmpDb: ReplayGainMath.sanitizeGainDb(ReplayGainMath.nativePreAmpFor(
          mode: mode,
          trackGainDb: song.replayGainTrack,
          albumGainDb: song.replayGainAlbum,
          albumContext: albumContext,
          preampWithRg:
              prefs.getDouble(PrefsKeys.replayGainPreampWithRg) ?? 0.0,
          preampWithoutRg:
              prefs.getDouble(PrefsKeys.replayGainPreampWithoutRg) ?? 0.0,
        )),
        preventClipping: true,
        enabled: true,
      );
      _nativeRgActive = applied;
      _syncNativeRgFlag();
      if (!applied) {
        await AudioEffectsChannel().setReplayGainEnabled(false);
      }
    } catch (_) {
      _nativeRgActive = false;
      _syncNativeRgFlag();
    }
  }

  DateTime? _lastNativeRgPush;
  int? _lastNativeRgSongId;

  Future<void> setVolume(double volume) async {
    // NaN.clamp() returns NaN, which would poison every composed gain after it.
    _volume = volume.isFinite ? volume.clamp(0.0, 1.0) : _volume;
    if (!_effectsReadyCompleter.isCompleted) {
      await _effectsReadyCompleter.future;
    }
    final song = currentSong;
    final target = _calculateReplayGainVolume(song);
    _volumeController?.updateSettings(userVolume: _volume);
    try {
      await _equalizerManager.updateLoudnessVolume(_volume);
    } catch (e, st) {
      ErrorLogger.log('Failed to update loudness volume in setVolume',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    await _activePlayer.setVolume((target * _sleepFadeFactor).clamp(0.0, 1.0));

    final now = DateTime.now();
    if (_lastNativeRgPush == null ||
        _lastNativeRgSongId != song?.id ||
        now.difference(_lastNativeRgPush!) > const Duration(seconds: 2)) {
      _lastNativeRgPush = now;
      _lastNativeRgSongId = song?.id;
      unawaited(_pushNativeReplayGain(song));
    }
  }

  /// Single re-apply point for the ACTIVE player's volume, composing the
  /// duck-aware ReplayGain/user target ([_calculateReplayGainVolume] already
  /// folds in the active duck factor via the volume controller) with the
  /// current sleep-fade factor. Routing duck-end and each sleep-fade tick
  /// through here means a duck-end can no longer wipe an in-flight fade for a
  /// tick, and a fade tick can no longer undo the duck.
  ///
  /// No-op while a crossfade is running: the CrossfadeManager owns both
  /// players' live volume ramps then (same contract the duck-end guard uses),
  /// so this must not fight it.
  Future<void> _reapplyActiveVolume() async {
    if (_crossfadeManager.isCrossfading) return;
    final target = _calculateReplayGainVolume(currentSong);
    try {
      await _activePlayer
          .setVolume((target * _sleepFadeFactor).clamp(0.0, 1.0));
    } catch (e, st) {
      ErrorLogger.log('Failed to re-apply active player volume',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Resets every piece of duck bookkeeping in one place so the interruption
  /// paths (pause end, unknown end, stop) cannot forget a field and leave a
  /// stale timer or captured volume behind.
  void _clearDuckState() {
    _duckSafetyTimer?.cancel();
    _duckSafetyTimer = null;
    _systemSoundTimer?.cancel();
    _systemSoundTimer = null;
    _duckActive = false;
    _duckDepthCounter = 0;
    _preDuckVolume = null;
    _preDuckInactiveVolume = null;
    _preDuckSongId = null;
    _preDuckRgTarget = null;
    _volumeController?.updateSettings(isDucked: false);
  }

  /// Toggles Direct Volume Control. Enabling pins Android's media stream to
  /// maximum and applies the composed gain in the native float DSP path;
  /// disabling restores the previous system volume. No-op when native DVC is
  /// unsupported (the preference push is then rolled back by the caller path).
  Future<void> setDvcEnabled(bool enabled) async {
    if (enabled == _dvcEnabled) {
      if (enabled) {
        await AudioEffectsChannel().setDvcEnabled(true);
      }
      return;
    }
    if (enabled) {
      final supported = await AudioEffectsChannel().isDvcSupported();
      if (!supported) {
        _dvcEnabled = false;
        _volumeController?.setDvcEnabled(false);
        await AudioEffectsChannel().setDvcEnabled(false);
        return;
      }
      _dvcEnabled = true;
      _volumeController?.setDvcEnabled(true);
      await AudioEffectsChannel().setDvcEnabled(true);
    } else {
      _dvcEnabled = false;
      _volumeController?.setDvcEnabled(false);
      await AudioEffectsChannel().setDvcEnabled(false);
    }
    // Re-apply the current volume so the new gain stage takes effect now.
    await setVolume(_volume);
  }

  @override
  int _engineSwitchGeneration = 0;
  @override
  bool _pendingPlaybackStart = false;

  /// Whether a completion report at [now] is distinct from a previous one at
  /// [last]. Split out so the debounce window is unit-testable.
  @visibleForTesting
  static bool isDistinctSleepCompletion(DateTime? last, DateTime now) =>
      last == null ||
      now.difference(last) >= const Duration(milliseconds: 1500);

  /// Guard for the automatic-skip cascade: halt once enough consecutive tracks
  /// have failed (or the whole queue has), or when the rapid-advance circuit
  /// breaker has tripped.
  ///
  /// Extracted so the invariant that error-driven gapless advances must NOT
  /// reset the failure budget is covered by a unit test: if a caller zeroes the
  /// counter on every auto-advance (as `_onGaplessIndexChanged` used to), this
  /// predicate can never become true and a dead queue skips forever.
  @visibleForTesting
  static bool shouldHaltFailureCascade({
    required int consecutiveFailures,
    required int rapidGaplessChanges,
    required int queueLength,
  }) =>
      consecutiveFailures >= 3 ||
      (queueLength > 0 && consecutiveFailures >= queueLength) ||
      rapidGaplessChanges >= 1;

  Future<void> onAppPaused() async {
    await saveCurrentPositionImmediate();
    await _equalizerManager.onAppPaused();
  }

  File? _cachedRecoveryFile;

  Future<File?> _getLastPositionRecoveryFile() async {
    // Resolved once: this runs every ~2s while playing and the path never
    // changes, so don't hit the path_provider platform channel each time.
    final cached = _cachedRecoveryFile;
    if (cached != null) return cached;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return _cachedRecoveryFile = File(p.join(dir.path, 'last_position.json'));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> _readCrashPositionRecovery() async {
    try {
      final file = await _getLastPositionRecoveryFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(saveCurrentPositionImmediate());
    }
  }

  Future<void>? _positionSaveInFlight;
  bool _positionSaveQueued = false;

  /// Serialized + coalesced: the 2s timer, [didChangeAppLifecycleState] and the
  /// lifecycle observer can all fire together on backgrounding, and two
  /// overlapping DB/file writes can land out of order. While a write is in
  /// flight, further calls just request one more pass and await the same run.
  @override
  Future<void> saveCurrentPositionImmediate() async {
    final inFlight = _positionSaveInFlight;
    if (inFlight != null) {
      _positionSaveQueued = true;
      return inFlight;
    }
    final completer = Completer<void>();
    _positionSaveInFlight = completer.future;
    try {
      do {
        _positionSaveQueued = false;
        await _writePositionSnapshot();
      } while (_positionSaveQueued && !_disposed);
    } finally {
      _positionSaveInFlight = null;
      completer.complete();
    }
  }

  Future<void> _writePositionSnapshot() async {
    final hasPosition = _songs.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _songs.length;
    if (!hasPosition) {
      // Nothing to write; clear so the periodic timer does not spin.
      _positionDirty = false;
      return;
    }
    final currentSong = _songs[_currentIndex];
    final posMs = _activePlayer.position.inMilliseconds;
    try {
      await PositionCrashGuard.writeSnapshot(
        songId: currentSong.id,
        queueIndex: _currentIndex,
        positionMs: posMs,
        queueIds: _songs.map((s) => s.id).toList(),
      );
      final recoveryFile = await _getLastPositionRecoveryFile();
      if (recoveryFile != null) {
        final payload = jsonEncode({
          'songId': currentSong.id,
          'positionMs': posMs,
          'queueIndex': _currentIndex,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        await recoveryFile.writeAsString(payload, flush: true);
      }
    } catch (_) {}
    try {
      await _repository.updateLastPosition(currentSong.id, posMs);
      if (_queueDirty || _currentIndex != _savedQueueIndex) {
        await _repository.saveQueue(
            _songs.map((s) => s.id).toList(), _currentIndex, posMs);
        _queueDirty = false;
        _savedQueueIndex = _currentIndex;
      } else {
        // Same track, later position: refresh just the current row so a cold
        // resume restores where the user actually was, not the position from
        // the last structural queue edit (skipToNext never dirtied the queue).
        await _repository.updateQueuePosition(posMs);
      }
      // Only clear AFTER a successful write, and only if no newer position arrived
      // while the async database write was in flight.
      if (_activePlayer.position.inMilliseconds == posMs) {
        _positionDirty = false;
      }
      unawaited(PositionCrashGuard.clearSnapshot());
    } catch (e, st) {
      // Re-dirty so the periodic timer (and a later app pause) retries.
      _positionDirty = true;
      ErrorLogger.log('Failed to save current position',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  @override
  void _saveCurrentPosition() {
    _positionDirty = true;
  }

  void _initSaveTimer() {
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_positionDirty) {
        unawaited(saveCurrentPositionImmediate());
      }
    });
  }

  Future<void> _init() async {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
    _initSaveTimer();
    AudioMemoryManager.adaptBudgetToSystemRam();
    await _initPrefs();
    // Restore the 24/32-bit float DSP path before any other player call so the
    // native sink is built with the persisted preference. Defaults ON so hi-res
    // sources are never truncated to 16-bit; 16-bit content is unaffected.
    await setFloatOutputEnabled(
      _cachedPrefs?.getBool(PrefsKeys.floatOutputEnabled) ?? true,
    );
    // Restore the opt-in AAudio Direct output before any other player call
    // so the sink is built with the persisted preference. Off by default.
    await setAaudioOutputEnabled(
      _cachedPrefs?.getBool(PrefsKeys.aaudioOutputEnabled) ?? false,
      preferExclusive:
          _cachedPrefs?.getBool(PrefsKeys.aaudioPreferExclusive) ?? true,
      targetBufferMs:
          _cachedPrefs?.getInt(PrefsKeys.aaudioTargetBufferMs) ?? 150,
    );
    // Unsupported optional DSP preferences must not abort player startup.
    // Android currently handles playback rate conversion itself.
    await setSincResamplerQuality(
      _cachedPrefs?.getInt(PrefsKeys.sincResamplerQuality) ?? 3,
    );
    // Restore Direct Volume Control. Only the system-stream pinning needs to
    // happen here; per-track gain is applied by _calculateReplayGainVolume.
    _dvcEnabled = _cachedPrefs?.getBool(PrefsKeys.dvcEnabled) ?? false;
    if (_dvcEnabled) {
      unawaited(AudioEffectsChannel().setDvcEnabled(true));
    }
    _crossfadeManager.bpmSyncEnabled =
        _cachedPrefs?.getBool(PrefsKeys.bpmSyncCrossfadeEnabled) ?? false;
    // Restore persisted playback speed/pitch and the extended speed range so a
    // saved out-of-range speed is not silently clamped to 0.25–4.0 on cold start.
    await restorePersistedSpeed();

    _playbackAnalytics = PlaybackAnalytics(
      onIncreaseBufferSizeRequested: () {
        debugPrint(
            '[AudioHandler] PlaybackAnalytics requested buffer size increase');
        _adaptiveBufferEngine.forceBucket(BufferBucket.generous);
      },
      onReduceQualityRequested: () {
        debugPrint(
            '[AudioHandler] PlaybackAnalytics requested quality reduction');
        // F4: adaptive quality step-down mid-track.
        unawaited(_maybeAdaptiveStepDown());
      },
    );

    _memoryManager = AudioMemoryManager(
      onEvictOldestCacheRequested: () {
        AudioMemoryManager.trimStreamCache(_streamCache);
      },
      onBackgroundReleaseRequested: () {
        AudioMemoryManager.trimStreamCache(_streamCache);
      },
      onPreloadRejected: (key, sizeBytes) {
        debugPrint(
            '[AudioHandler] Preload rejected for $key ($sizeBytes bytes)');
      },
    );

    _preloadScheduler = SmartPreloadScheduler(
      // Intentional no-op: URL warming is handled by _smartPrefetch() and
      // StreamPreResolver, so the scheduler only needs the cancel hook below.
      onPreloadRequested: (song, {required priority}) async {},
      onCancelRequested: () => cancelPrefetches(),
      qualityProvider: _currentStreamingQuality,
    );

    _streamPreResolver = StreamPreResolver(
      resolveUrl: (videoId, {quality = 'high'}) =>
          _ytmService.resolveStream(videoId, quality: quality),
      urlCache: getIt.isRegistered<YtmUrlCache>()
          ? getIt<YtmUrlCache>()
          : YtmUrlCache(),
      qualityProvider: _currentStreamingQuality,
      isAlreadyPrefetching: (id) =>
          _prefetching
              .contains('$id:${_currentStreamingQuality().toLowerCase()}') ||
          _prefetching.contains(id),
      repeatQueueProvider: () =>
          playbackState.value.repeatMode == AudioServiceRepeatMode.all,
    );

    _formatDecoder = FormatAwareDecoder(
      resolveYtmStream: (song, tag) => _resolveAudioSource(song, tag),
      decodeDsdToPcm: (song, tag) => DsdDecoderHelper.decodeDsdFile(song, tag),
    );

    _tripleBufferPipeline = TripleBufferPipeline(
      getActivePlayer: () => _activePlayer,
      getInactivePlayer: () => _inactivePlayer,
      prefetchPlayer: _prefetchPlayer,
      analytics: _playbackAnalytics,
      // Abort stale preloads: a resolve that outlives the track that
      // scheduled it must never setAudioSource on the now-active player.
      // Generation is the real guard (player objects are always distinct, so
      // `identical` alone can never detect a swap); crossfade state is the
      // secondary guard.
      isLoadStillValid: () => !_crossfadeManager.isCrossfading,
      getGeneration: () => _playGeneration,
      resolveAudioSource: (song, tag) => _resolveAudioSource(song, tag),
      songToMediaItem: (song, [fastArtUri]) =>
          _songToMediaItem(song, fastArtUri),
    );

    _batteryAwarePlayback = BatteryAwarePlayback(
      onLowPowerMode: ({required disableVisualizer, required reduceDsp}) {
        debugPrint('[AudioHandler] Battery low power mode triggered');
        if (reduceDsp) {
          unawaited(_equalizerManager.degradeToEssentials());
        }
        _adaptiveBufferEngine.forceBucket(BufferBucket.minimal);
      },
      onCriticalMode: ({required disableCrossfade, required minimalBuffer}) {
        debugPrint('[AudioHandler] Battery critical power mode triggered');
        if (disableCrossfade && _crossfadeManager.duration > Duration.zero) {
          setCrossfadeDuration(Duration.zero);
        }
        _adaptiveBufferEngine.forceBucket(BufferBucket.minimal);
      },
      onRestoreNormal: () {
        debugPrint('[AudioHandler] Battery restored to normal');
        unawaited(_equalizerManager.restoreFromDegrade());
        _adaptiveBufferEngine.releaseForce();
      },
    );

    _volumeController ??= PlaybackVolumeController(
      getActivePlayer: () => _activePlayer,
      getInactivePlayer: () => _inactivePlayer,
    );
    _syncVolumeControllerSettings();
    unawaited(HeadsetControlConfig.load(_cachedPrefs).then((cfg) {
      _cachedHeadsetConfig = cfg;
    }).catchError((Object e, StackTrace st) {
      ErrorLogger.log('Failed to load headset control config',
          error: e, stackTrace: st, category: 'AudioHandler');
    }));
    _streamResolutionPipeline = StreamResolutionPipeline(
      ytmService: _ytmService,
      getLatencyTracker: () => _latencyTracker,
    );

    _equalizerManager.attachDspPipeline(_dspPipeline);
    unawaited(_equalizerManager.syncNativeLatency(assumedOutputSampleRate));

    _gaplessMonitor.attach(
      currentIndexStream: _activePlayer.currentIndexStream,
      positionStream: _activePlayer.positionStream,
    );

    _subscriptions.add(
      _adaptiveBufferEngine.onBucketChanged.listen((bucket) {
        _onBufferBucketChanged(bucket);
      }),
    );
    // Quality step-down decisions are consolidated under AdaptiveQualityManager
    // (via PlaybackAnalytics -> _maybeAdaptiveStepDown) to avoid duplicate drops or thrashing.

    _subscriptions.add(
      // Battery-aware playback only needs the level while audio is actually
      // playing. Skip the native platform round-trip when paused/idle, and widen
      // the tick from 45s to 120s, so this subscription stops waking the CPU and
      // querying the OS every 45s forever while the app is idle/backgrounded.
      // The subscription stays registered in _subscriptions, so it is still
      // cancelled on dispose exactly as before.
      Stream.periodic(const Duration(seconds: 120)).listen((_) async {
        if (_disposed || !_activePlayer.playing) return;
        try {
          final level = await BatteryOptimizationService.getBatteryLevel();
          if (level != null) {
            _batteryAwarePlayback.onBatteryLevelChanged(level);
          }
        } catch (_) {
          // Best-effort telemetry; a platform hiccup must not become an
          // uncaught async error every two minutes.
        }
      }),
    );
    BatteryOptimizationService.getBatteryLevel().then((level) {
      if (level != null) {
        _batteryAwarePlayback.onBatteryLevelChanged(level);
      }
    }).catchError((_) {});

    void setupPlayerListeners(AudioPlayer player, bool isPlayerA) {
      bool isTargetActive() =>
          isPlayerA == _isPlayerAActive && identical(player, _activePlayer);

      _subscriptions.add(
        player.playbackEventStream.listen(
          (event) {
            if (_disposed) return;
            if (isTargetActive()) {
              if (event.processingState == ProcessingState.buffering &&
                  _activePlayer.playing) {
                _playbackAnalytics.recordBufferUnderrun();
                unawaited(AudioSessionLog.instance.recordUnderrun());
              }
              _broadcastState(event);
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player playbackEventStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.durationStream.listen(
          (dur) {
            if (_disposed) return;
            if (isTargetActive() && dur != null && dur > Duration.zero) {
              final current = mediaItem.value;
              if (current != null && current.duration != dur) {
                mediaItem.add(current.copyWith(duration: dur));
              }
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player durationStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.playerStateStream.listen(
          (state) async {
            if (_disposed) return;
            if (isTargetActive()) {
              // Broadcast is driven solely by the playbackEventStream listener
              // above (C-5): playerStateStream is derived from the same event
              // stream, so broadcasting here serialised every transition to the
              // platform twice per state change.
              // Gapless loop-all support
              if (_gaplessMode &&
                  state.processingState == ProcessingState.completed &&
                  _activePlayer.loopMode == LoopMode.all) {
                // `completed` can also fire mid-queue while the next item is
                // swapped in (see the comment below). Only wrap to the start
                // when the LAST item actually finished, otherwise this would
                // yank playback back to track 1 on every transition.
                final idx = _activePlayer.currentIndex;
                final len = _activePlayer.sequence.length;
                if (idx == null || idx >= len - 1) {
                  try {
                    await _activePlayer.seek(Duration.zero, index: 0);
                    unawaited(_activePlayer.play());
                  } catch (e, st) {
                    ErrorLogger.log('Failed to wrap queue for repeat-all',
                        error: e, stackTrace: st, category: 'AudioHandler');
                  }
                }
                return;
              }
              // In gapless mode the ConcatenatingAudioSource advances itself, so a
              // `completed` event at the very end (repeat off) means the queue is
              // exhausted. The crossfade engine (one source per track) needs a
              // manual skip only while a next item exists; both paths report queue
              // completion so the sleep timer's endOfQueue mode can fire.
              if (state.processingState == ProcessingState.completed &&
                  !_crossfadeManager.isCrossfading) {
                if (_gaplessMode && _gaplessLoaded) {
                  if (_activePlayer.loopMode == LoopMode.off) {
                    // `completed` fires both mid-queue (while ExoPlayer swaps
                    // to the next item) and at the very end. Mid-queue the
                    // boundary is already reported by the `currentIndexStream`
                    // advance, so only the last item reports here — otherwise
                    // the after-N sleep timer decremented twice per song and
                    // end-of-queue fired at the first gap.
                    if (!_activePlayer.hasNext) {
                      notifySleepTrackCompleted();
                      unawaited(_sleepTimerManager.onQueueCompleted());
                    }
                  }
                } else {
                  notifySleepTrackCompleted();
                  if (_getNextIndex(peek: true) == null) {
                    unawaited(_sleepTimerManager.onQueueCompleted());
                  }
                  unawaited(skipToNext().catchError((Object e, StackTrace st) {
                    ErrorLogger.log('Auto-advance skipToNext failed',
                        error: e, stackTrace: st, category: 'AudioHandler');
                  }));
                }
              }
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player playerStateStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.positionStream.listen(
          (pos) {
            if (_disposed) return;
            if (isTargetActive()) {
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - _lastHighRatePositionEmitMs >= 16 ||
                  pos == Duration.zero) {
                _lastHighRatePositionEmitMs = now;
                if (!_highRatePositionSubject.isClosed) {
                  _highRatePositionSubject.add(pos);
                }
              }
              if (now - _lastPositionEmitMs >= 250 || pos == Duration.zero) {
                _lastPositionEmitMs = now;
                if (!_positionSubject.isClosed) {
                  _positionSubject.add(pos);
                }
              }
              // FIX-B03: Guard failure reset on position ticks: only reset when ready and pos > 2s
              if (player.processingState == ProcessingState.ready &&
                  pos > const Duration(seconds: 2) &&
                  _consecutiveFailures > 0) {
                _consecutiveFailures = 0;
              }
              // Only dirty the 2s DB writer while actually playing; otherwise
              // a paused track keeps rewriting the same position forever.
              if (player.playing) {
                _saveCurrentPosition();
                // F1: AB loop wrap. Pass the live playback speed so the
                // look-ahead widens at 2–4x (a single ~150ms position tick
                // jumps far enough to overshoot the fixed 1x window otherwise).
                final wrap = abLoopManager.wrapTarget(pos,
                    songId: currentSong?.id, speed: _activePlayer.speed);
                if (wrap != null) {
                  unawaited(_activePlayer.seek(wrap));
                }
                // T10: enter the CUE window once decodable, then advance at
                // its end. Guards prevent a seek/advance storm on position
                // ticks before the native transition lands.
                if (player.processingState == ProcessingState.ready) {
                  final cueSong = currentSong;
                  final cueStartMs = cueSong?.cueStartMs;
                  final cueEndMs = cueSong?.cueEndMs;
                  if (cueStartMs != null &&
                      !_cueStartSeeked &&
                      pos < Duration(milliseconds: cueStartMs)) {
                    _cueStartSeeked = true;
                    unawaited(
                        _activePlayer.seek(Duration(milliseconds: cueStartMs)));
                  }
                  if (cueEndMs != null) {
                    if (!_cueAdvanceTriggered &&
                        pos >= Duration(milliseconds: cueEndMs)) {
                      _cueAdvanceTriggered = true;
                      unawaited(skipToNext());
                    } else if (pos < Duration(milliseconds: cueEndMs)) {
                      _cueAdvanceTriggered = false;
                    }
                  }
                }
                // F11: autosave bookmark for long-form tracks (throttled 5s).
                final song = currentSong;
                if (song != null &&
                    PlaybackBookmarkStore.shouldBookmark(
                        durationMs: song.durationMs,
                        genre: song.genre,
                        album: song.album)) {
                  final nowDt = DateTime.now();
                  if (_lastBookmarkSave == null ||
                      nowDt.difference(_lastBookmarkSave!) >=
                          const Duration(seconds: 5)) {
                    _lastBookmarkSave = nowDt;
                    final key = PlaybackBookmarkStore.keyFor(
                        songId: song.id,
                        remoteId: song.remoteId,
                        path: song.path);
                    bookmarkStore.save(key, pos.inMilliseconds,
                        durationMs: song.durationMs);
                  }
                }
                // F4: report healthy playback windows for adaptive step-up.
                final nowH = DateTime.now();
                if (_lastHealthyReport == null ||
                    nowH.difference(_lastHealthyReport!) >=
                        const Duration(seconds: 30)) {
                  _lastHealthyReport = nowH;
                  unawaited(_maybeAdaptiveStepUp());
                }
              }
              final rawDuration = player.duration;
              final songDurationMs = currentSong?.durationMs ?? 0;
              final duration =
                  (rawDuration != null && rawDuration > Duration.zero)
                      ? rawDuration
                      : (songDurationMs > 0
                          ? Duration(milliseconds: songDurationMs)
                          : Duration.zero);
              // Warm the next YouTube stream URL before the crossfade window even
              // opens, so resolve latency does not truncate the fade. Cheap no-op
              // for local tracks and for an already-cached url.
              if (duration > const Duration(seconds: 15) &&
                  (pos >= duration - const Duration(seconds: 15) ||
                      pos.inMilliseconds >= duration.inMilliseconds * 0.7)) {
                _smartPrefetch();
              }
              final compensatedPos = _dspPipeline.getCompensatedPosition(pos);
              if (_crossfadeManager.duration > Duration.zero &&
                  !_crossfadeManager.isCrossfading &&
                  !_gaplessMode) {
                // Peek the next index (item 10): the mutating _getNextIndex()
                // appends to shuffle history and draws a fresh random pick on
                // every qualifying tick before the crossfade latches.
                final nextIdx = _getNextIndex(peek: true);
                if (nextIdx != null &&
                    nextIdx != _currentIndex &&
                    nextIdx >= 0 &&
                    nextIdx < _songs.length) {
                  // Trigger early enough for the WHOLE fade to fit before the
                  // outgoing track ends (item 9): the effective fade can exceed
                  // the base duration (BPM alignment clamps up to 20s), and
                  // _startCrossfade needs a resolve + ~1.25s settle before the
                  // ramp opens. Firing at `duration - crossfadeDuration` (base)
                  // opened the fade too late, so the outgoing track could reach
                  // ProcessingState.completed mid-fade (one-sided fade).
                  final effFade = _crossfadeManager.effectiveFadeDuration(
                      trackId: _songs[nextIdx].id.toString());
                  const settleMargin = Duration(milliseconds: 1500);
                  if (duration > effFade + settleMargin &&
                      compensatedPos >= duration - effFade - settleMargin) {
                    _startCrossfade(nextIdx);
                  }
                }
              }
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player positionStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.androidAudioSessionIdStream.listen(
          (sessionId) {
            if (_disposed) return;
            if (isPlayerA) {
              _playerASessionId = sessionId;
            } else {
              _playerBSessionId = sessionId;
            }
            if (isTargetActive()) {
              _audioSessionIdRouter.handleSessionId(sessionId);
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player androidAudioSessionIdStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.currentIndexStream.listen(
          (index) {
            if (_disposed) return;
            // Native gapless advance: the concat moved to a new item on its own.
            // Reconcile our queue model, notification, history and position-save
            // off this single source of truth instead of a manual skip.
            if (_gaplessMode &&
                isTargetActive() &&
                index != null &&
                index != _lastGaplessIndex) {
              _onGaplessIndexChanged(index);
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player currentIndexStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );
    }

    setupPlayerListeners(_playerA, true);
    setupPlayerListeners(_playerB, false);

    // AudioSession configuration
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // Do NOT grab focus here: activating at construction steals audio focus
      // from other apps on cold start (pausing their playback) before the user
      // has played anything. just_audio activates on play()/resume and stop()
      // releases it.

      _subscriptions.add(
        session.interruptionEventStream.listen((event) async {
          if (event.begin) {
            switch (event.type) {
              case AudioInterruptionType.duck:
                unawaited(AudioSessionLog.instance
                    .recordInterruption(AudioInterruptionKind.duck));
                // F7: ducking behavior is user-controllable (duck/pause/ignore).
                if (duckingController.shouldIgnore) break;
                if (duckingController.shouldPause) {
                  _interruption.begin(InterruptionKind.duck,
                      playing: _activePlayer.playing);
                  if (_crossfadeManager.isCrossfading) {
                    await _crossfadeManager.cancel(
                        _inactivePlayer, _activePlayer,
                        restoreVolume: _preCrossfadeVolume ?? _volume);
                  }
                  await _activePlayer.pause();
                  break;
                }
                // Stack-safe: a second duck begin while already ducked must not
                // clobber the saved pre-duck level. Duck both engines so a
                // navigation prompt during a crossfade doesn't blast the fade-in.
                // Count depth only for ducks that are really engaged. Counting a
                // begin that arrived while paused left the counter one too high,
                // so the matching end never reached 0 and the volume stayed
                // ducked after playback resumed.
                if (_duckActive) {
                  _duckDepthCounter++;
                } else if (_activePlayer.playing) {
                  _duckDepthCounter = 1;
                  // Capture the clean (un-ducked) RG target and song identity
                  // first so a later duck-end can restore the EXACT pre-duck
                  // level when nothing changed during the duck.
                  _preDuckRgTarget = _calculateReplayGainVolume(currentSong);
                  _preDuckSongId = currentSong?.id;
                  _duckActive = true;
                  _duckSafetyTimer?.cancel();
                  // Safety net ONLY: if a duck-end event is never delivered this
                  // must NOT restore full volume (that would blast music over a
                  // still-active navigation prompt). It merely re-asserts the
                  // ducked level so a stuck state stays quiet; the real duck-end
                  // event remains the sole path that restores volume.
                  _duckSafetyTimer =
                      Timer(const Duration(seconds: 30), () async {
                    if (_duckActive) {
                      final rf = duckingController.duckFactor;
                      try {
                        await _activePlayer
                            .setVolume(rf * (_preDuckVolume ?? 1.0));
                        if (_crossfadeManager.isCrossfading) {
                          await _inactivePlayer
                              .setVolume(rf * (_preDuckInactiveVolume ?? 0.0));
                        }
                      } catch (_) {}
                    }
                  });
                  _preDuckVolume = _activePlayer.volume;
                  _preDuckInactiveVolume = _inactivePlayer.volume;
                  final f = duckingController.duckFactor;
                  _volumeController?.updateSettings(
                      duckFactor: f, isDucked: true);
                  await _activePlayer.setVolume(f * (_preDuckVolume ?? 1.0));
                  if (_crossfadeManager.isCrossfading) {
                    await _inactivePlayer
                        .setVolume(f * (_preDuckInactiveVolume ?? 0.0));
                  }
                }
                break;
              case AudioInterruptionType.pause:
                unawaited(AudioSessionLog.instance
                    .recordInterruption(AudioInterruptionKind.pause));
                // Stack-safe: keep the original pre-interruption state so an
                // overlapping duck + call doesn't lose the resume decision.
                _interruption.begin(InterruptionKind.pause,
                    playing: _activePlayer.playing);
                if (_interruption.wasPlayingBeforeInterruption) {
                  if (_crossfadeManager.isCrossfading) {
                    await _crossfadeManager.cancel(
                        _inactivePlayer, _activePlayer,
                        restoreVolume: _preCrossfadeVolume ?? _volume);
                  }
                  await _activePlayer.pause();
                }
                break;
              case AudioInterruptionType.unknown:
                unawaited(AudioSessionLog.instance
                    .recordInterruption(AudioInterruptionKind.unknown));
                // Permanent/unknown loss: pause, never auto-resume, free DSP.
                _interruption.begin(InterruptionKind.unknown,
                    playing: _activePlayer.playing);
                _interruption.neverResume();
                if (_crossfadeManager.isCrossfading) {
                  await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
                      restoreVolume: _preCrossfadeVolume ?? _volume);
                }
                await _activePlayer.pause();
                break;
            }
          } else {
            switch (event.type) {
              case AudioInterruptionType.duck:
                _duckSafetyTimer?.cancel();
                _duckSafetyTimer = null;
                // A duck that began in pause-mode also holds the interruption
                // bookkeeping; end it here so a later call can snapshot afresh
                // instead of inheriting a stale half-open pause (B-1).
                final wasPlayingBeforeDuck =
                    _interruption.end(InterruptionKind.duck);
                if (_duckDepthCounter > 0) _duckDepthCounter--;
                if (_duckActive && _duckDepthCounter == 0) {
                  _duckActive = false;
                  _volumeController?.updateSettings(isDucked: false);
                  // If neither the track nor the effective ReplayGain target
                  // changed during the duck, restore the EXACT captured pre-duck
                  // volume (preserving e.g. a mid-fade-in). Otherwise fall back
                  // to the current RG target (gain/track changed, or nothing was
                  // captured). This avoids both leaving the level permanently
                  // ducked and discarding an in-progress fade.
                  final currentTarget = _calculateReplayGainVolume(currentSong);
                  final sameTrack = _preDuckSongId == currentSong?.id;
                  final gainUnchanged = _preDuckRgTarget != null &&
                      (currentTarget - _preDuckRgTarget!).abs() < 0.001;
                  // When a sleep fade is in flight the captured pre-duck level
                  // is a stale faded value; restore from the clean target scaled
                  // by the LIVE fade factor so the duck-end composes with the
                  // fade instead of wiping it for a tick (Fight: duck-end vs
                  // sleep fade). With no fade (_sleepFadeFactor == 1.0) this is
                  // identical to the previous behaviour.
                  final sleepFading = _sleepFadeFactor < 0.999;
                  final restoreActive = (!sleepFading &&
                          _preDuckVolume != null &&
                          sameTrack &&
                          gainUnchanged)
                      ? _preDuckVolume!
                      : (currentTarget * _sleepFadeFactor).clamp(0.0, 1.0);
                  try {
                    await _activePlayer
                        .setVolume(restoreActive.clamp(0.0, 1.0));
                  } catch (e, st) {
                    ErrorLogger.log(
                        'Failed to restore active player volume after duck',
                        error: e,
                        stackTrace: st,
                        category: 'AudioHandler');
                  }
                  // During a crossfade the CrossfadeManager owns the inactive
                  // player's live volume ramp; forcing a value here (previously
                  // the OUTGOING track's RG applied to the INCOMING player) used
                  // the wrong gain AND overwrote the ramp. Only restore the
                  // inactive player when NOT crossfading, and then only to its
                  // captured pre-duck level.
                  if (!_crossfadeManager.isCrossfading &&
                      _preDuckInactiveVolume != null) {
                    try {
                      await _inactivePlayer.setVolume(_preDuckInactiveVolume!);
                    } catch (e, st) {
                      ErrorLogger.log(
                          'Failed to restore inactive volume after duck',
                          error: e,
                          stackTrace: st,
                          category: 'AudioHandler');
                    }
                  }
                  _preDuckVolume = null;
                  _preDuckInactiveVolume = null;
                  _preDuckSongId = null;
                  _preDuckRgTarget = null;
                } else if (shouldResumeAfterInterruption(
                  wasPlayingBeforeInterruption: wasPlayingBeforeDuck,
                  resumeAfterInterruption: _cachedPrefs
                          ?.getBool(PrefsKeys.resumeAfterInterruption) ??
                      true,
                  currentlyPlaying: _activePlayer.playing,
                )) {
                  // Pause-mode duck: playback was running when the navigation
                  // prompt began, so resume it now that the prompt ended. It was
                  // previously left paused permanently. Route through the public
                  // play() so the resume also runs AudioSession.setActive(true),
                  // the completed-replay guard, the DVC gain-curve clear and the
                  // fade-in convergence guard (a bare _activePlayer.play() skips
                  // all of them).
                  unawaited(play());
                }
                break;
              case AudioInterruptionType.pause:
                final wasPlayingBeforePause =
                    _interruption.end(InterruptionKind.pause);
                if (shouldResumeAfterInterruption(
                  wasPlayingBeforeInterruption: wasPlayingBeforePause,
                  // Cached prefs: this fires on every call-end; a disk read
                  // here delayed resume by ~10-20ms.
                  resumeAfterInterruption: _cachedPrefs
                          ?.getBool(PrefsKeys.resumeAfterInterruption) ??
                      true,
                  currentlyPlaying: _activePlayer.playing,
                )) {
                  // Route through the public play() (not a bare
                  // _activePlayer.play()) so the resume runs setActive(true),
                  // the completed-replay guard, the DVC clear and the fade-in
                  // guard.
                  unawaited(play());
                }
                // A call can arrive in the middle of a navigation-prompt duck.
                // The duck-end event may never come after that, so clear the duck
                // here AND put the volume back; before, the flags were reset but
                // the player stayed at the ducked level.
                final hadDuck = _duckActive;
                _clearDuckState();
                if (hadDuck) unawaited(_reapplyActiveVolume());
                break;
              case AudioInterruptionType.unknown:
                _interruption.reset();
                final hadUnknownDuck = _duckActive;
                _clearDuckState();
                if (hadUnknownDuck) unawaited(_reapplyActiveVolume());
                break;
            }
          }
        }),
      );

      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) async {
          // Debounce: wired + BT stacks can emit noisy twice for one unplug.
          final now = DateTime.now();
          if (_lastNoisyTime != null &&
              now.difference(_lastNoisyTime!) <
                  const Duration(milliseconds: 800)) {
            return;
          }
          _lastNoisyTime = now;
          unawaited(AudioSessionLog.instance
              .recordInterruption(AudioInterruptionKind.becomingNoisy));
          if (!_activePlayer.playing && !_crossfadeManager.isCrossfading) {
            return;
          }
          if (_crossfadeManager.isCrossfading) {
            await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
                restoreVolume: _preCrossfadeVolume ?? _volume);
          }
          // Pause first (pause() clears _pausedForNoisy, like a user pause),
          // THEN arm the auto-resume window so ONLY a becoming-noisy pause keeps
          // it armed for a quick reconnect.
          await pause();
          _noisyPauseTime = now;
          _pausedForNoisy = true;
        }),
      );

      _subscriptions.add(
        session.devicesStream.listen((devices) {
          _syncBluetoothRouteFromCache();
          _audioSessionIdRouter.handleRouteChanged();
          unawaited(_refreshBluetoothRoute());
          unawaited(_recordSessionRouteChange());
          unawaited(_maybeAutoResumeOnReconnect());
        }),
      );
    } catch (e, st) {
      ErrorLogger.log('Error configuring AudioSession',
          error: e, stackTrace: st, category: 'AudioHandler');
    }

    _subscriptions.add(
      AudioEffectsChannel().onRouteChanged.listen((_) {
        _audioSessionIdRouter.handleRouteChanged();
        unawaited(_recordSessionRouteChange());
      }),
    );

    // Initialize audio effects & equalizer preferences
    try {
      // Seed the BT mirror before effects init so the cold-start dither push
      // sees the real route when the output info is already cached.
      _syncBluetoothRouteFromCache();
      await _equalizerManager.init();
      unawaited(_refreshBluetoothRoute());
      unawaited(_equalizerManager.updateLoudnessVolume(_volume));
      await _restoreSkipSilence();
      // F2/F7/F9–F11: restore persisted feature state (best-effort).
      try {
        await Future.wait([
          trackDelayManager.load(),
          duckingController.load(),
          silenceSkipController.load(),
          dspSnapshotStore.load(),
          bookmarkStore.load(),
          perSongPlaybackStore.load(),
        ]);
        final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
        hedgedResolutionEnabled =
            prefs.getBool('hedged_resolution_enabled') ?? true;
        adaptiveQualityManager.enabled =
            prefs.getBool('adaptive_quality_enabled') ?? true;
        final savedQ = prefs.getString('adaptive_runtime_quality') ??
            prefs.getString('setting_streaming_quality');
        if (savedQ != null && savedQ.isNotEmpty) {
          adaptiveQualityManager.setQuality(savedQ);
        }
      } catch (_) {}
    } finally {
      // Signal effect-state listeners (e.g. PlayerCubit) even if restore
      // partially failed, so they re-sync whatever state is available.
      if (!_effectsReadyCompleter.isCompleted) {
        _effectsReadyCompleter.complete();
      }
    }

    // Register lifecycle observer to persist playback state and manage buffers on app background/resume
    _lifecycleObserver = AudioHandlerLifecycleObserver(
      onBackground: () {
        unawaited(saveCurrentPositionImmediate());
        _equalizerManager.onAppPaused();
        _memoryManager.onAppBackgrounded(inactivePlayer: _inactivePlayer);
      },
      onDetached: () {
        unawaited(saveCurrentPositionImmediate());
      },
      onHidden: () {
        unawaited(saveCurrentPositionImmediate());
      },
      onResume: () {
        if (_activePlayer.playing) {
          _smartPrefetch();
        }
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);

    // Restore last played song & queue session from database with 10s timeout guard
    try {
      await restoreLastPlaybackSession().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _playGeneration++;
          ErrorLogger.log('restoreLastPlaybackSession timed out after 10s',
              category: 'AudioHandler');
        },
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to restore playback session on startup',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  @override
  BufferBucket _currentBucket = BufferBucket.standard;

  static AudioLoadConfiguration _loadConfigForBucket(BufferBucket bucket) {
    return AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: bucket.minBufferDuration,
        maxBufferDuration: bucket.maxBufferDuration,
        bufferForPlaybackDuration: bucket.bufferForPlaybackDuration,
        bufferForPlaybackAfterRebufferDuration:
            bucket.bufferForPlaybackAfterRebufferDuration,
        prioritizeTimeOverSizeThresholds: false,
      ),
    );
  }

  @override
  AudioLoadConfiguration _currentAudioLoadConfiguration =
      _loadConfigForBucket(BufferBucket.standard);

  /// True for absolute HTTP(S) stream URLs (internet radio / Icecast /
  /// Shoutcast / HLS). These bypass the file/format-aware path entirely.
  static bool _isStreamUrl(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Returns a currently-valid stream URL for a YouTube row, reusing a memoized
  /// one until it nears expiry. Throws [YtmException] when nothing usable comes
  /// back, so the caller can tell "network down" from "skip this track".
  ///
  /// [quality] is reported back because it is part of every downstream cache key
  /// ([YtmUrlCache], the disk cache slot); the caller cannot assume `high`.
  @override
  Future<({String url, String? userAgent, String? cookies, String quality})>
      _resolveStreamUrl(SongsTableData song,
          {bool forceRefresh = false}) async {
    try {
      _latencyTracker?.markStage(PlaybackStage.resolutionRequested);
    } catch (_) {}
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) {
      throw const YtmException('YTM_UNAVAILABLE', 'Missing video id');
    }
    // Guard against placeholder local IDs (e.g. n_1f2cbFnkQ) that would waste
    // BotGuard + Innertube retries and then loop as VideoGone. Skip quietly.
    if (!_videoIdPattern.hasMatch(videoId) || videoId.startsWith('n_')) {
      throw const YtmException('YTM_UNAVAILABLE', 'Invalid video id');
    }

    // Hot path: reuse the cached prefs (loaded once in _init) instead of an
    // async disk read per resolve — saves ~5-20ms on every tap/prefetch.
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    final offlineOnly = prefs.getBool('setting_offline_only_mode') ?? false;
    if (offlineOnly) {
      throw const YtmException(
          'OFFLINE_ONLY', 'Offline Only Mode is enabled in Settings');
    }
    final wifiOnly = prefs.getBool('setting_wifi_only_mode') ?? false;
    if (wifiOnly) {
      final isWifi = await _ytmService.isWifiConnected();
      if (!isWifi) {
        throw const YtmException('WIFI_ONLY',
            'Wi-Fi Only Mode is enabled. Connect to Wi-Fi to stream');
      }
    }
    final quality = prefs.getString('setting_streaming_quality') ?? 'high';
    final cacheKey = '$videoId:${quality.toLowerCase()}';

    // Snapshot the resolve epoch. If a network-path or quality change bumps it
    // while this resolve is in flight, the result is bound to a now-stale egress
    // IP / rendition, so we must not write it back into the cache after the
    // caller already cleared it (that repopulated the cache with a URL that then
    // 403s on the new path).
    final resolveEpoch = _resolveEpoch;

    if (!forceRefresh) {
      final cached = _streamCache[cacheKey];
      if (cached != null && cached.expires.isAfter(DateTime.now())) {
        _streamCache.remove(cacheKey);
        _streamCache[cacheKey] = cached;
        _memoryManager.touch(cacheKey);
        try {
          _latencyTracker?.markStage(PlaybackStage.urlObtained);
        } catch (_) {}
        final songIndex = _songs.indexWhere((s) =>
            s.id == song.id ||
            (s.remoteId != null && s.remoteId == song.remoteId));
        if (songIndex != -1 && songIndex < _songs.length) {
          final target = _songs[songIndex];
          if (target.id == song.id ||
              (target.remoteId != null && target.remoteId == song.remoteId)) {
            if (target.bitrateKbps == null || target.bitrateKbps == 0) {
              final defaultKbps = quality == 'low'
                  ? 64
                  : quality == 'medium'
                      ? 128
                      : 160;
              final defaultCodec = quality == 'medium' ? 'AAC' : 'OPUS';
              final updated = target.copyWith(
                bitrateKbps: Value(defaultKbps),
                codec: Value(defaultCodec),
                sampleRate: Value(defaultCodec == 'OPUS' ? 48000 : 44100),
              );
              _songs[songIndex] = updated;
              if (songIndex == _currentIndex &&
                  !_onTrackChangedSubject.isClosed) {
                _onTrackChangedSubject.add(updated);
              }
            }
          }
        }
        return (
          url: cached.url,
          userAgent: cached.userAgent,
          cookies: cached.cookies,
          quality: quality
        );
      }
      final inFlight = _inFlightResolves[cacheKey];
      if (inFlight != null) {
        return await inFlight;
      }
    }

    Future<YtmStream> doResolve() => _ytmService.resolveStream(videoId,
        quality: quality, forceRefresh: forceRefresh);
    final future = () async {
      try {
        _latencyTracker?.markStage(PlaybackStage.pluginEntered);
        _latencyTracker?.markStage(PlaybackStage.clientRequestSent);
      } catch (_) {}
      // The native extractor already races its top two clients internally
      // (InnertubeClient's 350ms hedged race) and bounds each call, so a second,
      // independent Dart-level chain (coalesce:false) only doubled the native
      // load — two full multi-client chains contending for a 6-thread pool —
      // which made cold starts slower, not faster. One chain; the extractor
      // owns the hedging.
      final YtmStream stream = await doResolve();
      if (stream.url.trim().isEmpty) {
        throw const YtmException(
            'YTM_UNAVAILABLE', 'Resolved stream URL is empty');
      }

      final realBitrate = stream.bitrateKbps > 0
          ? stream.bitrateKbps
          : (quality == 'low'
              ? 64
              : quality == 'medium'
                  ? 128
                  : 160);
      final realCodec = stream.container.toUpperCase() == 'WEBM' ||
              stream.mimeType.contains('webm') ||
              stream.mimeType.contains('opus')
          ? 'OPUS'
          : (stream.container.toUpperCase() == 'M4A' ||
                  stream.mimeType.contains('mp4') ||
                  stream.mimeType.contains('aac')
              ? 'AAC'
              : 'OPUS');

      final songIndex = _songs.indexWhere((s) =>
          s.id == song.id ||
          (s.remoteId != null && s.remoteId == song.remoteId));
      if (songIndex != -1 && songIndex < _songs.length) {
        final target = _songs[songIndex];
        if (target.id == song.id ||
            (target.remoteId != null && target.remoteId == song.remoteId)) {
          final updated = target.copyWith(
            bitrateKbps: Value(realBitrate),
            codec: Value(realCodec),
            sampleRate: Value(realCodec == 'OPUS' ? 48000 : 44100),
          );
          _songs[songIndex] = updated;
          if (songIndex == _currentIndex && !_onTrackChangedSubject.isClosed) {
            _onTrackChangedSubject.add(updated);
          }
        }
      }
      // Prefer the resolver-provided expiry, then the URL stamp (which may be a
      // ?expire= query param or /expire/<s>/ path segment), then a safe default.
      final expireStamp =
          stream.expiresAt ?? YtmStream.expiryFromUrl(stream.url);
      final DateTime expireAt;
      if (expireStamp != null) {
        expireAt = DateTime.fromMillisecondsSinceEpoch(expireStamp);
      } else {
        expireAt = DateTime.now().add(const Duration(hours: 5));
      }
      final safeExpiry = expireAt.subtract(const Duration(minutes: 5));
      // Drop the write if a network-path/quality change invalidated caches
      // while we were resolving — otherwise we'd repopulate with a stale URL.
      if (_resolveEpoch == resolveEpoch && safeExpiry.isAfter(DateTime.now())) {
        _addToStreamCache(cacheKey, (
          url: stream.url,
          expires: safeExpiry,
          userAgent: stream.userAgent,
          cookies: stream.cookies
        ));
        AudioMemoryManager.trimStreamCache(_streamCache);
      }
      try {
        _latencyTracker?.markStage(PlaybackStage.urlObtained);
      } catch (_) {}
      return (
        url: stream.url,
        userAgent: stream.userAgent,
        cookies: stream.cookies,
        quality: quality
      );
    }();

    // Only non-force resolves participate in dedup, and removal is by identity.
    // A force-refresh must not overwrite (and then, on completion, evict) an
    // in-flight normal resolve's entry, which left later callers un-deduped and
    // firing a redundant native chain.
    if (!forceRefresh) {
      _inFlightResolves[cacheKey] = future;
    }
    try {
      return await future;
    } finally {
      if (identical(_inFlightResolves[cacheKey], future)) {
        _inFlightResolves.remove(cacheKey);
      }
    }
  }

  static const int _maxStreamCacheEntries = 64;

  @override
  int _prefetchGeneration = 0;

  /// Bumped whenever a network-path or streaming-quality change invalidates the
  /// URL caches, so a resolve already in flight won't write its now-stale result
  /// back after the caches were cleared. See [_resolveStreamUrl].
  @override
  int _resolveEpoch = 0;

  /// Track key shared with the per-song stores (id-based).
  static String trackKeyFor(SongsTableData song) => song.id.toString();

  /// Resume decision shared by every interruption-end path: resume only when
  /// playback was actually running when the interruption began, the user's
  /// preference allows it, and nothing else has already resumed playback.
  @visibleForTesting
  static bool shouldResumeAfterInterruption({
    required bool wasPlayingBeforeInterruption,
    required bool resumeAfterInterruption,
    required bool currentlyPlaying,
  }) =>
      wasPlayingBeforeInterruption &&
      resumeAfterInterruption &&
      !currentlyPlaying;

  // --- PLAYBACK ACTIONS ---

  // --- ANDROID AUTO & HEADSET BUTTON SUPPORT ---
  @override
  Timer? _headsetClickTimer;
  @override
  int _headsetClickCount = 0;

  /// Headset hook button with user-configurable mapping (see
  /// HeadsetControlConfig). 1x/2x/3x clicks resolve after [clickWindowMs];
  /// 3+ clicks collapse to the triple action so fast multi-presses never
  /// get swallowed.

  static const int maxQueueSize = 500;

  static const double _minPlaybackSpeed = 0.25;
  static const double _maxPlaybackSpeed = 4.0;
  static const double _minAdvancedPlaybackSpeed = 0.1;
  static const double _maxAdvancedPlaybackSpeed = 8.0;
  @override
  bool _advancedSpeedEnabled = false;

  @override
  double _pitch = 1.0;

  @override
  Future<List<R>> _boundedParallelMap<T, R>(
    List<T> items,
    Future<R> Function(T) mapper, {
    int concurrency = 6,
  }) async {
    if (items.isEmpty) return <R>[];
    final results = List<R?>.filled(items.length, null);
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= items.length) break;
        results[i] = await mapper(items[i]);
      }
    }

    final workerCount = math.min(concurrency, items.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results.cast<R>();
  }

  // --- ANDROID AUTO / MEDIA BROWSER TREE ---

  final Completer<void> _effectsReadyCompleter = Completer<void>();

  /// Completes when the handler's async init (effects/equalizer preference
  /// restore) has finished, so listeners can re-sync effect state that was
  /// read before the restore completed.
  Future<void> get effectsReady => _effectsReadyCompleter.future;

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'toggleFavorite':
        if (_songs.isNotEmpty &&
            _currentIndex >= 0 &&
            _currentIndex < _songs.length) {
          final currentSong = _songs[_currentIndex];
          final result = await _repository.toggleFavorite(currentSong.id);
          final newFav = result.fold((l) => currentSong.isFavorite, (r) => r);
          // Centralized so mediaItem, queue and notification controls all update.
          updateFavorite(currentSong.id, newFav);
          return newFav;
        }
        return false;
      case 'toggleShuffle':
        final currentShuffle = _activePlayer.shuffleModeEnabled;
        await setShuffleMode(currentShuffle
            ? AudioServiceShuffleMode.none
            : AudioServiceShuffleMode.all);
        return !currentShuffle;
      case 'cycleRepeat':
      case 'toggleRepeat':
        final currentLoop = _activePlayer.loopMode;
        if (currentLoop == LoopMode.off) {
          await setRepeatMode(AudioServiceRepeatMode.all);
        } else if (currentLoop == LoopMode.all) {
          await setRepeatMode(AudioServiceRepeatMode.one);
        } else {
          await setRepeatMode(AudioServiceRepeatMode.none);
        }
        return true;
      case 'seekRelative':
        final secs = (extras?['seconds'] as num?)?.toInt() ?? 10;
        await seekRelative(Duration(seconds: secs.clamp(-60, 60)));
        return true;
      case 'headsetAction':
        final count = (extras?['count'] as num?)?.toInt() ?? 1;
        await _performHeadsetAction(count.clamp(1, 3));
        return true;
      case 'setSpeed':
        final speed = (extras?['speed'] as num?)?.toDouble() ?? 1.0;
        await setSpeed(speed);
        return true;
      case 'action_bass_boost':
      case 'toggleBassBoost':
      case 'bassBoost':
        final current = _equalizerManager.currentPreset.bassBoost;
        final enable = extras?['enable'] as bool? ?? (current <= 0.05);
        // When disabling, always force 0: a stray `strength` in extras used to
        // leave bass boost active while this action reported `false`.
        final strength =
            enable ? ((extras?['strength'] as num?)?.toDouble() ?? 0.6) : 0.0;
        await _equalizerManager.setBassBoost(strength);
        return enable;
      case 'action_virtualizer':
      case 'toggleVirtualizer':
      case 'virtualizer':
        final enable = extras?['enable'] as bool? ??
            !_equalizerManager.isVirtualizerEnabled;
        final strength = (extras?['strength'] as num?)?.toDouble() ?? 0.5;
        await _equalizerManager.setVirtualizerEnabled(enable);
        if (enable) await _equalizerManager.setVirtualizerStrength(strength);
        return enable;
      case 'action_sleep_timer':
      case 'toggleSleepTimer':
      case 'sleepTimer':
        if (_sleepTimerManager.isActive) {
          _sleepTimerManager.cancelSleepTimer();
          return false;
        } else {
          // 0 / negative would fire immediately and pause playback at once.
          final minutes =
              ((extras?['minutes'] as num?)?.toInt() ?? 30).clamp(1, 24 * 60);
          _sleepTimerManager.startDurationTimer(Duration(minutes: minutes));
          return true;
        }
      case 'cycleSpeed':
        final currentSpeed = _activePlayer.speed;
        final nextSpeed =
            currentSpeed < 1.15 ? 1.25 : (currentSpeed < 1.4 ? 1.5 : 1.0);
        await setSpeed(nextSpeed);
        return nextSpeed;
      case 'switchEqPreset':
        final presets = EqPreset.defaultPresets;
        if (presets.isEmpty) return null;
        final current = _equalizerManager.currentPreset;
        final idx = presets.indexWhere((p) => p.name == current.name);
        final next = presets[(idx + 1) % presets.length];
        await _equalizerManager.applyPreset(next);
        return next.name;
      case 'cycleSleepTimer':
        if (!_sleepTimerManager.isActive) {
          _sleepTimerManager.startDurationTimer(const Duration(minutes: 15));
          return 15;
        } else {
          final curRemaining = _sleepTimerManager.remainingDuration.inSeconds;
          if (curRemaining <= 15 * 60) {
            _sleepTimerManager.startDurationTimer(const Duration(minutes: 30));
            return 30;
          } else if (curRemaining <= 30 * 60) {
            _sleepTimerManager.startDurationTimer(const Duration(minutes: 45));
            return 45;
          } else {
            _sleepTimerManager.cancelSleepTimer();
            return 0;
          }
        }
      default:
        return super.customAction(name, extras);
    }
  }

  @override
  Future<void> stop() async {
    _pendingPlaybackStart = false;
    // Invalidate any slow in-flight resolve so it cannot start playback after
    // the user stopped (pause() already does this; stop() did not).
    _playGeneration++;
    _headsetClickTimer?.cancel();
    _headsetClickTimer = null;
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    _crossfadeSwitchDebounce?.cancel();
    _crossfadeSwitchDebounce = null;
    _sleepTimerManager.cancelSleepTimer();
    unawaited(AudioSessionLog.instance.endSession());
    try {
      await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
          restoreVolume: _volume);
    } catch (e, st) {
      ErrorLogger.log('Failed to cancel crossfade during stop',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    // Reset transient volume/interruption state so the next session does not
    // start ducked, mid-fade or with a stale "resume after call" decision.
    _clearDuckState();
    _sleepFadeFactor = 1.0;
    _interruption.reset();
    _pausedForNoisy = false;
    // Persist the REAL position before the players are stopped. Previously this
    // only set a dirty flag; the 2s timer then ran after stop() had reset the
    // player to 0 and overwrote the saved resume position with 0:00.
    try {
      await saveCurrentPositionImmediate();
    } catch (_) {}
    unawaited(PositionCrashGuard.recordCleanShutdown());
    _gaplessLoaded = false;
    _gaplessTargetIndex = null;
    mediaItem.add(null);
    queue.add([]);
    // Each platform call is isolated: one throwing must not skip the rest and
    // leave the notification / foreground service stuck in a playing state.
    for (final player in [_playerA, _playerB]) {
      try {
        await player.stop();
      } catch (e, st) {
        ErrorLogger.log('Failed to stop player',
            error: e, stackTrace: st, category: 'AudioHandler');
      }
    }
    // The stopped players report position 0; make sure the timer cannot write
    // that over the position saved above.
    _positionDirty = false;
    try {
      await AudioEffectsChannel().releaseEffects();
    } catch (e, st) {
      ErrorLogger.log('Failed to release effects during stop',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [],
        systemActions: const {},
        androidCompactActionIndices: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
      ),
    );
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Route through the public pause path so it performs the same cleanup as a
    // user pause: reset the interruption bookkeeping, cancel any crossfade and
    // bump the play generation so a slow in-flight resolve cannot start
    // playback after the task is gone (B-3).
    try {
      await pause();
    } catch (_) {}
    // Save AFTER pausing: saving first let the track keep playing during the
    // DB/file writes, so the stored position was already stale on resume.
    try {
      await saveCurrentPositionImmediate();
    } catch (_) {}
    await super.onTaskRemoved();
  }

  @disposeMethod
  Future<void> dispose() async {
    // Idempotency check first: a second call used to re-run the observer and
    // timer teardown before bailing out.
    if (_disposed) return;
    _disposed = true;
    _headsetClickTimer?.cancel();
    _headsetClickTimer = null;
    final lifecycleObserver = _lifecycleObserver;
    if (lifecycleObserver != null) {
      try {
        WidgetsBinding.instance.removeObserver(lifecycleObserver);
      } catch (_) {}
      _lifecycleObserver = null;
    }
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    _fadeInGuardTimer?.cancel(); // FIX-#12
    _fadeInGuardTimer = null;
    _crossfadeSwitchDebounce?.cancel();
    _crossfadeSwitchDebounce = null;
    _duckSafetyTimer?.cancel();
    _duckSafetyTimer = null;
    _systemSoundTimer?.cancel();
    _systemSoundTimer = null;
    for (final sub in List.of(_subscriptions)) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    _subscriptions.clear();
    // Dispose sleep timer before closing its subject to avoid add-after-close race
    try {
      _sleepTimerManager.dispose();
    } catch (_) {}
    try {
      _gaplessMonitor.dispose();
    } catch (_) {}
    try {
      abLoopManager.dispose();
    } catch (_) {}
    try {
      multiOutputRouter.dispose();
    } catch (_) {}
    try {
      await silenceSkipController.persist();
    } catch (_) {}
    // Guarded: dispose() can run before the async _init() assigned this late
    // field (hot restart / test teardown / early init failure).
    try {
      _streamPreResolver.dispose();
    } catch (_) {}
    try {
      _preloadScheduler.clear();
    } catch (_) {}
    try {
      _adaptiveBufferEngine.dispose();
    } catch (_) {}
    try {
      _memoryManager.clearAll();
    } catch (_) {}
    try {
      adaptiveQualityManager.dispose();
    } catch (_) {}
    try {
      _volumeController?.dispose();
    } catch (_) {}
    if (!_positionSubject.isClosed) _positionSubject.close();
    if (!_highRatePositionSubject.isClosed) _highRatePositionSubject.close();
    if (!_audioSessionIdSubject.isClosed) _audioSessionIdSubject.close();
    if (!_errorSubject.isClosed) _errorSubject.close();
    if (!_onTrackChangedSubject.isClosed) _onTrackChangedSubject.close();
    try {
      _equalizerManager.dispose();
    } catch (_) {}
    try {
      _crossfadeManager.dispose();
    } catch (_) {}
    // Don't leave disposed objects registered in DI: a later consumer (or a
    // rebuilt handler) would otherwise resolve a dead EqualizerManager.
    try {
      if (getIt.isRegistered<EqualizerManager>() &&
          identical(getIt<EqualizerManager>(), _equalizerManager)) {
        getIt.unregister<EqualizerManager>();
      }
      if (getIt.isRegistered<AdaptiveBufferEngine>() &&
          identical(getIt<AdaptiveBufferEngine>(), _adaptiveBufferEngine)) {
        getIt.unregister<AdaptiveBufferEngine>();
      }
    } catch (_) {}
    try {
      await AudioEffectsChannel().releaseEffects();
    } catch (e, st) {
      ErrorLogger.log('Failed to release native audio effects',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
    try {
      await _playerA.dispose();
    } catch (_) {}
    try {
      await _playerB.dispose();
    } catch (_) {}
    try {
      await _prefetchPlayer.dispose();
    } catch (_) {}
    try {
      platformBridgeDegraded.dispose();
    } catch (_) {}
  }

  /// Transient system sound interruption: duck and auto-restore in 500ms.
  Future<void> handleSystemUiSoundInterruption() async {
    if (!_duckActive && _activePlayer.playing) {
      _duckActive = true;
      _interruption.begin(InterruptionKind.systemUiSound, playing: true);
      final f = duckingController.duckFactor;
      final curVol = _activePlayer.volume;
      await _activePlayer.setVolume(f * curVol);
      _systemSoundTimer?.cancel();
      _systemSoundTimer = Timer(const Duration(milliseconds: 500), () async {
        if (_duckActive &&
            _interruption.activeKind == InterruptionKind.systemUiSound) {
          _duckActive = false;
          _interruption.end(InterruptionKind.systemUiSound);
          // Compose with any in-flight sleep fade so this transient duck's
          // restore doesn't wipe the fade for a tick.
          final target = _calculateReplayGainVolume(currentSong);
          try {
            await _activePlayer
                .setVolume((target * _sleepFadeFactor).clamp(0.0, 1.0));
          } catch (_) {}
        }
      });
    }
  }

  /// Media button long-press: pause playback without clearing queue or position.
  Future<void> handleMediaButtonLongPress() async {
    _interruption.begin(InterruptionKind.mediaButtonLongPress,
        playing: _activePlayer.playing);
    if (_crossfadeManager.isCrossfading) {
      await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
          restoreVolume: _preCrossfadeVolume ?? _volume);
    }
    await _activePlayer.pause();
  }

  /// Queries the actual platform audio focus state via platform channel.
  Future<bool> getPlatformFocusState() async {
    try {
      final res = await MethodChannel(PulsrChannels.audioEffects)
          .invokeMethod<bool>('getFocusState');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }
}
```

---

## `lib/data/audio/audio_handler_dsp_bridge.dart`

```dart
part of 'audio_handler.dart';

mixin PulsrAudioDspBridge on BaseAudioHandler {
  bool get isEqualizerEnabled => _equalizerManager.isEnabled;

  EqPreset get currentPreset => _equalizerManager.currentPreset;

  bool get isVirtualizerEnabled => _equalizerManager.isVirtualizerEnabled;

  double get virtualizerStrength => _equalizerManager.virtualizerStrength;

  bool get isDynamicsEnabled => _equalizerManager.isDynamicsEnabled;

  bool get isDynamicsEffectivelyEnabled =>
      _equalizerManager.isDynamicsEffectivelyEnabled;

  bool get isDynamicsBypassed => _equalizerManager.isDynamicsBypassed;

  DynamicsPreset get dynamicsPreset => _equalizerManager.dynamicsPreset;

  HeadphoneProfile? get selectedHeadphoneProfile =>
      _equalizerManager.selectedHeadphoneProfile;

  Duration get crossfadeDuration => _crossfadeManager.duration;

  void setCrossfadeDuration(Duration duration) {
    final wasGapless = _gaplessMode;
    _crossfadeManager.duration = duration;
    final isGapless = _gaplessMode;
    if (wasGapless != isGapless) {
      _scheduleEngineSwitch(toGapless: isGapless);
    }
  }

  /// Applies the persisted gapless toggle. Switching it (queue non-empty)
  /// re-selects the gapless playlist engine or the per-track player.
  void setGaplessEnabled(bool enabled) {
    if (_gaplessEnabled == enabled) return;
    final wasGapless = _gaplessMode;
    _gaplessEnabled = enabled;
    final isGapless = _gaplessMode;
    if (wasGapless != isGapless) {
      _scheduleEngineSwitch(toGapless: isGapless);
    }
  }

  void _scheduleEngineSwitch({required bool toGapless}) {
    if (_songs.isEmpty || _currentIndex < 0 || _currentIndex >= _songs.length) {
      return;
    }
    // Debounce slider drags: rapid toggles previously spawned concurrent
    // _switchPlaybackEngine calls that interleaved.
    _crossfadeSwitchDebounce?.cancel();
    _crossfadeSwitchDebounce = Timer(const Duration(milliseconds: 300), () {
      // Re-evaluate at fire time: the setting may have flipped again during
      // the debounce window, and the captured value would be stale.
      unawaited(_switchPlaybackEngine(toGapless: _gaplessMode));
    });
  }

  Future<void> _switchPlaybackEngine({required bool toGapless}) async {
    final generation = ++_engineSwitchGeneration;
    final resumePos = _activePlayer.position;
    // During source preparation, the native player may still be stopped even
    // though loadQueue has accepted an autoplay request. Preserve that intent
    // when startup settings switch the engine before the first decoded frame.
    final wasPlaying = _activePlayer.playing ||
        _pendingPlaybackStart ||
        playbackState.value.playing;
    try {
      if (toGapless) {
        await _loadGaplessQueue(
            initialPosition: resumePos, preload: wasPlaying);
        return;
      }
      if (_currentIndex < 0 || _currentIndex >= _songs.length) return;
      if (wasPlaying) {
        _gaplessLoaded = false;
        await playSongAt(_currentIndex, initialPosition: resumePos);
        return;
      }
      final song = _songs[_currentIndex];
      final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
      // The old stale-check ran before any await (always true) and AFTER
      // _gaplessLoaded was cleared, so a superseded switch could still flip
      // state under a newer one. Check after the await, before mutating.
      if (generation != _engineSwitchGeneration) return;
      _gaplessLoaded = false;
      final item = PulsrAudioHandler._songToMediaItem(song, artUri);
      mediaItem.add(item);
      if (song.source != SongSource.youtube) {
        await _activePlayer.setAudioSource(
          _createAudioSource(song, item),
          initialPosition: resumePos,
          preload: false,
        );
      } else {
        _pendingLazyPosition = resumePos;
      }
      if (generation != _engineSwitchGeneration) return;
      _broadcastState(_activePlayer.playbackEvent);
    } catch (e, st) {
      _pendingLazyPosition = null;
      ErrorLogger.log('Error switching playback engine on crossfade toggle',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) =>
      _equalizerManager.setEqualizerEnabled(enabled);

  Future<void> setBandGain(int bandIndex, double gain) =>
      _equalizerManager.setBandGain(bandIndex, gain);

  Future<void> resetToFlat() => _equalizerManager.resetToFlat();

  Future<void> startAbComparison() => _equalizerManager.startAbComparison();

  Future<void> endAbComparison() => _equalizerManager.endAbComparison();

  bool get isAbComparisonActive => _equalizerManager.isAbComparisonActive;

  Future<void> setBassBoost(double value) =>
      _equalizerManager.setBassBoost(value);

  Future<void> setPreamp(double preampDb) =>
      _equalizerManager.setPreamp(preampDb);

  Future<void> applyPreset(EqPreset preset) =>
      _equalizerManager.applyPreset(preset);

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) =>
      _equalizerManager.applyHeadphoneProfile(profile);

  Future<void> setVirtualizerEnabled(bool enabled) =>
      _equalizerManager.setVirtualizerEnabled(enabled);

  Future<void> setVirtualizerStrength(double strength) =>
      _equalizerManager.setVirtualizerStrength(strength);

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) =>
      _equalizerManager.setDynamicsPreset(preset, enabled: enabled);

  Future<void> toggleDynamicsBypass() =>
      _equalizerManager.toggleDynamicsBypass();

  bool get isSpatializerEnabled => _equalizerManager.isSpatializerEnabled;

  bool get isSpatializerSupported => _equalizerManager.isSpatializerSupported;

  bool get isVirtualizerSupported => _equalizerManager.isVirtualizerSupported;

  bool get isDynamicsSupported => _equalizerManager.isDynamicsSupported;

  bool get isBassBoostSupported => _equalizerManager.isBassBoostSupported;

  bool get isVolumeBoostSupported => _equalizerManager.isVolumeBoostSupported;

  bool get isHeadTrackerAvailable => _equalizerManager.isHeadTrackerAvailable;

  Future<void> setSpatializerEnabled(bool enabled) =>
      _equalizerManager.setSpatializerEnabled(enabled);

  double get volumeBoost => _equalizerManager.volumeBoost;

  /// Engine-canonical EQ preamp (dB). Exposed at the handler boundary so the
  /// cubit's effect reconciliation reads it like every other DSP param.
  double get preampDb => _equalizerManager.preampDb;

  Future<void> setVolumeBoost(double value) =>
      _equalizerManager.setVolumeBoost(value);

  Future<void> setCustomFrequencies(List<double> frequencies) =>
      _equalizerManager.setCustomFrequencies(frequencies);

  bool get is32BandMode => _equalizerManager.is32BandMode;

  Future<void> set32BandMode(bool enabled) =>
      _equalizerManager.set32BandMode(enabled);

  Future<void> switchComparisonSlot(ComparisonSlot slot) =>
      _equalizerManager.switchComparisonSlot(slot);

  String exportPresetToJson([EqPreset? preset]) =>
      _equalizerManager.exportPresetToJson(preset);

  Future<bool> importPresetFromJson(String jsonString) =>
      _equalizerManager.importPresetFromJson(jsonString);

  // Native DSP features
  bool get isCrossfeedEnabled => _equalizerManager.isCrossfeedEnabled;

  double get crossfeedDelayUs => _equalizerManager.crossfeedDelayUs;

  double get crossfeedFeedDb => _equalizerManager.crossfeedFeedDb;

  int get crossfeedMode => _equalizerManager.crossfeedMode;

  Future<void> setCrossfeed(bool enabled,
          {double? delayUs, double? feedDb, int? mode}) =>
      _equalizerManager.setCrossfeed(enabled,
          delayUs: delayUs, feedDb: feedDb, mode: mode);

  Future<void> setCrossfeedMode(int mode) =>
      _equalizerManager.setCrossfeedMode(mode);

  bool get isLimiterEnabled => _equalizerManager.isLimiterEnabled;

  double get limiterThresholdDb => _equalizerManager.limiterThresholdDb;

  double get limiterReleaseMs => _equalizerManager.limiterReleaseMs;

  Future<void> setLookaheadLimiter(bool enabled,
          {double? thresholdDb, double? releaseMs, double? lookaheadMs}) =>
      _equalizerManager.setLookaheadLimiter(enabled,
          thresholdDb: thresholdDb,
          releaseMs: releaseMs,
          lookaheadMs: lookaheadMs);

  bool get isReverbEnabled => _equalizerManager.isReverbEnabled;

  int get reverbPreset => _equalizerManager.reverbPreset;

  double get reverbWetDry => _equalizerManager.reverbWetDry;

  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) =>
      _equalizerManager.setReverb(enabled, preset: preset, wetDry: wetDry);

  Future<void> setBypassCompare({
    required bool bypass,
    double gainCompensationDb = 0.0,
  }) =>
      _equalizerManager.setBypassCompare(
        bypass: bypass,
        gainCompensationDb: gainCompensationDb,
      );

  Future<bool> loadCustomImpulseResponse(List<double> irSamples) =>
      _equalizerManager.loadCustomImpulseResponse(irSamples);

  double get stereoBalance => _equalizerManager.stereoBalance;

  bool get monoMix => _equalizerManager.monoMix;

  Future<void> setStereoBalance(double balance) =>
      _equalizerManager.setStereoBalance(balance);

  Future<void> setMonoMix(bool mono) => _equalizerManager.setMonoMix(mono);

  bool get isSincResamplerEnabled => _equalizerManager.isSincResamplerEnabled;

  Future<void> setSincResampler(bool enabled) =>
      _equalizerManager.setSincResampler(enabled);

  bool get isDitherEnabled => _equalizerManager.isDitherEnabled;

  int get ditherTargetBitDepth => _equalizerManager.ditherTargetBitDepth;

  Future<void> setDither(bool enabled, {int? targetBitDepth}) =>
      _equalizerManager.setDither(enabled, targetBitDepth: targetBitDepth);

  Future<int> getPipelineLatencyFrames() =>
      _equalizerManager.getPipelineLatencyFrames();

  Future<void> setBandSolo(int index, bool solo) =>
      _equalizerManager.setBandSolo(index, solo);

  Future<void> setBandMute(int index, bool mute) =>
      _equalizerManager.setBandMute(index, mute);

  bool get hasOemAudio => _equalizerManager.hasOemAudio;

  List<String> get detectedOemEngines => _equalizerManager.detectedOemEngines;

  bool get isSaturationEnabled => _equalizerManager.isSaturationEnabled;

  double get saturationDrive => _equalizerManager.saturationDrive;

  double get saturationMix => _equalizerManager.saturationMix;

  double get saturationTilt => _equalizerManager.saturationTilt;

  bool get saturationMultiband => _equalizerManager.saturationMultiband;

  Future<void> setSaturation(
    bool enabled, {
    double? drive,
    double? mix,
    double? tilt,
    int? mode,
    bool? multiband,
  }) =>
      _equalizerManager.setSaturation(
        enabled,
        drive: drive,
        mix: mix,
        tilt: tilt,
        mode: mode,
        multiband: multiband,
      );

  Future<void> setSaturationMultiband(bool multiband) =>
      _equalizerManager.setSaturationMultiband(multiband);

  bool get isStereoWidthEnabled => _equalizerManager.isStereoWidthEnabled;

  double get stereoWidth => _equalizerManager.stereoWidth;

  Future<void> setStereoWidth(
    bool enabled, {
    double? width,
    bool? multiband,
    double? lowWidth,
    double? midWidth,
    double? highWidth,
    double? lowCrossoverHz,
    double? highCrossoverHz,
  }) =>
      _equalizerManager.setStereoWidth(
        enabled,
        width: width,
        multiband: multiband,
        lowWidth: lowWidth,
        midWidth: midWidth,
        highWidth: highWidth,
        lowCrossoverHz: lowCrossoverHz,
        highCrossoverHz: highCrossoverHz,
      );

  bool get isLoudnessContourEnabled =>
      _equalizerManager.isLoudnessContourEnabled;

  double get loudnessContourIntensity =>
      _equalizerManager.loudnessContourIntensity;

  Future<void> setLoudnessContour(bool enabled, {double? intensity}) =>
      _equalizerManager.setLoudnessContour(enabled, intensity: intensity);

  bool get isSubCrossoverEnabled => _equalizerManager.isSubCrossoverEnabled;

  double get subCrossoverCornerHz => _equalizerManager.subCrossoverCornerHz;

  double get subCrossoverSlopeDbPerOct =>
      _equalizerManager.subCrossoverSlopeDbPerOct;

  double get subCrossoverGain => _equalizerManager.subCrossoverGain;

  Future<void> setSubCrossover(
    bool enabled, {
    double? cornerHz,
    double? slopeDbPerOct,
    double? gain,
    bool? bassMono,
    bool? antiPop,
  }) =>
      _equalizerManager.setSubCrossover(
        enabled,
        cornerHz: cornerHz,
        slopeDbPerOct: slopeDbPerOct,
        gain: gain,
        bassMono: bassMono,
        antiPop: antiPop,
      );

  bool get isDynamicEqEnabled => _equalizerManager.isDynamicEqEnabled;

  List<DynamicEqBandConfig> get dynamicEqBands =>
      _equalizerManager.dynamicEqBands;

  Future<void> setDynamicEq(bool enabled) =>
      _equalizerManager.setDynamicEq(enabled);

  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) =>
      _equalizerManager.setDynamicEqBand(index, band);

  Future<void> addDynamicEqBand() => _equalizerManager.addDynamicEqBand();

  Future<void> removeDynamicEqBand(int index) =>
      _equalizerManager.removeDynamicEqBand(index);

  bool get isViperDdcEnabled => _equalizerManager.isViperDdcEnabled;

  String get viperDdcProfileName => _equalizerManager.viperDdcProfileName;

  Future<void> setViperDdc(bool enabled,
          {String? profileName, List<double>? coeffs, String? ddcContent}) =>
      _equalizerManager.setViperDdc(enabled,
          profileName: profileName, coeffs: coeffs, ddcContent: ddcContent);

  bool get isArbitraryEqEnabled => _equalizerManager.isArbitraryEqEnabled;

  String get arbitraryEqString => _equalizerManager.arbitraryEqString;

  bool get arbitraryEqLinearPhase => _equalizerManager.arbitraryEqLinearPhase;

  Future<void> setArbitraryEq(bool enabled,
          {String? eqString, bool? linearPhase}) =>
      _equalizerManager.setArbitraryEq(enabled,
          eqString: eqString, linearPhase: linearPhase);

  bool get isLiveProgEnabled => _equalizerManager.isLiveProgEnabled;

  String get liveProgCode => _equalizerManager.liveProgCode;

  Future<void> setLiveProg(bool enabled, {String? code}) =>
      _equalizerManager.setLiveProg(enabled, code: code);

  Future<void> setLiveProgSlider(int sliderIndex, double value) =>
      _equalizerManager.setLiveProgSlider(sliderIndex, value);

  bool get isDynamicBassEnabled => _equalizerManager.isDynamicBassEnabled;

  double get dynamicBassStrength => _equalizerManager.dynamicBassStrength;

  int get dynamicBassPreset => _equalizerManager.dynamicBassPreset;

  Future<void> setDynamicBass({
    required bool enabled,
    double? strength,
    int? preset,
    int? xLow,
    int? xHigh,
    int? yLow,
    int? yHigh,
    double? sideGainLow,
    double? sideGainHigh,
  }) =>
      _equalizerManager.setDynamicBass(
        enabled: enabled,
        strength: strength,
        preset: preset,
        xLow: xLow,
        xHigh: xHigh,
        yLow: yLow,
        yHigh: yHigh,
        sideGainLow: sideGainLow,
        sideGainHigh: sideGainHigh,
      );
  // Abstract contract supplied by the composing PulsrAudioHandler (same
  // library). Declaring these here keeps the mixin stateless and lets the
  // analyser type-check each mixin against the host's private members.
  AudioPlayer get _activePlayer;

  void _broadcastState(PlaybackEvent event);

  UriAudioSource _createAudioSource(SongsTableData song, MediaItem tag);

  CrossfadeManager get _crossfadeManager;

  Timer? get _crossfadeSwitchDebounce;
  set _crossfadeSwitchDebounce(Timer? value);

  int get _currentIndex;

  int get _engineSwitchGeneration;
  bool get _pendingPlaybackStart;
  set _engineSwitchGeneration(int value);

  EqualizerManager get _equalizerManager;

  bool get _gaplessEnabled;
  set _gaplessEnabled(bool value);

  bool get _gaplessMode;

  Future<void> _loadGaplessQueue(
      {Duration? initialPosition, bool preload = true});

  List<SongsTableData> get _songs;

  set _gaplessLoaded(bool value);

  set _pendingLazyPosition(Duration? value);

  Future<void> playSongAt(int index, {Duration? initialPosition});
}
```

---

## `lib/data/audio/audio_session_id_router.dart`

```dart
// lib/data/audio/audio_session_id_router.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/utils/error_logger.dart';

/// Single source of truth for routing Android audio session ids from the
/// active just_audio player into the DSP/equalizer stack.
///
/// Contract:
///  * Validates ids — null/0/negative mean "no session yet" and are ignored
///    (attaching effects to session 0 would bind them to the global output
///    mix instead of the player's stream).
///  * Suppresses duplicate same-id re-emissions (e.g. BehaviorSubject replay
///    after re-subscribe) so a repeated event never triggers a native
///    release/recreate cycle.
///  * Serializes out-of-order updates: if several ids arrive before the
///    drain runs, only the most recently requested id is applied;
///    intermediate ids are collapsed (latest wins).
class AudioSessionIdRouter {
  /// Invoked at most once per distinct session id, in application order.
  final void Function(int sessionId) onSessionChanged;

  /// Invoked when the audio route changed (e.g. Bluetooth <-> speaker).
  /// The Android session id usually stays the same across route switches,
  /// but the HAL effect chain is re-initialized by the platform, so consumers
  /// re-push their full effect state through this callback.
  final void Function()? onRouteChanged;

  int? _currentSessionId;
  Future<void> _chain = Future<void>.value();
  final List<int> _pendingSessionIds = <int>[];
  bool _routeResyncPending = false;
  bool _isDraining = false;
  bool _drainQueued = false;

  AudioSessionIdRouter({required this.onSessionChanged, this.onRouteChanged});

  /// The last session id accepted by this router (never 0).
  int? get currentSessionId => _currentSessionId;

  /// Feed every emission of the player's `androidAudioSessionIdStream` here,
  /// including the first non-zero id emitted right after player init.
  void handleSessionId(int? sessionId) {
    if (sessionId == null || sessionId <= 0) {
      ErrorLogger.log(
        'Ignoring invalid audio session ID: $sessionId (null or <= 0)',
        category: 'AudioSessionIdRouter',
      );
      return;
    }

    // Duplicate of whatever will be the effective id once the queue drains.
    final effective = _pendingSessionIds.isEmpty
        ? _currentSessionId
        : _pendingSessionIds.last;
    if (sessionId == effective) return;

    ErrorLogger.log(
      'AudioSessionIdRouter received sessionId: $sessionId (current: $_currentSessionId)',
      category: 'AudioSessionIdRouter',
    );

    // Latest wins: a newer id supersedes any not-yet-applied one. (Previously
    // the oldest pending id was kept as well, so an "intermediate" id was
    // still applied, contradicting the documented contract.)
    _pendingSessionIds
      ..clear()
      ..add(sessionId);

    if (!_drainQueued) {
      _drainQueued = true;
      _chain = _chain.then((_) => _drainQueue()).catchError((
        Object e,
        StackTrace st,
      ) {
        _drainQueued = false;
        ErrorLogger.log(
          'AudioSessionIdRouter chain error',
          error: e,
          stackTrace: st,
          category: 'AudioSessionIdRouter',
        );
      });
    }
  }

  void handleRouteChanged() {
    if (_routeResyncPending) return;
    _routeResyncPending = true;
    _chain = _chain.then((_) {
      _routeResyncPending = false;
      final callback = onRouteChanged;
      if (callback != null) callback();
    }).catchError((Object e, StackTrace st) {
      _routeResyncPending = false;
      ErrorLogger.log(
        'AudioSessionIdRouter route resync error',
        error: e,
        stackTrace: st,
        category: 'AudioSessionIdRouter',
      );
    });
  }

  Future<void> _drainQueue() async {
    if (_isDraining) return;
    _isDraining = true;
    try {
      while (_pendingSessionIds.isNotEmpty) {
        final next = _pendingSessionIds.removeAt(0);
        if (next == _currentSessionId) continue;
        _currentSessionId = next;
        try {
          onSessionChanged(next);
        } catch (e, st) {
          ErrorLogger.log(
            'AudioSessionIdRouter callback error',
            error: e,
            stackTrace: st,
            category: 'AudioSessionIdRouter',
          );
        }
        await Future.microtask(() {});
      }
    } finally {
      _isDraining = false;
      _drainQueued = false;
    }
  }

  /// Test-only: completes when every queued operation has been applied.
  @visibleForTesting
  Future<void> get idleForTest => _chain;

  /// Test-only: resets dedupe state (hot restart / test teardown).
  @visibleForTesting
  void resetForTest() {
    _currentSessionId = null;
    _pendingSessionIds.clear();
    _routeResyncPending = false;
    _isDraining = false;
    _drainQueued = false;
  }
}
```

---

## `lib/data/audio/multi_output_router.dart`

```dart
// F8: Multi-output routing (A2DP + speaker simultaneously).
import 'dart:async';
import 'package:flutter/services.dart';

enum MultiOutputMode {
  systemDefault,
  speakerAndBluetooth,
  speakerOnly,
  bluetoothOnly
}

/// Best-effort simultaneous routing. Android has no public API for true
/// concurrent A2DP + speaker; we attempt the vendor route via the audio
/// effects channel and always degrade gracefully to system default.
class MultiOutputRouter {
  static const MethodChannel _channel =
      MethodChannel('com.pulsr.music/audio_effects');

  MultiOutputMode mode = MultiOutputMode.systemDefault;
  bool lastRouteSupported = true;
  String? lastError;

  final StreamController<MultiOutputMode> _changeSubject =
      StreamController<MultiOutputMode>.broadcast();
  Stream<MultiOutputMode> get changes => _changeSubject.stream;

  Future<bool> setMode(MultiOutputMode next) async {
    mode = next;
    if (!_changeSubject.isClosed) _changeSubject.add(next);
    if (next == MultiOutputMode.systemDefault) {
      lastRouteSupported = true;
      lastError = null;
      return true;
    }
    try {
      final result =
          await _channel.invokeMethod<String>('setMultiOutputRoute', {
        'mode': next.name,
      }).timeout(const Duration(seconds: 3));
      lastRouteSupported = result != 'unsupported';
      lastError = lastRouteSupported ? null : 'unsupported';
      return lastRouteSupported;
    } on MissingPluginException catch (e) {
      lastRouteSupported = false;
      lastError = e.toString();
      return false;
    } catch (e) {
      // Timeout / platform errors: keep playback alive on system default.
      lastRouteSupported = false;
      lastError = e.toString();
      return false;
    }
  }

  bool get isSimultaneous => mode == MultiOutputMode.speakerAndBluetooth;

  void dispose() => _changeSubject.close();
}
```

---

## `lib/data/audio/collaborators/float_output_controller.dart`

```dart
import 'package:just_audio/just_audio.dart';

/// Pushes the opt-in 24/32-bit float DSP-path preference to every playback
/// player.
///
/// Default OFF: callers pass `false`, which keeps today's 16-bit sink path
/// untouched. Each [AudioPlayer.dspSetFloatOutput] call is best-effort — a
/// player or platform that cannot honour float output keeps the 16-bit path,
/// and this function never throws so a fan-out failure can never interrupt
/// playback.
Future<void> pushFloatOutputToPlayers(
  bool enabled,
  Iterable<AudioPlayer> players,
) async {
  for (final player in players) {
    try {
      await player.dspSetFloatOutput(enabled);
    } catch (_) {
      // Keep today's 16-bit path on unsupported platforms.
    }
  }
}
```

---

## `lib/data/audio/collaborators/playback_volume_controller.dart`

```dart
// lib/data/audio/collaborators/playback_volume_controller.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/core/utils/error_logger.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/audio/replay_gain_math.dart';

/// Manages player volume staging, ReplayGain application with smooth transitions,
/// volume ducking, and crossfade volume math.
class PlaybackVolumeController {
  AudioPlayer Function()? getActivePlayer;
  AudioPlayer Function()? getInactivePlayer;

  double _userVolume = 1.0;
  String _replayGainMode = 'off';
  double _preampWithRg = 0.0;
  double _preampWithoutRg = 0.0;
  bool _isDucked = false;
  double _duckFactor = 0.2;
  bool _isDopActive = false;
  bool _nativeRgActive = false;
  bool _dvcEnabled = false;
  bool _bitPerfectBypass = false;

  Completer<void>? _transitionCompleter;
  bool _isDisposed = false;
  bool _isTransitionActive = false;

  /// BUG-07: bumped whenever a transition starts or the controller is disposed.
  /// A timer callback from a superseded / disposed transition bails out before
  /// touching the player again.
  int _transitionGeneration = 0;

  double get userVolume => _userVolume;
  String get replayGainMode => _replayGainMode;
  double get preampWithRg => _preampWithRg;
  double get preampWithoutRg => _preampWithoutRg;
  bool get isDucked => _isDucked;
  double get duckFactor => _duckFactor;
  bool get isDopActive => _isDopActive;
  bool get nativeRgActive => _nativeRgActive;
  bool get dvcEnabled => _dvcEnabled;
  bool get bitPerfectBypass => _bitPerfectBypass;
  bool get isDisposed => _isDisposed;
  bool get hasActiveTransitionTimer => _isTransitionActive && !_isDisposed;

  void setDopActive(bool active) {
    _isDopActive = active;
  }

  void setDvcEnabled(bool enabled) {
    _dvcEnabled = enabled;
  }

  void setBitPerfectBypass(bool bypass) {
    _bitPerfectBypass = bypass;
  }

  /// Mirrors [PulsrAudioHandler.isNativeRgActive]: when true the native DSP
  /// pre-gain owns ReplayGain, so this controller must not re-apply it in
  /// [calculateTargetVolume] (ducking/crossfade path) — otherwise the gain
  /// would double. DoP unity-gain still takes precedence over both.
  void setNativeRgActive(bool active) {
    _nativeRgActive = active;
  }

  void setDuckedState(bool ducked) {
    _isDucked = ducked;
  }

  PlaybackVolumeController({
    required this.getActivePlayer,
    required this.getInactivePlayer,
  });

  void updateSettings({
    double? userVolume,
    String? replayGainMode,
    double? preampWithRg,
    double? preampWithoutRg,
    double? duckFactor,
    bool? isDucked,
    bool? nativeRgActive,
    bool? dvcEnabled,
    bool? isDopActive,
    bool? bitPerfectBypass,
  }) {
    if (userVolume != null) _userVolume = userVolume.clamp(0.0, 1.0);
    if (replayGainMode != null) _replayGainMode = replayGainMode;
    if (preampWithRg != null) _preampWithRg = preampWithRg;
    if (preampWithoutRg != null) _preampWithoutRg = preampWithoutRg;
    if (duckFactor != null) _duckFactor = duckFactor.clamp(0.05, 1.0);
    if (isDucked != null) _isDucked = isDucked;
    if (nativeRgActive != null) _nativeRgActive = nativeRgActive;
    if (dvcEnabled != null) _dvcEnabled = dvcEnabled;
    if (isDopActive != null) _isDopActive = isDopActive;
    if (bitPerfectBypass != null) _bitPerfectBypass = bitPerfectBypass;
  }

  /// Calculates target volume for [song] with current ReplayGain, ducking, and per-song offset.
  double calculateTargetVolume(
    SongsTableData? song, {
    bool albumContext = false,
    double perSongOffsetDb = 0.0,
  }) {
    // During DSD DoP transmission, volume must strictly stay at 1.0 (unity gain)
    // to avoid corrupting 0x05 / 0xFA marker bits into white noise.
    if (_isDopActive) return 1.0;

    // Strict Bit-Perfect: bypass ReplayGain completely to preserve exact PCM samples
    if (_bitPerfectBypass) return _userVolume;

    final effectiveUserVolume = _dvcEnabled ? 1.0 : _userVolume;
    final baseVolume =
        _isDucked ? (effectiveUserVolume * _duckFactor) : effectiveUserVolume;

    if (song == null) {
      return baseVolume;
    }

    // Native pre-gain owns RG: keep the mixer at user volume (+ per-song).
    // Prompt 1.2: simplified condition to `_nativeRgActive`
    final rgVolume = _nativeRgActive
        ? baseVolume
        : ReplayGainMath.apply(
            mode: _replayGainMode,
            volume: baseVolume,
            trackGainDb: song.replayGainTrack,
            trackPeak: song.replayGainTrackPeak,
            albumGainDb: song.replayGainAlbum,
            albumPeak: song.replayGainAlbumPeak,
            albumContext: albumContext,
            preampWithRg: _preampWithRg,
            preampWithoutRg: _preampWithoutRg,
          );

    if (perSongOffsetDb.abs() >= 0.01) {
      final multiplier = math.pow(10, perSongOffsetDb / 20.0).toDouble();
      return (rgVolume * multiplier).clamp(0.0, 1.0);
    }
    return rgVolume;
  }

  /// Applies calculated volume to [player] with an optional 500ms smooth ramp (P2-1).
  Future<void> applyVolume(
    AudioPlayer player,
    double targetVolume, {
    bool smoothTransition = false,
  }) async {
    if (_isDisposed) return;
    final clamped = targetVolume.clamp(0.0, 1.0);
    _transitionGeneration++;
    // Bumping the generation supersedes any in-flight smooth transition. That
    // transition's loop can no longer clear this flag (its finally is
    // generation-gated), so clear it here. The smooth path below re-arms it.
    _isTransitionActive = false;

    if (!smoothTransition) {
      try {
        await player.setVolume(clamped);
      } catch (e, st) {
        ErrorLogger.log('Failed to set player volume',
            error: e, stackTrace: st, category: 'VolumeController');
      }
      return;
    }

    final startVol = player.volume;
    if ((startVol - clamped).abs() < 0.01) {
      try {
        await player.setVolume(clamped);
      } catch (_) {}
      return;
    }

    // P2-1: 500ms smooth crossfade between gain values
    const steps = 10;
    const stepDuration = Duration(milliseconds: 50);
    final diff = clamped - startVol;
    var stepIndex = 0;

    if (_transitionCompleter != null && !_transitionCompleter!.isCompleted) {
      _transitionCompleter!.complete();
    }
    final completer = Completer<void>();
    _transitionCompleter = completer;
    final generation = _transitionGeneration;
    _isTransitionActive = true;

    unawaited(() async {
      try {
        while (stepIndex < steps) {
          await Future.delayed(stepDuration);
          if (_isDisposed || generation != _transitionGeneration) break;

          stepIndex++;
          final current =
              (startVol + diff * (stepIndex / steps)).clamp(0.0, 1.0);
          if (_isDisposed || generation != _transitionGeneration) break;

          try {
            await player.setVolume(current);
          } catch (_) {
            break;
          }
        }
      } finally {
        if (generation == _transitionGeneration) {
          _isTransitionActive = false;
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }());

    return completer.future;
  }

  /// Sets ducked state for transient notifications / speech.
  /// [perSongOffsetDb] keeps per-track volume overrides applied across the
  /// duck ramp; without it the restore target would drop the override.
  Future<void> setDucked(bool ducked, SongsTableData? currentSong,
      {double perSongOffsetDb = 0.0}) async {
    _isDucked = ducked;
    final active = getActivePlayer?.call();
    if (active != null) {
      final target =
          calculateTargetVolume(currentSong, perSongOffsetDb: perSongOffsetDb);
      await applyVolume(active, target, smoothTransition: true);
    }
  }

  /// Lifecycle teardown hook (Prompt 1.3).
  void dispose() {
    // BUG-07: mark disposed and bump the generation so any in-flight smooth
    // transition loop bails out (generation-gated) before touching the player.
    _isDisposed = true;
    _isTransitionActive = false;
    _transitionGeneration++;
    if (_transitionCompleter != null && !_transitionCompleter!.isCompleted) {
      _transitionCompleter!.complete();
    }
    _transitionCompleter = null;
    getActivePlayer = null;
    getInactivePlayer = null;
  }
}
```

---

