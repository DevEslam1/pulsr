import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/earbud_optimization_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../domain/models/quran_mode_profile.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_switch.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// Bottom sheet entry point for Quran Mode.
class QuranModeSheet extends StatelessWidget {
  const QuranModeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => const QuranModeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const PulsrBottomSheetContainer(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QuranModePanel(),
            SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

/// The interactive control surface. Reused by [QuranModeSheet] and the
/// full-screen `/quran-mode` route.
class QuranModePanel extends StatefulWidget {
  const QuranModePanel({super.key});

  @override
  State<QuranModePanel> createState() => _QuranModePanelState();
}

class _QuranModePanelState extends State<QuranModePanel> {
  Future<EarbudCapabilities>? _capsFuture;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    _capsFuture ??= context.read<PlayerCubit>().detectEarbudCapabilities();

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (a, b) =>
          a.isQuranModeEnabled != b.isQuranModeEnabled ||
          a.quranReciterStyle != b.quranReciterStyle ||
          a.isReverbEnabled != b.isReverbEnabled ||
          a.reverbWetDry != b.reverbWetDry ||
          a.isSaturationEnabled != b.isSaturationEnabled ||
          a.saturationMix != b.saturationMix ||
          a.playbackSpeed != b.playbackSpeed,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final enabled = state.isQuranModeEnabled;
        final style = state.quranReciterStyle;
        final profile = QuranModeProfile.forStyle(style);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.xxs, AppSpacing.s20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s10),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadii.r14),
                    ),
                    child: Icon(Icons.menu_book_rounded,
                        color: p.accent, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.quranMode,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.title,
                              fontWeight: FontWeight.w800,
                            )),
                        Text(context.l10n.reciterDesc,
                          style:
                              TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
                        ),
                      ],
                    ),
                  ),
                  PulsrSwitch(
                    value: enabled,
                    onChanged: (v) => unawaited(cubit.setQuranModeEnabled(v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s14),

            // Reciter styles
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Text(context.l10n.reciterStyle,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.overline,
                  )),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(height: AppSpacing.s40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                itemCount: QuranReciterStyle.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, i) {
                  final s = QuranReciterStyle.values[i];
                  final selected = s == style;
                  return ChoiceChip(
                    selected: selected,
                    onSelected: (_) => cubit.setQuranReciterStyle(s),
                    label: Text(s.label),
                    labelStyle: TextStyle(
                      color: selected ? p.onAccent : p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: AppFontSize.label,
                    ),
                    backgroundColor: p.surfaceContainer,
                    selectedColor: p.accent,
                    side: BorderSide(color: p.hairline),
                    showCheckmark: false,
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Text(
                '${style.tagline} • ${style.description}',
                style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.label),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Tuning sliders
            _QuranSliderTile(
              icon: Icons.mosque_rounded,
              title: context.l10n.dspMosqueAmbience,
              subtitle: context.l10n.dspMosqueAmbienceDesc,
              value: state.reverbWetDry.clamp(0.0, 0.6),
              max: 0.6,
              enabled: enabled,
              valueLabel: '${(state.reverbWetDry * 100).round()}%',
              onChanged: (v) => cubit.setQuranAmbience(v),
            ),
            _QuranSliderTile(
              icon: Icons.local_fire_department_rounded,
              title: context.l10n.dspVocalWarmth,
              subtitle: context.l10n.dspVocalWarmthDesc,
              value: state.saturationMix.clamp(0.0, 0.6),
              max: 0.6,
              enabled: enabled,
              valueLabel: '${(state.saturationMix * 100).round()}%',
              onChanged: (v) => cubit.setSaturation(true,
                  drive: profile.saturationDrive,
                  mix: v,
                  tilt: profile.saturationTilt),
            ),

            // Learning speed
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.s6, AppSpacing.s20, 0),
              child: Row(
                children: [
                  Icon(Icons.speed_rounded, color: p.textSecondary, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.learningSpeed,
                            style: TextStyle(
                                color: p.textPrimary,
                                fontSize: AppFontSize.body,
                                fontWeight: FontWeight.w700)),
                        Text(context.l10n.reciterSpeedDesc,
                            style: TextStyle(
                                color: p.textSecondary, fontSize: AppFontSize.label)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0.5, label: Text('0.5x')),
                  ButtonSegment(value: 0.75, label: Text('0.75x')),
                  ButtonSegment(value: 1.0, label: Text('1.0x')),
                ],
                selected: {
                  [0.5, 0.75, 1.0].reduce((a, b) =>
                      (a - state.playbackSpeed).abs() <
                              (b - state.playbackSpeed).abs()
                          ? a
                          : b)
                },
                onSelectionChanged:
                    enabled ? (v) => cubit.setPlaybackSpeed(v.first) : null,
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(p.textPrimary),
                  side: WidgetStatePropertyAll(BorderSide(color: p.hairline)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s18),

            // Detected output hardware
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Text(context.l10n.outputHardware,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.overline,
                  )),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: FutureBuilder<EarbudCapabilities>(
                future: _capsFuture,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _card(
                      p,
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                        child: Text(
                          context.l10n.outputHardware,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return _card(
                      p,
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: SizedBox(width: AppSpacing.s18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    );
                  }
                  final caps = snap.data!;
                  return _card(
                    p,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv(p, context.l10n.dspDevice, caps.deviceName),
                        _kv(p, context.l10n.dspCodec,
                            '${caps.codec.label} (${caps.codec.quality})'),
                        _kv(
                            p,
                            context.l10n.format,
                            '${caps.bitDepth}-bit • '
                                '${caps.sampleRateHz ~/ 1000} kHz'),
                        _kv(
                          p,
                          context.l10n.dspLatency,
                          caps.isBluetooth ? '~${caps.latencyMs} ms' : '—',
                        ),
                        const SizedBox(height: AppSpacing.s6),
                        Text(
                          caps.isBluetooth
                              ? context.l10n.dspBluetoothCompensationDesc
                              : context.l10n.dspWiredCompensationDesc,
                          style:
                              TextStyle(color: p.textTertiary, fontSize: AppFontSize.caption),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Reset
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          enabled ? () => cubit.reapplyQuranProfile() : null,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: Text(context.l10n.resetProfile),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.accent,
                        side:
                            BorderSide(color: p.accent.withValues(alpha: 0.5)),
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Text(context.l10n.sibilanceDesc,
                style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.tiny),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(PulsrPalette p, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r14),
        border: Border.all(color: p.hairline),
      ),
      child: child,
    );
  }

  Widget _kv(PulsrPalette p, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child:
                Text(k, style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.label)),
          ),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _QuranSliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double max;
  final bool enabled;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  const _QuranSliderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.max,
    required this.enabled,
    required this.valueLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, 0, AppSpacing.s20, AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: p.textSecondary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.body,
                            fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        style:
                            TextStyle(color: p.textSecondary, fontSize: AppFontSize.label)),
                  ],
                ),
              ),
              Text(valueLabel,
                  style: TextStyle(
                      color: p.accent,
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: value.clamp(0.0, max),
            max: max,
            onChanged: enabled ? onChanged : null,
            activeColor: p.accent,
            inactiveColor: p.hairline,
          ),
        ],
      ),
    );
  }
}
