// lib/data/audio/sacd/sacd_iso_probe.dart
//
// Cheap SACD disc-image probe: an `.iso` file is a SACD image only when it
// carries an ISO9660 primary volume descriptor AND a SACD area directory with
// at least one TOC file. Both checks read a handful of sectors, so this runs
// safely during library scanning.

import 'dart:io';

import '../../../core/constants/audio_formats.dart';
import '../../../core/utils/error_logger.dart';
import 'iso9660_reader.dart';
import 'sacd_toc.dart';

/// Returns true when [path] looks like a SACD ISO image.
///
/// The check is structural, not extension based alone: the image must expose a
/// `SACD` directory containing at least one `.TOC` file. This is a probe used
/// on untrusted files, so it never throws: unreadable, missing, malformed or
/// hostile images (RangeError from a mutated header included) return false and
/// the cause is logged.
Future<bool> isSacdIso(String path) async {
  if (!AudioFormats.isSacdIsoPath(path)) return false;
  final file = File(path);
  Iso9660Reader? reader;
  try {
    if (!await file.exists()) return false;
    reader = await Iso9660Reader.open(file);
    final area = await reader.lookupPath(SacdLayout.directoryName);
    if (area == null || !area.isDirectory) return false;
    final children = await reader.list(area);
    for (final child in children) {
      if (!child.isDirectory && SacdLayout.isAreaTocFileName(child.name)) {
        return true;
      }
    }
    return false;
  } catch (error, stack) {
    // Catch Object, not just IsoFormatException/FileSystemException: the probe
    // must also survive a platform file error or a programming bug in a parser
    // without failing a library scan.
    ErrorLogger.log(
      'Rejected image without a usable ISO9660/SACD structure',
      error: error,
      stackTrace: stack,
      category: 'SacdIso',
    );
    return false;
  } finally {
    try {
      await reader?.close();
    } catch (error, stack) {
      ErrorLogger.log(
        'Could not close a probed SACD image',
        error: error,
        stackTrace: stack,
        category: 'SacdIso',
      );
    }
  }
}
