// lib/features/settings/presentation/widgets/usb_dac_section.dart
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/feature_flags.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/di/injection.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/audio/hires_dac_bridge.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../data/services/usb_exclusive_service.dart';
import '../../../usb_tools/usb_quirk_store.dart';
import '../../../usb_tools/usb_stream_mode.dart';
import '../../../usb_tools/usb_stream_mode_selector.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import 'settings_tiles.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

/// USB DAC controls: hardware volume (UAC Feature Unit) plus the optional
/// exclusive-interface claim. Renders nothing on non-Android platforms or when
/// no USB audio device is attached.
class UsbDacSection extends StatefulWidget {
  final SettingsCubit cubit;
  final SettingsState state;

  const UsbDacSection({super.key, required this.cubit, required this.state});

  @override
  State<UsbDacSection> createState() => _UsbDacSectionState();
}

class _UsbDacSectionState extends State<UsbDacSection> {
  final UsbExclusiveService _service = UsbExclusiveService();

  /// The DAC's own attenuator. The bridge fails closed (null), and a null
  /// range keeps the legacy dB slider exactly as it was.
  final HiresDacBridge _dacBridge = const HiresDacBridge();
  StreamSubscription<UsbExclusiveStatus>? _sub;
  UsbExclusiveStatus _status = UsbExclusiveStatus.none;
  bool _busy = false;
  bool _streamingBusy = false;
  double? _pendingDb;

  // UAC2 volume, distinct from the legacy dB slider: the DAC reports its own
  // q8 range, and the control works in that range's 0…1 position. Unknown
  // until a query lands, which is why the legacy path stays the default.
  ({int minQ8, int maxQ8})? _uac2Range;
  double? _uac2Position;
  double? _pendingUac2Position;
  bool? _uac2Muted;
  // (deviceId, hasVolumeControl): re-query only when the device or the
  // advertised control changes, not on every status tick.
  (int?, bool)? _uac2Key;

  // Per-device clock architecture. Loaded from preferences once the device ids
  // are known; the selector itself stays presentational.
  UsbStreamModeStore? _modeStore;
  UsbStreamMode _streamMode = UsbStreamMode.bestEffort;
  bool _pullFlagEnabled = false;
  bool _asrcFlagEnabled = false;
  int? _modeLoadedForDeviceId;

  bool get _isAndroid => PlatformCapabilities.isAndroid;

