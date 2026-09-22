// ignore_for_file: experimental_member_use
// lib/features/settings/presentation/widgets/room_correction_sheet.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/room_correction_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

/// In-memory measurement sweep playable through a dedicated [AudioPlayer]
/// (NOT the app handler) so the measurement never touches the user's queue,
/// volume stage or DSP pipeline.
class _SweepSource extends StreamAudioSource {
  final Uint8List bytes;
  _SweepSource(this.bytes);

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

enum _RcPhase { idle, measuring, analyzing, result }


/// Phase 5: room-correction wizard. Plays a stepped-sine sweep through the
/// active output device, records it with the mic, fits a Room Correction EQ
/// preset and (optionally) applies it through [PlayerCubit.applyPreset] -
/// the same guarded path as every other preset, so conflict rules hold.
class RoomCorrectionSheet extends StatefulWidget {
  const RoomCorrectionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => const RoomCorrectionSheet(),
    );
  }

  @override
  State<RoomCorrectionSheet> createState() => _RoomCorrectionSheetState();
}

class _RoomCorrectionSheetState extends State<RoomCorrectionSheet> {
  late final RoomCorrectionService _service =
      getIt.isRegistered<RoomCorrectionService>()
          ? getIt<RoomCorrectionService>()
          : RoomCorrectionService();
  AudioPlayer? _player;
  Timer? _progressTimer;
  _RcPhase _phase = _RcPhase.idle;
  double _progress = 0.0;
  List<double>? _responseDb;
  List<double>? _gains;
  String? _error;
  bool _mergeWithHeadphone = false;

  @override
  void dispose() {
    _progressTimer?.cancel();
    _progressTimer = null;
    try {
      _player?.stop();
      _player?.dispose();
    } catch (_) {}
    _player = null;
    if (_service.isCapturing) {
      _service.stopCapture();
    }
    super.dispose();
  }

