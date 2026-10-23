// lib/features/player/presentation/widgets/dsp_inspector_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/telemetry/dsp_reliability_tracker.dart';
import '../../../../data/audio/audio_effects_channel.dart';
import '../../../../data/audio/equalizer_manager.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../../domain/models/dsp_debug_report.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';

import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'engine_telemetry_panel.dart';
import 'sync_diagnostics_sheet.dart';

class DspInspectorSheet extends StatefulWidget {
  const DspInspectorSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => const DspInspectorSheet(),
    );
  }

  /// Redacts absolute device file paths before exporting for privacy (S2).
  @visibleForTesting
  static String sanitizeReport(String raw) {
    return raw
        .replaceAll(
            RegExp(r'(/data/user/\d+/[^"\s\\]+)'), '[REDACTED_APP_PATH]')
        .replaceAll(RegExp(r'(/storage/emulated/\d+/[^"\s\\]+)'),
            '[REDACTED_STORAGE_PATH]')
        .replaceAll(RegExp(r'([A-Za-z]:\\[^"\s]+)'), '[REDACTED_LOCAL_PATH]');
  }

  @override
  State<DspInspectorSheet> createState() => _DspInspectorSheetState();
}

class _DspInspectorSheetState extends State<DspInspectorSheet>
    with WidgetsBindingObserver {
  DspDebugReport? _report;
  bool _isLoading = true;
  bool _isResyncing = false;
  int _pipelineLatencyFrames = 0;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshReport();
    _startTimer();
  }

  void _startTimer() {
    _autoRefreshTimer?.cancel();
    // Poll every 1.5 seconds while open to show live updates when toggles change
    _autoRefreshTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) _refreshReport(silent: true);
    });
  }

  void _stopTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      _refreshReport(silent: true);
    } else {
      _stopTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    super.dispose();
  }

  Future<void> _refreshReport({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final reportFuture = AudioEffectsChannel().getDspDebugReport();
      final latencyFuture = AudioEffectsChannel().getPipelineLatencyFrames();
      final results = await Future.wait([reportFuture, latencyFuture]);
      final report = results[0] as DspDebugReport;
      final latencyFrames = results[1] as int;
      if (mounted) {
        setState(() {
          _report = report;
          _pipelineLatencyFrames = latencyFrames;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resyncDsp(BuildContext context) async {
    if (_isResyncing) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _isResyncing = true);
    try {
      if (getIt.isRegistered<EqualizerManager>()) {
        await getIt<EqualizerManager>().resyncActiveEffects();
      } else {
        await AudioEffectsChannel().resyncForTrack(44100);
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.dspResyncSuccess),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.dspResyncFailure(e.toString())),
            backgroundColor: errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isResyncing = false);
        await _refreshReport(silent: true);
      }
    }
  }

  String exportReportForShare() {
    final raw = _report?.toFormattedJson() ?? '{}';
    // S2: Redact absolute device file paths before exporting for privacy
    return DspInspectorSheet.sanitizeReport(raw);
  }

  Future<void> _shareReport(BuildContext context) async {
    if (_report == null) return;
    final jsonText = exportReportForShare();
    await SharePlus.instance.share(ShareParams(text: jsonText));
  }

  Future<void> _copyReportToClipboard(BuildContext context) async {
    if (_report == null) return;
    final jsonText = _report!.toFormattedJson();
    await Clipboard.setData(ClipboardData(text: jsonText));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.dspReportCopied),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isEqEnabled =
        context.select<PlayerCubit, bool>((c) => c.state.isEqEnabled);
    final isDspActive =
        context.select<PlayerCubit, bool>((c) => c.state.isDspActive);
    final audioSessionId =
        context.select<PlayerCubit, int?>((c) => c.state.audioSessionId);
    final currentOutputDevice = context.select<SettingsCubit, AudioOutputInfo?>(
        (c) => c.state.currentOutputDevice);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Adaptive.sheetConstraints(context).maxWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Material(
          color: p.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Top Handle
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: AppRadii.r2All,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.15),
                          borderRadius: AppRadii.r10All,
                        ),
                        child: Icon(Icons.sensors_rounded,
                            color: p.accent, size: 20),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.dspInspector,
                              style: TextStyle(
                                fontSize: AppFontSize.bodyLarge,
                                fontWeight: FontWeight.w800,
                                color: p.textPrimary,
                              ),
                            ),
                            Text(
                              context.l10n.dspInspectorDesc,
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                color: p.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget),
                        tooltip: context.l10n.dspCopyJsonReport,
                        icon:
                            Icon(Icons.copy_rounded, color: p.accent, size: 20),
                        onPressed: () => _copyReportToClipboard(context),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget),
                        tooltip: context.l10n.share,
                        icon: Icon(Icons.share_rounded,
                            color: p.accent, size: 20),
                        onPressed: () => _shareReport(context),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget),
                        tooltip: context.l10n.latencySyncDiagnostics,
                        icon:
                            Icon(Icons.sync_rounded, color: p.accent, size: 20),
                        onPressed: () => SyncDiagnosticsSheet.show(context),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget),
                        tooltip: context.l10n.dspRefreshStatus,
                        icon: Icon(Icons.refresh_rounded,
                            color: p.accent, size: 20),
                        onPressed: () => _refreshReport(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Divider(height: 1, color: p.hairline),

                // Content
                Expanded(
                  child: _isLoading && _report == null
                      ? const SingleChildScrollView(
                          padding: EdgeInsetsDirectional.fromSTEB(
                              AppSpacing.s18,
                              AppSpacing.s14,
                              AppSpacing.s18,
                              AppSpacing.s28),
                          child: SkeletonShimmer(
                            child: Column(
                              children: [
                                SkeletonBox(height: 188, radius: AppRadii.r16),
                                SizedBox(height: AppSpacing.sm),
                                SkeletonBox(height: 96, radius: AppRadii.r16),
                                SizedBox(height: AppSpacing.md),
                                SkeletonBox(height: 72, radius: AppRadii.r12),
                                SizedBox(height: AppSpacing.xs),
                                SkeletonBox(height: 72, radius: AppRadii.r12),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              AppSpacing.s18,
                              AppSpacing.s14,
                              AppSpacing.s18,
                              AppSpacing.s28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Master Engine Banner
                              _buildMasterEngineCard(
                                p: p,
                                isEqEnabled: isEqEnabled,
                                isDspActive: isDspActive,
                                audioSessionId: audioSessionId,
                                currentOutputDevice: currentOutputDevice,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              const EngineTelemetryPanel(initialExpanded: true),
                              const SizedBox(height: AppSpacing.md),
                              _buildReliabilityCard(p),
                              const SizedBox(height: AppSpacing.md),

                              // Active Effects Summary Header
                              Row(
                                children: [
                                  Text(
                                    context.l10n.activeAudioStages,
                                    style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: AppTracking.wide,
                                      color: p.accent,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.xs,
                                        vertical: AppSpacing.s2),
                                    decoration: BoxDecoration(
                                      color: (_report?.activeEffectNames
                                                  .isNotEmpty ==
                                              true)
                                          ? AppColors.studioGreen
                                              .withValues(alpha: 0.15)
                                          : p.surfaceContainerHigh,
                                      borderRadius: AppRadii.r6All,
                                    ),
                                    child: Text(
                                      context.l10n.dspActiveEffectsCount(
                                          _report?.activeEffectNames.length ??
                                              0),
                                      style: TextStyle(
                                        fontSize: AppFontSize.tiny,
                                        fontWeight: FontWeight.w800,
                                        color: (_report?.activeEffectNames
                                                    .isNotEmpty ==
                                                true)
                                            ? AppColors.studioGreen
                                            : p.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.s10),

                              // List of DSP stages
                              if (_report != null && _report!.stages.isNotEmpty)
                                ..._report!.stages.map(
                                  (stage) => _buildStageCard(stage, p),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: p.surfaceContainer,
                                    borderRadius: AppRadii.r12All,
                                    border: Border.all(color: p.hairline),
                                  ),
                                  child: Center(
                                    child: Text(
                                      context.l10n.noDspStages,
                                      style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: AppFontSize.label),
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

  Widget _buildMasterEngineCard({
    required PulsrPalette p,
    required bool isEqEnabled,
    required bool isDspActive,
    required int? audioSessionId,
    required AudioOutputInfo? currentOutputDevice,
  }) {
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
    } else if (!rawAttached &&
        hasOem &&
        (rep?.isNativeDspLoaded == true) &&
        (rep?.activeDspStagesMask ?? 0) != 0) {
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
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(
          color: isBypassed
              ? AppColors.dacGold.withValues(alpha: 0.4)
              : (isAttached
                  ? p.accent.withValues(alpha: 0.3)
                  : (isPendingNoSession || isOemSoftDetached
                      ? p.warning.withValues(alpha: 0.35)
                      : p.hairline)),
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
                            : (isOemSoftDetached
                                ? Icons.warning_amber_rounded
                                : Icons.sensors_off_rounded))),
                color: isBypassed
                    ? AppColors.dacGold
                    : (isAttached
                        ? AppColors.studioGreen
                        : (isPendingNoSession || isOemSoftDetached
                            ? p.warning
                            : p.error)),
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  isBypassed
                      ? context.l10n.dspBitPerfectDirectPassThrough
                      : (isAttached
                          ? context.l10n.dspAudioEffectSessionActive(sessionId)
                          : (isPendingNoSession
                              ? context.l10n.dspSessionPendingPlayTrack
                              : (isOemSoftDetached
                                  ? context.l10n.dspHalDetachedDolbyNativeDsp
                                  : context
                                      .l10n.dspAudioEffectSessionDetached))),
                  style: TextStyle(
                    fontSize: AppFontSize.bodySmall,
                    fontWeight: FontWeight.w800,
                    color: isBypassed
                        ? AppColors.dacGold
                        : (isAttached
                            ? p.textPrimary
                            : (isPendingNoSession || isOemSoftDetached
                                ? p.warning
                                : p.error)),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: isBypassed
                      ? AppColors.dacGold.withValues(alpha: 0.15)
                      : (isAttached
                          ? AppColors.studioGreen.withValues(alpha: 0.15)
                          : (isPendingNoSession || isOemSoftDetached
                              ? p.warning.withValues(alpha: 0.15)
                              : p.error.withValues(alpha: 0.15))),
                  borderRadius: AppRadii.r6All,
                ),
                child: Text(
                  isBypassed
                      ? context.l10n.dspStatusBypassed
                      : (isAttached
                          ? context.l10n.dspStatusAttached
                          : (isPendingNoSession
                              ? context.l10n.dspStatusPending
                              : (isOemSoftDetached
                                  ? context.l10n.dspStatusHalOff
                                  : context.l10n.dspStatusDetached))),
                  style: TextStyle(
                    fontSize: AppFontSize.tiny,
                    fontWeight: FontWeight.w800,
                    color: isBypassed
                        ? AppColors.dacGold
                        : (isAttached
                            ? AppColors.studioGreen
                            : (isPendingNoSession || isOemSoftDetached
                                ? p.warning
                                : p.error)),
                  ),
                ),
              ),
            ],
          ),
          if (isOemSoftDetached) ...[
            const SizedBox(height: AppSpacing.s10),
            Container(
              padding: const EdgeInsets.all(AppSpacing.s10),
              decoration: BoxDecoration(
                color: p.warning.withValues(alpha: 0.1),
                borderRadius: AppRadii.r10All,
                border: Border.all(color: p.warning.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_rounded, size: 16, color: p.warning),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      context.l10n.dolbyHijackDesc,
                      style: TextStyle(
                          fontSize: AppFontSize.caption,
                          height: 1.35,
                          color: p.textSecondary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final cubit = context.read<SettingsCubit>();
                    await cubit.setDspPreference('oem');
                    if (!mounted) return;
                    messenger.showSnackBar(
                        SnackBar(content: Text(context.l10n.switchedToOem)));
                    unawaited(_refreshReport());
                  } catch (_) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                        SnackBar(content: Text(context.l10n.switchPrefFailed)));
                  }
                },
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: Text(context.l10n.fixSwitchOem,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.label)),
                style: FilledButton.styleFrom(
                    backgroundColor: p.warning,
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.s10)),
              ),
            ),
          ],
          if (isPendingNoSession) ...[
            const SizedBox(height: AppSpacing.s10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  // Best-effort reattach using current PlayerState session.
                  final sid = audioSessionId;
                  if (sid != null && sid > 0) {
                    try {
                      await AudioEffectsChannel().setAudioSessionId(sid);
                    } catch (_) {}
                  }
                  // Refresh report after attempt
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.retryingHal)));
                  unawaited(_refreshReport());
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(context.l10n.retryAttach,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.label)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: p.accent,
                    side: BorderSide(color: p.accent.withValues(alpha: 0.4)),
                    visualDensity: VisualDensity.compact),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s10),
          // Resync DSP Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isResyncing ? null : () => _resyncDsp(context),
              icon: _isResyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(
                _isResyncing
                    ? context.l10n.dspResyncing
                    : context.l10n.dspResyncAction,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.onAccent,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s10),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: AppSpacing.s10),

          // Diagnostic stats table
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildStatChip(
                  p,
                  context.l10n.dspStatDspEngine,
                  rep?.isNativeDspLoaded == true
                      ? context.l10n.dspStatDspEngineNative
                      : context.l10n.dspStatDspEngineAndroid),
              _buildStatChip(
                  p,
                  context.l10n.dspStatDspPreference,
                  rep?.dspPreference.toUpperCase() ??
                      context.l10n.dspStatNative),
              _buildStatChip(
                p,
                context.l10n.dspStatMasterEq,
                isEqEnabled ? context.l10n.dspStatOn : context.l10n.dspStatOff,
                isHighlight: isEqEnabled,
              ),
              _buildStatChip(
                p,
                context.l10n.dspStatMasterDsp,
                isDspActive ? context.l10n.dspStatOn : context.l10n.dspStatOff,
                isHighlight: isDspActive,
              ),
              _buildStatChip(
                p,
                'CODEC',
                currentOutputDevice?.btCodecName ?? 'PCM',
              ),
              _buildStatChip(
                p,
                'LATENCY',
                '${((_pipelineLatencyFrames / (currentOutputDevice?.sampleRate ?? 44100)) * 1000.0).toStringAsFixed(1)} ms ($_pipelineLatencyFrames f)',
              ),
              _buildStatChip(
                p,
                'BIT-PERFECT',
                isBypassed ? 'BYPASSED' : 'OFF',
                isHighlight: isBypassed,
              ),
              if (rep?.hasOemAudio == true)
                _buildStatChip(
                  p,
                  context.l10n.dspStatOemAudioAlert,
                  rep?.detectedOemEngines.join(', ') ??
                      context.l10n.dspStatDetected,
                  isWarning: true,
                ),
              _buildStatChip(
                p,
                context.l10n.dspStatOutputTarget,
                context.l10n.dspStatOutputFormat(
                    currentOutputDevice?.sampleRate ?? 44100,
                    currentOutputDevice?.bitDepth ?? 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReliabilityCard(PulsrPalette p) {
    return StreamBuilder<DspReliabilityCounters>(
      stream: DspReliabilityTracker.instance.stream,
      initialData: DspReliabilityTracker.instance.counters,
      builder: (context, snapshot) {
        final counters =
            snapshot.data ?? DspReliabilityTracker.instance.counters;
        final hasError = counters.lastRedactedError != null &&
            counters.lastRedactedError!.isNotEmpty;

        return Container(
          padding: const EdgeInsets.all(AppSpacing.s14),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: AppRadii.r16All,
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_heart_rounded, size: 18, color: p.accent),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    context.l10n.dspReliabilityTitle,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.wide,
                      color: p.accent,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await DspReliabilityTracker.instance.resetCounters();
                      if (mounted) setState(() {});
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      context.l10n.dspResetCounters,
                      style: TextStyle(
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w700,
                        color: p.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Divider(height: 1, color: p.hairline),
              const SizedBox(height: AppSpacing.s10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStatChip(
                    p,
                    context.l10n.dspNativeSetterRejections,
                    '${counters.nativeSetterRejection}',
                    isWarning: counters.nativeSetterRejection > 0,
                  ),
                  _buildStatChip(
                    p,
                    context.l10n.dspBridgeTimeouts,
                    '${counters.bridgeTimeoutFailure}',
                    isWarning: counters.bridgeTimeoutFailure > 0,
                  ),
                  _buildStatChip(
                    p,
                    context.l10n.dspRouteResyncFailures,
                    '${counters.routeResyncFailure}',
                    isWarning: counters.routeResyncFailure > 0,
                  ),
                  _buildStatChip(
                    p,
                    context.l10n.dspSessionReattachFailures,
                    '${counters.sessionReattachFailure}',
                    isWarning: counters.sessionReattachFailure > 0,
                  ),
                  _buildStatChip(
                    p,
                    context.l10n.dspAutoDegradeEvents,
                    '${counters.autoDegradeActivation} / ${counters.autoDegradeRecovery}',
                    isWarning: counters.autoDegradeActivation > 0,
                  ),
                ],
              ),
              if (hasError) ...[
                const SizedBox(height: AppSpacing.s10),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s10),
                  decoration: BoxDecoration(
                    color: p.error.withValues(alpha: 0.1),
                    borderRadius: AppRadii.r10All,
                    border: Border.all(color: p.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 16, color: p.error),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.dspLatestError,
                              style: TextStyle(
                                fontSize: AppFontSize.micro,
                                fontWeight: FontWeight.w800,
                                color: p.error,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              counters.lastRedactedError!,
                              style: TextStyle(
                                fontSize: AppFontSize.caption,
                                color: p.textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatChip(PulsrPalette p, String label, String value,
      {bool isHighlight = false, bool isWarning = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: isWarning
            ? p.warning.withValues(alpha: 0.12)
            : (isHighlight
                ? p.accent.withValues(alpha: 0.12)
                : p.surfaceContainerHigh),
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: isWarning
              ? p.warning.withValues(alpha: 0.4)
              : (isHighlight ? p.accent.withValues(alpha: 0.3) : p.hairline),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.dspStatChipLabel(label),
            style: TextStyle(
              fontSize: AppFontSize.tiny,
              color: p.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: isWarning
                  ? p.warning
                  : (isHighlight ? p.accent : p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageCard(DspStageDebugInfo stage, PulsrPalette p) {
    final bool isActive =
        stage.isEnabled && !stage.isBypassed && !stage.isDegraded;
    final bool isBypassed = stage.isBypassed;
    final bool isDegraded = stage.isDegraded;

    final Color statusColor = isBypassed
        ? AppColors.dacGold
        : (isDegraded
            ? p.error
            : (isActive ? AppColors.studioGreen : p.textSecondary));

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r12All,
        border: Border.all(
          color: isActive ? statusColor.withValues(alpha: 0.4) : p.hairline,
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
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  stage.name,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                decoration: BoxDecoration(
                  color: p.surfaceContainerHigh,
                  borderRadius: AppRadii.r4All,
                ),
                child: Text(
                  stage.category,
                  style: TextStyle(
                    fontSize: AppFontSize.micro,
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: AppRadii.r4All,
                ),
                child: Text(
                  isBypassed
                      ? context.l10n.dspStatusBypassed
                      : (isDegraded
                          ? context.l10n.dspStatusDegraded
                          : (isActive
                              ? context.l10n.dspStageStatusActive
                              : context.l10n.dspStageStatusOff)),
                  style: TextStyle(
                    fontSize: AppFontSize.micro,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            stage.statusDescription,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: isActive ? p.textPrimary : p.textSecondary,
              fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
