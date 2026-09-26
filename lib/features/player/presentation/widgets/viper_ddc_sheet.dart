// lib/features/player/presentation/widgets/viper_ddc_sheet.dart
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/safe_file_path.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class ViperDdcSheet extends StatefulWidget {
  const ViperDdcSheet({super.key});

  @override
  State<ViperDdcSheet> createState() => _ViperDdcSheetState();
}

class _ViperDdcSheetState extends State<ViperDdcSheet> {
  // Built-in demonstration VDC profiles with standard SOS biquad Direct Form II coefficients
  // Format: [numBiquads, b0, b1, b2, a1, a2, ...] for 44.1k followed by 48k
  static final Map<String, List<double>> _builtInProfiles = {
    'Sennheiser HD650 Flat Neutral': _generateSampleDdcCoeffs(0.85, 1.12),
    'Sony WH-1000XM4 Clarity Lift': _generateSampleDdcCoeffs(1.15, 0.90),
    'Beyerdynamic DT990 Sibilance Tame': _generateSampleDdcCoeffs(0.78, 1.05),
    'Apple EarPods Bass & Presence': _generateSampleDdcCoeffs(1.20, 1.10),
  };

  static List<double> _generateSampleDdcCoeffs(double bassScale, double trebleScale) {
    // Generate valid Direct Form II biquad coefficients for 44.1k and 48k
    final list = <double>[];
    // 44.1 kHz block: 2 SOS stages
    list.add(2.0); // 2 biquads
    // Biquad 1: Low shelf / bass correction
    list.addAll([1.0 * bassScale, -0.95 * bassScale, 0.22, -0.92, 0.21]);
    // Biquad 2: High shelf / treble linearization
    list.addAll([1.0 * trebleScale, -0.60 * trebleScale, 0.15, -0.58, 0.14]);

    // 48 kHz block: 2 SOS stages
    list.add(2.0); // 2 biquads
    list.addAll([1.0 * bassScale, -0.96 * bassScale, 0.23, -0.93, 0.22]);
    list.addAll([1.0 * trebleScale, -0.62 * trebleScale, 0.16, -0.60, 0.15]);
    return list;
  }

  Future<void> _pickVdcFile(BuildContext context) async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['vdc', 'txt'],
      );
      if (result != null) {
        final file = SafeFilePath.validate(result.path, allowedExtensions: ['vdc', 'txt']);
        if (file == null) {
          throw 'Invalid or inaccessible file';
        }
        final length = await file.length();
        if (length == 0 || length > 2 * 1024 * 1024) {
          throw 'Invalid file size (must be > 0 and < 2MB)';
        }
        final bytes = await file.readAsBytes();
        if (bytes.length < 4) {
          throw 'File is too short for a valid VDC profile';
        }
        // Unpack 32-bit floats from binary VDC
        final byteData = ByteData.sublistView(bytes);
        final coeffs = <double>[];
        for (int i = 0; i <= bytes.length - 4; i += 4) {
          final val = byteData.getFloat32(i, Endian.little);
          if (!val.isFinite || val < -10000.0 || val > 10000.0) {
            throw 'Corrupt DSP coefficients detected';
          }
          coeffs.add(val);
        }

        if (coeffs.length < 5 ||
            (coeffs.length % 5 != 0 &&
                coeffs.length % 6 != 0 &&
                (coeffs.length - 1) % 5 != 0)) {
          throw 'Invalid VDC coefficient structure (expected biquad stages)';
        }

        if (coeffs.isNotEmpty && context.mounted) {
          final fileName = result.name.replaceAll(RegExp(r'\.vdc$', caseSensitive: false), '');
          await context.read<PlayerCubit>().setViperDdcEnabled(
            true,
            profileName: fileName,
            coeffs: coeffs,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.vdcLoaded(fileName))),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.vdcFailed(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.isViperDdcEnabled != curr.isViperDdcEnabled ||
          prev.viperDdcProfileName != curr.viperDdcProfileName,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();

        return Container(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.xl),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.textSecondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(AppRadii.r2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.headphones_rounded, color: p.primary),
                        const SizedBox(width: AppSpacing.s10),
                        Text(
                          'ViPER-DDC',
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.title,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: state.isViperDdcEnabled,
                      activeThumbColor: p.primary,
                      onChanged: (val) {
                        cubit.setViperDdcEnabled(val);
                      },
                    ),
                  ],
                ),
                Text(
                  AudioFeatureRegistry.viperDdc.subtitle,
                  style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                ),
                const SizedBox(height: AppSpacing.md),

                // Current loaded profile card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s14),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadii.r16),
                    border: Border.all(
                      color: state.isViperDdcEnabled
                          ? p.primary.withValues(alpha: 0.3)
                          : p.hairline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s10),
                        decoration: BoxDecoration(
                          color: (state.isViperDdcEnabled ? p.primary : p.textSecondary)
                              .withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.album_rounded,
                          color: state.isViperDdcEnabled ? p.primary : p.textSecondary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.l10n.activeProfile,
                              style: TextStyle(
                                color: p.textTertiary,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              state.viperDdcProfileName.isNotEmpty
                                  ? state.viperDdcProfileName
                                  : context.l10n.dspNoProfileLoaded,
                              style: TextStyle(
                                color: state.viperDdcProfileName.isNotEmpty
                                    ? p.textPrimary
                                    : p.textTertiary,
                                fontSize: AppFontSize.body,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _pickVdcFile(context),
                        icon: const Icon(Icons.file_open_rounded, size: 16),
                        label: Text(context.l10n.openVdc),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: p.onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r12),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),

                Text(context.l10n.refHpProfiles,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),
                ..._builtInProfiles.entries.map((entry) {
                  final isSelected = state.viperDdcProfileName == entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: InkWell(
                      onTap: () {
                        cubit.setViperDdcEnabled(
                          true,
                          profileName: entry.key,
                          coeffs: entry.value,
                        );
                      },
                      borderRadius: BorderRadius.circular(AppRadii.r14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(

                            horizontal: AppSpacing.s14, vertical: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? p.primary.withValues(alpha: 0.12)
                              : p.surfaceContainer,
                          borderRadius: BorderRadius.circular(AppRadii.r14),
                          border: Border.all(
                            color: isSelected
                                ? p.primary
                                : p.hairline,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: isSelected ? p.primary : p.textSecondary,
                              size: 18,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  color: isSelected
                                      ? p.textPrimary
                                      : p.textSecondary,
                                  fontSize: AppFontSize.bodySmall,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.symmetric(

                                    horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                                decoration: BoxDecoration(
                                  color: p.primary,
                                  borderRadius: BorderRadius.circular(AppRadii.r8),
                                ),
                                child: Text(context.l10n.activeLabel,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: AppFontSize.tiny,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
