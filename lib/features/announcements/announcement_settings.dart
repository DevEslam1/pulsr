// lib/features/announcements/announcement_settings.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/error_logger.dart';
import 'announcement_composer.dart';

export 'announcement_composer.dart' show AnnouncementElement;

/// User preferences for spoken track announcements.
///
/// Backed by [SharedPreferences] under the `announce_` key prefix. Every setter
/// clamps its input to the documented range, notifies listeners and persists
/// eagerly, so the settings survive a process restart without an explicit
/// teardown. [load] is restart-safe: unknown persisted element names (from a
/// build that knew more elements) are ignored rather than treated as errors.
class AnnouncementSettings extends ChangeNotifier {
  AnnouncementSettings._(this._prefs);

  // ── Preference keys ─────────────────────────────────────────────────────
  /// Whether announcements are enabled at all. Defaults to `false`.
  static const String keyEnabled = 'announce_enabled';

  /// Ordered list of announced elements, stored as enum names.
  static const String keyElements = 'announce_elements';

  /// Delay between track start and speech, in milliseconds.
  static const String keyDelayMs = 'announce_delay_ms';

  /// Speech volume, 0.4–1.0.
  static const String keyVolume = 'announce_volume';

  /// Whether music should be lowered while the announcement plays.
  static const String keyDuckAudio = 'announce_duck_audio';

  /// Whether announcements are skipped while casting.
  static const String keySkipWhenCasting = 'announce_skip_when_casting';

  /// Whether announcements are skipped during bit-perfect playback.
  static const String keySkipWhenBitPerfect = 'announce_skip_when_bit_perfect';

  /// Selected platform voice id, empty for the system default.
  static const String keyVoiceId = 'announce_voice_id';

  /// BCP-47 locale of the selected voice, empty for the system default.
  static const String keyLocaleId = 'announce_locale_id';

  /// Maximum spoken announcement length in characters.
  static const String keyMaxLength = 'announce_max_length';

  // ── Defaults and bounds ─────────────────────────────────────────────────
  /// Default for [enabled]: announcements are opt-in.
  static const bool defaultEnabled = false;

  /// Default announced elements, in speaking order.
  static const List<AnnouncementElement> defaultElements = [
    AnnouncementElement.title,
    AnnouncementElement.artist,
  ];

  /// Default delay before speaking, in milliseconds.
  static const int defaultDelayMs = 1500;

  /// Lowest accepted delay (speak immediately).
  static const int minDelayMs = 0;

  /// Highest accepted delay, in milliseconds.
  static const int maxDelayMs = 10000;

  /// Default speech volume.
  static const double defaultVolume = 0.8;

  /// Lowest accepted speech volume, so an announcement is never inaudible.
  static const double minVolume = 0.4;

  /// Highest accepted speech volume.
  static const double maxVolume = 1.0;

  /// Default for [duckAudio].
  static const bool defaultDuckAudio = true;

  /// Default for [skipWhenCasting].
  static const bool defaultSkipWhenCasting = true;

  /// Default for [skipWhenBitPerfect].
  static const bool defaultSkipWhenBitPerfect = true;

  /// Default for [maxLength], shared with the composer.
  static const int defaultMaxLength = kDefaultAnnouncementMaxLength;

  /// Shortest accepted [maxLength]: below this, names become unrecognisable.
  static const int minMaxLength = 40;

  /// Longest accepted [maxLength]: keeps one announcement under a few seconds.
  static const int maxMaxLength = 600;

  final SharedPreferences? _prefs;

  bool _enabled = defaultEnabled;
  List<AnnouncementElement> _elements = List.of(defaultElements);
  int _delayMs = defaultDelayMs;
  double _volume = defaultVolume;
  bool _duckAudio = defaultDuckAudio;
  bool _skipWhenCasting = defaultSkipWhenCasting;
  bool _skipWhenBitPerfect = defaultSkipWhenBitPerfect;
  String _voiceId = '';
  String _localeId = '';
  int _maxLength = defaultMaxLength;
  bool _disposed = false;

