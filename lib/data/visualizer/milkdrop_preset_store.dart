// lib/data/visualizer/milkdrop_preset_store.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/milkdrop_preset.dart';

/// Persists a user-imported Milkdrop preset (raw .milk text) for the visualizer.
class MilkdropPresetStore {
  static const String _keyContent = 'setting_milkdrop_preset';
  static const String _keyName = 'setting_milkdrop_preset_name';

  Future<MilkdropPreset> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString(_keyContent);
      if (content == null || content.trim().isEmpty) {
        return MilkdropPresetLibrary.defaultPreset;
      }
      return MilkdropPreset.fromMilk(
        content,
        fallbackName: prefs.getString(_keyName),
      );
    } catch (_) {
      return MilkdropPresetLibrary.defaultPreset;
    }
  }

  Future<void> save(MilkdropPreset preset, String rawContent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyContent, rawContent);
    await prefs.setString(_keyName, preset.name);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyContent);
    await prefs.remove(_keyName);
  }

  /// Opens a file picker for a `.milk` preset and persists it. Returns the
  /// parsed preset, or null when the user cancels or the file cannot be read.
  Future<MilkdropPreset?> importFromFile() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['milk'],
      );
      final path = result?.path;
      if (path == null) return null;
      final content = await File(path).readAsString();
      final preset = MilkdropPreset.fromMilk(
        content,
        fallbackName: result?.name.replaceAll(RegExp(r'\.milk$'), ''),
      );
      await save(preset, content);
      return preset;
    } catch (_) {
      return null;
    }
  }
}
