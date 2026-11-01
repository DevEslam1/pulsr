import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/channels.dart';

class BatteryOptimizationService {
  static const MethodChannel _channel = MethodChannel(PulsrChannels.battery);
  static const String prefDismissedKey = 'battery_opt_card_dismissed';

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final isIgnoring =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return isIgnoring ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final res = await _channel
          .invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openOemBatterySettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('openOemBatterySettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> getDeviceManufacturer() async {
    if (kIsWeb || !Platform.isAndroid) return '';
    try {
      final m = await _channel.invokeMethod<String>('getDeviceManufacturer');
      return m?.toLowerCase() ?? '';
    } catch (_) {
      return '';
    }
  }

  static final StreamController<int> _batteryController =
      StreamController<int>.broadcast();

  /// Event-driven stream of battery level percentage updates (0..100).
  static Stream<int> get onBatteryChanged => _batteryController.stream;

  /// Pushes a battery level reading to active listeners.
  static void notifyBatteryChanged(int level) {
    if (!_batteryController.isClosed) {
      _batteryController.add(level.clamp(0, 100));
    }
  }

  static Future<int?> getBatteryLevel() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final level = await _channel.invokeMethod<int>('getBatteryLevel');
      if (level != null) notifyBatteryChanged(level);
      return level;
    } catch (_) {
      return null;
    }
  }

  /// Queries total device physical RAM in bytes via platform channel.
  static Future<int?> getTotalRamBytes() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final ram = await _channel.invokeMethod<int>('getTotalRamBytes');
      return ram;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isCardDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefDismissedKey) ?? false;
  }

  static Future<void> dismissCard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefDismissedKey, true);
  }

  static bool isAggressiveOem(String manufacturer) {
    final m = manufacturer.toLowerCase();
    return m.contains('xiaomi') ||
        m.contains('redmi') ||
        m.contains('poco') ||
        m.contains('oppo') ||
        m.contains('realme') ||
        m.contains('vivo') ||
        m.contains('iqoo') ||
        m.contains('huawei') ||
        m.contains('honor') ||
        m.contains('samsung') ||
        m.contains('oneplus');
  }

  static String getDontKillMyAppUrl(String manufacturer) {
    final m = manufacturer.toLowerCase();
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return 'https://dontkillmyapp.com/xiaomi';
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return 'https://dontkillmyapp.com/huawei';
    }
    if (m.contains('oppo') || m.contains('realme')) {
      return 'https://dontkillmyapp.com/oppo';
    }
    if (m.contains('vivo') || m.contains('iqoo')) {
      return 'https://dontkillmyapp.com/vivo';
    }
    if (m.contains('samsung')) {
      return 'https://dontkillmyapp.com/samsung';
    }
    if (m.contains('oneplus')) {
      return 'https://dontkillmyapp.com/oneplus';
    }
    return 'https://dontkillmyapp.com';
  }
}