  /// Loads the persisted settings, falling back to the defaults when the
  /// preference store is unavailable.
  static Future<AnnouncementSettings> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } on Exception catch (error, stackTrace) {
      ErrorLogger.log(
        'Announcement settings could not read preferences; using defaults',
        error: error,
        stackTrace: stackTrace,
        category: 'Announcements',
      );
    }
    final settings = AnnouncementSettings._(prefs);
    if (prefs == null) return settings;
    settings._enabled = prefs.getBool(keyEnabled) ?? defaultEnabled;
    settings._elements = _readElements(prefs.getStringList(keyElements));
    settings._delayMs = (prefs.getInt(keyDelayMs) ?? defaultDelayMs)
        .clamp(minDelayMs, maxDelayMs)
        .toInt();
    settings._volume = (prefs.getDouble(keyVolume) ?? defaultVolume)
        .clamp(minVolume, maxVolume)
        .toDouble();
    settings._duckAudio = prefs.getBool(keyDuckAudio) ?? defaultDuckAudio;
    settings._skipWhenCasting =
        prefs.getBool(keySkipWhenCasting) ?? defaultSkipWhenCasting;
    settings._skipWhenBitPerfect =
        prefs.getBool(keySkipWhenBitPerfect) ?? defaultSkipWhenBitPerfect;
    settings._voiceId = prefs.getString(keyVoiceId) ?? '';
    settings._localeId = prefs.getString(keyLocaleId) ?? '';
    settings._maxLength = (prefs.getInt(keyMaxLength) ?? defaultMaxLength)
        .clamp(minMaxLength, maxMaxLength)
        .toInt();
    return settings;
  }

  /// Whether announcements are spoken at all.
  bool get enabled => _enabled;

  /// Ordered elements an announcement reads out.
  List<AnnouncementElement> get elements => List.unmodifiable(_elements);

  /// Delay between a track starting and the announcement, in milliseconds.
  int get delayMs => _delayMs;

  /// Announcement volume in the 0.4–1.0 range.
  double get volume => _volume;

  /// Whether the music should duck under the announcement.
  bool get duckAudio => _duckAudio;

  /// Whether announcements are skipped while casting.
  bool get skipWhenCasting => _skipWhenCasting;

  /// Whether announcements are skipped during bit-perfect playback.
  bool get skipWhenBitPerfect => _skipWhenBitPerfect;

  /// Selected platform voice id, empty for the system default.
  String get voiceId => _voiceId;

  /// BCP-47 locale of the selected voice, empty for the system default.
  String get localeId => _localeId;

  /// Maximum spoken announcement length in characters.
  int get maxLength => _maxLength;

  /// Enables or disables announcements.
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _changed();
  }

  /// Replaces the announced elements, de-duplicating while keeping order.
  void setElements(List<AnnouncementElement> value) {
    final next = <AnnouncementElement>[];
    for (final element in value) {
      if (!next.contains(element)) next.add(element);
    }
    if (listEquals(_elements, next)) return;
    _elements = next;
    _changed();
  }

  /// Adds [element] to the end of the speaking order or removes it.
  void setElementEnabled(AnnouncementElement element, bool enabled) {
    if (enabled) {
      if (_elements.contains(element)) return;
      _elements = [..._elements, element];
    } else {
      if (!_elements.contains(element)) return;
      _elements = _elements.where((e) => e != element).toList();
    }
    _changed();
  }

  /// Sets the delay before speaking, clamped to 0–10000 ms.
  void setDelayMs(int value) {
    final next = value.clamp(minDelayMs, maxDelayMs).toInt();
    if (_delayMs == next) return;
    _delayMs = next;
    _changed();
  }

  /// Sets the announcement volume, clamped to 0.4–1.0.
  void setVolume(double value) {
    final next = value.clamp(minVolume, maxVolume).toDouble();
    if (_volume == next) return;
    _volume = next;
    _changed();
  }

  /// Sets whether music ducks under the announcement.
  void setDuckAudio(bool value) {
    if (_duckAudio == value) return;
    _duckAudio = value;
    _changed();
  }

  /// Sets whether announcements are skipped while casting.
  void setSkipWhenCasting(bool value) {
    if (_skipWhenCasting == value) return;
    _skipWhenCasting = value;
    _changed();
  }

  /// Sets whether announcements are skipped during bit-perfect playback.
  void setSkipWhenBitPerfect(bool value) {
    if (_skipWhenBitPerfect == value) return;
    _skipWhenBitPerfect = value;
    _changed();
  }

  /// Sets the platform voice id; pass an empty string for the system default.
  void setVoiceId(String value) {
    if (_voiceId == value) return;
    _voiceId = value;
    _changed();
  }

  /// Sets the voice locale, empty for the system default.
  void setLocaleId(String value) {
    if (_localeId == value) return;
    _localeId = value;
    _changed();
  }

  /// Sets the maximum announcement length, clamped to 40–600 characters.
  void setMaxLength(int value) {
    final next = value.clamp(minMaxLength, maxMaxLength).toInt();
    if (_maxLength == next) return;
    _maxLength = next;
    _changed();
  }

  /// Writes every field to the preference store.
  ///
  /// Setters already call this; await it when the caller needs the write to be
  /// durable before tearing the settings object down.
  Future<void> save() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setBool(keyEnabled, _enabled);
      await prefs.setStringList(
        keyElements,
        _elements.map((element) => element.name).toList(),
      );
      await prefs.setInt(keyDelayMs, _delayMs);
      await prefs.setDouble(keyVolume, _volume);
      await prefs.setBool(keyDuckAudio, _duckAudio);
      await prefs.setBool(keySkipWhenCasting, _skipWhenCasting);
      await prefs.setBool(keySkipWhenBitPerfect, _skipWhenBitPerfect);
      await prefs.setString(keyVoiceId, _voiceId);
      await prefs.setString(keyLocaleId, _localeId);
      await prefs.setInt(keyMaxLength, _maxLength);
    } on Exception catch (error, stackTrace) {
      ErrorLogger.log(
        'Announcement settings could not be saved',
        error: error,
        stackTrace: stackTrace,
        category: 'Announcements',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    unawaited(save());
  }

  static List<AnnouncementElement> _readElements(List<String>? stored) {
    if (stored == null) return List.of(defaultElements);
    final parsed = <AnnouncementElement>[];
    for (final name in stored) {
      for (final element in AnnouncementElement.values) {
        if (element.name == name) {
          if (!parsed.contains(element)) parsed.add(element);
          break;
        }
      }
    }
    // An empty stored list is a real user choice (announce nothing); a
    // non-empty list that parsed to nothing comes from a build with a different
    // vocabulary, so defaults keep announcements working.
    if (parsed.isEmpty && stored.isNotEmpty) return List.of(defaultElements);
    return parsed;
  }
}
