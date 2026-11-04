// lib/features/settings/presentation/widgets/headphone_safety_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/sound_dose_tracker_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_dialog.dart';

/// Sheet displaying WHO-ITU H.870 / EN 62368-1 sound dose tracking and
/// automatic headphone safety protection controls.
class HeadphoneSafetySheet extends StatefulWidget {
  const HeadphoneSafetySheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => const HeadphoneSafetySheet(),
    );
  }

  @override
  State<HeadphoneSafetySheet> createState() => _HeadphoneSafetySheetState();
}

class _HeadphoneSafetySheetState extends State<HeadphoneSafetySheet> {
  final SoundDoseTrackerService _dose = SoundDoseTrackerService();
  Timer? _pollTimer;

  double _weeklyDose = 0.0;
  double _budget = SoundDoseTrackerService.defaultBudget;
  bool _safetyEnabled = false;
  bool _attenuationActive = false;
  bool _loading = true;

  /// Dose consumed as a fraction of the user's budget — at a 25 % budget the
  /// gauge is full after a quarter of the reference dose, which is the whole
  /// point of choosing one.
  double get _usedFraction => SoundDoseTrackerService.budgetUsedFraction(
      weeklyDose: _weeklyDose, budget: _budget);

  @override
  void initState() {
    super.initState();
    _refreshState();
    unawaited(_loadSafetyPreference());
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) _pollTelemetry();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshState() async {
    try {
      final snapshot = await _dose.read();
      if (!mounted) return;
      setState(() {
        _weeklyDose = snapshot.weeklyDose;
        _budget = snapshot.budget;
        _attenuationActive = snapshot.attenuationActive;
        _loading = false;
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to refresh headphone safety state',
          error: e, stackTrace: st, category: 'HeadphoneSafetySheet');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadSafetyPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSafety = prefs.getBool(PrefsKeys.headphoneSafetyEnabled);
      if (!mounted || savedSafety == null) return;
      setState(() => _safetyEnabled = savedSafety);
    } catch (e, st) {
      ErrorLogger.log('Failed to read headphone safety preference',
          error: e, stackTrace: st, category: 'HeadphoneSafetySheet');
    }
  }

  Future<void> _persistSafetyEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.headphoneSafetyEnabled, enabled);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist headphone safety preference',
          error: e, stackTrace: st, category: 'HeadphoneSafetySheet');
    }
  }

  Future<void> _pollTelemetry() async {
    try {
      final snapshot = await _dose.read();
      if (!mounted) return;
      if (snapshot.weeklyDose != _weeklyDose ||
          snapshot.attenuationActive != _attenuationActive) {
        setState(() {
          _weeklyDose = snapshot.weeklyDose;
          _attenuationActive = snapshot.attenuationActive;
        });
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to poll headphone safety telemetry',
          error: e, stackTrace: st, category: 'HeadphoneSafetySheet');
    }
  }

  Future<void> _toggleSafety(bool enabled) async {
    try {
      await _dose.applyBudget(budget: _budget, safetyEnabled: enabled);
      if (!mounted) return;
      setState(() => _safetyEnabled = enabled);
      unawaited(_persistSafetyEnabled(enabled));
      await _refreshState();
    } catch (e, st) {
      ErrorLogger.log('Headphone safety was not applied',
          error: e, stackTrace: st, category: 'HeadphoneSafetySheet');
    }
  }

  /// The budget IS the native engagement threshold, so choosing a smaller one
  /// makes the existing safety stage act sooner instead of adding a second
  /// limiter that could disagree with it.
  Future<void> _selectBudget(double tier) async {
    final normalized = SoundDoseTrackerService.normalizeBudget(tier);
    if (normalized == _budget) return;
    try {
      setState(() => _budget = normalized);
      await _dose.applyBudget(
          budget: normalized, safetyEnabled: _safetyEnabled);
      await _refreshState();
    } catch (e, st) {
      ErrorLogger.log('Failed to apply the sound dose budget',
          error: e, stackTrace: st, category: 'HeadphoneSafetySheet');
    }
  }

  Future<void> _confirmResetDose() async {
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: context.l10n.resetWeeklyDoseTitle,
      message: context.l10n.resetWeeklyDoseDesc,
      confirmLabel: context.l10n.resetDoseAction,
      cancelLabel: context.l10n.cancel,
      isDestructive: true,
      icon: Icons.restore_rounded,
    );

    if (confirmed == true && mounted) {
      await _dose.resetDose();
      await _refreshState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.weeklyDoseResetSnackbar),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Color _getDoseColor(PulsrPalette p) {
    final used = _usedFraction;
    if (used >= 1.0) return AppColors.error;
    if (used >= 0.8) return p.warning;
    return p.accent;
  }

  /// Compact quiet-time wording. The engine releases at 95 % of the budget, so
  /// the figure is derived from the same decay constant the native stage uses.
  String _formatQuietTime(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    if (hours < 48) return '${hours}h ${minutes % 60}m';
    return '${(minutes / 1440).toStringAsFixed(1)}d';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dosePercent = (_usedFraction * 100.0).clamp(0.0, 999.0);
    final doseColor = _getDoseColor(p);
    final quietTime = DoseSnapshot(
      weeklyDose: _weeklyDose,
      budget: _budget,
      attenuationActive: _attenuationActive,
    ).quietTimeUntilClear;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s10),
                  decoration: BoxDecoration(
                    color: doseColor.withValues(alpha: 0.15),
                    borderRadius: AppRadii.r12All,
                  ),
                  child: Icon(
                    Icons.health_and_safety_rounded,
                    color: doseColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.headphoneSafetyTitle,
                        style: const TextStyle(
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.headphoneSafetyStandard,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.label,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Dose Gauge Card
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: p.surfaceContainer.withValues(alpha: 0.7),
                borderRadius: AppRadii.r16All,
                border: Border.all(
                  color: _attenuationActive
                      ? AppColors.error
                      : p.hairline.withValues(alpha: 0.4),
                  width: _attenuationActive ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.weeklySoundAllowance,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.body,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _loading ? '...' : '${dosePercent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: doseColor,
                          fontSize: AppFontSize.headline,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s10),
                  ClipRRect(
                    borderRadius: AppRadii.r8All,
                    child: LinearProgressIndicator(
                      value: _usedFraction.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: p.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(doseColor),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        _attenuationActive
                            ? Icons.warning_amber_rounded
                            : (_usedFraction >= 0.8
                                ? Icons.info_outline_rounded
                                : Icons.check_circle_outline_rounded),
                        color: doseColor,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _attenuationActive
                              ? context.l10n.safetyLimiterActiveDesc
                              : (_usedFraction >= 0.8
                                  ? context.l10n.highSoundDoseWarning
                                  : context.l10n.optimalExposureDesc),
                          style: TextStyle(
                            color: doseColor,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (quietTime != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        context.l10n.doseQuietUntilClear(
                            _formatQuietTime(quietTime)),
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.caption,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Weekly dose budget selector
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.doseBudgetLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: AppFontSize.body,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.doseBudgetDesc,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.caption,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s10),
                  Wrap(
                    spacing: AppSpacing.s10,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final tier in SoundDoseTrackerService.budgetTiers)
                        ChoiceChip(
                          label: Text('${(tier * 100).round()} %'),
                          selected: _budget == tier,
                          onSelected: (_) => unawaited(_selectBudget(tier)),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Protection Switch Tile
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.l10n.headphoneSafetyToggleTitle,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                context.l10n.headphoneSafetyToggleDesc,
                style: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.caption),
              ),
              value: _safetyEnabled,
              activeTrackColor: p.accent,
              activeThumbColor: p.onAccent,
              onChanged: _toggleSafety,
            ),
            const SizedBox(height: AppSpacing.md),

            // Reset Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.r12All,
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text(context.l10n.resetDoseAction),
              onPressed: _confirmResetDose,
            ),
          ],
        ),
      ),
    );
  }
}
