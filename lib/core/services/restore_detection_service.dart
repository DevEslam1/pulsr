import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_logger.dart';
import '../../data/scanner/media_scanner_service.dart';

class RestoreDetectionService {
  static const String _tokenFileName = 'app_instance_token';

  static int computeCrc32(String input) {
    final bytes = utf8.encode(input);
    int crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1 != 0) ? (crc >> 1) ^ 0xEDB88320 : (crc >> 1);
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static Future<bool> checkAndHandleRestore(
      MediaScannerService scannerService) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final tokenFile = File('${docDir.path}/$_tokenFileName');
      final prefs = await SharedPreferences.getInstance();
      final isOnboardingCompleted =
          prefs.getBool('onboarding_completed') ?? false;

      bool validToken = false;
      if (await tokenFile.exists()) {
        try {
          final content = await tokenFile.readAsString();
          final parts = content.trim().split('|');
          if (parts.length == 2) {
            final expectedCrc = computeCrc32(parts[0]).toString();
            if (parts[1] == expectedCrc) {
              validToken = true;
            }
          }
        } catch (_) {}
      }

      if (!validToken) {
        // Create token file with CRC32 checksum so subsequent launches know this instance is established
        final now = DateTime.now().toIso8601String();
        final tokenWithCrc = '$now|${computeCrc32(now)}';
        await tokenFile.writeAsString(tokenWithCrc);

        if (isOnboardingCompleted) {
          // Restored from backup without local database!
          ErrorLogger.log(
            'Restore detected from cloud backup/device transfer. Triggering full library rescan.',
            category: 'Restore',
          );
          final hasPerm = await scannerService.checkPermission();
          if (hasPerm) {
            await scannerService.scanDeviceLibrary();
          }
          return true;
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Error checking restore status',
          error: e, stackTrace: st, category: 'Restore');
    }
    return false;
  }
}
