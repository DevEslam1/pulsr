// lib/domain/services/notification_permission_service.dart
abstract class INotificationPermissionService {
  Future<bool> checkPermission();
  Future<bool> requestPermission();
  Future<bool> shouldShowRationale();
}
