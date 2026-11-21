// lib/data/visualizer/visualizer_preset_store.dart
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/error_logger.dart';
import '../../core/utils/safe_file_path.dart';
import '../../domain/models/visualizer_preset.dart';

/// Persists a user-authored Custom (JSON) visualizer preset.
class VisualizerPresetStore {
  static const String _key = 'setting_custom_visualizer_preset';

  @visibleForTesting
  static Future<Directory> Function() directoryProvider =
      getApplicationSupportDirectory;

  static Future<Directory> _getPresetsDir() async {
    Directory base;
    try {
      base = await directoryProvider();
    } catch (_) {
      base = Directory.systemTemp;
    }
    final dir = Directory('${base.path}/visualizer_presets');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Upper bound on an imported .json preset, so a multi-GB or malformed file
  /// cannot be slurped into memory before it is parsed/stored.
  static const int maxImportBytes = 2 * 1024 * 1024;

  Future<VisualizerPreset> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      if (stored == null || stored.trim().isEmpty) {
        return VisualizerPreset.fallback;
      }

      // Backward compatibility: If stored value is legacy raw JSON
      if (stored.trim().startsWith('{')) {
        return VisualizerPreset.fromJsonString(stored);
      }

      final dir = await _getPresetsDir();
      final file = File('${dir.path}/$stored');
      if (!file.existsSync()) {
        return VisualizerPreset.fallback;
      }
      final content = await file.readAsString();
      return VisualizerPreset.fromJsonString(content);
    } catch (e, st) {
      ErrorLogger.log('VisualizerPresetStore load failed',
          error: e, stackTrace: st, category: 'VisualizerPresetStore');
      return VisualizerPreset.fallback;
    }
  }

  Future<void> save(VisualizerPreset preset) async {
    try {
      final dir = await _getPresetsDir();
      const fileName = 'custom_preset.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonEncode(preset.toJson()), flush: true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, fileName);
    } catch (e, st) {
      ErrorLogger.log('VisualizerPresetStore save failed',
          error: e, stackTrace: st, category: 'VisualizerPresetStore');
      rethrow;
    }
  }

  Future<void> clear() async {
    try {
      final dir = await _getPresetsDir();
      const fileName = 'custom_preset.json';
      final file = File('${dir.path}/$fileName');
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e, st) {
      ErrorLogger.log('VisualizerPresetStore clear file failed',
          error: e, stackTrace: st, category: 'VisualizerPresetStore');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Opens a file picker for a `.json` preset and persists it. Returns the
  /// parsed preset, or null when cancelled or the file is not a valid preset.
  Future<VisualizerPreset?> importFromFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null) return null;
      final ioFile =
          SafeFilePath.validate(file.path, allowedExtensions: const ['json']);
      if (ioFile == null) return null;
      final size = await ioFile.length();
      if (size > maxImportBytes) {
        ErrorLogger.log(
          'VisualizerPresetStore import rejected: file is $size bytes '
          '(max $maxImportBytes)',
          category: 'VisualizerPresetStore',
        );
        return null;
      }
      final content = await ioFile.readAsString();
      final preset = VisualizerPreset.fromJsonString(content);
      await save(preset);
      return preset;
    } catch (e, st) {
      ErrorLogger.log('VisualizerPresetStore importFromFile failed',
          error: e, stackTrace: st, category: 'VisualizerPresetStore');
      return null;
    }
  }
}
