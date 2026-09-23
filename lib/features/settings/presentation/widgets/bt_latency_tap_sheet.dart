// lib/features/settings/presentation/widgets/bt_latency_tap_sheet.dart
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';
import '../../../../domain/services/room_correction_service.dart';
import '../../../../core/services/bluetooth_latency_calibrator.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../cubit/settings_cubit.dart';
import '../../../../core/utils/error_logger.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class _BeepSource extends StreamAudioSource {
  final Uint8List bytes;
  _BeepSource(this.bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? bytes.length;
    return StreamAudioResponse(
      rangeRequestsSupported: false,
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      contentType: 'audio/wav',
      stream: Stream.value(bytes.sublist(from, to)),
    );
  }
}

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
  AudioPlayer? _player;
  bool _initError = false;
  late final Uint8List _beepWav;

  @override
  void initState() {
    super.initState();
    _beepWav = RoomCorrectionService.synthSweepWav([880.0], toneMs: 60, fadeMs: 4, amp: 0.5);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final player = AudioPlayer();
    _player = player;
    try {
      await player.setAudioSource(_BeepSource(_beepWav));
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize AudioPlayer in BT latency test',
          error: e, stackTrace: st, category: 'BtLatency');
      try {
        await player.dispose();
      } catch (_) {}
      if (identical(_player, player)) {
        _player = null;
      }
      if (mounted) setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    try {
      _player?.stop();
      _player?.dispose();
    } catch (e, st) {
      ErrorLogger.log('Failed to dispose player in BT latency test',
          error: e, stackTrace: st, category: 'BtLatency');
    }
    _player = null;
    super.dispose();
  }

  void _start() {
    if (_initError || _player == null) return;
    _timer?.cancel();
    setState(() {
      _beepsEmitted = 0;
      _deltas.clear();
      _resultMs = null;
      _running = true;
    });
    _emitBeep();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      if (_beepsEmitted >= kTrials) {
        _finish();
        return;
      }
      _emitBeep();
    });
  }

  void _emitBeep() {
    if (_player == null) return;
    _lastBeepAt = DateTime.now();
    _beepsEmitted++;
    try {
      unawaited(_player!.seek(Duration.zero).then((_) => _player?.play()).catchError((e, st) {
        ErrorLogger.log('Failed to play beep in BT latency test',
            error: e, stackTrace: st, category: 'BtLatency');
      }));
    } catch (e, st) {
      ErrorLogger.log('Failed to trigger beep playback in BT latency test',
          error: e, stackTrace: st, category: 'BtLatency');
    }
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
      if (mounted) setState(() {});
    }
  }

  void _finish() {
    _timer?.cancel();
    if (!mounted) return;
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
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.watch<SettingsCubit>();
    final current = cubit.state.bluetoothLatencyOffsetMs;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.lg),
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
                  borderRadius: BorderRadius.circular(AppRadii.r2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.bluetoothLatencyTitle,
              style: TextStyle(
                fontSize: AppFontSize.bodyLarge,
                fontWeight: FontWeight.w800,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              context.l10n.bluetoothLatencySubtitle(current),
              style: TextStyle(fontSize: AppFontSize.label, color: p.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  context.l10n.settingsSyncOffset,
                  style: TextStyle(fontSize: AppFontSize.label, color: p.textSecondary),
                ),
                const Spacer(),
                Text(
                  _resultMs != null ? '${_resultMs!} ms' : '$current ms',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w800,
                    color: p.accent,
                  ),
                ),
              ],
            ),
            Text(
              '${_deltas.length} / $kTrials',
              style: TextStyle(fontSize: AppFontSize.caption, color: p.textTertiary),
            ),
            const SizedBox(height: AppSpacing.sm),
            GestureDetector(
              onTap: _tap,
              child: Container(
                width: double.infinity,
                height: 120,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.r16),
                  border: Border.all(color: p.accent.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  Icons.fingerprint_rounded,
                  size: 44,
                  color: p.accent,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
                const Spacer(),
                if (_resultMs == null)
                  FilledButton.icon(
                    onPressed: (_running || _initError || _player == null) ? null : _start,
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
                      const SizedBox(width: AppSpacing.xs),
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
