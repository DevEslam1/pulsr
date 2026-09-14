// lib/features/player/presentation/widgets/quran_mode_sheet.dart
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/earbud_optimization_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../domain/models/quran_mode_profile.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

/// Bottom sheet entry point for Quran Mode.
class QuranModeSheet extends StatelessWidget {
  const QuranModeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QuranModeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: Adaptive.sheetConstraints(context),
        child: Material(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const QuranModePanel(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.menu_book_rounded,
                        color: p.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quran Mode',
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            )),
                        Text(context.l10n.reciterDesc,
                          style:
                              TextStyle(color: p.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: enabled,
                    activeTrackColor: p.accent,
                    activeThumbColor: p.onAccent,
                    onChanged: (v) => cubit.setQuranModeEnabled(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Reciter styles
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(context.l10n.reciterStyle,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  )),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: QuranReciterStyle.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                      fontSize: 12,
                    ),
                    backgroundColor: p.surfaceContainer,
                    selectedColor: p.accent,
                    side: BorderSide(color: p.hairline),
                    showCheckmark: false,
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${style.tagline} • ${style.description}',
                style: TextStyle(color: p.textTertiary, fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 16),

            // Tuning sliders
            _QuranSliderTile(
              icon: Icons.church_rounded,
              title: 'Mosque Ambience',
              subtitle: 'Convolution reverb for a hall-like space',
              value: state.reverbWetDry.clamp(0.0, 0.6),
              max: 0.6,
              enabled: enabled,
              valueLabel: '${(state.reverbWetDry * 100).round()}%',
              onChanged: (v) => cubit.setQuranAmbience(v),
            ),
            _QuranSliderTile(
              icon: Icons.local_fire_department_rounded,
              title: 'Vocal Warmth',
              subtitle: 'Harmonic richness on the reciter\'s voice',
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
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Row(
                children: [
                  Icon(Icons.speed_rounded, color: p.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.learningSpeed,
                            style: TextStyle(
                                color: p.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        Text(context.l10n.reciterSpeedDesc,
                            style: TextStyle(
                                color: p.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
            const SizedBox(height: 18),

            // Detected output hardware
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(context.l10n.outputHardware,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  )),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FutureBuilder<EarbudCapabilities>(
                future: _capsFuture,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return _card(
                      p,
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: SizedBox(
                            width: 18,
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
                        _kv(p, 'Device', caps.deviceName),
                        _kv(p, 'Codec',
                            '${caps.codec.label} (${caps.codec.quality})'),
                        _kv(
                            p,
                            'Format',
                            '${caps.bitDepth}-bit • '
                                '${caps.sampleRateHz ~/ 1000} kHz'),
                        _kv(
                          p,
                          'Latency',
                          caps.isBluetooth ? '~${caps.latencyMs} ms' : '—',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          caps.isBluetooth
                              ? 'Lossy Bluetooth gets a small presence '
                                  'compensation and a shorter reverb tail.'
                              : 'Wired / USB output is left untouched by '
                                  'hardware compensation.',
                          style:
                              TextStyle(color: p.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // Reset
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(context.l10n.sibilanceDesc,
                style: TextStyle(color: p.textTertiary, fontSize: 10.5),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: child,
    );
  }

  Widget _kv(PulsrPalette p, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child:
                Text(k, style: TextStyle(color: p.textTertiary, fontSize: 12)),
          ),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 12,
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: p.textSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        style:
                            TextStyle(color: p.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Text(valueLabel,
                  style: TextStyle(
                      color: p.accent,
                      fontSize: 12,
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
