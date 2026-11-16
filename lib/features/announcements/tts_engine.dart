// lib/features/announcements/tts_engine.dart

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
  Future<void> speak(String text, {double volume = 1.0});

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
  MethodChannelTtsEngine({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// Method channel name shared with `TtsPlugin.kt`.
  static const String channelName = 'com.pulsr.music/tts';

  final MethodChannel _channel;
  bool _available = false;

  /// Voice id applied to the next [speak] call; empty keeps the system voice.
  String voiceId = '';

  /// Locale tag applied to the next [speak] call; empty keeps the system one.
  String localeId = '';

  @override
  bool get isAvailable => _available;

  @override
  Future<bool> init() async {
    try {
      final ready = await _channel.invokeMethod<bool>('init') ?? false;
      _available = ready;
      return ready;
    } on Exception catch (error, stackTrace) {
      _handleFailure(error, stackTrace, 'init');
      return false;
    }
  }

  @override
  Future<void> speak(String text, {double volume = 1.0}) async {
    if (!_available || text.isEmpty) return;
    final arguments = <String, Object?>{
      'text': text,
      'volume': volume.clamp(0.0, 1.0),
    };
    if (voiceId.isNotEmpty) arguments['voiceId'] = voiceId;
    if (localeId.isNotEmpty) arguments['localeId'] = localeId;
    try {
      await _channel.invokeMethod<void>('speak', arguments);
    } on Exception catch (error, stackTrace) {
      _handleFailure(error, stackTrace, 'speak');
    }
  }

  @override
  Future<void> stop() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on Exception catch (error, stackTrace) {
      _handleFailure(error, stackTrace, 'stop');
    }
  }

  @override
  Future<List<TtsVoice>> voices() async {
    if (!_available) return const <TtsVoice>[];
    try {
      final raw = await _channel.invokeListMethod<dynamic>('voices');
      if (raw == null) return const <TtsVoice>[];
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
      _handleFailure(error, stackTrace, 'voices');
      return const <TtsVoice>[];
    }
  }

  /// Whether the platform is speaking right now.
  ///
  /// Not part of [TtsEngine]: it exists so a settings surface can show live
  /// speech state without widening the interface every fake must implement.
  Future<bool> isSpeaking() async {
    if (!_available) return false;
    try {
      return await _channel.invokeMethod<bool>('isSpeaking') ?? false;
    } on Exception catch (error, stackTrace) {
      _handleFailure(error, stackTrace, 'isSpeaking');
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_available) {
      try {
        await _channel.invokeMethod<void>('stop');
      } on Exception catch (error, stackTrace) {
        _handleFailure(error, stackTrace, 'dispose');
      }
    }
    _available = false;
  }

  void _handleFailure(Object error, StackTrace stackTrace, String action) {
    _available = false;
    final isMissingPlugin = error is MissingPluginException;
    ErrorLogger.log(
      isMissingPlugin
          ? 'TTS channel $channelName has no native handler ($action)'
          : 'TTS $action failed',
      error: error,
      stackTrace: stackTrace,
      category: 'TtsEngine',
    );
  }
}
