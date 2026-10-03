part of 'audio_sound_section.dart';

/// B-25 Sub-widget 2: DSP features, Room Correction, Inspector, Loudness Contour, System effects.
class _DspSection extends StatelessWidget {
  final SettingsState state;
  final bool hasPcmDspPath;

  const _DspSection({
    required this.state,
    required this.hasPcmDspPath,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    final isAndroid = PlatformCapabilities.isAndroid;
    final unsupported = context.l10n.settingsNotAvailablePlatform;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAndroid ? () => RoomCorrectionSheet.show(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.s10),
              child: Row(
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 20,
                    color: isAndroid ? p.accent : p.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.l10n.rcTitle,
                                style: TextStyle(
                                  color: isAndroid
                                      ? p.textPrimary
                                      : p.textTertiary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.info_outline_rounded,
                                  size: 18, color: p.textTertiary),
                              tooltip: context.l10n.learnMore,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => showAudioFeatureInfoDialog(
                                context,
                                AudioFeatureRegistry.roomCorrection,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          isAndroid ? context.l10n.rcSubtitle : unsupported,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Icon(Icons.chevron_right_rounded,
                      color: p.textTertiary, size: 20),
                ],
              ),
            ),
          ),
        ),
        settingsCardDivider(p),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAndroid ? () => DspInspectorSheet.show(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.s10),
              child: Row(
                children: [
                  Icon(
                    Icons.sensors_rounded,
                    size: 20,
                    color: isAndroid ? p.accent : p.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.dspInspectorDebug,
                          style: TextStyle(
                            color: isAndroid ? p.textPrimary : p.textTertiary,
                            fontWeight: FontWeight.w700,
                            fontSize: AppFontSize.body,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          isAndroid
                              ? context.l10n.settingsDspInspectorDesc
                              : unsupported,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Icon(Icons.chevron_right_rounded,
                      color: p.textTertiary, size: 20),
                ],
              ),
            ),
          ),
        ),
        settingsCardDivider(p),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.surround_sound_rounded, size: 20, color: p.accent),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      context.l10n.systemEffectsTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.body,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                !isAndroid
                    ? unsupported
                    : switch (state.systemEffectsStatus) {
                        'bypassed' =>
                          context.l10n.systemEffectsSubtitleBypassed,
                        'active' => context.l10n.systemEffectsSubtitleActive,
                        'unsupportedDevice' =>
                          context.l10n.systemEffectsSubtitleUnsupported,
                        _ => context.l10n
                            .settingsStatusLabel(state.systemEffectsStatus),
                      },
                style: TextStyle(
                  color: state.systemEffectsStatus == 'bypassed'
                      ? p.success
                      : p.textSecondary,
                  fontSize: AppFontSize.label,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: 'auto',
                      label: Text(context.l10n.systemEffectsAuto,
                          style: const TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700)),
                    ),
                    ButtonSegment(
                      value: 'tryDisable',
                      label: Text(context.l10n.systemEffectsTryDisable,
                          style: const TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700)),
                    ),
                    ButtonSegment(
                      value: 'leaveOn',
                      label: Text(context.l10n.systemEffectsLeaveOn,
                          style: const TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                  selected: {state.systemEffectsPolicy},
                  onSelectionChanged: isAndroid
                      ? (selected) {
                          if (selected.isNotEmpty) {
                            cubit.setSystemEffectsPolicy(selected.first);
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        settingsCardDivider(p),
        // Loudness Contour (Fletcher–Munson) — B-24: uses cached hasPcmDspPath
        BlocBuilder<PlayerCubit, PlayerState>(
          buildWhen: (prev, curr) =>
              prev.isLoudnessContourEnabled != curr.isLoudnessContourEnabled ||
              prev.loudnessContourIntensity != curr.loudnessContourIntensity,
          builder: (context, playerState) {
            final l10n = context.l10n;
            final playerCubit = context.read<PlayerCubit>();
            final isLoudnessContourEnabled =
                playerState.isLoudnessContourEnabled;
            final loudnessContourIntensity =
                playerState.loudnessContourIntensity;
            final lcBlocked = AudioConflicts.dspBlockedByBitPerfect(
              bitPerfectOutput: state.bitPerfectOutput,
              bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
              device: state.currentOutputDevice,
            );
            return Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded,
                          color: lcBlocked != null ? p.textTertiary : p.accent,
                          size: 20),
                      const SizedBox(width: AppSpacing.s10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.dspLoudnessTitle,
                                    style: TextStyle(
                                      color: lcBlocked != null
                                          ? p.textTertiary
                                          : p.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.body,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.info_outline_rounded,
                                      size: 18, color: p.textTertiary),
                                  tooltip: context.l10n.learnMore,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => showAudioFeatureInfoDialog(
                                      context,
                                      AudioFeatureRegistry.loudnessContour,
                                      conflictReason: lcBlocked),
                                ),
                              ],
                            ),
                            Text(
                              lcBlocked ?? l10n.dspLoudnessSubtitle,
                              style: TextStyle(
                                color: lcBlocked != null
                                    ? p.error
                                    : p.textSecondary,
                                fontSize: AppFontSize.label,
                                fontWeight: lcBlocked != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: isLoudnessContourEnabled,
                        activeTrackColor: p.accent,
                        activeThumbColor: p.onAccent,
                        onChanged: lcBlocked != null || !hasPcmDspPath
                            ? null
                            : (val) => playerCubit.setLoudnessContour(val),
                      ),
                    ],
                  ),
                  if (lcBlocked == null &&
                      hasPcmDspPath &&
                      isLoudnessContourEnabled) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    SettingSliderRow(
                      label: l10n.dspLoudnessIntensity,
                      value: loudnessContourIntensity,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      defaultValue: 0.0,
                      formatValue: (v) => '${(v * 100).round()}%',
                      onChanged: (v) =>
                          playerCubit.setLoudnessContour(true, intensity: v),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    Text(
                      l10n.dspLoudnessReplayGainNote,
                      style: TextStyle(
                          color: p.textTertiary, fontSize: AppFontSize.tiny),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
