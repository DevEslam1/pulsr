// lib/features/settings/presentation/widgets/usb_dac_section.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../domain/services/usb_exclusive_service.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import 'settings_tiles.dart';

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
  StreamSubscription<UsbExclusiveStatus>? _sub;
  UsbExclusiveStatus _status = UsbExclusiveStatus.none;
  bool _busy = false;
  bool _streamingBusy = false;
  double? _pendingDb;

  bool get _isAndroid => PlatformCapabilities.isAndroid;

  @override
  void initState() {
    super.initState();
    if (!_isAndroid) return;
    _sub = _service.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
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
    if (mounted) setState(() => _status = s);
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
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.l10n.usbPermDenied),
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

  Future<void> _commitVolume(double db) async {
    await widget.cubit.setUsbHardwareVolumeEnabled(true);
    await _service.setHardwareVolume(db);
    await _refresh();
  }

  Future<void> _toggleStreaming(bool enabled) async {
    if (_streamingBusy) return;
    setState(() => _streamingBusy = true);
    try {
      if (enabled) {
        if (!_status.permitted) {
          final granted = await _service.requestPermission();
          if (!granted) return;
        }
        final ok = await _service.startStreaming(sampleRate: 48000);
        if (!mounted) return;
        if (!ok) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text(context.l10n.usbBpFailed),
          ));
        }
      } else {
        await _service.stopStreaming();
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _streamingBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid || !_status.attached) return const SizedBox.shrink();
    final p = context.palette;
    final enabled = widget.state.usbHardwareVolumeEnabled;
    final hasHwVolume = _status.hasVolumeControl;
    final minDb = _status.minVolumeDb ?? -60.0;
    final maxDb = _status.maxVolumeDb ?? 0.0;
    final currentDb = (_pendingDb ?? _status.hardwareVolumeDb ?? maxDb)
        .clamp(minDb, maxDb);

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
          disabledReason: hasHwVolume ? null : context.l10n.settingsDacNoUacVolume,
          onChanged: hasHwVolume ? _onToggle : (v) {},
        ),
        if (enabled && hasHwVolume)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
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
                  value: currentDb,
                  min: minDb,
                  max: maxDb,
                  onChanged: (v) => setState(() => _pendingDb = v),
                  onChangeEnd: (v) {
                    _pendingDb = null;
                    unawaited(_commitVolume(v));
                  },
                ),
              ],
            ),
          ),
        SettingsSwitchTile(
          Icons.lock_rounded,
          context.l10n.settingsExclusiveUsb,
          _status.exclusiveActive
              ? context.l10n.settingsStreamingClaimed
              : context.l10n.settingsExclusiveUsbDesc,
          value: _status.exclusiveActive,
          disabledReason:
              _status.exclusiveSupported ? null : context.l10n.settingsRequiresUacDac,
          onChanged: _status.exclusiveSupported
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
            _status.streamingActive
                ? context.l10n.settingsUsbStreamingActive
                : context.l10n.settingsUsbStreamingDesc,
            value: _status.streamingActive,
            disabledReason: _streamingBusy ? context.l10n.settingsStarting : null,
            onChanged: _streamingBusy ? (v) {} : _toggleStreaming,
          ),
      ],
    );
  }
}