  Future<void> _cancelSweep() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    try {
      await _service.stopCapture();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _phase = _RcPhase.idle;
        _progress = 0.0;
      });
    }
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _phase = _RcPhase.measuring;
      _progress = 0.0;
    });

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (!mounted) return;
      setState(() {
        _phase = _RcPhase.idle;
        _error = context.l10n.rcMicNeeded;
      });
      return;
    }

    try {
      final tones = RoomCorrectionService.tonePlan();
      final wav = RoomCorrectionService.synthSweepWav(tones);

      bool started = false;
      try {
        started = await _service.startCapture();
      } catch (err) {
        if (mounted) {
          setState(() {
            _phase = _RcPhase.idle;
            _error = '${context.l10n.rcMicNeeded} ($err)';
          });
        }
        return;
      }
      if (!started || !mounted) {
        if (mounted) {
          setState(() {
            _phase = _RcPhase.idle;
            _error = context.l10n.rcMicNeeded;
          });
        }
        return;
      }

      await _player?.stop();
      await _player?.dispose();
      _player = null;

      final player = AudioPlayer();
      _player = player;
      await player.setAudioSource(_SweepSource(wav));
      await player.play();

      // Progress: playback position vs sweep duration.
      final durationMs = (tones.length * 350).clamp(1000, 60000);
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        if (!mounted || _phase != _RcPhase.measuring) {
          t.cancel();
          return;
        }
        final posMs = player.position.inMilliseconds;
        if (posMs >= durationMs) {
          t.cancel();
          return;
        }
        if (mounted) {
          setState(() => _progress = (posMs / durationMs).clamp(0.0, 1.0));
        }
      });

      // Wait until playback finishes or user cancels.
      await player.playerStateStream.firstWhere(
        (s) =>
            s.processingState == ProcessingState.completed ||
            _phase != _RcPhase.measuring,
      );
      _progressTimer?.cancel();
      _progressTimer = null;

      // Tail margin so the last tone's window is fully captured.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      setState(() => _phase = _RcPhase.analyzing);
      final pcm = await _service.stopCapture();
      final response =
          RoomCorrectionService.analyzeResponse(pcm, RoomCorrectionService.captureSampleRate, tones);
      if (response.length < tones.length ~/ 2) {
        throw StateError('capture too short');
      }
      final gains = RoomCorrectionService.fitCorrection(response, tones);
      if (!mounted) return;
      setState(() {
        _responseDb = response;
        _gains = gains;
        _phase = _RcPhase.result;
      });
    } catch (e, st) {
      ErrorLogger.log('Room correction failed', error: e, stackTrace: st, category: 'RoomCorrection');
      _progressTimer?.cancel();
      _progressTimer = null;
      try {
        await _player?.stop();
        await _player?.dispose();
      } catch (_) {}
      _player = null;
      if (!mounted) return;
      setState(() {
        _phase = _RcPhase.idle;
        _error = e.toString();
      });
      try {
        await _service.stopCapture();
      } catch (_) {}
    }
  }

  Future<void> _apply() async {
    if (_gains == null) return;
    final cubit = context.read<PlayerCubit>();
    final effectiveGains = _mergeWithHeadphone
        ? cubit.mergeRoomCorrectionWithHeadphoneCurve(_gains!)
        : _gains!;
    final preset = RoomCorrectionService.buildPreset(effectiveGains);
    await cubit.setEqualizerEnabled(true);
    await cubit.applyPreset(preset);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.rcApplied)),
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;

    return BlocListener<PlayerCubit, PlayerState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage && b.errorMessage != null,
      listener: (ctx, state) {
        final msg = state.errorMessage;
        if (msg != null && msg.isNotEmpty) {
          ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ));
          ctx.read<PlayerCubit>().clearError();
        }
      },
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Adaptive.sheetConstraints(context).maxWidth,
          ),
          child: Material(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: 20,
                  end: 20,
                  top: 12,
                  bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top drag handle
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: p.hairline,
                          borderRadius: BorderRadius.circular(AppRadii.r2),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Header
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: p.accentContainer,
                            borderRadius: BorderRadius.circular(AppRadii.r12),
                          ),
                          child: Icon(Icons.graphic_eq_rounded,
                              color: p.accent, size: 20),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.rcTitle,
                                style: TextStyle(
                                  fontSize: AppFontSize.bodyLarge,
                                  fontWeight: FontWeight.w800,
                                  color: p.textPrimary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s2),
                              Text(
                                l10n.rcSubtitle,
                                style: TextStyle(
                                  fontSize: AppFontSize.label,
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: p.textSecondary),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s18),

                    if (_phase == _RcPhase.idle) ...[
                      if (_error != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: p.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadii.r12),
                            border: Border.all(
                                color: p.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  color: p.error, size: 18),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(_error!,
                                    style: TextStyle(
                                        color: p.error, fontSize: AppFontSize.label)),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(AppRadii.r12),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.volume_off_rounded,
                                color: p.accent, size: 18),
                            const SizedBox(width: AppSpacing.s10),
                            Expanded(
                              child: Text(
                                l10n.rcQuietHint,
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.label,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s18),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: p.accent,
                            foregroundColor: p.onAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadii.r14),
                            ),
                          ),
                          icon: const Icon(Icons.graphic_eq_rounded, size: 20),
                          label: Text(
                            l10n.rcStart,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: AppFontSize.callout),
                          ),
                          onPressed: _start,
                        ),
                      ),
                    ] else if (_phase == _RcPhase.measuring ||
                        _phase == _RcPhase.analyzing) ...[
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              l10n.rcMeasuring,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.body,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadii.r6),
                              child: LinearProgressIndicator(
                                value: _phase == _RcPhase.measuring
                                    ? _progress
                                    : null,
                                backgroundColor: p.hairline,
                                color: p.accent,
                                minHeight: 8,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s18),
                            OutlinedButton.icon(
                              onPressed: _cancelSweep,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: Text(context.l10n.cancel),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        ),
                      ),
                    ] else ...[
                      Text(
                        l10n.rcResult,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.body,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s10),
                      Container(
                        height: 130,
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(AppRadii.r12),
                          border: Border.all(color: p.hairline),
                        ),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _ResponsePainter(
                            response: _responseDb ?? const [],
                            gains: _gains ?? const [],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                              width: 10,
                              height: 10,
                              color: AppColors.ldacViolet),
                          const SizedBox(width: AppSpacing.s6),
                          Text(l10n.rcMeasuredResponse,
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: AppFontSize.caption)),
                          const SizedBox(width: AppSpacing.md),
                          Container(
                              width: 10,
                              height: 10,
                              color: AppColors.emeraldDeep),
                          const SizedBox(width: AppSpacing.s6),
                          Text(l10n.rcFittedEqGain,
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: AppFontSize.caption)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.rcKeepPlayerPaused,
                        style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.caption),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _mergeWithHeadphone,
                        activeColor: p.accent,
                        onChanged: (v) => setState(
                            () => _mergeWithHeadphone = v ?? false),
                        title: Text(
                          l10n.rcStackWithHeadphoneEq,
                          style: TextStyle(
                              color: p.textPrimary, fontSize: AppFontSize.bodySmall),
                        ),
                        subtitle: Text(
                          l10n.rcStackWithHeadphoneEqSubtitle,
                          style: TextStyle(
                              color: p.textSecondary, fontSize: AppFontSize.caption),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: p.textSecondary,
                                  side: BorderSide(color: p.hairline),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadii.r12),
                                  ),
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(l10n.rcDiscard),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: p.accent,
                                  foregroundColor: p.onAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadii.r12),
                                  ),
                                ),
                                icon:
                                    const Icon(Icons.check_rounded, size: 18),
                                label: Text(
                                  l10n.rcApply,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                onPressed: _apply,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple side-by-side bars: measured response (top, normalized) and the
/// fitted correction gains (bottom, clamped to +/-15 dB).
class _ResponsePainter extends CustomPainter {
  final List<double> response;
  final List<double> gains;
  _ResponsePainter({required this.response, required this.gains});

  @override
  void paint(Canvas canvas, Size size) {
    if (response.isEmpty) return;
    final barW = size.width / response.length;
    final mid = size.height / 2;
    final fit = gains.take(response.length).toList();
    final maxAbs = response.fold<double>(6.0, (m, v) => math.max(m, v.abs()));
    final gridPaint = Paint()
      ..color = const Color(0x33888888)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), gridPaint);
    for (var i = 0; i < response.length; i++) {
      final r = (response[i] / maxAbs).clamp(-1.0, 1.0);
      final h = r * (size.height / 2 - 4);
      canvas.drawRect(
        Rect.fromLTRB(i * barW + 1, mid - h, (i + 1) * barW - 1, mid),
        Paint()..color = AppColors.ldacViolet,
      );
    }
    for (var i = 0; i < fit.length; i++) {
      final g = (gains[i] / 15.0).clamp(-1.0, 1.0);
      final h = g * (size.height / 2 - 4);
      canvas.drawRect(
        Rect.fromLTRB(i * barW + 1, mid, (i + 1) * barW - 1, mid + h),
        Paint()..color = AppColors.emeraldDeep,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ResponsePainter old) =>
      old.response != response || old.gains != gains;
}