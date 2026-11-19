// lib/features/player/presentation/abx_screen.dart
//
// Blind ABX listening test screen (P2-10).
//
// The listener compares two conditions — A: DSP bypassed, B: DSP active —
// without knowing which one the hidden stimulus X is, then answers "X is A"
// or "X is B" per trial. The score and the binomial p-value come straight
// from AbxCubit/AbxSession; this file only renders them.

import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/abx_report_export.dart';
import '../../../core/services/hires_audio_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../data/audio/audio_handler.dart';
import '../../../domain/models/abx_session.dart';
import '../../../domain/models/audio_output_info.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../cubit/abx_cubit.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';

class AbxScreen extends StatefulWidget {
  const AbxScreen({
    super.key,
    this.trials = AbxCubit.defaultTrials,
    this.sessionFactory,
    this.getTempDirectory,
    this.getSaveDirectory,
    this.shareReport,
    this.onReportSaved,
    this.outputInfoProvider,
  });

  final int trials;
  final AbxSession Function(int trials)? sessionFactory;
  final Future<Directory> Function()? getTempDirectory;
  final Future<Directory> Function()? getSaveDirectory;
  final Future<ShareResult> Function(AbxReportArtifact artifact)? shareReport;
  final Future<void> Function(AbxReportArtifact artifact)? onReportSaved;
  final AudioOutputInfo? Function()? outputInfoProvider;

  @override
  State<AbxScreen> createState() => _AbxScreenState();
}

