// lib/data/visualizer/milkdrop_preset_store.dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/error_logger.dart';
import '../../core/utils/safe_file_path.dart';
import '../../domain/models/milkdrop_preset.dart';

/// Persists a user-imported Milkdrop preset (raw .milk text) for the visualizer.
class MilkdropPresetStore {
  static const String _keyContent = 'setting_milkdrop_preset';
  static const String _keyName = 'setting_milkdrop_preset_name';
  static const String _keyFileName = 'setting_milkdrop_preset_file';

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

  /// Upper bound on an imported .milk file, so a multi-GB or malformed file
  /// cannot be slurped into memory before it is parsed/stored.
  static const int maxImportBytes = 2 * 1024 * 1024;

  Future<MilkdropPreset> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fileName = prefs.getString(_keyFileName);
      final presetName = prefs.getString(_keyName);

      if (fileName != null && fileName.trim().isNotEmpty) {
        final dir = await _getPresetsDir();
        final file = File('${dir.path}/$fileName');
        if (file.existsSync()) {
          final content = await file.readAsString();
          return MilkdropPreset.fromMilk(
            content,
            fallbackName: presetName,
          );
        }
      }

      // Legacy fallback: check _keyContent
      final legacyContent = prefs.getString(_keyContent);
      if (legacyContent != null && legacyContent.trim().isNotEmpty) {
        return MilkdropPreset.fromMilk(
          legacyContent,
          fallbackName: presetName,
        );
      }

      return MilkdropPresetLibrary.defaultPreset;
    } catch (e, st) {
      ErrorLogger.log('MilkdropPresetStore load failed',
          error: e, stackTrace: st, category: 'MilkdropPresetStore');
      return MilkdropPresetLibrary.defaultPreset;
    }
  }

  Future<void> save(MilkdropPreset preset, String rawContent) async {
    try {
      final dir = await _getPresetsDir();
      const fileName = 'custom_preset.milk';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(rawContent, flush: true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyFileName, fileName);
      await prefs.setString(_keyName, preset.name);
      await prefs.remove(_keyContent);
    } catch (e, st) {
      ErrorLogger.log('MilkdropPresetStore save failed',
          error: e, stackTrace: st, category: 'MilkdropPresetStore');
      rethrow;
    }
  }

  Future<void> clear() async {
    try {
      final dir = await _getPresetsDir();
      const fileName = 'custom_preset.milk';
      final file = File('${dir.path}/$fileName');
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e, st) {
      ErrorLogger.log('MilkdropPresetStore clear file failed',
          error: e, stackTrace: st, category: 'MilkdropPresetStore');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFileName);
    await prefs.remove(_keyName);
    await prefs.remove(_keyContent);
  }

  /// Opens a file picker for a `.milk` preset and persists it. Returns the
  /// parsed preset, or null when the user cancels or the file cannot be read.
  Future<MilkdropPreset?> importFromFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['milk'],
      );
      if (file == null) return null;
      final ioFile =
          SafeFilePath.validate(file.path, allowedExtensions: const ['milk']);
      if (ioFile == null) return null;
      final size = await ioFile.length();
      if (size > maxImportBytes) {
        ErrorLogger.log(
          'MilkdropPresetStore import rejected: file is $size bytes '
          '(max $maxImportBytes)',
          category: 'MilkdropPresetStore',
        );
        return null;
      }
      final content = await ioFile.readAsString();
      final cleanName =
          file.name.replaceAll(RegExp(r'\.milk$', caseSensitive: false), '');
      final preset = MilkdropPreset.fromMilk(
        content,
        fallbackName: cleanName.isNotEmpty ? cleanName : 'Imported Preset',
      );
      await save(preset, content);
      return preset;
    } catch (e, st) {
      ErrorLogger.log('MilkdropPresetStore importFromFile failed',
          error: e, stackTrace: st, category: 'MilkdropPresetStore');
      return null;
    }
  }
}
