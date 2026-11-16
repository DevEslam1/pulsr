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
/// `SACD` directory containing at least one `.TOC` file. Unreadable, missing or
/// malformed images return false; the cause is logged, never thrown.
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
  } on IsoFormatException catch (error) {
    ErrorLogger.log(
      'Rejected image without a usable ISO9660/SACD structure',
      error: error,
      category: 'SacdIso',
    );
    return false;
  } on FileSystemException catch (error) {
    ErrorLogger.log(
      'Could not read image while probing for SACD',
      error: error,
      category: 'SacdIso',
    );
    return false;
  } finally {
    await reader?.close();
  }
}
