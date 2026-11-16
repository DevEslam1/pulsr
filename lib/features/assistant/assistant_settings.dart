// lib/features/assistant/assistant_settings.dart
//
// Opt-in state for the Android search-suggestion surface. Push rows into the
// system search cache only after the user explicitly enables it; the default is
// OFF because the cache is readable by the privileged search UI.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/error_logger.dart';

/// User preference backing `AssistantSuggestionSync`.
///
/// Mirrors the other feature settings objects: a [ChangeNotifier] over an
/// injected [SharedPreferences] store, every setter persists eagerly, and a
/// missing store degrades to in-memory defaults instead of throwing.
class AssistantSettings extends ChangeNotifier {
  AssistantSettings._(this._prefs);

  /// Preference key for the suggestion opt-in.
  static const String keySuggestionsEnabled = 'assistant_suggestions_enabled';

  /// Suggestions are opt-in and stay off on a fresh install.
  static const bool defaultSuggestionsEnabled = false;

  final SharedPreferences? _prefs;
  bool _suggestionsEnabled = defaultSuggestionsEnabled;
  bool _disposed = false;

  /// Loads the persisted toggle, falling back to OFF when preferences are
  /// unavailable.
  static Future<AssistantSettings> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } on Exception catch (error, stackTrace) {
      ErrorLogger.log(
        'Assistant settings could not read preferences; suggestions stay off',
        error: error,
        stackTrace: stackTrace,
        category: 'Assistant',
      );
    }
    final settings = AssistantSettings._(prefs);
    if (prefs == null) return settings;
    settings._suggestionsEnabled =
        prefs.getBool(keySuggestionsEnabled) ?? defaultSuggestionsEnabled;
    return settings;
  }

  /// Whether assistant suggestions may be pushed to the system search cache.
  bool get suggestionsEnabled => _suggestionsEnabled;

  /// Enables or disables the system search-suggestion cache.
  void setSuggestionsEnabled(bool value) {
    if (_suggestionsEnabled == value) return;
    _suggestionsEnabled = value;
    if (_disposed) return;
    notifyListeners();
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(() async {
      try {
        await prefs.setBool(keySuggestionsEnabled, value);
      } catch (error) {
        ErrorLogger.log(
          'Assistant settings could not be saved',
          error: error,
          category: 'Assistant',
        );
      }
    }());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
