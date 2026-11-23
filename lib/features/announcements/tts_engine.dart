// lib/features/announcements/tts_engine.dart

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter/services.dart';

import '../../core/utils/error_logger.dart';

/// A platform voice that can read announcements aloud.
///
/// Value object returned by [TtsEngine.voices]; the settings screen lists these
/// and persists the chosen [id].
class TtsVoice {
  /// Creates a voice descriptor.
  const TtsVoice({
    required this.id,
    required this.name,
    required this.localeCode,
    required this.quality,
  });

  /// Platform identifier passed back to the engine when speaking.
  final String id;

  /// Human-readable name shown in the voice picker.
  final String name;

  /// BCP-47 locale tag, e.g. `en-GB`.
  final String localeCode;

  /// Coarse quality bucket reported by the platform (`low`, `normal`, `high`…).
  final String quality;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsVoice &&
          other.id == id &&
          other.name == name &&
          other.localeCode == localeCode &&
          other.quality == quality;

  @override
  int get hashCode => Object.hash(id, name, localeCode, quality);

  @override
  String toString() => 'TtsVoice($id, $localeCode, $quality)';
}

/// Text-to-speech backend used by the announcement track announcer.
///
/// Implementations must report availability through [isAvailable] instead of
/// throwing, so callers can degrade to silence on unsupported platforms.
abstract class TtsEngine {
  /// Prepares the engine. Returns `false` when this platform cannot speak.
  Future<bool> init();

  /// Speaks [text], replacing any utterance already queued, at [volume].
  ///
  /// When [duckAudio] is true the platform asks for transient audio focus with
  /// ducking, so music continues quietly under the announcement instead of
  /// being stopped.
  Future<void> speak(
    String text, {
    double volume = 1.0,
    bool duckAudio = false,
  });

  /// Stops speech immediately.
  Future<void> stop();

  /// Lists the voices installed on the platform. Empty when unavailable.
  Future<List<TtsVoice>> voices();

  /// Releases native resources.
  Future<void> dispose();

  /// Whether the engine can speak on this platform right now.
  bool get isAvailable;
}

