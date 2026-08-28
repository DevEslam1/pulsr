// lib/domain/models/download_settings.dart
import 'package:shared_preferences/shared_preferences.dart';

class DownloadSettings {
  final bool wifiOnly;
  final String quality; // high / medium / low
  final int maxConcurrent; // 1..5
  final String? downloadLocation; // SAF uri or null for default Music/
  final int progressTimeoutWindowSeconds; // default 30s

  const DownloadSettings({
    this.wifiOnly = false,
    this.quality = 'high',
    this.maxConcurrent = 3,
    this.downloadLocation,
    this.progressTimeoutWindowSeconds = 30,
  });

  factory DownloadSettings.defaultSettings() => const DownloadSettings();

  static const _kWifi = 'setting_wifi_only_mode';
  static const _kQuality = 'setting_download_quality';
  static const _kConcurrency = 'setting_download_max_concurrent';
  static const _kLocation = 'setting_download_location';
  static const _kProgressTimeout = 'setting_download_progress_timeout';

  static Future<DownloadSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return DownloadSettings(
      wifiOnly: prefs.getBool(_kWifi) ?? false,
      quality: prefs.getString(_kQuality) ?? 'high',
      maxConcurrent: prefs.getInt(_kConcurrency) ?? 3,
      downloadLocation: prefs.getString(_kLocation),
      progressTimeoutWindowSeconds: prefs.getInt(_kProgressTimeout) ?? 30,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWifi, wifiOnly);
    await prefs.setString(_kQuality, quality);
    await prefs.setInt(_kConcurrency, maxConcurrent.clamp(1, 5));
    await prefs.setInt(_kProgressTimeout, progressTimeoutWindowSeconds);
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
    int? progressTimeoutWindowSeconds,
  }) =>
      DownloadSettings(
        wifiOnly: wifiOnly ?? this.wifiOnly,
        quality: quality ?? this.quality,
        maxConcurrent: maxConcurrent ?? this.maxConcurrent,
        downloadLocation: downloadLocation ?? this.downloadLocation,
        progressTimeoutWindowSeconds:
            progressTimeoutWindowSeconds ?? this.progressTimeoutWindowSeconds,
      );
}