  @override
  void initState() {
    super.initState();
    if (!_isAndroid) return;
    _sub = _service.statusStream.listen((s) {
      if (!mounted) return;
      setState(() => _status = s);
      _maybeLoadUac2Volume(s);
      if (s.deviceId != _modeLoadedForDeviceId) {
        unawaited(_loadStreamMode(s));
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await _service.getStatus();
    if (!mounted) return;
    setState(() => _status = s);
    _maybeLoadUac2Volume(s);
    if (s.deviceId != _modeLoadedForDeviceId) {
      // Never block a streaming toggle (or its busy flag) on preference I/O:
      // the selector is cosmetic until the next start, which re-resolves the
      // mode on the platform side anyway.
      unawaited(_loadStreamMode(s));
    }
  }

  /// Loads the rollout flags and this device's stored mode. A read failure
  /// leaves best effort selected: a missing preference never opts a user into
  /// an experimental clock path.
  Future<void> _loadStreamMode(UsbExclusiveStatus status) async {
    final vid = status.vendorId;
    final pid = status.productId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final flags = FeatureFlags(prefs: prefs);
      await flags.init();
      if (!mounted) return;
      setState(() {
        _modeStore = UsbStreamModeStore(prefs: prefs);
        _streamMode = (vid == null || pid == null)
            ? UsbStreamMode.bestEffort
            : _modeStore!.read(vid, pid);
        _pullFlagEnabled = flags.isEnabled(PrefsKeys.usbPullRenderer);
        _asrcFlagEnabled = flags.isEnabled(PrefsKeys.usbClockSyncAsrc);
        _modeLoadedForDeviceId = status.deviceId;
      });
      // The exclusive plugin persists quirks itself, but it can only persist a
      // document it has seen. Push the stored profile for this DAC so a profile
      // saved in a previous session is in force before the next start, without
      // requiring the ergonomics screen to be opened first.
      final quirk = UsbQuirkStore(prefs: prefs).profileForDevice(vid, pid);
      if (quirk != null && vid != null && pid != null) {
        unawaited(_service.applyQuirkProfile(<String, Object?>{
          ...quirk.toJson(),
          'vid': vid,
          'pid': pid,
        }));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _modeStore = null;
        _streamMode = UsbStreamMode.bestEffort;
        _pullFlagEnabled = false;
        _asrcFlagEnabled = false;
        _modeLoadedForDeviceId = status.deviceId;
      });
    }
  }

  /// Queries the DAC's UAC2 attenuator once per device/permission state.
  ///
  /// Nothing here may throw at the UI: the bridge already answers null on any
  /// failure, and a null range simply leaves the legacy dB slider in place.
  void _maybeLoadUac2Volume(UsbExclusiveStatus status) {
    if (!_isAndroid) return;
    if (!status.attached || !status.permitted) {
      _uac2Key = null;
      if (_uac2Range != null || _uac2Position != null) {
        setState(() {
          _uac2Range = null;
          _uac2Position = null;
          _pendingUac2Position = null;
        });
      }
      return;
    }
    final key = (status.deviceId, status.hasVolumeControl);
    if (key != _uac2Key) {
      _uac2Key = key;
      unawaited(_loadUac2Volume(status));
      return;
    }
    // Hardware keys / the front panel move the DAC without touching the app
    // volume. Mirror the status reading into this slider.
    final range = _uac2Range;
    final db = status.hardwareVolumeDb;
    if (range != null && db != null && _pendingUac2Position == null) {
      final minDb = range.minQ8 / 256.0;
      final maxDb = range.maxQ8 / 256.0;
      if (maxDb > minDb) {
        final position = ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
        if (_uac2Position == null || (_uac2Position! - position).abs() > 0.005) {
          setState(() => _uac2Position = position);
        }
      }
    }
    if (status.hasMuteControl &&
        status.hardwareMute != null &&
        _uac2Muted != status.hardwareMute) {
      setState(() => _uac2Muted = status.hardwareMute);
    }
  }

  Future<void> _loadUac2Volume(UsbExclusiveStatus status) async {
    ({int minQ8, int maxQ8})? range;
    num? raw;
    bool? muted;
    try {
      range = await _dacBridge.getUac2VolumeRange();
      if (range != null) {
        raw = await _dacBridge.getUac2HardwareVolume();
        muted = await _dacBridge.getUac2HardwareMute();
      }
    } catch (_) {
      range = null;
    }
    if (!mounted) return;
    setState(() {
      _uac2Range = range;
      _uac2Position = range == null
          ? null
          : _uac2PositionFrom(raw, range, status.hardwareVolumeDb);
      _pendingUac2Position = null;
      _uac2Muted = muted;
    });
  }

  Future<void> _toggleUac2Mute(bool muted) async {
    final ok = await _dacBridge.setUac2HardwareMute(muted);
    if (!mounted) return;
    if (ok) {
      setState(() => _uac2Muted = muted);
    }
  }

  /// Normalises a bridge reading against [range].
  ///
  /// The bridge may answer with a 0…1 position or a raw 1/256 dB value. A
  /// reading inside 0…1 is the position (a q8 gain of that magnitude would be
  /// 0.004 dB, not a real set point); exactly 0 is ambiguous (0 dB is unity),
  /// so it is resolved from the status snapshot and otherwise read as unity,
  /// never as silence. When the bridge cannot read at all, the snapshot's dB
  /// is the fallback: it is the same q8 scale and the same DAC.
  double? _uac2PositionFrom(
    num? raw,
    ({int minQ8, int maxQ8}) range,
    double? statusDb,
  ) {
    final span = range.maxQ8 - range.minQ8;
    if (span <= 0) return null;
    double fromQ8(double q8) => ((q8 - range.minQ8) / span).clamp(0.0, 1.0);
    if (raw != null && raw.isFinite) {
      final v = raw.toDouble();
      if (v > 0.0 && v <= 1.0) return v;
      if (v == 0.0 && statusDb != null && statusDb.isFinite) {
        return fromQ8(statusDb * 256.0);
      }
      return fromQ8(v);
    }
    if (statusDb != null && statusDb.isFinite) {
      return fromQ8(statusDb * 256.0);
    }
    return null;
  }

  /// Persists a new request for this DAC. The platform still re-checks flags
  /// and feedback support when the stream is (re)started.
  Future<void> _onStreamModeChanged(UsbStreamMode mode) async {
    final vid = _status.vendorId;
    final pid = _status.productId;
    final store = _modeStore;
    if (vid == null || pid == null || store == null) return;
    setState(() => _streamMode = mode);
    await store.write(vid, pid, mode);
  }

  Future<void> _onToggle(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (enabled) {
        if (!_status.permitted) {
          final granted = await _service.requestPermission();
          if (!granted) {
            if (mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                content: Text(context.l10n.usbPermDenied),
              ));
            }
            await _refresh();
            return;
          }
        }
        await _service.getStatus();
      }
      await widget.cubit.setUsbHardwareVolumeEnabled(enabled);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // FIX-M11: Check hardware volume is enabled and supported before setting volume
  Future<void> _commitVolume(double db) async {
    if (!widget.state.usbHardwareVolumeEnabled || !_status.hasVolumeControl) {
      return;
    }
    await _service.setHardwareVolume(db);
    final minDb = _status.minVolumeDb;
    final maxDb = _status.maxVolumeDb;
    if (minDb != null &&
        maxDb != null &&
        getIt.isRegistered<PulsrAudioHandler>()) {
      getIt<PulsrAudioHandler>().syncVolumeFromExternalHardwareDb(
        db,
        minDb: minDb,
        maxDb: maxDb,
      );
    }
    await _refresh();
  }

