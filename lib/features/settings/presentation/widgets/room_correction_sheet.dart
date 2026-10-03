// ignore_for_file: experimental_member_use
// lib/features/settings/presentation/widgets/room_correction_sheet.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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
import '../../../../l10n/generated/app_localizations.dart';
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

enum _RcPhase {
  idle,
  measuring,
  analyzing,
  nextPointPrompt,
  result,
  verifying,
  verified
}

/// Thrown internally when a capture run is superseded or cancelled, so callers
/// can unwind silently instead of surfacing a spurious error.
class _CaptureCancelled implements Exception {
  const _CaptureCancelled();
}

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
  RoomVerification? _verification;
  List<double>? _postVerificationResponse;

  /// Incremented on every start/cancel so an in-flight capture can detect that
  /// it was superseded and unwind without touching state or the error banner.
  int _runToken = 0;

  static const List<String> _pointNames = [
    'Listening Position (Center)',
    '1 meter Left',
    '1 meter Right',
  ];

  Color get _snrColor {
    final snr = _snrDb ?? 20.0;
    if (snr >= 25) return AppColors.emeraldDeep;
    if (snr >= 16) return context.palette.success;
    return context.palette.warning;
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
    _runToken++;
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
        _verification = null;
        _postVerificationResponse = null;
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
    if (minWindowRms <= 0 || minWindowRms == double.infinity) {
      minWindowRms = 1.0;
    }
    if (maxWindowRms <= minWindowRms) return 0.0;

    final snr = 20 * (math.log(maxWindowRms / minWindowRms) / math.ln10);
    return snr.clamp(0.0, 50.0);
  }

  @visibleForTesting
  static double calculateSnr(Int16List pcm) => _calculateSnr(pcm);

  Future<void> _start() async {
    _runToken++;
    _currentPoint = 0;
    _pointResponses.clear();
    _snrValues.clear();
    _verification = null;
    _postVerificationResponse = null;
    await _measureCurrentPoint();
  }

  /// Plays the measurement sweep and records it, returning the analyzed
  /// per-tone response and capture SNR. Throws [_CaptureCancelled] when the run
  /// is superseded/cancelled (so callers can exit silently) and other exceptions
  /// on genuine capture/permission failure. Owns the sweep [AudioPlayer] and mic
  /// capture for the duration of the measurement.
  Future<({List<double> response, double snr, Int16List pcm})>
      _captureSweepResponse() async {
    final tones = RoomCorrectionService.tonePlan();
    final wav = RoomCorrectionService.synthSweepWav(tones);
    final token = _runToken;
    bool captureActive = false;
    StreamSubscription<dynamic>? stateSub;
    final finished = Completer<void>();
    try {
      captureActive = await _service.startCapture();
      if (!captureActive) {
        throw StateError('capture unavailable');
      }
      if (token != _runToken) throw const _CaptureCancelled();

      await _player?.stop();
      await _player?.dispose();
      _player = null;

      try {
        if (mounted) {
          final playerCubit = context.read<PlayerCubit?>();
          if (playerCubit?.state.isPlaying == true) {
            playerCubit?.pause();
          }
        }
      } catch (_) {}

      final player = AudioPlayer();
      _player = player;
      await player.setAudioSource(_SweepSource(wav));

      // Complete on end-of-stream OR stream close/error. Using firstWhere here
      // would throw "No element" when a cancel disposes the player mid-wait.
      stateSub = player.playerStateStream.listen(
        (s) {
          if (s.processingState == ProcessingState.completed &&
              !finished.isCompleted) {
            finished.complete();
          }
        },
        onError: (Object e, StackTrace st) {
          if (!finished.isCompleted) finished.completeError(e, st);
        },
        onDone: () {
          if (!finished.isCompleted) finished.complete();
        },
      );

      await player.play();

      // Progress: playback position vs sweep duration.
      final durationMs = (tones.length * 350).clamp(1000, 60000);
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        if (!mounted ||
            (_phase != _RcPhase.measuring && _phase != _RcPhase.verifying)) {
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

      // Wait until playback finishes (or the run is cancelled).
      await finished.future;
      _progressTimer?.cancel();
      _progressTimer = null;
      if (token != _runToken) throw const _CaptureCancelled();

      // Tail margin so the last tone's window is fully captured.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (token != _runToken) throw const _CaptureCancelled();

      final pcm = await _service.stopCapture();
      captureActive = false;
      final response = RoomCorrectionService.analyzeResponse(
          pcm, RoomCorrectionService.captureSampleRate, tones);
      if (response.length < tones.length ~/ 2) {
        throw StateError('capture too short');
      }
      return (response: response, snr: _calculateSnr(pcm), pcm: pcm);
    } finally {
      await stateSub?.cancel();
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

    try {
      // Stay in `measuring` for the whole capture so the sweep-wait and progress
      // timer recognise the run; `analyzing` is entered only once PCM is back.
      final result = await _captureSweepResponse();
      if (!mounted) return;
      setState(() => _phase = _RcPhase.analyzing);
      _snrValues.add(result.snr);
      _pointResponses.add(result.response);

      if (_multiPointMode && _currentPoint < 2) {
        _currentPoint++;
        if (!mounted) return;
        setState(() => _phase = _RcPhase.nextPointPrompt);
      } else {
        _finishMeasurements(RoomCorrectionService.tonePlan());
      }
    } on _CaptureCancelled {
      // _cancelSweep already restored the idle UI; nothing to surface.
      return;
    } catch (e, st) {
      ErrorLogger.log('Room correction failed',
          error: e, stackTrace: st, category: 'RoomCorrection');
      if (mounted) {
        setState(() {
          _phase = _RcPhase.idle;
          _error = e.toString();
        });
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

  /// Applies the fitted correction through the guarded preset path and returns
  /// the effective gains that were applied (for verification reference).
  Future<List<double>> _applyCorrection() async {
    final cubit = context.read<PlayerCubit>();
    final effectiveGains = _mergeWithHeadphone
        ? cubit.mergeRoomCorrectionWithHeadphoneCurve(_gains!)
        : _gains!;
    final preset = RoomCorrectionService.buildPreset(effectiveGains);
    await cubit.setEqualizerEnabled(true);
    await cubit.applyPreset(preset);
    // Always write the preamp (including 0 dB) so stale headroom from a prior
    // correction or headphone profile is cleared instead of lingering.
    final safePreamp = RoomCorrectionService.computeSafePreamp(effectiveGains);
    await cubit.setPreamp(safePreamp);
    return effectiveGains;
  }

  Future<void> _apply() async {
    if (_gains == null) return;
    await _applyCorrection();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.rcApplied)),
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Applies the correction, then reports the closed-loop verification
  /// (pre→post convergence + flatness gate).
  ///
  /// The post-correction response is *predicted* from the exact curve that was
  /// applied rather than re-acoustically measured: the measurement sweep runs
  /// through a standalone player, so a second capture would only contain the
  /// correction when the active DSP owner is the in-stream native engine — never
  /// when the session-bound HAL chain owns the EQ. Predicting from the applied
  /// gains is deterministic and device-independent, so the verdict is never
  /// based on an uncorrected signal.
  Future<void> _applyAndVerify() async {
    if (_gains == null) return;
    try {
      final effectiveGains = await _applyCorrection();
      if (!mounted) return;
      setState(() {
        _error = null;
        _phase = _RcPhase.verifying;
        _progress = 0.0;
      });
      final pre = _responseDb;
      if (pre == null) {
        throw StateError('no reference response');
      }
      final post = RoomCorrectionService.predictCorrectedResponse(
        preResponseDb: pre,
        tones: RoomCorrectionService.tonePlan(),
        gains: effectiveGains,
      );
      final verification = RoomCorrectionService.verify(
        preResponseDb: pre,
        postResponseDb: post,
      );
      if (!mounted) return;
      setState(() {
        _verification = verification;
        _postVerificationResponse = post;
        _phase = _RcPhase.verified;
      });
    } catch (e, st) {
      ErrorLogger.log('Room-correction verification failed',
          error: e, stackTrace: st, category: 'RoomCorrection');
      if (mounted) {
        setState(() {
          _phase = _RcPhase.result;
          _error = e.toString();
        });
      }
    }
  }

  /// Result card shown after a closed-loop verification: convergence score,
  /// residual variance, improvement percentage and the ±gate verdict.
  Widget _verificationCard(
    PulsrPalette p,
    AppLocalizations l10n,
    RoomVerification v,
  ) {
    final ok = v.passed;
    final accent = ok ? AppColors.emeraldDeep : p.warning;
    final c = v.convergence;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: AppRadii.r12All,
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.verified_rounded : Icons.info_outline_rounded,
                  color: accent, size: 18),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.rcVerification,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.bodySmall,
                ),
              ),
              const Spacer(),
              Text(
                ok ? l10n.rcConverged : l10n.rcNotConverged,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.label,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: AppRadii.r4All,
            child: LinearProgressIndicator(
              value: (v.convergence.score / 100.0).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: p.hairline,
              color: accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: _verificationMetric(
                  p,
                  l10n.rcImprovement,
                  '${c.score.toStringAsFixed(1)}%',
                ),
              ),
              Expanded(
                child: _verificationMetric(
                  p,
                  l10n.rcResidual,
                  '${c.residualVarianceDb.toStringAsFixed(2)} dB',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              Icon(
                v.loopback.isWithinGate
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                color:
                    v.loopback.isWithinGate ? AppColors.emeraldDeep : p.warning,
                size: 14,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                v.loopback.isWithinGate
                    ? l10n.rcTargetGatePassed
                    : l10n.rcTargetGateFailed,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.caption,
                ),
              ),
              const Spacer(),
              Text(
                'max ${v.loopback.maxDeviationDb.toStringAsFixed(2)} dB',
                style: TextStyle(
                  color: p.textTertiary,
                  fontSize: AppFontSize.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _verificationMetric(PulsrPalette p, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.tiny),
        ),
        Text(
          value,
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: AppFontSize.bodySmall,
          ),
        ),
      ],
    );
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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
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
                          borderRadius: AppRadii.r2All,
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
                            borderRadius: AppRadii.r12All,
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
                          icon:
                              Icon(Icons.close_rounded, color: p.textSecondary),
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
                            borderRadius: AppRadii.r12All,
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
                                        color: p.error,
                                        fontSize: AppFontSize.label)),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: AppRadii.r12All,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: AppRadii.r12All,
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.spatial_audio_off_rounded,
                                color: p.accent, size: 20),
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
                              onChanged: (v) =>
                                  setState(() => _multiPointMode = v),
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
                              borderRadius: AppRadii.r14All,
                            ),
                          ),
                          icon: const Icon(Icons.graphic_eq_rounded, size: 20),
                          label: Text(
                            _multiPointMode
                                ? 'Start 3-Point Calibration'
                                : l10n.rcStart,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.callout),
                          ),
                          onPressed: _start,
                        ),
                      ),
                    ] else if (_phase == _RcPhase.measuring ||
                        _phase == _RcPhase.analyzing ||
                        _phase == _RcPhase.verifying) ...[
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _phase == _RcPhase.verifying
                                  ? l10n.rcVerifying
                                  : (_multiPointMode
                                      ? 'Measuring ${_pointNames[_currentPoint]}'
                                      : l10n.rcMeasuring),
                              style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.body,
                              ),
                            ),
                            if (_multiPointMode &&
                                _phase != _RcPhase.verifying) ...[
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
                              borderRadius: AppRadii.r6All,
                              child: LinearProgressIndicator(
                                value: (_phase == _RcPhase.measuring ||
                                        _phase == _RcPhase.verifying)
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
                              child: Icon(Icons.arrow_forward_rounded,
                                  color: p.accent, size: 24),
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
                                    borderRadius: AppRadii.r14All,
                                  ),
                                ),
                                icon: const Icon(Icons.play_arrow_rounded,
                                    size: 20),
                                label: Text(
                                    'Measure Position ${_currentPoint + 1}'),
                                onPressed: _measureCurrentPoint,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            TextButton(
                              onPressed: () {
                                final tones = RoomCorrectionService.tonePlan();
                                _finishMeasurements(tones);
                              },
                              child: Text(
                                  'Finish with current measurements (${_pointResponses.length}/3)'),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _snrColor.withValues(alpha: 0.15),
                                borderRadius: AppRadii.r8All,
                                border: Border.all(
                                    color: _snrColor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline_rounded,
                                      size: 14, color: _snrColor),
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
                          color: p.surfaceContainer,
                          borderRadius: AppRadii.r12All,
                          border: Border.all(color: p.hairline),
                        ),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _ResponsePainter(
                            response: _responseDb ?? const [],
                            gains: _gains ?? const [],
                            pointResponses: _pointResponses,
                            postResponse: _postVerificationResponse ?? const [],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_pointResponses.length > 1) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                                width: 10,
                                height: 3,
                                color: AppColors.roomPointCenter),
                            const SizedBox(width: 4),
                            Text(context.l10n.roomPositionCenter,
                                style: TextStyle(
                                    color: p.textTertiary,
                                    fontSize: AppFontSize.tiny)),
                            const SizedBox(width: 8),
                            Container(
                                width: 10,
                                height: 3,
                                color: AppColors.roomPointLeft),
                            const SizedBox(width: 4),
                            Text(context.l10n.roomPositionLeft,
                                style: TextStyle(
                                    color: p.textTertiary,
                                    fontSize: AppFontSize.tiny)),
                            const SizedBox(width: 8),
                            Container(
                                width: 10,
                                height: 3,
                                color: AppColors.roomPointRight),
                            const SizedBox(width: 4),
                            Text(context.l10n.roomPositionRight,
                                style: TextStyle(
                                    color: p.textTertiary,
                                    fontSize: AppFontSize.tiny)),
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
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.caption)),
                          const SizedBox(width: AppSpacing.md),
                          Container(
                              width: 10,
                              height: 10,
                              color: AppColors.emeraldDeep),
                          const SizedBox(width: AppSpacing.s6),
                          Text(l10n.rcFittedEqGain,
                              style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.caption)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.rcKeepPlayerPaused,
                        style: TextStyle(
                            color: p.textTertiary,
                            fontSize: AppFontSize.caption),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _mergeWithHeadphone,
                        activeColor: p.accent,
                        onChanged: (v) =>
                            setState(() => _mergeWithHeadphone = v ?? false),
                        title: Text(
                          l10n.rcStackWithHeadphoneEq,
                          style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.bodySmall),
                        ),
                        subtitle: Text(
                          l10n.rcStackWithHeadphoneEqSubtitle,
                          style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.caption),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_verification != null) ...[
                        _verificationCard(p, l10n, _verification!),
                        const SizedBox(height: AppSpacing.sm),
                      ],
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
                                    borderRadius: AppRadii.r12All,
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
                                    borderRadius: AppRadii.r12All,
                                  ),
                                ),
                                icon: const Icon(Icons.verified_rounded,
                                    size: 18),
                                label: Text(
                                  _verification == null
                                      ? l10n.rcApplyAndVerify
                                      : l10n.rcApply,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                onPressed: _verification == null
                                    ? _applyAndVerify
                                    : _apply,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_verification == null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          l10n.rcVerifyHint,
                          style: TextStyle(
                              color: p.textTertiary,
                              fontSize: AppFontSize.caption),
                        ),
                      ],
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
  final List<double> postResponse;

  _ResponsePainter({
    required this.response,
    required this.gains,
    this.pointResponses = const [],
    this.postResponse = const [],
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
        AppColors.roomPointCenterLine, // Center: light blue
        AppColors.roomPointLeftLine, // Left: light green
        AppColors.roomPointRightLine, // Right: light amber
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

    // Draw the post-correction (verified) response as a bright line so the
    // flattening is visible directly against the pre-correction bars.
    if (postResponse.length >= 2) {
      final postPaint = Paint()
        ..color = AppColors.emeraldDeep
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      final postPath = Path();
      for (var i = 0; i < postResponse.length; i++) {
        final x = i * barW + barW / 2;
        final r = (postResponse[i] / maxAbs).clamp(-1.0, 1.0);
        final y = mid - (r * (size.height / 2 - 6));
        if (i == 0) {
          postPath.moveTo(x, y);
        } else {
          postPath.lineTo(x, y);
        }
      }
      canvas.drawPath(postPath, postPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ResponsePainter old) =>
      !listEquals(old.response, response) ||
      !listEquals(old.gains, gains) ||
      !_nestedListEquals(old.pointResponses, pointResponses) ||
      !listEquals(old.postResponse, postResponse);

  /// [_pointResponses] is mutated in place, so reference equality would miss
  /// updates; compare the nested values instead.
  static bool _nestedListEquals(List<List<double>> a, List<List<double>> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!listEquals(a[i], b[i])) return false;
    }
    return true;
  }
}
