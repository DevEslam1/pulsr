// lib/core/constants/app_timing.dart

abstract class AppTiming {
  static const Duration debounceShort = Duration(milliseconds: 200);
  static const Duration debounceMedium = Duration(milliseconds: 300);
  static const Duration debounceLong = Duration(milliseconds: 500);
  static const Duration throttleProgress = Duration(milliseconds: 100);
  static const Duration navThrottle = Duration(milliseconds: 200);
  static const Duration staggerDelay = Duration(milliseconds: 500);
}