class _AbxScreenState extends State<AbxScreen> {
  late final AbxCubit _cubit;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final PlayerCubit player = context.read<PlayerCubit>();
    // The A/B mechanism is `PlayerCubit.setBypassCompare`, which is a
    // PlayerDspController extension whose holder is @visibleForTesting. The
    // screen therefore drives the exact delegate that forwarder wraps:
    // PulsrAudioHandler -> EqualizerManager -> AudioEffectsChannel.
    final PulsrAudioHandler? handler = getIt.isRegistered<PulsrAudioHandler>()
        ? getIt<PulsrAudioHandler>()
        : null;
    _cubit = AbxCubit(
      switchCondition: (bool bypass) async {
        await handler?.setBypassCompare(bypass: bypass);
      },
      isReady: () => handler != null && _canRun(player.state),
      trials: widget.trials,
      sessionFactory: widget.sessionFactory,
    );
  }

  /// A test needs something to listen to and a DSP chain worth bypassing.
  static bool _canRun(PlayerState state) =>
      state.currentSong != null && state.isDspActive;

  @override
  void dispose() {
    // close() restores the un-bypassed path before the cubit is torn down.
    unawaited(_cubit.close());
    super.dispose();
  }

  void _start() {
    _cubit.start();
  }

  void _answer(AbxAnswer answer) {
    _cubit.answer(answer);
  }

  AudioOutputInfo? _resolveOutputInfo() {
    final override = widget.outputInfoProvider?.call();
    if (override != null) return override;
    if (getIt.isRegistered<SettingsCubit>()) {
      final fromSettings = getIt<SettingsCubit>().state.currentOutputDevice;
      if (fromSettings != null) return fromSettings;
    }
    if (getIt.isRegistered<HiResAudioService>()) {
      return getIt<HiResAudioService>().currentOutputInfo;
    }
    return null;
  }

  AbxReport _buildCompletedReport() {
    final song = context.read<PlayerCubit>().state.currentSong;
    final output = _resolveOutputInfo();
    final outputDevice = output != null
        ? AbxOutputDeviceInfo(
            name: output.deviceName,
            type: output.activeDeviceType,
            isUsbDac: output.isUsbDac,
            sampleRate: output.sampleRate > 0
                ? output.sampleRate
                : output.nativeSampleRate,
            bitDepth: output.bitDepth > 0 ? output.bitDepth : null,
            isBitPerfectActive: output.isBitPerfectActive,
          )
        : const AbxOutputDeviceInfo(
            name: 'Unknown',
            type: 'unknown',
            isUsbDac: false,
          );
    final activeSampleRate = (output?.sampleRate ?? 0) > 0
        ? output!.sampleRate
        : (output?.nativeSampleRate ?? song?.sampleRate);
    return _cubit.buildReport(
      outputDevice: outputDevice,
      sampleRate: activeSampleRate,
      codec: song?.codec ?? 'Unknown',
      trackTitle: song?.title,
      trackArtist: song?.artist,
      sourceSampleRate: song?.sampleRate,
      sourceBitDepth: song?.bitDepth,
    );
  }

  Future<void> _shareReport() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final l10n = context.l10n;
      final report = _buildCompletedReport();
      final directory =
          await (widget.getTempDirectory ?? getTemporaryDirectory)();
      final artifact = await exportAbxReport(report, directory: directory);
      final ShareResult result = widget.shareReport != null
          ? await widget.shareReport!(artifact)
          : await SharePlus.instance.share(
              ShareParams(
                files: <XFile>[
                  XFile(artifact.file.path, mimeType: 'application/json'),
                ],
                text: artifact.jsonText,
                subject: l10n.abxScreenTitle,
              ),
            );
      if (!mounted || result.status == ShareResultStatus.dismissed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(artifact.file.uri.pathSegments.last),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e, st) {
      ErrorLogger.log(
        'ABX report share failed',
        error: e,
        stackTrace: st,
        category: 'AbxScreen',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.exportFailed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveReport() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final report = _buildCompletedReport();
      final directory = await (widget.getSaveDirectory ??
          getApplicationDocumentsDirectory)();
      final artifact = await exportAbxReport(report, directory: directory);
      if (widget.onReportSaved != null) {
        await widget.onReportSaved!(artifact);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(artifact.file.uri.pathSegments.last),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e, st) {
      ErrorLogger.log(
        'ABX report save failed',
        error: e,
        stackTrace: st,
        category: 'AbxScreen',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.exportFailed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PulsrPalette p = context.palette;
    final AppLocalizations l10n = context.l10n;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Text(l10n.abxScreenTitle),
        backgroundColor: Colors.transparent,
        foregroundColor: p.textPrimary,
      ),
      body: SafeArea(
        // Playback can stop (or DSP can be switched off) while the screen is
        // open; re-evaluate the gate instead of leaving a dead Start button.
        child: BlocListener<PlayerCubit, PlayerState>(
          listenWhen: (PlayerState previous, PlayerState next) =>
              _canRun(previous) != _canRun(next),
          listener: (_, __) => _cubit.refreshReadiness(),
          child: BlocBuilder<AbxCubit, AbxState>(
            bloc: _cubit,
            builder: (BuildContext context, AbxState state) {
              return ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s18,
                    AppSpacing.s14, AppSpacing.s18, AppSpacing.s28),
                children: <Widget>[
                  _buildIntro(p),
                  const SizedBox(height: AppSpacing.sm),
                  if (state.isComplete)
                    _buildResult(p, state)
                  else if (state.isRunning)
                    _buildTrial(p, state)
                  else
                    _buildIdle(p, state),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(PulsrPalette p) {
    final AppLocalizations l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.hearing_rounded, color: p.accent, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.abxScreenTitle,
                  style: TextStyle(
                    fontSize: AppFontSize.bodyLarge,
                    fontWeight: FontWeight.w800,
                    color: p.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Text(
            l10n.abxScreenSubtitle,
            style: TextStyle(
              fontSize: AppFontSize.bodySmall,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s10),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _conditionChip(p, 'A', l10n.abxBypassCondition),
              _conditionChip(p, 'B', l10n.abxDspCondition),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdle(PulsrPalette p, AbxState state) {
    final AppLocalizations l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!state.canStart) ...<Widget>[
          _notice(p, l10n.abxNeedsPlayback),
          const SizedBox(height: AppSpacing.sm),
        ],
        FilledButton.icon(
          onPressed: state.canStart ? _start : null,
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: Text(
            l10n.abxStart,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          ),
        ),
      ],
    );
  }

  Widget _buildTrial(PulsrPalette p, AbxState state) {
    final AppLocalizations l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              l10n.abxTrialLabel(state.trialNumber, state.total),
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w800,
                letterSpacing: AppTracking.wide,
                color: p.accent,
              ),
            ),
            const Spacer(),
            _scoreChip(p, state),
          ],
        ),
        const SizedBox(height: AppSpacing.s10),
        Text(
          l10n.abxQuestion,
          style: TextStyle(
            fontSize: AppFontSize.titleLarge,
            fontWeight: FontWeight.w800,
            height: 1.2,
            color: p.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: _stimulusButton(
                p: p,
                letter: 'A',
                label: l10n.abxBypassCondition,
                selected: state.activeCondition == AbxStimulus.a,
                onTap: () => _cubit.playCondition(AbxStimulus.a),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _stimulusButton(
                p: p,
                letter: 'B',
                label: l10n.abxDspCondition,
                selected: state.activeCondition == AbxStimulus.b,
                onTap: () => _cubit.playCondition(AbxStimulus.b),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _stimulusButton(
                p: p,
                letter: 'X',
                // Hidden stimulus: intentionally unlabelled.
                label: '\u2022 \u2022 \u2022',
                selected: state.activeCondition == AbxStimulus.x,
                onTap: () => _cubit.playCondition(AbxStimulus.x),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: () => _answer(AbxAnswer.a),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.textPrimary,
                  side: BorderSide(color: p.hairline),
                  minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                ),
                child: Text(
                  l10n.abxAnswerA,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _answer(AbxAnswer.b),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.textPrimary,
                  side: BorderSide(color: p.hairline),
                  minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                ),
                child: Text(
                  l10n.abxAnswerB,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        if (state.lastAnswerCorrect != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _answerFeedback(p, state.lastAnswerCorrect!),
        ],
      ],
    );
  }

  Widget _buildResult(PulsrPalette p, AbxState state) {
    final AppLocalizations l10n = context.l10n;
    final Color verdictColor = _verdictColor(p, state.verdictKey);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: verdictColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.insights_rounded, color: verdictColor, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.abxResultTitle,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w800,
                  letterSpacing: AppTracking.wide,
                  color: verdictColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '${state.correctCount} / ${state.total}',
                style: TextStyle(
                  fontSize: AppFontSize.display,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures()
                  ],
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.abxCorrectShort,
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Text(
            l10n.abxPValue(_formatPValue(state.pValue)),
            style: TextStyle(
              fontSize: AppFontSize.bodySmall,
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _verdictLabel(l10n, state.verdictKey),
            style: TextStyle(
              fontSize: AppFontSize.title,
              fontWeight: FontWeight.w800,
              color: verdictColor,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exporting ? null : _shareReport,
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(
                    l10n.share,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.textPrimary,
                    side: BorderSide(color: p.hairline),
                    minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exporting ? null : _saveReport,
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: Text(
                    l10n.save,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.textPrimary,
                    side: BorderSide(color: p.hairline),
                    minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => unawaited(_cubit.restart()),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text(
                l10n.abxRestart,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.onAccent,
                minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _conditionChip(PulsrPalette p, String letter, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: p.surfaceContainerHigh,
        borderRadius: AppRadii.r8All,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            letter,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w800,
              color: p.accent,
            ),
          ),
          const SizedBox(width: AppSpacing.s6),
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w600,
              color: p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreChip(PulsrPalette p, AbxState state) {
    final String label = '${state.correctCount}/${state.answeredCount}';
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: p.surfaceContainerHigh,
        borderRadius: AppRadii.r6All,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppFontSize.caption,
          fontWeight: FontWeight.w800,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          color: p.textPrimary,
        ),
      ),
    );
  }

  Widget _stimulusButton({
    required PulsrPalette p,
    required String letter,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: AppRadii.r14All,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.s14, horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color:
              selected ? p.accent.withValues(alpha: 0.16) : p.surfaceContainer,
          borderRadius: AppRadii.r14All,
          border: Border.all(
            color: selected ? p.accent : p.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: <Widget>[
            Text(
              letter,
              style: TextStyle(
                fontSize: AppFontSize.titleXL,
                fontWeight: FontWeight.w800,
                color: selected ? p.accent : p.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w600,
                color: selected ? p.accent : p.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _answerFeedback(PulsrPalette p, bool correct) {
    final AppLocalizations l10n = context.l10n;
    final Color color = correct ? p.success : p.error;
    return Row(
      children: <Widget>[
        Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 16, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          correct ? l10n.abxCorrectShort : l10n.abxIncorrectShort,
          style: TextStyle(
            fontSize: AppFontSize.label,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _notice(PulsrPalette p, String message) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s10),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.1),
        borderRadius: AppRadii.r10All,
        border: Border.all(color: p.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_rounded, size: 16, color: p.warning),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppFontSize.label,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: p.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Localized label for the stable verdict keys of [AbxSession].
  static String _verdictLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case AbxSession.chanceKey:
        return l10n.abxVerdictChance;
      case AbxSession.suggestiveKey:
        return l10n.abxVerdictSuggestive;
      case AbxSession.significantKey:
        return l10n.abxVerdictSignificant;
      case AbxSession.strongKey:
        return l10n.abxVerdictStrong;
      case AbxSession.insufficientKey:
      default:
        return l10n.abxVerdictInsufficient;
    }
  }

  static Color _verdictColor(PulsrPalette p, String key) {
    switch (key) {
      case AbxSession.strongKey:
      case AbxSession.significantKey:
        return p.success;
      case AbxSession.suggestiveKey:
        return p.accent;
      case AbxSession.chanceKey:
      case AbxSession.insufficientKey:
      default:
        return p.textSecondary;
    }
  }

  /// Four decimals down to 1e-4, scientific notation below that so a tiny
  /// p-value never renders as a misleading `0.0000`.
  static String _formatPValue(double pValue) {
    if (pValue.isNaN) return '-';
    if (pValue < 0.0001) return pValue.toStringAsExponential(2);
    return pValue.toStringAsFixed(4);
  }
}
