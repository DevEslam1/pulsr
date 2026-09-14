// lib/data/visualizer/visualizer_preset_store.dart
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/visualizer_preset.dart';

/// Persists a user-authored Custom (JSON) visualizer preset.
class VisualizerPresetStore {
  static const String _key = 'setting_custom_visualizer_preset';

  Future<VisualizerPreset> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) {
        return VisualizerPreset.fallback;
      }
      return VisualizerPreset.fromJsonString(raw);
    } catch (_) {
      return VisualizerPreset.fallback;
    }
  }

  Future<void> save(VisualizerPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(preset.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Opens a file picker for a `.json` preset and persists it. Returns the
  /// parsed preset, or null when cancelled or the file is not a valid preset.
  Future<VisualizerPreset?> importFromFile() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final path = result?.path;
      if (path == null) return null;
      final content = await File(path).readAsString();
      final preset = VisualizerPreset.fromJsonString(content);
      await save(preset);
      return preset;
    } catch (_) {
      return null;
    }
  }
}
