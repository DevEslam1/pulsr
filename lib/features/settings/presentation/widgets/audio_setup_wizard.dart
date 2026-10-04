// lib/features/settings/presentation/widgets/audio_setup_wizard.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_pressable.dart';
import '../../cubit/settings_cubit.dart';

enum AudioWizardOutputType { usbDac, bluetooth, speaker, headphones }

enum AudioWizardPriority { fidelity, balanced, dataSaver }

enum AudioWizardTransition { gapless, crossfade, none }

class AudioSetupWizardSheet extends StatefulWidget {
  final SettingsCubit cubit;

  const AudioSetupWizardSheet({super.key, required this.cubit});

  static Future<void> show(BuildContext context, {SettingsCubit? cubit}) {
    final activeCubit = cubit ?? context.read<SettingsCubit>();
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => AudioSetupWizardSheet(cubit: activeCubit),
    );
  }

  @override
  State<AudioSetupWizardSheet> createState() => _AudioSetupWizardSheetState();
}

class _AudioSetupWizardSheetState extends State<AudioSetupWizardSheet> {
  int _currentStep = 0;
  late AudioWizardOutputType _selectedOutput;
  AudioWizardPriority _selectedPriority = AudioWizardPriority.balanced;
  AudioWizardTransition _selectedTransition = AudioWizardTransition.gapless;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    final device = widget.cubit.state.currentOutputDevice;
    if (device?.isUsbDac == true) {
      _selectedOutput = AudioWizardOutputType.usbDac;
      _selectedPriority = AudioWizardPriority.fidelity;
    } else if (device?.isBluetooth == true) {
      _selectedOutput = AudioWizardOutputType.bluetooth;
      _selectedPriority = AudioWizardPriority.balanced;
    } else {
      _selectedOutput = AudioWizardOutputType.speaker;
      _selectedPriority = AudioWizardPriority.balanced;
    }
  }

  Future<void> _applyConfiguration() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);

    try {
      final cubit = widget.cubit;

      // 1. Apply coherent priority preset
      switch (_selectedPriority) {
        case AudioWizardPriority.fidelity:
          await cubit.applyMaximumQualityPreset();
          break;
        case AudioWizardPriority.balanced:
          await cubit.applySmoothPlaybackPreset();
          break;
        case AudioWizardPriority.dataSaver:
          await cubit.applyPoorNetworkPreset();
          break;
      }

      // 2. Hardware-specific guard rails
      if (_selectedOutput == AudioWizardOutputType.bluetooth) {
        await cubit.setBitPerfectOutput(false);
      } else if (_selectedOutput == AudioWizardOutputType.usbDac &&
          _selectedPriority == AudioWizardPriority.fidelity) {
        await cubit.setFollowTrackSampleRate(true);
      }

      // 3. Apply transition choice
      switch (_selectedTransition) {
        case AudioWizardTransition.gapless:
          await cubit.setCrossfade(0.0);
          await cubit.setGapless(true);
          break;
        case AudioWizardTransition.crossfade:
          await cubit.setGapless(false);
          await cubit.setCrossfade(3.0);
          break;
        case AudioWizardTransition.none:
          await cubit.setGapless(false);
          await cubit.setCrossfade(0.0);
          break;
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(context.l10n.settingsWizardTitle),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title & Progress Bar
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.16),
                    borderRadius: AppRadii.r10All,
                  ),
                  child: Icon(Icons.auto_awesome_rounded,
                      color: p.accent, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsWizardTitle,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.bodyLarge,
                          fontWeight: FontWeight.w800,
                          letterSpacing: AppTracking.heading,
                        ),
                      ),
                      Text(
                        'Step ${_currentStep + 1} of 3',
                        style: TextStyle(
                          color: p.accent,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: p.textTertiary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Progress Indicator Bars
            Row(
              children: [
                for (int i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: AnimatedContainer(
                      duration: context.motionMs(200),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _currentStep
                            ? p.accent
                            : p.surfaceContainerHigh,
                        borderRadius: AppRadii.full,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Animated Step Body
            AnimatedSwitcher(
              duration: context.motionMs(220),
              child: switch (_currentStep) {
                0 => _buildStep1(context),
                1 => _buildStep2(context),
                _ => _buildStep3(context),
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            // Bottom Action Buttons
            Row(
              children: [
                if (_currentStep > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        side: BorderSide(color: p.hairline),
                        shape: RoundedRectangleBorder(
                            borderRadius: AppRadii.r12All),
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _currentStep--);
                      },
                      child: Text(
                        context.l10n.cancel,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.onAccent,
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      shape:
                          RoundedRectangleBorder(borderRadius: AppRadii.r12All),
                    ),
                    onPressed: _isApplying
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            if (_currentStep < 2) {
                              setState(() => _currentStep++);
                            } else {
                              _applyConfiguration();
                            }
                          },
                    child: _isApplying
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: p.onAccent,
                            ),
                          )
                        : Text(
                            _currentStep < 2
                                ? 'Next'
                                : l10n.settingsWizardApply,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: AppFontSize.bodySmall,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsWizardStep1Title,
          style: TextStyle(
            color: context.palette.textPrimary,
            fontSize: AppFontSize.title,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.settingsWizardStep1Subtitle,
          style: TextStyle(
            color: context.palette.textSecondary,
            fontSize: AppFontSize.caption,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildOptionCard(
          context,
          icon: Icons.usb_rounded,
          title: 'USB DAC / Dongle',
          subtitle: 'External hardware DAC with bit-perfect & DSD support',
          isSelected: _selectedOutput == AudioWizardOutputType.usbDac,
          onTap: () =>
              setState(() => _selectedOutput = AudioWizardOutputType.usbDac),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildOptionCard(
          context,
          icon: Icons.bluetooth_audio_rounded,
          title: 'Bluetooth Audio',
          subtitle: 'Wireless headphones, TWS earbuds, or car audio',
          isSelected: _selectedOutput == AudioWizardOutputType.bluetooth,
          onTap: () =>
              setState(() => _selectedOutput = AudioWizardOutputType.bluetooth),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildOptionCard(
          context,
          icon: Icons.speaker_rounded,
          title: 'Speaker / Built-in',
          subtitle: 'Phone speakers with system equalization and loudness',
          isSelected: _selectedOutput == AudioWizardOutputType.speaker,
          onTap: () =>
              setState(() => _selectedOutput = AudioWizardOutputType.speaker),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildOptionCard(
          context,
          icon: Icons.headphones_rounded,
          title: 'Wired Headphones',
          subtitle: '3.5mm jack or passive analog headset',
          isSelected: _selectedOutput == AudioWizardOutputType.headphones,
          onTap: () => setState(
              () => _selectedOutput = AudioWizardOutputType.headphones),
        ),
      ],
    );
  }

  Widget _buildStep2(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsWizardStep2Title,
          style: TextStyle(
            color: context.palette.textPrimary,
            fontSize: AppFontSize.title,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.settingsWizardStep2Subtitle,
          style: TextStyle(
            color: context.palette.textSecondary,
            fontSize: AppFontSize.caption,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildOptionCard(
          context,
          icon: Icons.album_rounded,
          title: l10n.settingsWizardFidelity,
          subtitle: l10n.settingsWizardFidelityDesc,
          badge: 'Hi-Res',
          isSelected: _selectedPriority == AudioWizardPriority.fidelity,
          onTap: () =>
              setState(() => _selectedPriority = AudioWizardPriority.fidelity),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildOptionCard(
          context,
          icon: Icons.auto_awesome_rounded,
          title: l10n.settingsWizardBalanced,
          subtitle: l10n.settingsWizardBalancedDesc,
          badge: 'Recommended',
          isSelected: _selectedPriority == AudioWizardPriority.balanced,
          onTap: () =>
              setState(() => _selectedPriority = AudioWizardPriority.balanced),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildOptionCard(
          context,
          icon: Icons.cloud_off_rounded,
          title: l10n.settingsWizardDataSaver,
          subtitle: l10n.settingsWizardDataSaverDesc,
          isSelected: _selectedPriority == AudioWizardPriority.dataSaver,
          onTap: () =>
              setState(() => _selectedPriority = AudioWizardPriority.dataSaver),
        ),
      ],
    );
  }

  Widget _buildStep3(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsWizardStep3Title,
          style: TextStyle(
            color: context.palette.textPrimary,
            fontSize: AppFontSize.title,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.settingsWizardStep3Subtitle,
          style: TextStyle(
            color: context.palette.textSecondary,
            fontSize: AppFontSize.caption,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildOptionCard(
          context,
          icon: Icons.graphic_eq_rounded,
          title: l10n.gaplessPlayback,
          subtitle: l10n.gaplessSubtitle,
          isSelected: _selectedTransition == AudioWizardTransition.gapless,
          onTap: () => setState(
              () => _selectedTransition = AudioWizardTransition.gapless),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildOptionCard(
          context,
          icon: Icons.shuffle_rounded,
          title: l10n.crossfade,
          subtitle: '3.0s smooth blending between tracks',
          isSelected: _selectedTransition == AudioWizardTransition.crossfade,
          onTap: () => setState(
              () => _selectedTransition = AudioWizardTransition.crossfade),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildOptionCard(
          context,
          icon: Icons.stop_circle_outlined,
          title: l10n.rgOff,
          subtitle: 'Standard track separation with zero overlap',
          isSelected: _selectedTransition == AudioWizardTransition.none,
          onTap: () =>
              setState(() => _selectedTransition = AudioWizardTransition.none),
        ),
      ],
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    String? badge,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: isSelected,
      label: title,
      child: PulsrPressable(
        pressedScale: 0.985,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: context.motionMs(180),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: isSelected
                ? p.accentContainer.withValues(alpha: 0.4)
                : p.surfaceContainer,
            borderRadius: AppRadii.cardRadius,
            border: Border.all(
              color: isSelected ? p.accent : p.hairline,
              width: isSelected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected
                      ? p.accent.withValues(alpha: 0.2)
                      : p.surfaceContainerHigh,
                  borderRadius: AppRadii.r10All,
                ),
                child: Icon(
                  icon,
                  color: isSelected ? p.accent : p.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              color:
                                  isSelected ? p.textPrimary : p.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: AppFontSize.bodySmall,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6, vertical: 1),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.15),
                              borderRadius: AppRadii.full,
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                color: p.accent,
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: p.textTertiary,
                        fontSize: AppFontSize.caption,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? p.accent : p.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
