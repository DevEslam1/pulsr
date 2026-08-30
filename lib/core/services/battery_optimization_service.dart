// lib/core/services/battery_optimization_service.dart
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
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations').timeout(const Duration(seconds: 2));
      // MIUI and some OEMs return null for non-standard POWER_SERVICE; treat null as whitelisted to avoid perpetual card
      if (isIgnoring == null) return true;
      return isIgnoring;
    } on PlatformException {
      // Platform channel missing or OEM quirk - assume whitelisted to avoid spam
      return true;
    } catch (_) {
      // Timeout after 2s - assume not whitelisted conservatively but avoid crash
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

  static Future<bool> openBatteryOptimizationSettings() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final res = await _channel
          .invokeMethod<bool>('openBatteryOptimizationSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }


  static Future<String> getDeviceManufacturer() async {
    if (kIsWeb || !Platform.isAndroid) return '';
    try {
      final m = await _channel.invokeMethod<String>('getDeviceManufacturer').timeout(const Duration(seconds: 2));
      return m?.toLowerCase() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<int> getBatteryLevel() async {
    if (kIsWeb || !Platform.isAndroid) return 100;
    try {
      final level = await _channel.invokeMethod<int>('getBatteryLevel').timeout(const Duration(seconds: 2));
      return level ?? 100;
    } catch (_) {
      return 100;
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
