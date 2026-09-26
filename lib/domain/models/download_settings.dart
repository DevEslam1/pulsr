// lib/domain/models/download_settings.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart'; // FIX-A10: Import ErrorLogger for error reporting

class DownloadSettings {
  final bool wifiOnly;
  final String quality; // high / medium / low
  final int maxConcurrent; // 1..5
  final String? downloadLocation; // SAF uri or null for default Music/

  const DownloadSettings({
    this.wifiOnly = false,
    this.quality = 'high',
    this.maxConcurrent = 3,
    this.downloadLocation,
  });

  static const _kWifi = 'setting_wifi_only_mode';
  static const _kQuality = 'setting_download_quality';
  static const _kConcurrency = 'setting_download_max_concurrent';
  static const _kLocation = 'setting_download_location';

  static Future<DownloadSettings> load() async {
    try { // FIX-A10: Wrap load body in try/catch
      final prefs = await SharedPreferences.getInstance();
      return DownloadSettings(
        wifiOnly: prefs.getBool(_kWifi) ?? false,
        quality: prefs.getString('setting_streaming_quality') ??
            prefs.getString(_kQuality) ??
            'high',
        maxConcurrent: prefs.getInt(_kConcurrency) ?? 3,
        downloadLocation: prefs.getString(_kLocation),
      );
    } catch (e, st) { // FIX-A10: Log via ErrorLogger and return default settings
      ErrorLogger.log('DownloadSettings.load failed', error: e, stackTrace: st, category: 'DownloadSettings');
      return const DownloadSettings();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWifi, wifiOnly);
    await prefs.setString(_kQuality, quality);
    await prefs.setInt(_kConcurrency, maxConcurrent.clamp(1, 5));
    if (downloadLocation != null) {
      await prefs.setString(_kLocation, downloadLocation!);
    } else {
      await prefs.remove(_kLocation);
    }
  }

  DownloadSettings copyWith({
    bool? wifiOnly,
    String? quality,
    int? maxConcurrent,
    String? downloadLocation,
  }) =>
      DownloadSettings(
        wifiOnly: wifiOnly ?? this.wifiOnly,
        quality: quality ?? this.quality,
        maxConcurrent: maxConcurrent ?? this.maxConcurrent,
        downloadLocation: downloadLocation ?? this.downloadLocation,
      );
}
