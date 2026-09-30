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
    final total = bytes.length;
    final from = (start ?? 0).clamp(0, total);
    final to = (end ?? total).clamp(from, total);
    return StreamAudioResponse(
      rangeRequestsSupported: false,
      sourceLength: total,
      contentLength: to - from,
      offset: from,
      contentType: 'audio/wav',
      stream: Stream.value(bytes.sublist(from, to)),
    );
  }
}

enum _RcPhase { idle, measuring, analyzing, nextPointPrompt, result }

/// Phase 5: room-correction wizard. Plays a stepped-sine sweep through the
/// active output device, records it with the mic, fits a Room Correction EQ
/// preset and (optionally) applies it through [PlayerCubit.applyPreset] -
/// the same guarded path as every other preset, so conflict rules hold.
class RoomCorrectionSheet extends StatefulWidget {
  const RoomCorrectionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => const RoomCorrectionSheet(),
    );
  }

  @visibleForTesting
  static double calculateSnr(Int16List pcm) =>
      _RoomCorrectionSheetState.calculateSnr(pcm);

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

  // Multi-point measurement mode (Center, 1m Left, 1m Right)
  bool _multiPointMode = true;
  int _currentPoint = 0;
  final List<List<double>> _pointResponses = [];
  final List<double> _snrValues = [];
  double? _snrDb;

  static const List<String> _pointNames = [
    'Listening Position (Center)',
    '1 meter Left',
    '1 meter Right',
  ];

  Color get _snrColor {
    final snr = _snrDb ?? 20.0;
    if (snr >= 25) return AppColors.emeraldDeep;
    if (snr >= 16) return Colors.teal;
    return Colors.amber;
  }

  String get _snrLabel {
    final snr = _snrDb ?? 20.0;
    if (snr >= 25) return 'Excellent';
    if (snr >= 16) return 'Good';
    return 'Moderate Noise';
  }

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
      try {
        _service.stopCapture();
      } catch (_) {}
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
        _currentPoint = 0;
        _pointResponses.clear();
        _snrValues.clear();
      });
    }
  }

  static double _calculateSnr(Int16List pcm) {
    if (pcm.isEmpty || pcm.length < 1024) return 0.0;
    const windowSize = 1024;
    double maxWindowRms = 0.0;
    double minWindowRms = double.infinity;

    for (int i = 0; i + windowSize <= pcm.length; i += windowSize) {
      double sumSq = 0.0;
      for (int j = 0; j < windowSize; j++) {
        final sample = pcm[i + j].toDouble();
        sumSq += sample * sample;
      }
      final rms = math.sqrt(sumSq / windowSize);
      if (rms > maxWindowRms) maxWindowRms = rms;
      if (rms > 0 && rms < minWindowRms) minWindowRms = rms;
    }

    if (maxWindowRms <= 0.0) return 0.0;
    if (minWindowRms <= 0 || minWindowRms == double.infinity) minWindowRms = 1.0;
    if (maxWindowRms <= minWindowRms) return 0.0;

    final snr = 20 * (math.log(maxWindowRms / minWindowRms) / math.ln10);
    return snr.clamp(0.0, 50.0);
  }

  @visibleForTesting
  static double calculateSnr(Int16List pcm) => _calculateSnr(pcm);

  Future<void> _start() async {
    _currentPoint = 0;
    _pointResponses.clear();
    _snrValues.clear();
    await _measureCurrentPoint();
  }

  Future<void> _measureCurrentPoint() async {
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

    bool captureActive = false;
    try {
      final tones = RoomCorrectionService.tonePlan();
      final wav = RoomCorrectionService.synthSweepWav(tones);

      try {
        captureActive = await _service.startCapture();
      } catch (err) {
        if (mounted) {
          setState(() {
            _phase = _RcPhase.idle;
            _error = '${context.l10n.rcMicNeeded} ($err)';
          });
        }
        return;
      }
      if (!captureActive || !mounted) {
        if (captureActive) {
          try {
            await _service.stopCapture();
          } catch (_) {}
          captureActive = false;
        }
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

      if (mounted) {
        try {
          final playerCubit = context.read<PlayerCubit?>();
          if (playerCubit?.state.isPlaying == true) {
            playerCubit?.pause();
          }
        } catch (_) {}
      }

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
      if (!mounted) {
        return;
      }

      setState(() => _phase = _RcPhase.analyzing);
      final pcm = await _service.stopCapture();
      captureActive = false;
      final response =
          RoomCorrectionService.analyzeResponse(pcm, RoomCorrectionService.captureSampleRate, tones);
      if (response.length < tones.length ~/ 2) {
        throw StateError('capture too short');
      }

      final snr = _calculateSnr(pcm);
      _snrValues.add(snr);
      _pointResponses.add(response);

      if (_multiPointMode && _currentPoint < 2) {
        _currentPoint++;
        if (!mounted) return;
        setState(() => _phase = _RcPhase.nextPointPrompt);
      } else {
        _finishMeasurements(tones);
      }
    } catch (e, st) {
      ErrorLogger.log('Room correction failed', error: e, stackTrace: st, category: 'RoomCorrection');
      if (mounted) {
        setState(() {
          _phase = _RcPhase.idle;
          _error = e.toString();
        });
      }
    } finally {
      _progressTimer?.cancel();
      _progressTimer = null;
      try {
        await _player?.stop();
        await _player?.dispose();
      } catch (_) {}
      _player = null;
      if (captureActive || _service.isCapturing) {
        try {
          await _service.stopCapture();
        } catch (_) {}
      }
    }
  }

  void _finishMeasurements(List<double> tones) {
    if (_pointResponses.isEmpty) return;

    // Average the measurements across all recorded points
    final avgResponse = List.filled(tones.length, 0.0);
    for (int i = 0; i < tones.length; i++) {
      double sum = 0.0;
      int count = 0;
      for (final resp in _pointResponses) {
        if (i < resp.length) {
          sum += resp[i];
          count++;
        }
      }
      avgResponse[i] = count > 0 ? (sum / count) : 0.0;
    }

    final gains = RoomCorrectionService.fitCorrection(avgResponse, tones);
    final avgSnr = _snrValues.isNotEmpty
        ? (_snrValues.reduce((a, b) => a + b) / _snrValues.length)
        : 0.0;

    if (!mounted) return;
    setState(() {
      _snrDb = avgSnr;
      _responseDb = avgResponse;
      _gains = gains;
      _phase = _RcPhase.result;
    });
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
                          tooltip: context.l10n.close,
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
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(AppRadii.r12),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.spatial_audio_off_rounded, color: p.accent, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.roomAveragingTitle,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: AppFontSize.bodySmall,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    context.l10n.roomAveragingSubtitle,
                                    style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _multiPointMode,
                              activeTrackColor: p.accent,
                              onChanged: (v) => setState(() => _multiPointMode = v),
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
                            _multiPointMode
                                ? 'Start 3-Point Calibration'
                                : l10n.rcStart,
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
                              _multiPointMode
                                  ? 'Measuring ${_pointNames[_currentPoint]}'
                                  : l10n.rcMeasuring,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.body,
                              ),
                            ),
                            if (_multiPointMode) ...[
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Point ${_currentPoint + 1} of 3',
                                style: TextStyle(
                                  color: p.accent,
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
                    ] else if (_phase == _RcPhase.nextPointPrompt) ...[
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: p.accentContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.arrow_forward_rounded, color: p.accent, size: 24),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Position ${_currentPoint + 1} of 3',
                              style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.body,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Move your device to: ${_pointNames[_currentPoint]}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: AppFontSize.label,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
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
                                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                                label: Text('Measure Position ${_currentPoint + 1}'),
                                onPressed: _measureCurrentPoint,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            TextButton(
                              onPressed: () {
                                final tones = RoomCorrectionService.tonePlan();
                                _finishMeasurements(tones);
                              },
                              child: Text('Finish with current measurements (${_pointResponses.length}/3)'),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            l10n.rcResult,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: AppFontSize.body,
                            ),
                          ),
                          if (_snrDb != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _snrColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(AppRadii.r8),
                                border: Border.all(color: _snrColor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline_rounded, size: 14, color: _snrColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    'SNR: ${_snrDb!.toStringAsFixed(1)} dB ($_snrLabel)',
                                    style: TextStyle(
                                      color: _snrColor,
                                      fontSize: AppFontSize.caption,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
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
                            pointResponses: _pointResponses,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_pointResponses.length > 1) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(width: 10, height: 3, color: const Color(0xFF4FC3F7)),
                            const SizedBox(width: 4),
                            Text(context.l10n.roomPositionCenter, style: TextStyle(color: p.textTertiary, fontSize: 10)),
                            const SizedBox(width: 8),
                            Container(width: 10, height: 3, color: const Color(0xFF81C784)),
                            const SizedBox(width: 4),
                            Text(context.l10n.roomPositionLeft, style: TextStyle(color: p.textTertiary, fontSize: 10)),
                            const SizedBox(width: 8),
                            Container(width: 10, height: 3, color: const Color(0xFFFFB74D)),
                            const SizedBox(width: 4),
                            Text(context.l10n.roomPositionRight, style: TextStyle(color: p.textTertiary, fontSize: 10)),
                          ],
                        ),
                        const SizedBox(height: 2),
                      ],
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

