// lib/features/audio_profiles/audio_profile_bootstrap.dart
//
// Startup glue for the audio-profile scheduler (P0-1.8).
//
// The service can apply a profile, but nothing ever called it: marking a
// profile as the default changed a preference and no more. This is the missing
// caller. It applies the default once after startup settings are ready and
// again when a USB DAC is attached — but only when the profile pins a
// vid/pid that the attached device matches.
//
// Every failure is logged and swallowed: a profile that cannot be read must
// never abort app startup or a route change.

import 'dart:async';

import '../../core/utils/error_logger.dart';
import '../../data/services/usb_exclusive_service.dart';
import 'audio_profile_service.dart';

/// Applies the default audio profile at startup and on USB attach.
class AudioProfileBootstrap {
  /// Creates the scheduler over [service].
  ///
  /// [usbExclusive] is injectable so tests can drive attachment changes
  /// without the platform channel.
  AudioProfileBootstrap({
    required AudioProfileService service,
    UsbExclusiveService? usbExclusive,
  })  : _service = service,
        _usb = usbExclusive ?? UsbExclusiveService();

  final AudioProfileService _service;
  final UsbExclusiveService _usb;

  StreamSubscription<UsbExclusiveStatus>? _statusSub;
  bool _started = false;
  bool _disposed = false;
  bool _applying = false;
  bool _lastAttached = false;
  UsbExclusiveStatus? _pendingUsbStatus;

  /// Whether the startup pass ran and the status listener is installed.
  bool get isStarted => _started && !_disposed;

  /// Runs the startup apply and starts watching for USB attachments.
  ///
  /// Idempotent: a second call does nothing. Returns the startup report when a
  /// profile was applied, otherwise `null`.
  Future<AudioProfileApplyReport?> start() async {
    if (_started || _disposed) return null;
    _started = true;

    UsbExclusiveStatus? status;
    try {
      status = await _usb.getStatus();
    } catch (e, st) {
      // No USB stack (desktop, tests, plugin missing): the startup apply still
      // runs, it just cannot be device-matched.
      ErrorLogger.log(
        'Reading the USB status for the audio-profile scheduler failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfiles',
      );
    }

    _lastAttached = status?.attached ?? false;

    try {
      _statusSub = _usb.statusStream.listen(
        (UsbExclusiveStatus next) => unawaited(_onUsbStatus(next)),
        onError: (Object error, StackTrace stackTrace) {
          ErrorLogger.log(
            'USB status stream failed in the audio-profile scheduler',
            error: error,
            stackTrace: stackTrace,
            category: 'AudioProfiles',
          );
        },
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Watching the USB status for the audio-profile scheduler failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfiles',
      );
    }

    final report = await _apply(
      startup: true,
      vid: status != null && status.attached ? status.vendorId : null,
      pid: status != null && status.attached ? status.productId : null,
      deviceKey: _deviceKey(status),
    );

    return report;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final StreamSubscription<UsbExclusiveStatus>? sub = _statusSub;
    _statusSub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  Future<void> _onUsbStatus(UsbExclusiveStatus status) async {
    if (_disposed) return;
    if (_applying) {
      _pendingUsbStatus = status;
      return;
    }
    await _handleUsbStatus(status);
  }

  Future<void> _handleUsbStatus(UsbExclusiveStatus status) async {
    if (_disposed) return;
    final bool attached = status.attached;
    if (attached == _lastAttached) return;
    _lastAttached = attached;

    if (!attached) {
      // A detached DAC frees the marker: plugging it back in is a new event
      // that should re-apply the profile the user assigned to it.
      try {
        await _service.clearLastAppliedMarker();
      } catch (e, st) {
        ErrorLogger.log(
          'Clearing the audio-profile marker on detach failed',
          error: e,
          stackTrace: st,
          category: 'AudioProfiles',
        );
      }
      return;
    }

    await _apply(
      startup: false,
      vid: status.vendorId,
      pid: status.productId,
      deviceKey: _deviceKey(status),
    );
  }

  Future<AudioProfileApplyReport?> _apply({
    required bool startup,
    int? vid,
    int? pid,
    String? deviceKey,
  }) async {
    if (_applying) return null;
    _applying = true;
    try {
      return await _service.applyDefaultProfile(
        startup: startup,
        deviceVid: vid,
        devicePid: pid,
        deviceKey: deviceKey,
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Applying the default audio profile failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfiles',
      );
      return null;
    } finally {
      _applying = false;
      if (_pendingUsbStatus != null && !_disposed) {
        final pending = _pendingUsbStatus!;
        _pendingUsbStatus = null;
        unawaited(_handleUsbStatus(pending));
      }
    }
  }

  String? _deviceKey(UsbExclusiveStatus? status) {
    if (status == null || !status.attached) return null;
    final vid = status.vendorId;
    final pid = status.productId;
    if (vid == null && pid == null) {
      return 'usb:${status.deviceName ?? status.deviceId ?? 'unknown'}';
    }
    return 'usb:$vid:$pid';
  }
}
