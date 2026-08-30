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
    final isAttached = rep?.isSessionAttached == true;
    final sessionId = rep?.audioSessionId ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBypassed
              ? const Color(0xFFFFD700).withValues(alpha: 0.4)
              : (isAttached ? p.accent.withValues(alpha: 0.3) : p.hairline),
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
                    : (isAttached ? Icons.bolt_rounded : Icons.sensors_off_rounded),
                color: isBypassed
                    ? const Color(0xFFFFD700)
                    : (isAttached ? const Color(0xFF10B981) : p.error),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isBypassed
                      ? 'Bit-Perfect Direct Pass-Through'
                      : (isAttached
                          ? 'AudioEffect Session Active (#$sessionId)'
                          : 'AudioEffect Session Detached'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isBypassed
                        ? const Color(0xFFFFD700)
                        : (isAttached ? p.textPrimary : p.error),
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
                          : p.error.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isBypassed ? 'BYPASSED' : (isAttached ? 'ATTACHED' : 'DETACHED'),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isBypassed
                        ? const Color(0xFFFFD700)
                        : (isAttached ? const Color(0xFF10B981) : p.error),
                  ),
                ),
              ),
            ],
          ),
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
