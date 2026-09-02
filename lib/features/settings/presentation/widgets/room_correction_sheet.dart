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
import '../../../../domain/services/room_correction_service.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';

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

  @override
  State<RoomCorrectionSheet> createState() => _RoomCorrectionSheetState();
}

class _RoomCorrectionSheetState extends State<RoomCorrectionSheet> {
  late final RoomCorrectionService _service =
      getIt.isRegistered<RoomCorrectionService>()
          ? getIt<RoomCorrectionService>()
          : RoomCorrectionService();
  AudioPlayer? _player;
  _RcPhase _phase = _RcPhase.idle;
  double _progress = 0.0;
  List<double>? _responseDb;
  List<double>? _gains;
  String? _error;

  @override
  void dispose() {
    _player?.stop();
    _player?.dispose();
    if (_service.isCapturing) {
      _service.stopCapture();
    }
    super.dispose();
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

      final started = await _service.startCapture();
      if (!started || !mounted) {
        setState(() {
          _phase = _RcPhase.idle;
          _error = context.l10n.rcMicNeeded;
        });
        return;
      }

      final player = AudioPlayer();
      _player = player;
      await player.setAudioSource(_SweepSource(wav));
      await player.play();

      // Progress: playback position vs sweep duration.
      final durationMs = (tones.length * 350).clamp(1000, 60000);
      Timer.periodic(const Duration(milliseconds: 100), (t) {
        if (!mounted || _phase != _RcPhase.measuring) {
          t.cancel();
          return;
        }
        final posMs = player.position.inMilliseconds;
        setState(() => _progress = (posMs / durationMs).clamp(0.0, 1.0));
      });

      await player.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed);
      await player.stop();

      // Tail margin so the last tone's window is fully captured.
      await Future<void>.delayed(const Duration(milliseconds: 250));

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
    } catch (e) {
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
    final preset = RoomCorrectionService.buildPreset(_gains!);
    final cubit = context.read<PlayerCubit>();
    await cubit.setEqualizerEnabled(true);
    await cubit.applyPreset(preset);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.rcApplied)),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rcTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(l10n.rcSubtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            if (_phase == _RcPhase.idle) ...[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ),
              Text(l10n.rcQuietHint,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.graphic_eq_rounded),
                  label: Text(l10n.rcStart),
                  onPressed: _start,
                ),
              ),
            ] else if (_phase == _RcPhase.measuring ||
                _phase == _RcPhase.analyzing) ...[
              Text(l10n.rcMeasuring,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: _phase == _RcPhase.measuring ? _progress : null),
              const SizedBox(height: 14),
            ] else ...[
              Text(l10n.rcResult,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 10),
              SizedBox(
                height: 120,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _ResponsePainter(
                      response: _responseDb ?? const [], gains: _gains ?? const []),
                ),
              ),
              const SizedBox(height: 6),
              Text(l10n.rcKeepPlayerPaused,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.rcDiscard),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_rounded),
                    label: Text(l10n.rcApply),
                    onPressed: _apply,
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 8),
          ],
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
        Paint()..color = const Color(0xFF7C4DFF),
      );
    }
    for (var i = 0; i < fit.length; i++) {
      final g = (gains[i] / 15.0).clamp(-1.0, 1.0);
      final h = g * (size.height / 2 - 4);
      canvas.drawRect(
        Rect.fromLTRB(i * barW + 1, mid, (i + 1) * barW - 1, mid + h),
        Paint()..color = const Color(0xFF2BB673),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ResponsePainter old) =>
      old.response != response || old.gains != gains;
}