  /// Writes the DAC's own attenuator. The legacy service is deliberately not
  /// used here: mixing a dB write into a 0…1 control would move the DAC to a
  /// value the slider is not showing.
  Future<void> _commitUac2Volume(double position) async {
    final range = _uac2Range;
    if (range == null || !widget.state.usbHardwareVolumeEnabled) return;
    final previous = _uac2Position;
    setState(() => _pendingUac2Position = null);
    final applied = await _dacBridge.setUac2HardwareVolume(position);
    if (!mounted) return;
    if (!applied) {
      // A rejected write must not leave the slider parked on a value the DAC
      // never accepted.
      setState(() => _uac2Position = previous);
      return;
    }
    setState(() => _uac2Position = position);
    final minDb = range.minQ8 / 256.0;
    final maxDb = range.maxQ8 / 256.0;
    if (getIt.isRegistered<PulsrAudioHandler>()) {
      getIt<PulsrAudioHandler>().syncVolumeFromExternalHardwareDb(
        minDb + position * (maxDb - minDb),
        minDb: minDb,
        maxDb: maxDb,
      );
    }
    await _refresh();
  }

  /// One owner for the mode: SettingsCubit also arms the DSP bypass, crossfade
  /// exclusion, strict contract and rollback/teardown. Starting the sink here
  /// directly used to produce a "bit-perfect" stream with effects still live.
  Future<void> _toggleStreaming(bool enabled) async {
    if (_streamingBusy) return;
    setState(() => _streamingBusy = true);
    try {
      await widget.cubit.setBitPerfectOutput(enabled);
      if (!mounted) return;
      final failure = widget.cubit.state.errorMessage;
      if (enabled && failure != null) {
        PulsrToast.show(
          context,
          isError: true,
          duration: const Duration(seconds: 8),
          position: PulsrToastPosition.top,
          maxLines: 6,
          message: '${context.l10n.usbBpFailed}: $failure',
          // A refused claim is recoverable: keep the retry affordance the
          // exclusive-mode failure needs, routed through the same owner.
          actionLabel: context.l10n.retry,
          onActionPressed: () {
            if (!mounted || _streamingBusy) return;
            _toggleStreaming(true);
          },
        );
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _streamingBusy = false);
    }
  }

