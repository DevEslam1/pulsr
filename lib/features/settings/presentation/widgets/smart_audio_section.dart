// lib/features/settings/presentation/widgets/smart_audio_section.dart
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/hires_audio_service.dart';
import '../../../../core/services/smart_audio_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../domain/services/smart_audio_plan.dart';
import '../../../../data/audio/headphone_profiles_repository.dart';
import '../../../../domain/services/device_profile_service.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// Settings surface for the Smart Audio coordinator.
///
/// Auto: automatically match the connected headphones to an AutoEQ correction
/// and negotiate the best output quality the device supports.
/// Manual: leave the user's EQ/effects/output choices untouched.
class SmartAudioSection extends StatefulWidget {
  const SmartAudioSection({super.key});

  @override
  State<SmartAudioSection> createState() => _SmartAudioSectionState();
}

class _SmartAudioSectionState extends State<SmartAudioSection> {
  late final SmartAudioService _service =
      getIt.isRegistered<SmartAudioService>()
          ? getIt<SmartAudioService>()
          : SmartAudioService();

  SmartAudioMode _mode = SmartAudioMode.auto;
  String? _deviceName;
  String? _matchedProfileName;
  String? _deviceDetectionError;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _isLoading = true);
    try {
      final mode = await _service.getMode();
      String? deviceName;
      String? matchedName;
      String? detectionError;
      try {
        final info = getIt.isRegistered<HiResAudioService>()
            ? getIt<HiResAudioService>().currentOutputInfo
            : null;
        if (info != null) {
          deviceName = info.deviceName;
          final key = DeviceProfileService.deviceKeyFromInfo(info);
          final link = await _service.linkForDeviceKey(key);
          if (link != null) {
            final repo = HeadphoneProfilesRepository();
            await repo.loadProfiles();
            matchedName = repo.getProfileById(link.profileId)?.name;
          }
        }
      } catch (e, st) {
        detectionError = e.toString();
        ErrorLogger.log('Error matching device profile in SmartAudioSection',
            error: e, stackTrace: st, category: 'SmartAudio');
      }
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _deviceName = deviceName;
        _matchedProfileName = matchedName;
        _deviceDetectionError = detectionError;
      });
    } catch (e, st) {
      ErrorLogger.log('Error reloading SmartAudioSection',
          error: e, stackTrace: st, category: 'SmartAudio');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setMode(SmartAudioMode mode) async {
    await _service.setMode(mode);
    if (!mounted) return;
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final isAuto = _mode == SmartAudioMode.auto;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            l10n.smartAudioSubtitle,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.label,
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<SmartAudioMode>(
            showSelectedIcon: true,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
            segments: [
              ButtonSegment<SmartAudioMode>(
                value: SmartAudioMode.auto,
                label: Text(l10n.smartAudioAuto),
                icon: const Icon(Icons.auto_awesome_rounded),
              ),
              ButtonSegment<SmartAudioMode>(
                value: SmartAudioMode.manual,
                label: Text(l10n.smartAudioManual),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) _setMode(selection.first);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        SizedBox(
          height: 38,
          child: AnimatedSwitcher(
            duration: context.motionMs(200),
            child: Text(
              isAuto ? l10n.smartAudioAutoDesc : l10n.smartAudioManualDesc,
              key: ValueKey<bool>(isAuto),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.label,
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (_deviceDetectionError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: p.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.r10),
              border: Border.all(color: p.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: p.error),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _deviceDetectionError!,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: p.error,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_isLoading) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${context.l10n.settingsAudioOutputDevice}...',
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  color: p.textTertiary,
                ),
              ),
            ],
          ),
        ] else if (_deviceName != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: p.surfaceContainerHigh.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadii.r10),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _deviceName!.toLowerCase().contains('speaker')
                          ? Icons.volume_up_rounded
                          : Icons.headphones_rounded,
                      size: 15,
                      color: isAuto ? p.accent : p.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        l10n.smartAudioDetectedDevice(_deviceName!),
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                      decoration: BoxDecoration(
                        color: (isAuto ? p.accent : p.textTertiary)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadii.r6),
                      ),
                      child: Text(
                        isAuto ? l10n.smartAudioAuto : l10n.smartAudioManual,
                        style: TextStyle(
                          fontSize: AppFontSize.tiny,
                          fontWeight: FontWeight.w700,
                          color: isAuto ? p.accent : p.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                AnimatedSwitcher(
                  duration: context.motionMs(200),
                  child: Text(
                    isAuto
                        ? (_matchedProfileName != null
                            ? l10n
                                .smartAudioMatchedProfile(_matchedProfileName!)
                            : l10n.smartAudioNoMatch)
                        : l10n.dspEqCurvesBypassed,
                    key: ValueKey<String>(
                      isAuto
                          ? (_matchedProfileName ?? 'no_match')
                          : 'manual_bypassed',
                    ),
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: p.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: p.surfaceContainerHigh.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppRadii.r10),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.headphones_outlined,
                  size: 15,
                  color: p.textTertiary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    context.l10n.noDevicesSeen,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: p.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