/// Side-by-side bars: measured response (top, normalized) and fitted correction gains
/// (bottom, clamped to +/-15 dB), with overlaid multi-point lines.
class _ResponsePainter extends CustomPainter {
  final List<double> response;
  final List<double> gains;
  final List<List<double>> pointResponses;

  _ResponsePainter({
    required this.response,
    required this.gains,
    this.pointResponses = const [],
  });

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

    // If multi-point measurements exist, draw individual point curves
    if (pointResponses.length > 1) {
      final pointColors = [
        const Color(0xAA4FC3F7), // Center: light blue
        const Color(0xAA81C784), // Left: light green
        const Color(0xAAFFB74D), // Right: light amber
      ];
      for (int pIdx = 0; pIdx < pointResponses.length; pIdx++) {
        final pts = pointResponses[pIdx];
        final pPaint = Paint()
          ..color = pointColors[pIdx % pointColors.length]
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        final path = Path();
        for (int i = 0; i < pts.length; i++) {
          final x = i * barW + barW / 2;
          final r = (pts[i] / maxAbs).clamp(-1.0, 1.0);
          final y = mid - (r * (size.height / 2 - 6));
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, pPaint);
      }
    }

    // Draw average response bars
    for (var i = 0; i < response.length; i++) {
      final r = (response[i] / maxAbs).clamp(-1.0, 1.0);
      final h = r * (size.height / 2 - 4);
      canvas.drawRect(
        Rect.fromLTRB(i * barW + 1, mid - h, (i + 1) * barW - 1, mid),
        Paint()..color = AppColors.ldacViolet.withValues(alpha: 0.85),
      );
    }

    // Draw fitted gains
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
      old.response != response ||
      old.gains != gains ||
      old.pointResponses != pointResponses;
}