  String _buildActiveStreamingSubtitle(BuildContext context) {
    final base = context.l10n.settingsUsbStreamingActive;
    if (!_status.streamingActive || _status.streamingSampleRate <= 0) {
      return base;
    }
    final khz = _status.streamingSampleRate / 1000.0;
    final rateText = khz == khz.roundToDouble()
        ? '${khz.round()} kHz'
        : '${khz.toStringAsFixed(1)} kHz';
    final parts = <String>[
      base,
      rateText,
      if (_status.streamingBitDepth > 0) '${_status.streamingBitDepth}-bit',
      if (_status.rateVerified) context.l10n.usbClockVerified,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid || !_status.attached) return const SizedBox.shrink();
    final p = context.palette;
    final enabled = widget.state.usbHardwareVolumeEnabled;
    final uac2Range = _uac2Range;
    final minDb = _status.minVolumeDb;
    final maxDb = _status.maxVolumeDb;
    final hasDbRange = minDb != null && maxDb != null;
    // A bridge-reported range proves a working attenuator even when the legacy
    // status snapshot did not advertise one. Without a real range, no slider is
    // shown: the old -60/0 fallback invented a scale the DAC never claimed.
    final hasHwVolume =
        uac2Range != null || (_status.hasVolumeControl && hasDbRange);
    final currentDb = (minDb != null && maxDb != null)
        ? (_pendingDb ?? _status.hardwareVolumeDb ?? maxDb)
            .clamp(minDb, maxDb)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.usb_rounded,
          context.l10n.settingsUsbDacHardwareVolume,
          _status.permitted
              ? context.l10n.settingsUsbHwVolumeDesc(
                  _status.uacLabel, _status.deviceName ?? '')
              : context.l10n.settingsUsbHwVolumeGrant,
          value: enabled && hasHwVolume,
          disabledReason:
              hasHwVolume ? null : context.l10n.settingsDacNoUacVolume,
          onChanged: hasHwVolume ? _onToggle : (v) {},
        ),
        if (enabled && hasHwVolume)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, AppSpacing.xxs, AppSpacing.md, AppSpacing.xs),
            child: uac2Range != null
                ? _buildUac2Volume(context)
                : (minDb != null && maxDb != null)
                    ? _buildDbVolume(context, currentDb, minDb, maxDb)
                    : const SizedBox.shrink(),
          ),
        SettingsSwitchTile(
          Icons.lock_rounded,
          context.l10n.settingsExclusiveUsb,
          _status.exclusiveActive || _status.streamingActive
              ? context.l10n.settingsStreamingClaimed
              : context.l10n.settingsExclusiveUsbDesc,
          value: _status.exclusiveActive || _status.streamingActive,
          disabledReason: _status.streamingActive
              ? context.l10n.settingsStreamingClaimed
              : (_status.exclusiveSupported
                  ? null
                  : context.l10n.settingsRequiresUacDac),
          onChanged: (_status.exclusiveSupported && !_status.streamingActive)
              ? (v) async {
                  await _service.setExclusive(v);
                  await _refresh();
                }
              : (v) {},
        ),
        if (_status.streamingSupported)
          SettingsSwitchTile(
            Icons.graphic_eq_rounded,
            context.l10n.settingsUsbBitPerfectStreaming,
            // The cubit owns the mode now: it may be satisfied by the platform's
            // exclusive mixer rather than Pulsr's own endpoint.
            widget.state.bitPerfectOutput
                ? _buildActiveStreamingSubtitle(context)
                : context.l10n.settingsUsbStreamingDesc,
            value: widget.state.bitPerfectOutput,
            disabledReason:
                _streamingBusy ? context.l10n.settingsStarting : null,
            onChanged: _streamingBusy ? (v) {} : _toggleStreaming,
          ),
        if (_status.streamingSupported)
          UsbStreamModeSelector(
            status: _status,
            selected: _streamMode,
            pullFlagEnabled: _pullFlagEnabled,
            asrcFlagEnabled: _asrcFlagEnabled,
            streamingActive: _status.streamingActive,
            onChanged: _onStreamModeChanged,
          ),
        if (widget.cubit.state.errorMessage != null &&
            !widget.state.bitPerfectOutput)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: p.error.withValues(alpha: 0.12),
                borderRadius: AppRadii.r12All,
                border: Border.all(color: p.error.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: p.error),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          context.l10n.directStreamDiagnostics(
                            _status.lastStreamErrorCode != null
                                ? context.l10n.directStreamCode(
                                    '${_status.lastStreamErrorCode}')
                                : context.l10n.directStreamRefused,
                          ),
                          style: TextStyle(
                            color: p.error,
                            fontWeight: FontWeight.w700,
                            fontSize: AppFontSize.caption,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    widget.cubit.state.errorMessage!,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: AppFontSize.label,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Legacy dB slider, anchored on the DAC's reported range when it has one.
  ///
  /// This is the fallback only while [HiresDacBridge] reports no UAC2 range:
  /// once the DAC states a range, the position control owns the write and this
  /// assumed scale is never used.
  Widget _buildDbVolume(
    BuildContext context,
    num currentDb,
    double minDb,
    double maxDb,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.l10n.hwVolume,
                style: Theme.of(context).textTheme.bodyMedium),
            Text('${currentDb.toStringAsFixed(1)} dB',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        Slider(
          value: currentDb.toDouble(),
          min: minDb,
          max: maxDb,
          onChanged: (v) => setState(() => _pendingDb = v),
          onChangeEnd: (v) {
            _pendingDb = null;
            unawaited(_commitVolume(v));
          },
        ),
      ],
    );
  }

  /// The DAC's own attenuator in its reported 0…1 position. No slider is shown
  /// when the range exists but the current value cannot be read: a guessed
  /// position is the failure this control exists to avoid.
  Widget _buildUac2Volume(BuildContext context) {
    final position = _pendingUac2Position ?? _uac2Position;
    final textTheme = Theme.of(context).textTheme;
    if (position == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.settingsUac2VolumeTitle,
              style: textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(context.l10n.settingsUac2VolumeUnsupported,
              style: textTheme.bodySmall),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.l10n.settingsUac2VolumeTitle,
                style: textTheme.bodyMedium),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(position * 100).round()} %', style: textTheme.bodySmall),
                if (_status.hasMuteControl) ...[
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    icon: Icon(
                      _uac2Muted == true
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      size: 18,
                      color: _uac2Muted == true
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    tooltip: _uac2Muted == true
                        ? context.l10n.usbUnmuteDac
                        : context.l10n.usbMuteDac,
                    onPressed: () =>
                        unawaited(_toggleUac2Mute(!(_uac2Muted == true))),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        Slider(
          value: position.clamp(0.0, 1.0),
          min: 0.0,
          max: 1.0,
          onChanged: (v) => setState(() => _pendingUac2Position = v),
          onChangeEnd: (v) {
            _pendingUac2Position = null;
            unawaited(_commitUac2Volume(v));
          },
        ),
        Text(context.l10n.settingsUac2VolumeDesc, style: textTheme.bodySmall),
      ],
    );
  }
}
