// lib/domain/models/download_settings.dart
// DL-13: NetworkPolicy resolution rules for wifiOnly, cellular failover, and metered connections.

import 'package:shared_preferences/shared_preferences.dart';

/// Where the download engine may consume network bandwidth.
enum NetworkPolicy {
  wifiOnly,
  allowCellularFailover,
  alwaysAllow;

  bool shouldAllowDownload({
    required bool isWifi,
    required bool isMetered,
  }) {
    return switch (this) {
      NetworkPolicy.wifiOnly => isWifi,
      NetworkPolicy.allowCellularFailover => isWifi || !isMetered,
      NetworkPolicy.alwaysAllow => true,
    };
  }
}

/// User preferences for the download engine.
///
/// Pure value object: persistence goes through [load]/[save]; both round-trip
/// every field and clamp numeric bounds so a hand-edited store cannot poison
/// the queue.
class DownloadSettings {
  final bool wifiOnly;
  final NetworkPolicy networkPolicy;
  final String quality; // high / medium / low
  final int maxConcurrent; // 1..5
  final String? downloadLocation; // SAF uri or null for default Music/
  final int progressTimeoutWindowSeconds; // default 30s

  static const int minConcurrent = 1;
  static const int maxConcurrentLimit = 5;
  static const int minProgressTimeoutSeconds = 10;
  static const int maxProgressTimeoutSeconds = 3600;
  static const int defaultProgressTimeoutSeconds = 30;

  const DownloadSettings({
    this.wifiOnly = false,
    this.networkPolicy = NetworkPolicy.allowCellularFailover,
    this.quality = 'high',
    this.maxConcurrent = 3,
    this.downloadLocation,
    this.progressTimeoutWindowSeconds = defaultProgressTimeoutSeconds,
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
      maxConcurrent:
          (prefs.getInt(_kConcurrency) ?? 3).clamp(minConcurrent, maxConcurrentLimit),
      downloadLocation: prefs.getString(_kLocation),
      progressTimeoutWindowSeconds:
          (prefs.getInt(_kProgressTimeout) ?? defaultProgressTimeoutSeconds)
              .clamp(minProgressTimeoutSeconds, maxProgressTimeoutSeconds),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWifi, wifiOnly);
    await prefs.setString(_kQuality, quality);
    await prefs.setInt(
        _kConcurrency, maxConcurrent.clamp(minConcurrent, maxConcurrentLimit));
    await prefs.setInt(
        _kProgressTimeout,
        progressTimeoutWindowSeconds
            .clamp(minProgressTimeoutSeconds, maxProgressTimeoutSeconds));
    if (downloadLocation != null) {
      await prefs.setString(_kLocation, downloadLocation!);
    } else {
      await prefs.remove(_kLocation);
    }
  }

  DownloadSettings copyWith({
    bool? wifiOnly,
    NetworkPolicy? networkPolicy,
    String? quality,
    int? maxConcurrent,
    String? downloadLocation,
    int? progressTimeoutWindowSeconds,
  }) =>
      DownloadSettings(
        wifiOnly: wifiOnly ?? this.wifiOnly,
        networkPolicy: networkPolicy ?? this.networkPolicy,
        quality: quality ?? this.quality,
        maxConcurrent: maxConcurrent ?? this.maxConcurrent,
        downloadLocation: downloadLocation ?? this.downloadLocation,
        progressTimeoutWindowSeconds:
            progressTimeoutWindowSeconds ?? this.progressTimeoutWindowSeconds,
      );
}
