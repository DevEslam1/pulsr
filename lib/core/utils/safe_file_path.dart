// lib/core/utils/safe_file_path.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'error_logger.dart';

/// Validates file paths obtained from FilePicker or external input before File operations (I16).
class SafeFilePath {
  /// Validates a raw path string (e.g. from FilePicker or external drag-and-drop).
  ///
  /// Checks for:
  /// - Null or empty path
  /// - Null byte injection (\x00)
  /// - Path normalization
  /// - Optional extension restrictions (e.g. ['.json', '.txt', '.vdc'])
  /// - File existence and ensure it is not a directory
  ///
  /// Returns a valid [File] instance if safe and valid, or `null` if invalid.
  static File? validate(
    String? rawPath, {
    List<String>? allowedExtensions,
    bool checkExists = true,
  }) {
    if (rawPath == null || rawPath.trim().isEmpty) {
      return null;
    }

    final trimmed = rawPath.trim();

    // Check for null-byte poison attacks
    if (trimmed.contains('\x00')) {
      ErrorLogger.log('Null-byte detected in file path: $trimmed',
          category: 'Security');
      return null;
    }

    try {
      final normalized = p.normalize(trimmed);

      // Check allowed extensions if specified
      if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
        final ext = p.extension(normalized).toLowerCase();
        final match = allowedExtensions.any(
          (allowed) =>
              allowed.toLowerCase() == ext ||
              '.${allowed.toLowerCase().replaceAll('.', '')}' == ext,
        );
        if (!match) {
          ErrorLogger.log(
            'File extension "$ext" not permitted. Allowed: $allowedExtensions',
            category: 'Security',
          );
          return null;
        }
      }

      final file = File(normalized);
      if (checkExists) {
        if (!file.existsSync()) {
          ErrorLogger.log('Target file does not exist: $normalized',
              category: 'Security');
          return null;
        }
        if (FileSystemEntity.isDirectorySync(normalized)) {
          ErrorLogger.log('Target path is a directory, not a file: $normalized',
              category: 'Security');
          return null;
        }
      }

      return file;
    } catch (e, st) {
      ErrorLogger.log('Error validating file path "$rawPath"',
          error: e, stackTrace: st, category: 'Security');
      return null;
    }
  }

  /// Validates a path intended for writing (e.g. FilePicker.saveFile).
  /// Ensures path is valid, non-empty, and has an allowed extension if specified.
  static File? validateSavePath(
    String? rawPath, {
    List<String>? allowedExtensions,
  }) {
    return validate(rawPath,
        allowedExtensions: allowedExtensions, checkExists: false);
  }
}
