// lib/features/player/presentation/widgets/usb_rate_switch_dialog.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/pulsr_dialog.dart';

/// Modal dialog prompting the user when track sample rate is not natively supported
/// by the connected USB DAC, offering resampling with a persistent auto-switch preference.
class UsbRateSwitchDialog extends StatefulWidget {
  static const String prefsKeyAutoSwitch = 'usb_exclusive_auto_resample';

  final int trackSampleRate;
  final int targetSampleRate;
  final List<int> supportedRates;

  const UsbRateSwitchDialog({
    super.key,
    required this.trackSampleRate,
    required this.targetSampleRate,
    required this.supportedRates,
  });

  /// Finds the optimal supported DAC sample rate for the track rate.
  /// Prefers matching family (44.1k vs 48k) then closest rate.
  static int findBestSupportedRate(int trackRate, List<int> supportedRates) {
    if (supportedRates.isEmpty) return trackRate;
    if (supportedRates.contains(trackRate)) return trackRate;

    final is441Family = (trackRate % 11025 == 0) && (trackRate % 4000 != 0);

    // Try same family first
    final sameFamily = supportedRates.where((r) {
      final r441 = (r % 11025 == 0) && (r % 4000 != 0);
      return r441 == is441Family;
    }).toList();

    final candidates = sameFamily.isNotEmpty ? sameFamily : supportedRates;

    // Prefer higher or equal rate to avoid loss of high-frequency content
    final higher = candidates.where((r) => r >= trackRate).toList();
    if (higher.isNotEmpty) {
      higher.sort((a, b) => a.compareTo(b));
      return higher.first;
    }

    // Otherwise closest supported rate
    candidates.sort((a, b) => (a - trackRate).abs().compareTo((b - trackRate).abs()));
    return candidates.first;
  }

  /// Checks if track rate is supported by DAC. If unsupported and auto-switch
  /// is not permanently enabled, shows the dialog.
  /// Returns the target sample rate to stream at, or null if user cancelled.
  static Future<int?> checkAndPrompt(
    BuildContext context, {
    required int trackSampleRate,
    required List<int> supportedRates,
  }) async {
    if (supportedRates.isEmpty || supportedRates.contains(trackSampleRate)) {
      return trackSampleRate;
    }

    final targetRate = findBestSupportedRate(trackSampleRate, supportedRates);

    final prefs = await SharedPreferences.getInstance();
    final autoSwitch = prefs.getBool(prefsKeyAutoSwitch) ?? false;
    if (autoSwitch) {
      return targetRate;
    }

    if (!context.mounted) return targetRate;

    return PulsrDialogHelper.showCustomDialog<int>(
      context,
      builder: (_) => UsbRateSwitchDialog(
        trackSampleRate: trackSampleRate,
        targetSampleRate: targetRate,
        supportedRates: supportedRates,
      ),
    );
  }

  @override
  State<UsbRateSwitchDialog> createState() => _UsbRateSwitchDialogState();
}

class _UsbRateSwitchDialogState extends State<UsbRateSwitchDialog> {
  bool _rememberChoice = false;

  String _formatKhz(int rate) {
    final khz = rate / 1000.0;
    return rate % 1000 == 0 ? khz.toInt().toString() : khz.toStringAsFixed(1);
  }

  Future<void> _confirm() async {
    if (_rememberChoice) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(UsbRateSwitchDialog.prefsKeyAutoSwitch, true);
    }
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(widget.targetSampleRate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final trackStr = _formatKhz(widget.trackSampleRate);
    final targetStr = _formatKhz(widget.targetSampleRate);
    final supportedStr = widget.supportedRates.map(_formatKhz).join('/');

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 330,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: GlassContainer(
            borderRadius: BorderRadius.circular(AppRadii.r24),
            padding: const EdgeInsets.all(AppSpacing.s20),
            color: p.surface.withValues(alpha: 0.85),
            blur: 24,
            border: Border.all(
              color: AppColors.dacGold.withValues(alpha: 0.35),
              width: 1.2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.dacGold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.dacGold.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.usb_rounded,
                        color: AppColors.dacGold,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        context.l10n.dacRateSwitchTitle,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.l10n.dacRateSwitchBody(supportedStr, trackStr),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.body,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: p.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadii.r12),
                    border: Border.all(
                      color: p.hairline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.transform_rounded,
                          color: AppColors.dacGold, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          context.l10n.dacRateSwitchResample(targetStr),
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                InkWell(
                  onTap: () => setState(() => _rememberChoice = !_rememberChoice),
                  borderRadius: BorderRadius.circular(AppRadii.r8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _rememberChoice,
                            onChanged: (v) => setState(() => _rememberChoice = v ?? false),
                            activeColor: AppColors.dacGold,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            context.l10n.dacRateSwitchRemember,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.caption,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).pop(null),
                        style: TextButton.styleFrom(
                          foregroundColor: p.textSecondary,
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r12),
                          ),
                        ),
                        child: Text(context.l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dacGold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r12),
                          ),
                        ),
                        child: Text(
                          context.l10n.dacRateSwitchConfirm(targetStr),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
