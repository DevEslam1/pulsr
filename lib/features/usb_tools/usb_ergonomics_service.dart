// lib/features/usb_tools/usb_ergonomics_service.dart
//
// Glue between the USB quirk store, the attached DAC and the native ergonomics
// plugin. It watches UsbExclusiveService's status stream, resolves the profile
// that applies to the attached device, pushes it to
// `com.pulsr.music/usb_ergonomics`, and publishes one immutable state object for
// the screen.
//
// Every channel call is best-effort: a missing plugin (other platforms, or a
// build where the plugin is not registered yet) or a PlatformException is
// logged and turned into [ErgonomicsState.lastError]. Nothing in this file
// throws at a caller.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mutex/mutex.dart';

import '../../core/utils/error_logger.dart';
import '../../data/services/usb_exclusive_service.dart';
import 'usb_ergonomics_strings.dart';
import 'usb_quirk_profile.dart';
import 'usb_quirk_store.dart';

/// Signature of an injectable method-channel invoker.
///
/// Production uses [UsbErgonomicsService.channel]; tests pass a fake that
/// records calls and can reply (or throw) synchronously.
typedef ErgonomicsInvoker = Future<Object?> Function(MethodCall call);

/// HID consumer-control state reported by the native plugin.
@immutable
class HidStatus {
  /// Creates a HID status snapshot.
  const HidStatus({
    this.claimed = false,
    this.consumerControl = false,
    this.lastButton,
    this.detail,
  });

  /// Reads the map returned by the native `getHidStatus` method.
  factory HidStatus.fromMap(Map<dynamic, dynamic> map) {
    final button = map['lastButton'];
    final detail = map['detail'];
    return HidStatus(
      claimed: map['claimed'] == true,
      consumerControl: map['consumerControl'] == true,
      lastButton: button is String && button.isNotEmpty ? button : null,
      detail: detail is String && detail.isNotEmpty ? detail : null,
    );
  }

  /// Nothing claimed, nothing known.
  static const HidStatus none = HidStatus();

  /// Whether the plugin currently holds the HID interfaces.
  final bool claimed;

  /// Whether a consumer-control collection (usage page 0x0C) was found.
  final bool consumerControl;

  /// Last media usage the plugin decoded (`play_pause`, `next`, ...).
  final String? lastButton;

  /// Native explanation when the claim could not be made.
  final String? detail;

  /// One-line description for the status row.
  String describe() {
    if (!claimed) {
      return detail ?? UsbErgonomicsStrings.hidNotClaimed;
    }
    final base = consumerControl
        ? UsbErgonomicsStrings.hidClaimed
        : UsbErgonomicsStrings.hidClaimedNoConsumer;
    return lastButton == null ? base : '$base - $lastButton';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HidStatus &&
          other.claimed == claimed &&
          other.consumerControl == consumerControl &&
          other.lastButton == lastButton &&
          other.detail == detail;

  @override
  int get hashCode => Object.hash(claimed, consumerControl, lastButton, detail);
}

/// Immutable snapshot the ergonomics screen renders.
@immutable
class ErgonomicsState {
  /// Creates a state snapshot.
  const ErgonomicsState({
    this.attached = false,
    this.deviceLabel,
    this.deviceVid,
    this.devicePid,
    this.deviceId,
    this.quirk,
    this.busSpeedMbps,
    this.hid = HidStatus.none,
    this.lastError,
  });

  /// Nothing attached, nothing known.
  static const ErgonomicsState empty = ErgonomicsState();

  /// Whether a USB audio device is attached.
  final bool attached;

  /// Human name of the attached device.
  final String? deviceLabel;

  /// USB vendor id of the attached device, when known.
  final int? deviceVid;

  /// USB product id of the attached device, when known.
  final int? devicePid;

  /// Android `UsbDevice.deviceId` of the attached device, when known.
  ///
  /// Used to probe the exact physical device instead of the first sysfs entry
  /// with the same vendor/product ids.
  final int? deviceId;

