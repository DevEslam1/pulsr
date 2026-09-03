// lib/features/player/presentation/widgets/dsp_inspector_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../data/audio/audio_effects_channel.dart';
import '../../../../domain/models/dsp_debug_report.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

import '../../../../core/utils/error_logger.dart';
class DspInspectorSheet extends StatefulWidget {
  const DspInspectorSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DspInspectorSheet(),
    );
  }

  @override
  State<DspInspectorSheet> createState() => _DspInspectorSheetState();
}

class _DspInspectorSheetState extends State<DspInspectorSheet> {
  DspDebugReport? _report;
  bool _isLoading = true;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshReport();
    // Poll every 1.5 seconds while open to show live updates when toggles change
    _autoRefreshTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) _refreshReport(silent: true);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshReport({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    final report = await AudioEffectsChannel().getDspDebugReport();
    if (mounted) {
      setState(() {
        _report = report;
        _isLoading = false;
      });
    }
  }

  Future<void> _copyReportToClipboard(BuildContext context) async {
    if (_report == null) return;
    final jsonText = _report!.toFormattedJson();
    await Clipboard.setData(ClipboardData(text: jsonText));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('DSP Debug Report copied to clipboard!'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerState = context.watch<PlayerCubit>().state;
    final settingsState = context.watch<SettingsCubit>().state;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Adaptive.sheetConstraints(context).maxWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Material(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Top Handle
                const SizedBox(height: 12),
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

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.sensors_rounded,
                            color: p.accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DSP Signal Inspector',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: p.textPrimary,
                              ),
                            ),
                            Text(
                              'Real-time Audio Engine & DSP Debugging',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: p.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy JSON Report',
                        icon: Icon(Icons.copy_rounded, color: p.accent, size: 19),
                        onPressed: () => _copyReportToClipboard(context),
                      ),
                      IconButton(
                        tooltip: 'Refresh Status',
                        icon: Icon(Icons.refresh_rounded, color: p.accent, size: 20),
                        onPressed: () => _refreshReport(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: p.hairline),

                // Content
                Expanded(
                  child: _isLoading && _report == null
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Master Engine Banner
                              _buildMasterEngineCard(p, playerState, settingsState),
                              const SizedBox(height: 16),

                              // Active Effects Summary Header
                              Row(
                                children: [
                                  Text(
                                    'ACTIVE AUDIO STAGES',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                      color: p.accent,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (_report?.activeEffectNames.isNotEmpty == true)
                                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                          : p.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${_report?.activeEffectNames.length ?? 0} ACTIVE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: (_report?.activeEffectNames.isNotEmpty == true)
                                            ? const Color(0xFF10B981)
                                            : p.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // List of DSP stages
                              if (_report != null && _report!.stages.isNotEmpty)
                                ..._report!.stages.map(
                                  (stage) => _buildStageCard(stage, p),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: p.surfaceContainer,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: p.hairline),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'No DSP stages reported from platform engine.',
                                      style: TextStyle(
                                          color: p.textSecondary, fontSize: 12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMasterEngineCard(
      PulsrPalette p, PlayerState playerState, SettingsState settingsState) {
    final rep = _report;
    final isBypassed = rep?.isBitPerfectBypassActive == true;
    final rawAttached = rep?.isSessionAttached == true;
    final sessionId = rep?.audioSessionId ?? 0;
    final hasOem = rep?.hasOemAudio == true;
    // OnePlus / Dolby devices create a valid HAL session only after ExoPlayer
    // has emitted a non-zero audioSessionId. While sessionId==0 the HAL
    // effect chain cannot be created — show "Pending" instead of alarming red.
    // When OEM audio is present the native C++ pipeline (limiter, crossfeed)
    // remains ACTIVE even if the HAL EQ is temporarily detached; treat that as
    // a soft warning (amber) rather than a hard error, and surface the OEM
    // conflict so the user can switch DSP Preference → OEM or disable Dolby.
    final bool isAttached;
    final bool isPendingNoSession;
    final bool isOemSoftDetached;
    if (sessionId == 0 && (rep?.activeEffectNames.isNotEmpty == true)) {
      isAttached = false;
      isPendingNoSession = true;
      isOemSoftDetached = false;
    } else if (!rawAttached && hasOem && (rep?.isNativeDspLoaded == true) && (rep?.activeDspStagesMask ?? 0) != 0) {
      // HAL detached but native stages are configured — OEM (Dolby) has
      // hijacked the HAL session; native limiter/crossfeed still run via
      // the C++ resampler. Show as warning, not error.
      isAttached = false;
      isPendingNoSession = false;
      isOemSoftDetached = true;
    } else {
      isAttached = rawAttached;
      isPendingNoSession = false;
      isOemSoftDetached = false;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBypassed
              ? const Color(0xFFFFD700).withValues(alpha: 0.4)
              : (isAttached
                  ? p.accent.withValues(alpha: 0.3)
                  : (isPendingNoSession || isOemSoftDetached ? Colors.amber.withValues(alpha: 0.35) : p.hairline)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isBypassed
                    ? Icons.verified_rounded
                    : (isAttached
                        ? Icons.bolt_rounded
                        : (isPendingNoSession
                            ? Icons.hourglass_top_rounded
                            : (isOemSoftDetached ? Icons.warning_amber_rounded : Icons.sensors_off_rounded))),
                color: isBypassed
                    ? const Color(0xFFFFD700)
                    : (isAttached
                        ? const Color(0xFF10B981)
                        : (isPendingNoSession || isOemSoftDetached ? Colors.amber : p.error)),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isBypassed
                      ? 'Bit-Perfect Direct Pass-Through'
                      : (isAttached
                          ? 'AudioEffect Session Active (#$sessionId)'
                          : (isPendingNoSession
                              ? 'Session Pending — Play a track to attach'
                              : (isOemSoftDetached ? 'HAL Detached (Dolby) — Native DSP Active' : 'AudioEffect Session Detached'))),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isBypassed
                        ? const Color(0xFFFFD700)
                        : (isAttached ? p.textPrimary : (isPendingNoSession || isOemSoftDetached ? Colors.amber : p.error)),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isBypassed
                      ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                      : (isAttached
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : (isPendingNoSession || isOemSoftDetached ? Colors.amber.withValues(alpha: 0.15) : p.error.withValues(alpha: 0.15))),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isBypassed
                      ? 'BYPASSED'
                      : (isAttached
                          ? 'ATTACHED'
                          : (isPendingNoSession ? 'PENDING' : (isOemSoftDetached ? 'HAL OFF' : 'DETACHED'))),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isBypassed
                        ? const Color(0xFFFFD700)
                        : (isAttached ? const Color(0xFF10B981) : (isPendingNoSession || isOemSoftDetached ? Colors.amber : p.error)),
                  ),
                ),
              ),
            ],
          ),
          if (isOemSoftDetached) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_rounded, size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dolby Atmos is hijacking the HAL session. Native limiter/crossfeed still run, but EQ needs HAL. Fix: tap below to switch to OEM (lets system handle EQ) or disable Dolby in system Sound settings, then restart track.',
                      style: TextStyle(fontSize: 11, height: 1.35, color: p.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final cubit = context.read<SettingsCubit>();
                    await cubit.setDspPreference('oem');
                    if (!mounted) return;
                    messenger.showSnackBar(const SnackBar(content: Text('Switched DSP Preference → OEM. Restart track to attach.')));
                    unawaited(_refreshReport());
                  } catch (e, st) {
                    ErrorLogger.log('dsp_inspector_sheet failed, using fallback', error: e, stackTrace: st, category: 'DspInspectorSheet');
                    if (!mounted) return;
                    messenger.showSnackBar(const SnackBar(content: Text('Failed to switch preference — change in Settings → Audio')));
                  }
                },
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Fix: Switch to OEM', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                style: FilledButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(vertical: 10)),
              ),
            ),
          ],
          if (isPendingNoSession) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  // Best-effort reattach using current PlayerState session.
                  final sid = playerState.audioSessionId;
                  if (sid != null && sid > 0) {
                    try { await AudioEffectsChannel().setAudioSessionId(sid); } catch (e, st) {
                      ErrorLogger.log('dsp_inspector_sheet failed', error: e, stackTrace: st, category: 'DspInspectorSheet');
                    }
                  }
                  // Refresh report after attempt
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retrying HAL attach… play a track if idle')) );
                  unawaited(_refreshReport());
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry Attach', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                style: OutlinedButton.styleFrom(foregroundColor: p.accent, side: BorderSide(color: p.accent.withValues(alpha: 0.4)), visualDensity: VisualDensity.compact),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: 10),

          // Diagnostic stats table
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildStatChip(
                  p, 'DSP Engine', rep?.isNativeDspLoaded == true ? 'C++ & HAL' : 'Android HAL'),
              _buildStatChip(p, 'DSP Preference', rep?.dspPreference.toUpperCase() ?? 'NATIVE'),
              _buildStatChip(
                p,
                'Master EQ',
                playerState.isEqEnabled ? 'ON' : 'OFF',
                isHighlight: playerState.isEqEnabled,
              ),
              _buildStatChip(
                p,
                'Master DSP',
                playerState.isDspActive ? 'ON' : 'OFF',
                isHighlight: playerState.isDspActive,
              ),
              if (rep?.hasOemAudio == true)
                _buildStatChip(
                  p,
                  'OEM Audio Alert',
                  rep?.detectedOemEngines.join(', ') ?? 'Detected',
                  isWarning: true,
                ),
              _buildStatChip(
                p,
                'Output Target',
                '${settingsState.currentOutputDevice?.sampleRate ?? 44100} Hz / ${settingsState.currentOutputDevice?.bitDepth ?? 16}-bit',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(PulsrPalette p, String label, String value,
      {bool isHighlight = false, bool isWarning = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isWarning
            ? Colors.amber.withValues(alpha: 0.12)
            : (isHighlight
                ? p.accent.withValues(alpha: 0.12)
                : p.surfaceContainerHigh),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isWarning
              ? Colors.amber.withValues(alpha: 0.4)
              : (isHighlight
                  ? p.accent.withValues(alpha: 0.3)
                  : p.hairline),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 10.5,
              color: p.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: isWarning
                  ? Colors.amber
                  : (isHighlight ? p.accent : p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageCard(DspStageDebugInfo stage, PulsrPalette p) {
    final bool isActive = stage.isEnabled && !stage.isBypassed && !stage.isDegraded;
    final bool isBypassed = stage.isBypassed;
    final bool isDegraded = stage.isDegraded;

    final Color statusColor = isBypassed
        ? const Color(0xFFFFD700)
        : (isDegraded
            ? p.error
            : (isActive ? const Color(0xFF10B981) : p.textSecondary));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? statusColor.withValues(alpha: 0.4)
              : p.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stage.name,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: p.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  stage.category,
                  style: TextStyle(
                    fontSize: 9,
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isBypassed
                      ? 'BYPASSED'
                      : (isDegraded
                          ? 'DEGRADED'
                          : (isActive ? 'ACTIVE' : 'OFF')),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            stage.statusDescription,
            style: TextStyle(
              fontSize: 11,
              color: isActive ? p.textPrimary : p.textSecondary,
              fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
