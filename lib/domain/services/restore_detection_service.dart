// lib/core/services/restore_detection_service.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';
import '../../data/scanner/media_scanner_service.dart';

class RestoreDetectionService {
  static const String _tokenFileName = 'app_instance_token';

  static Future<bool> checkAndHandleRestore(
      MediaScannerService scannerService) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final tokenFile = File('${docDir.path}/$_tokenFileName');
      final prefs = await SharedPreferences.getInstance();
      final isOnboardingCompleted =
          prefs.getBool('onboarding_completed') ?? false;

      final tokenExists = await tokenFile.exists();

      if (!tokenExists) {
        // Create token file so subsequent launches know this instance is established
        await tokenFile.writeAsString(DateTime.now().toIso8601String());

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

