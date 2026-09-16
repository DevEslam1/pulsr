// lib/features/settings/presentation/widgets/bt_latency_tap_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/services/bluetooth_latency_calibrator.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../cubit/settings_cubit.dart';

/// Interactive BT latency tap test: plays 6 beeps 2s apart, user taps the pad
/// the moment each beep is HEARD. Mean(tap-beep) minus reaction baseline
/// becomes the lyrics/visual sync offset. Uses only existing l10n keys.
class BtLatencyTapSheet extends StatefulWidget {
  const BtLatencyTapSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => const BtLatencyTapSheet(),
    );
  }

  @override
  State<BtLatencyTapSheet> createState() => _BtLatencyTapSheetState();
}

class _BtLatencyTapSheetState extends State<BtLatencyTapSheet> {
  static const int kTrials = 6;
  Timer? _timer;
  DateTime? _lastBeepAt;
  int _beepsEmitted = 0;
  final List<int> _deltas = [];
  bool _running = false;
  int? _resultMs;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    setState(() {
      _beepsEmitted = 0;
      _deltas.clear();
      _resultMs = null;
      _running = true;
    });
    _emitBeep();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_beepsEmitted >= kTrials) {
        _finish();
        return;
      }
      _emitBeep();
    });
  }

  void _emitBeep() {
    _lastBeepAt = DateTime.now();
    _beepsEmitted++;
    unawaited(SystemSound.play(SystemSoundType.click));
    if (mounted) setState(() {});
  }

  void _tap() {
    if (!_running || _lastBeepAt == null) return;
    final delta = DateTime.now().difference(_lastBeepAt!).inMilliseconds;
    if (delta < 0 || delta > 1500) return;
    _deltas.add(delta);
    HapticFeedback.selectionClick();
    if (_deltas.length >= kTrials) {
      _finish();
    } else {
      setState(() {});
    }
  }

  void _finish() {
    _timer?.cancel();
    final offset = BluetoothLatencyCalibrator()
        .offsetFromTapDeltas(List.of(_deltas));
    setState(() {
      _running = false;
      _resultMs = offset;
    });
  }

  Future<void> _apply() async {
    if (_resultMs == null) return;
    await context.read<SettingsCubit>().setBluetoothLatencyOffsetMs(_resultMs!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.watch<SettingsCubit>();
    final current = cubit.state.bluetoothLatencyOffsetMs;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.bluetoothLatencyTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.bluetoothLatencySubtitle(current),
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  context.l10n.settingsSyncOffset,
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
                const Spacer(),
                Text(
                  _resultMs != null ? '${_resultMs!} ms' : '$current ms',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: p.accent,
                  ),
                ),
              ],
            ),
            Text(
              '${_deltas.length} / $kTrials',
              style: TextStyle(fontSize: 11, color: p.textTertiary),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _tap,
              child: Container(
                width: double.infinity,
                height: 120,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.accent.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  Icons.fingerprint_rounded,
                  size: 44,
                  color: p.accent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
                const Spacer(),
                if (_resultMs == null)
                  FilledButton.icon(
                    onPressed: _running ? null : _start,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(context.l10n.rcStart),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(context.l10n.retry),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _apply,
                        child: Text(context.l10n.done),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
