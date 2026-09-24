// lib/features/settings/presentation/widgets/headphone_safety_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../data/audio/audio_effects_channel.dart';

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
  final AudioEffectsChannel _channel = AudioEffectsChannel();
  Timer? _pollTimer;

  double _weeklyDose = 0.0;
  bool _safetyEnabled = true;
  bool _attenuationActive = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshState();
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
    final dose = await _channel.getWeeklyDose();
    if (!mounted) return;
    final active = await _channel.isSafetyAttenuationActive();
    if (!mounted) return;
    setState(() {
      _weeklyDose = dose;
      _attenuationActive = active;
      _loading = false;
    });
  }

  Future<void> _pollTelemetry() async {
    final dose = await _channel.getWeeklyDose();
    if (!mounted) return;
    final active = await _channel.isSafetyAttenuationActive();
    if (!mounted) return;
    if (dose != _weeklyDose || active != _attenuationActive) {
      setState(() {
        _weeklyDose = dose;
        _attenuationActive = active;
      });
    }
  }

  Future<void> _toggleSafety(bool enabled) async {
    setState(() => _safetyEnabled = enabled);
    await _channel.setHeadphoneSafetyParams(
      enabled: enabled,
      doseThreshold: 1.0,
      safetyCeilingDb: -6.0,
    );
    await _refreshState();
  }

  Future<void> _confirmResetDose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.surfaceContainer,
        title: Text(context.l10n.resetWeeklyDoseTitle),
        content: Text(context.l10n.resetWeeklyDoseDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.resetDoseAction),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _channel.resetWeeklyDose();
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
    if (_weeklyDose >= 1.0) return AppColors.error;
    if (_weeklyDose >= 0.8) return p.warning;
    return p.accent;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dosePercent = (_weeklyDose * 100.0).clamp(0.0, 999.0);
    final doseColor = _getDoseColor(p);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s20),
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
                    borderRadius: BorderRadius.circular(AppRadii.r12),
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
                borderRadius: BorderRadius.circular(AppRadii.r16),
                border: Border.all(
                  color: _attenuationActive ? AppColors.error : p.hairline.withValues(alpha: 0.4),
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
                    borderRadius: BorderRadius.circular(AppRadii.r8),
                    child: LinearProgressIndicator(
                      value: (_weeklyDose).clamp(0.0, 1.0),
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
                            : (_weeklyDose >= 0.8
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
                              : (_weeklyDose >= 0.8
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
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Protection Switch Tile
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                "Automatic Safety Attenuation",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                "When weekly dose reaches 100%, smoothly engage lookahead safety limiter to clamp output peak to -6 dBFS.",
                style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.caption),
              ),
              value: _safetyEnabled,
              activeThumbColor: p.accent,
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
                  borderRadius: BorderRadius.circular(AppRadii.r12),
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
