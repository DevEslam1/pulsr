// lib/core/utils/local_delete_guard.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'error_logger.dart';
import 'safe_file_path.dart';

/// Containment policy for deleting files that Pulsr itself owns or manages.
///
/// Every destructive file operation in the data layer must go through this
/// guard: a persisted path (download task JSON, database row, restored backup)
/// is untrusted input, so it may only be removed when it resolves to a real
/// audio file *inside* an app-owned root. Paths outside those roots are left
/// untouched and logged; the platform MediaStore channel remains the only way
/// to remove files the user owns in a shared collection.
///
/// This mirrors the policy already enforced by
/// `MusicRepository._isSafeLocalDeletePath` and keeps both delete paths from
/// drifting apart again (the download path previously had no check at all).
Future<List<String>> allowedAppDeleteRoots() async {
  final roots = <String>[];
  Future<void> add(Future<Directory?> Function() provider) async {
    try {
      final dir = await provider();
      if (dir != null) roots.add(dir.path);
    } catch (_) {
      // Provider unsupported on this platform: skip it rather than failing the
      // whole allowlist.
    }
  }

  await add(getApplicationDocumentsDirectory);
  await add(getApplicationSupportDirectory);
  await add(getTemporaryDirectory);
  if (Platform.isAndroid) {
    await add(getExternalStorageDirectory);
  }
  return roots;
}

/// Returns the canonical file to delete when [path] is a regular audio file
/// that resolves inside one of [roots]; otherwise `null`.
///
/// Fails closed: an unresolvable root, an empty allowlist, a symbolic-link
/// escape or a path equal to a root all refuse the delete.
Future<File?> resolveDeletableAudioFile(
  String path, {
  required List<String> allowedExtensions,
  required List<String> roots,
  String logCategory = 'Security',
}) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty || !p.isAbsolute(trimmed)) return null;

  final file = SafeFilePath.validate(
    trimmed,
    allowedExtensions: allowedExtensions,
    checkExists: true,
  );
  if (file == null) return null;

  if (roots.isEmpty) {
    ErrorLogger.log(
      'Refusing to delete "$path": no allowed root could be resolved',
      category: logCategory,
    );
    return null;
  }

  try {
    final canonicalFile = await file.resolveSymbolicLinks();
    for (final root in roots) {
      String canonicalRoot;
      try {
        canonicalRoot = await Directory(root).resolveSymbolicLinks();
      } catch (_) {
        continue;
      }
      if (p.equals(canonicalFile, canonicalRoot)) continue;
      if (p.isWithin(canonicalRoot, canonicalFile)) return File(canonicalFile);
    }
  } catch (e, st) {
    ErrorLogger.log('Failed to canonicalize delete path "$path"',
        error: e, stackTrace: st, category: logCategory);
    return null;
  }

  ErrorLogger.log(
    'Refusing to delete file outside allowed roots: $path',
    category: logCategory,
  );
  return null;
}
