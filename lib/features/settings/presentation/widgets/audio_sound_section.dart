// lib/features/settings/presentation/widgets/audio_sound_section.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/services/bluetooth_latency_calibrator.dart';
import '../../../../core/telemetry/audio_session_log.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../data/audio/audio_effects_channel.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../player/presentation/widgets/audio_quality_sheet.dart';
import '../../../player/presentation/widgets/equalizer_sheet.dart';
import '../../../player/presentation/widgets/dsp_inspector_sheet.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import 'battery_optimization_card.dart';
import 'bit_perfect_conflict_dialog.dart';
import 'bt_latency_tap_sheet.dart';
import 'cast_section.dart';
import 'headphone_safety_sheet.dart';
import 'room_correction_sheet.dart';
import 'settings_conflict_card.dart';
import 'settings_section.dart';
import 'settings_slider_row.dart';
import 'settings_tiles.dart';
import 'studio_bridge_footer.dart';
import 'usb_dac_section.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';
part 'audio_sound_dop_selector.dart';
part 'audio_output_section.dart';
part 'audio_dsp_section.dart';
part 'audio_gain_section.dart';
part 'audio_diagnostic_section.dart';

/// Loudness and gain controls: ReplayGain segmented control + preamp sliders, DVC, resampler.
class AudioGainSection extends StatelessWidget {
  final SettingsState state;

  const AudioGainSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      icon: Icons.volume_up_rounded,
      title: context.l10n.expGainTitle,
      children: [
        RepaintBoundary(
          child: _GainSection(
            state: state,
            onResolveReplayGainConflict: (ctx, cubit) async {
              await cubit.setBypassDspOnBitPerfect(false);
              if (!ctx.mounted) return;
              ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(ctx.l10n.bpResolved),
              ));
            },
          ),
        ),
      ],
    );
  }
}

/// Effects & DSP surface: collapsed disclosure in Normal mode; expanded list in Professional.
class AudioEffectsDspSection extends StatefulWidget {
  final SettingsState state;

  const AudioEffectsDspSection({super.key, required this.state});

  @override
  State<AudioEffectsDspSection> createState() => _AudioEffectsDspSectionState();
}

class _AudioEffectsDspSectionState extends State<AudioEffectsDspSection> {
  bool _hasPcmDspPath = false;

  @override
  void initState() {
    super.initState();
    _hasPcmDspPath = AudioEffectsChannel().hasPcmDspPath;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hasPcmDspPath = AudioEffectsChannel().hasPcmDspPath;
  }

  Future<void> _autoCalibrateBluetoothLatency(
      BuildContext context, SettingsCubit cubit) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    final codec = widget.state.currentOutputDevice?.btCodecName;
    final result =
        await BluetoothLatencyCalibrator().calibrate(codecName: codec);
    await cubit.setBluetoothLatencyOffsetMs(result.offsetMs);
    messenger?.showSnackBar(SnackBar(
      content: Text(
        '${l10n.btCalibrated(result.offsetMs)}'
        '${codec != null && codec.isNotEmpty ? ' ($codec)' : ''}',
      ),
    ));
  }

  Future<void> _exportSessionLogs(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final noLogsText = context.l10n.noSessionLogs;
    final exportFailedText = context.l10n.exportFailed;
    final shareText = context.l10n.settingsSessionLogsShareText;
    try {
      final file = await AudioSessionLog.instance.exportToFile();
      if (file == null || await file.length() == 0) {
        messenger?.showSnackBar(SnackBar(
          content: Text(noLogsText),
        ));
        return;
      }
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/x-ndjson')],
        text: shareText,
      ));
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(exportFailedText)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;

    if (!widget.state.isProfessional) {
      return SettingsSection(
        icon: Icons.tune_rounded,
        title: l10n.expEqTitle,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppRadii.cardRadius,
              onTap: () {
                HapticFeedback.selectionClick();
                showStudioExplainerSheet(context);
              },
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.14),
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
                          Row(
                            children: [
                              Text(
                                l10n.expEqTitle,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.bodySmall,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.s6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.15),
                                  borderRadius: AppRadii.full,
                                ),
                                child: Text(
                                  'PRO',
                                  style: TextStyle(
                                    color: p.accent,
                                    fontSize: AppFontSize.tiny,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            l10n.expEqPro,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.caption,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: p.textTertiary, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return SettingsSection(
      icon: Icons.tune_rounded,
      title: l10n.expEqTitle,
      children: [
        RepaintBoundary(
          child: _DspSection(
            state: widget.state,
            hasPcmDspPath: _hasPcmDspPath,
          ),
        ),
        settingsCardDivider(p),
        RepaintBoundary(
          child: _DiagnosticSection(
            state: widget.state,
            onCalibrateBt: _autoCalibrateBluetoothLatency,
            onExportLogs: _exportSessionLogs,
          ),
        ),
      ],
    );
  }
}

/// Unified composite sound section for backwards compatibility.
class AudioSoundSection extends StatelessWidget {
  final SettingsState state;

  const AudioSoundSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          icon: Icons.speaker_group_outlined,
          title: context.l10n.settingsOutputAudioQuality,
          children: [
            DeviceAdaptiveOutputSection(state: state),
          ],
        ),
        AudioGainSection(state: state),
        AudioEffectsDspSection(state: state),
        const CastSection(),
      ],
    );
  }
}
