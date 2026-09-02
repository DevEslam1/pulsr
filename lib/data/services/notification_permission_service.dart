// lib/data/services/notification_permission_service.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/channels.dart';
import '../../domain/services/notification_permission_service.dart';

@LazySingleton(as: INotificationPermissionService)
class NotificationPermissionService implements INotificationPermissionService {
  int? _cachedSdkInt;

  Future<int> _getSdkInt() async {
    if (_cachedSdkInt != null) return _cachedSdkInt!;
    if (!Platform.isAndroid) {
      _cachedSdkInt = 0;
      return 0;
    }
    try {
      final sdk = await const MethodChannel(PulsrChannels.audioEffects)
          .invokeMethod<int>('getSdkInt')
          .timeout(const Duration(seconds: 1));
      _cachedSdkInt = sdk ?? 33;
    } catch (_) {
      _cachedSdkInt = 33;
    }
    return _cachedSdkInt!;
  }

  @override
  Future<bool> checkPermission() async {
    if (!Platform.isAndroid) return true;
    final sdk = await _getSdkInt();
    if (sdk < 33) return true; // Pre-Android 13: POST_NOTIFICATIONS granted automatically
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  @override
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    final sdk = await _getSdkInt();
    if (sdk < 33) return true;
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  @override
  Future<bool> shouldShowRationale() async {
    if (!Platform.isAndroid) return false;
    final sdk = await _getSdkInt();
    if (sdk < 33) return false;
    return await Permission.notification.shouldShowRequestRationale;
  }
}