/// [TtsEngine] backed by the Android `com.pulsr.music/tts` method channel.
///
/// Every channel failure (missing plugin on iOS/desktop, platform error) is
/// logged through `ErrorLogger` and turns [isAvailable] off so announcements
/// fail silently instead of throwing at the playback path.
class MethodChannelTtsEngine implements TtsEngine {
  /// Creates the engine.
  ///
  /// [channel] is injectable for tests; production uses [channelName].
  MethodChannelTtsEngine({
    MethodChannel? channel,
    Duration retryCooldown = defaultRetryCooldown,
    DateTime Function()? now,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _retryCooldown = retryCooldown,
        _now = now ?? DateTime.now;

  /// Method channel name shared with `TtsPlugin.kt`.
  static const String channelName = 'com.pulsr.music/tts';

  /// Default cooldown before retrying initialization after a transient failure.
  static const Duration defaultRetryCooldown = Duration(seconds: 10);

  final MethodChannel _channel;
  final Duration _retryCooldown;
  final DateTime Function() _now;
  bool _available = false;
  bool _disposed = false;
  bool _permanentlyUnavailable = false;
  int _consecutiveFailures = 0;
  DateTime? _nextRetryAt;

  /// Whether [dispose] has been called on this engine.
  @visibleForTesting
  bool get isDisposed => _disposed;

  /// Number of consecutive transient failures since last successful operation.
  @visibleForTesting
  int get consecutiveFailures => _consecutiveFailures;

  /// Earliest timestamp at which a transient failure may retry initialization.
  @visibleForTesting
  DateTime? get nextRetryAt => _nextRetryAt;

  /// True when the engine is currently unavailable due to a transient failure
  /// and the retry cooldown has elapsed.
  bool get canRetryInit =>
      !_disposed &&
      !_available &&
      !_permanentlyUnavailable &&
      _nextRetryAt != null &&
      !_now().isBefore(_nextRetryAt!);

  /// Voice id applied to the next [speak] call; empty keeps the system voice.
  String voiceId = '';

  /// Locale tag applied to the next [speak] call; empty keeps the system one.
  String localeId = '';

  /// Fires whenever [isAvailable] changes.
  ///
  /// A method-channel engine learns it can speak only after a successful
  /// `init` (or loses the ability when a call fails), so the settings screen
  /// needs a signal to re-list voices instead of showing a stale empty list.
  final ValueNotifier<bool> availability = ValueNotifier<bool>(false);

  @override
  bool get isAvailable => _available;

  @override
  Future<bool> init() async {
    if (_disposed || _permanentlyUnavailable) return false;
    try {
      final ready = await _channel
              .invokeMethod<bool>('init')
              .timeout(const Duration(seconds: 12)) ??
          false;
      if (_disposed) return false;
      if (ready) {
        _consecutiveFailures = 0;
        _nextRetryAt = null;
      } else {
        _consecutiveFailures++;
        _nextRetryAt = _now().add(_retryCooldown);
      }
      _setAvailable(ready);
      return ready;
    } on Exception catch (error, stackTrace) {
      if (!_disposed) {
        _handleFailure(error, stackTrace, 'init');
      }
      return false;
    }
  }

  @override
  Future<void> speak(
    String text, {
    double volume = 1.0,
    bool duckAudio = false,
  }) async {
    if (_disposed || text.isEmpty) return;
    if (!_available) {
      if (canRetryInit) {
        final recovered = await init();
        if (!recovered) return;
      } else {
        return;
      }
    }
    final arguments = <String, Object?>{
      'text': text,
      'volume': volume.clamp(0.0, 1.0),
      'duckAudio': duckAudio,
    };
    if (voiceId.isNotEmpty) arguments['voiceId'] = voiceId;
    if (localeId.isNotEmpty) arguments['localeId'] = localeId;
    try {
      await _channel
          .invokeMethod<void>('speak', arguments)
          .timeout(const Duration(seconds: 15));
      _consecutiveFailures = 0;
      _nextRetryAt = null;
    } on Exception catch (error, stackTrace) {
      if (!_disposed) {
        _handleFailure(error, stackTrace, 'speak');
      }
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed || !_available) return;
    try {
      await _channel
          .invokeMethod<void>('stop')
          .timeout(const Duration(seconds: 5));
    } on Exception catch (error, stackTrace) {
      if (!_disposed) {
        _handleFailure(error, stackTrace, 'stop');
      }
    }
  }

  @override
  Future<List<TtsVoice>> voices() async {
    if (_disposed) return const <TtsVoice>[];
    if (!_available) {
      if (canRetryInit) {
        final recovered = await init();
        if (!recovered) return const <TtsVoice>[];
      } else {
        return const <TtsVoice>[];
      }
    }
    try {
      final raw = await _channel
          .invokeListMethod<dynamic>('voices')
          .timeout(const Duration(seconds: 5));
      if (raw == null || _disposed) return const <TtsVoice>[];
      final voices = <TtsVoice>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final id = entry['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        voices.add(TtsVoice(
          id: id,
          name: entry['name']?.toString() ?? id,
          localeCode: entry['localeCode']?.toString() ?? '',
          quality: entry['quality']?.toString() ?? 'unknown',
        ));
      }
      return voices;
    } on Exception catch (error, stackTrace) {
      if (!_disposed) {
        _handleFailure(error, stackTrace, 'voices');
      }
      return const <TtsVoice>[];
    }
  }

  /// Whether the platform is speaking right now.
  ///
  /// Not part of [TtsEngine]: it exists so a settings surface can show live
  /// speech state without widening the interface every fake must implement.
  Future<bool> isSpeaking() async {
    if (_disposed || !_available) return false;
    try {
      return await _channel
              .invokeMethod<bool>('isSpeaking')
              .timeout(const Duration(seconds: 5)) ??
          false;
    } on Exception catch (error, stackTrace) {
      if (!_disposed) {
        _handleFailure(error, stackTrace, 'isSpeaking');
      }
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    final wasAvailable = _available;
    _disposed = true;
    _available = false;
    if (wasAvailable) {
      try {
        await _channel
            .invokeMethod<void>('stop')
            .timeout(const Duration(seconds: 5));
      } on Exception catch (error, stackTrace) {
        ErrorLogger.log(
          'TTS dispose stop failed',
          error: error,
          stackTrace: stackTrace,
          category: 'TtsEngine',
        );
      }
    }
    availability.dispose();
  }

  /// Updates [isAvailable] and notifies listeners on a real change only.
  void _setAvailable(bool value) {
    if (_disposed) return;
    if (_available == value) return;
    _available = value;
    availability.value = value;
  }

  void _handleFailure(Object error, StackTrace stackTrace, String action) {
    final isMissingPlugin = error is MissingPluginException;
    final isTimeout = error is TimeoutException;
    if (isMissingPlugin) {
      _permanentlyUnavailable = true;
      _nextRetryAt = null;
    } else {
      _consecutiveFailures++;
      _nextRetryAt = _now().add(_retryCooldown);
    }
    _setAvailable(false);
    ErrorLogger.log(
      isMissingPlugin
          ? 'TTS channel $channelName has no native handler ($action)'
          : isTimeout
              ? 'TTS $action timed out'
              : 'TTS $action failed',
      error: error,
      stackTrace: stackTrace,
      category: 'TtsEngine',
    );
  }
}