  /// Profile resolved for the attached device (per-device entry, else global
  /// defaults, else null for "no profile stored").
  final UsbQuirkProfile? quirk;

  /// Last measured bus speed in Mbps; null until probed.
  final double? busSpeedMbps;

  /// HID consumer-control status.
  final HidStatus hid;

  /// Last channel failure, cleared by the next successful call.
  final String? lastError;

  /// Whether any part of the state is usable.
  bool get hasDevice => attached;

  /// Copy with selected fields replaced.
  ///
  /// [quirk], [busSpeedMbps] and [lastError] accept an explicit null so the
  /// service can clear them on detach.
  ErgonomicsState copyWith({
    bool? attached,
    String? deviceLabel,
    int? deviceVid,
    int? devicePid,
    Object? deviceId = _unset,
    Object? quirk = _unset,
    Object? busSpeedMbps = _unset,
    HidStatus? hid,
    Object? lastError = _unset,
  }) {
    return ErgonomicsState(
      attached: attached ?? this.attached,
      deviceLabel: deviceLabel ?? this.deviceLabel,
      deviceVid: deviceVid ?? this.deviceVid,
      devicePid: devicePid ?? this.devicePid,
      deviceId: identical(deviceId, _unset)
          ? this.deviceId
          : deviceId as int?,
      quirk: identical(quirk, _unset) ? this.quirk : quirk as UsbQuirkProfile?,
      busSpeedMbps: identical(busSpeedMbps, _unset)
          ? this.busSpeedMbps
          : busSpeedMbps as double?,
      hid: hid ?? this.hid,
      lastError: identical(lastError, _unset)
          ? this.lastError
          : lastError as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErgonomicsState &&
          other.attached == attached &&
          other.deviceLabel == deviceLabel &&
          other.deviceVid == deviceVid &&
          other.devicePid == devicePid &&
          other.deviceId == deviceId &&
          other.quirk == quirk &&
          other.busSpeedMbps == busSpeedMbps &&
          other.hid == hid &&
          other.lastError == lastError;

  @override
  int get hashCode => Object.hash(
        attached,
        deviceLabel,
        deviceVid,
        devicePid,
        deviceId,
        quirk,
        busSpeedMbps,
        hid,
        lastError,
      );
}

/// Sentinel so [ErgonomicsState.copyWith] can distinguish "unchanged" from
/// "clear this field".
const Object _unset = Object();

/// Owns the quirk profile that applies to the attached DAC.
class UsbErgonomicsService extends ChangeNotifier {
  /// Creates the service.
  ///
  /// [store] is the quirk store (injected so the caller owns the
  /// [SharedPreferences] instance). [statusStream] and [statusReader] default
  /// to [UsbExclusiveService]; tests override them to avoid platform channels.
  /// [invoker] defaults to [channel].
  UsbErgonomicsService({
    required UsbQuirkStore store,
    UsbExclusiveService? usb,
    Stream<UsbExclusiveStatus>? statusStream,
    Future<UsbExclusiveStatus> Function()? statusReader,
    ErgonomicsInvoker? invoker,
  })  : _store = store,
        _usb = usb ?? (statusStream == null ? UsbExclusiveService() : null),
        _statusStream = statusStream,
        _statusReader = statusReader,
        _invoker = invoker ?? _invokeOnChannel;

  /// Native channel the ergonomics plugin listens on.
  static const MethodChannel channel =
      MethodChannel('com.pulsr.music/usb_ergonomics');

  /// Method that pushes a profile to the native side.
  static const String applyMethod = 'applyQuirks';

  /// Method that reads the measured bus speed.
  static const String probeMethod = 'probeBusSpeed';

  /// Method that reads HID consumer-control status.
  static const String hidMethod = 'getHidStatus';

  /// Method that returns the streaming interface to alternate setting 0.
  static const String resetAltMethod = 'resetAltSetting';

  final UsbQuirkStore _store;
  final UsbExclusiveService? _usb;
  final Stream<UsbExclusiveStatus>? _statusStream;
  final Future<UsbExclusiveStatus> Function()? _statusReader;
  final ErgonomicsInvoker _invoker;

  StreamSubscription<UsbExclusiveStatus>? _subscription;
  ErgonomicsState _state = ErgonomicsState.empty;
  String? _appliedSignature;
  bool _started = false;
  final Mutex _opMutex = Mutex();
  bool _disposed = false;

  /// Current snapshot; never null.
  ErgonomicsState get state => _state;

  /// The store backing this service, for the editor's list and delete.
  UsbQuirkStore get store => _store;

  /// Subscribes to the status stream and reads the current status once.
  ///
  /// Idempotent; safe to call from `initState`.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final stream = _statusStream ?? _usb?.statusStream;
    if (stream != null) {
      _subscription = stream.listen(
        (status) => unawaited(_onStatus(status)),
        onError: (Object e, StackTrace st) {
          _log('USB ergonomics status stream failed', e, st);
        },
        cancelOnError: false,
      );
    }
    final readStatus = _statusReader ?? _usb?.getStatus;
    if (readStatus == null) return;
    try {
      final status = await readStatus();
      await _onStatus(status);
    } catch (e, st) {
      _log('Reading the initial USB status failed', e, st);
    }
  }

  /// Re-reads the device status (after a permission grant, for example).
  Future<void> refresh() async {
    final readStatus = _statusReader ?? _usb?.getStatus;
    if (readStatus == null) return;
    try {
      await _onStatus(await readStatus());
    } catch (e, st) {
      _log('Refreshing the USB status failed', e, st);
    }
  }

  /// Stores [profile] and, when it belongs to the attached DAC, pushes it to
  /// the native side.
  ///
  /// Returns false when the store rejected the write; the native side is left
  /// on the previously applied profile in that case. Editing a profile for a
  /// device that is not the one currently attached only persists the entry (so
  /// the list refreshes); it must not replace [ErgonomicsState.quirk] or reach
  /// the native side, which would apply another DAC's settings to this one.
  Future<bool> saveQuirk(UsbQuirkProfile profile) =>
      _opMutex.protect(() async {
        final stored = await _store.put(profile);
        if (!stored) {
          _emit(_state.copyWith(lastError: UsbErgonomicsStrings.saveFailed));
          return false;
        }
        if (!_profileAppliesToAttachedDevice(profile)) {
          // Persisted only: the attached device's resolution stays as it was.
          _emit(_state.copyWith(lastError: null));
          return true;
        }
        // Drop the signature so the very same profile is re-applied after an edit
        // that only touched the label or was made while detached.
        _appliedSignature = null;
        _emit(_state.copyWith(quirk: profile, lastError: null));
        if (_state.attached) await _applyActive();
        return true;
      });

  /// Whether [profile] is the stored entry for the DAC attached right now.
  bool _profileAppliesToAttachedDevice(UsbQuirkProfile profile) {
    if (!_state.attached) return false;
    final vid = _state.deviceVid;
    final pid = _state.devicePid;
    if (vid == null || pid == null) return false;
    return UsbQuirkProfile.deviceKey(vid, pid) == profile.key;
  }

  /// Removes the stored entry for the attached device and applies the fallback.
  Future<bool> deleteQuirk() => _opMutex.protect(() async {
        final vid = _state.deviceVid;
        final pid = _state.devicePid;
        if (vid == null || pid == null) {
          _emit(_state.copyWith(lastError: UsbErgonomicsStrings.noDeviceId));
          return false;
        }
        final removed = await _store.remove(vid, pid);
        if (!removed) {
          _emit(_state.copyWith(lastError: UsbErgonomicsStrings.deleteFailed));
          return false;
        }
        final fallback = _store.profileForDevice(vid, pid);
        _appliedSignature = null;
        _emit(_state.copyWith(quirk: fallback, lastError: null));
        if (_state.attached) await _applyActive();
        return true;
      });

  /// Measures the bus speed of the attached device.
  ///
  /// Returns the Mbps value, or null when nothing is attached or the probe
  /// failed. Failures land in [ErgonomicsState.lastError].
  Future<double?> probeBusSpeed() async {
    final vid = _state.deviceVid;
    final pid = _state.devicePid;
    if (!_state.attached) return null;
    final result = await _invoke(probeMethod, <String, Object?>{
      'vid': vid,
      'pid': pid,
      'deviceId': _state.deviceId,
    });
    final mbps = _readDouble(result, 'mbps');
    if (mbps == null) {
      if (_state.lastError == null) {
        _emit(_state.copyWith(
          lastError: UsbErgonomicsStrings.busSpeedUnavailable,
        ));
      }
      return null;
    }
    _emit(_state.copyWith(busSpeedMbps: mbps, lastError: null));
    return mbps;
  }

  /// Reads the native HID consumer-control status.
  Future<void> refreshHidStatus() async {
    final result = await _invoke(hidMethod);
    if (result is Map) _emit(_state.copyWith(hid: HidStatus.fromMap(result)));
  }

  /// Asks the native side to return the streaming interface to alt setting 0.
  ///
  /// Returns true only when the plugin reported success.
  Future<bool> resetAltSetting() async {
    if (!_state.attached) return false;
    final result = await _invoke(resetAltMethod, <String, Object?>{
      'vid': _state.deviceVid,
      'pid': _state.devicePid,
      'deviceId': _state.deviceId,
    });
    final ok = result is Map && result['ok'] == true;
    if (!ok && _state.lastError == null) {
      final detail = result is Map ? result['detail'] : null;
      _emit(_state.copyWith(
        lastError: detail is String && detail.isNotEmpty
            ? detail
            : UsbErgonomicsStrings.resetAltFailed,
      ));
    }
    return ok;
  }

  /// Whether [signature] differs from the last applied profile for the same
  /// device; exposed for tests that assert re-apply behaviour.
  @visibleForTesting
  bool get hasAppliedProfile => _appliedSignature != null;

  @override
  void dispose() {
    _disposed = true;
    final sub = _subscription;
    _subscription = null;
    if (sub != null) unawaited(sub.cancel());
    super.dispose();
  }

  // ---- internals ----

  Future<void> _onStatus(UsbExclusiveStatus status) =>
      _opMutex.protect(() async {
        if (_disposed) return;
        final vid = status.vendorId;
        final pid = status.productId;
        final quirk = _store.profileForDevice(vid, pid);
        final label = status.deviceName ??
            (vid != null && pid != null
                ? UsbQuirkProfile.deviceKey(vid, pid)
                : UsbErgonomicsStrings.unknownDevice);
        if (!status.attached) {
          _appliedSignature = null;
          _emit(_state.copyWith(
            attached: false,
            deviceLabel: label,
            deviceVid: vid,
            devicePid: pid,
            deviceId: null,
            quirk: quirk,
            busSpeedMbps: null,
            hid: HidStatus.none,
            lastError: null,
          ));
          return;
        }
        final deviceChanged = _state.deviceVid != vid ||
            _state.devicePid != pid ||
            _state.deviceId != status.deviceId;
        if (deviceChanged) {
          _appliedSignature = null;
        }
        _emit(_state.copyWith(
          attached: true,
          deviceLabel: label,
          deviceVid: vid,
          devicePid: pid,
          deviceId: status.deviceId,
          quirk: quirk,
          busSpeedMbps: deviceChanged ? null : _state.busSpeedMbps,
          hid: deviceChanged ? HidStatus.none : _state.hid,
          lastError: deviceChanged ? null : _state.lastError,
        ));
        await _applyActive(force: false);
      });

  /// Pushes the resolved profile when it differs from what was last applied.
  Future<void> _applyActive({bool force = true}) async {
    final vid = _state.deviceVid;
    final pid = _state.devicePid;
    final deviceId = _state.deviceId;
    final quirk = _state.quirk;
    final signature = _signature(vid, pid, deviceId, quirk);
    if (!force && signature == _appliedSignature) return;
    final applied = await _pushQuirk(
      vid: vid,
      pid: pid,
      deviceId: deviceId,
      quirk: quirk,
    );
    if (applied) {
      _appliedSignature = signature;
      await refreshHidStatus();
    }
  }

  Future<bool> _pushQuirk({
    required int? vid,
    required int? pid,
    required int? deviceId,
    required UsbQuirkProfile? quirk,
  }) async {
    final profile = quirk ?? UsbQuirkProfile.defaults;
    final payload = <String, Object?>{
      ...profile.toJson(),
      'vid': vid ?? profile.vid,
      'pid': pid ?? profile.pid,
      'deviceId': deviceId,
    };
    // The exclusive plugin owns the direct audio path; it validates the same
    // document again and applies only the safe transport quirks. A missing
    // handler is expected on older builds and never fails the ergonomics push.
    final usb = _usb;
    if (usb != null) {
      try {
        await usb.applyQuirkProfile(payload);
      } catch (e, st) {
        _log('USB quirk profile push failed', e, st);
      }
    }
    final result = await _invoke(applyMethod, payload);
    if (result is Map) {
      final error = result['error'];
      if (error != null) {
        _emit(_state.copyWith(
          lastError: error is String && error.isNotEmpty
              ? error
              : UsbErgonomicsStrings.applyFailed,
        ));
        return false;
      }
      return result['ok'] != false;
    }
    // No reply means the plugin is absent or crashed; nothing was confirmed.
    return result == true;
  }

  String _signature(int? vid, int? pid, int? deviceId, UsbQuirkProfile? quirk) {
    final q = quirk;
    final fields = q == null
        ? const <Object?>['none']
        : <Object?>[
            q.hidEnabled,
            q.silenceMs,
            q.force16Bit,
            q.altResetOnStop,
            q.transferSizeBytes,
            q.bufferMs,
            q.disableExplicitFeedback,
            q.preferredSelectorPin,
            q.volumeCalibrationDb,
            q.uac1ReassertAfterAlt,
            q.disableUac2ClockSwitch,
          ];
    return <String>[
      '${vid ?? -1}:${pid ?? -1}:${deviceId ?? -1}',
      ...fields.map((f) => '$f'),
    ].join('|');
  }

  Future<Object?> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (_disposed) return null;
    try {
      return await _invoker(MethodCall(method, arguments));
    } on MissingPluginException catch (e, st) {
      // Expected off-Android and in widget tests: log once per call site.
      _log('USB ergonomics method "$method" has no native handler', e, st);
      return null;
    } on PlatformException catch (e, st) {
      _log('USB ergonomics method "$method" failed', e, st);
      _emit(_state.copyWith(
        lastError: e.message ?? UsbErgonomicsStrings.applyFailed,
      ));
      return null;
    } catch (e, st) {
      _log('USB ergonomics method "$method" threw', e, st);
      _emit(_state.copyWith(lastError: UsbErgonomicsStrings.applyFailed));
      return null;
    }
  }

  static double? _readDouble(Object? result, String key) {
    if (result is! Map) return null;
    final value = result[key];
    if (value is num) return value.toDouble();
    return null;
  }

  void _emit(ErgonomicsState next) {
    if (_disposed) return;
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  void _log(String message, Object error, StackTrace stackTrace) {
    ErrorLogger.log(
      message,
      error: error,
      stackTrace: stackTrace,
      category: 'UsbErgonomics',
    );
  }

  static Future<Object?> _invokeOnChannel(MethodCall call) =>
      channel.invokeMethod<Object?>(call.method, call.arguments);
}
