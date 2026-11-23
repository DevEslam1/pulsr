part of '../equalizer_sheet.dart';

/// Normal-mode (`ExperienceMode.normal`) Quick Sound Studio:
/// interactive EQ curve, Preset Carousel, 3 macro tone sliders (Warmth/Bass,
/// Vocal Clarity, Soundstage/Air), AutoEQ badge, A/B Bypass toggle, and an
/// "Open Pro Studio" pill.
extension _EqQuickSoundView on _EqualizerSheetState {
  List<(String, String, EqPreset)> _quickPresets(BuildContext context) {
    return <(String, String, EqPreset)>[
      (
        'Flat',
        context.l10n.eqPresetFlat,
        EqPreset.defaultPresets.firstWhere(
          (p) => p.name == 'Flat',
          orElse: () => EqPreset.defaultPresets.first,
        ),
      ),
      (
        'Bass Boost',
        context.l10n.eqPresetBassBoost,
        EqPreset.defaultPresets.firstWhere(
          (p) => p.name == 'Bass Boost',
          orElse: () => EqPreset.defaultPresets.first,
        ),
      ),
      (
        'Vocal',
        context.l10n.eqPresetVocal,
        EqPreset.defaultPresets.firstWhere(
          (p) => p.name == 'Vocal Boost',
          orElse: () => EqPreset.defaultPresets.first,
        ),
      ),
      (
        'Treble',
        context.l10n.eqPresetTreble,
        const EqPreset(
          name: 'Treble',
          gains: [-1, -0.5, 0, 0, 1, 2, 3.5, 5, 6, 6.5],
          bassBoost: 0.0,
        ),
      ),
      (
        'Custom',
        context.l10n.eqPresetCustom,
        EqPreset(name: 'Custom', gains: List.filled(10, 0.0)),
      ),
    ];
  }

  Widget _buildQuickSoundView(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    final effectiveEnabled = state.isEqEnabled && dspBlocked == null;

    return SingleChildScrollView(
      key: const ValueKey('eq_quick_sound_view'),
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md, AppSpacing.s6, AppSpacing.md, AppSpacing.lg),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dspBlocked != null) ...[
            _conflictBanner(dspBlocked, p),
            const SizedBox(height: AppSpacing.xs),
          ],

          // 1. AutoEQ Badge & A/B Bypass Row
          _buildQuickStatusRow(
            context: context,
            cubit: cubit,
            state: state,
            p: p,
            dspBlocked: dspBlocked,
          ),
          const SizedBox(height: AppSpacing.sm),

          // 2. Interactive EQ Response Curve
          Container(
            height: 84,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.s6),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: BlocSelector<PlayerCubit, PlayerState, List<double>>(
              selector: (s) => s.eqPreset.gains,
              builder: (context, gains) => RepaintBoundary(
                child: EqCurveVisualizer(
                  gains: gains,
                  activeColor: effectiveEnabled ? p.accent : p.textTertiary,
                  height: 72,
                  showLabels: true,
                  selectedBandIndex: _activeDraggedBandIndex,
                  onGainChanged: dspBlocked == null
                      ? (idx, gain) {
                          if (!state.isEqEnabled) {
                            cubit.setEqualizerEnabled(true);
                          }
                          cubit.setBandGain(idx, gain);
                        }
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. Preset Carousel
          _buildQuickPresetCarousel(
            context: context,
            cubit: cubit,
            state: state,
            p: p,
            dspBlocked: dspBlocked,
          ),
          const SizedBox(height: AppSpacing.md),

          // 4. Three Macro Tone Sliders (Warmth/Bass, Vocal Clarity, Soundstage)
          _buildMacroSliders(context, cubit, p, spacing: AppSpacing.s10),
          const SizedBox(height: AppSpacing.lg),

          // 5. Open Pro Studio Pill
          _buildOpenProStudioPill(context, p),
        ],
      ),
    );
  }

  Widget _buildQuickStatusRow({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required PulsrPalette p,
    required String? dspBlocked,
  }) {
    final profile = state.selectedHeadphoneProfile;
    return Row(
      children: [
        // AutoEQ Badge
        Expanded(
          child: Semantics(
            button: true,
            label: profile != null
                ? '${context.l10n.autoEqLabel}: ${profile.name}'
                : context.l10n.autoEqSearch,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const ValueKey('eq_quick_autoeq_badge'),
                borderRadius: AppRadii.r12All,
                onTap: () {
                  PulsrHaptics.selectionClick();
                  PulsrSheetHelper.showPulsrSheet<void>(
                    context: context,
                    wrapWithContainer: false,
                    builder: (_) => const AutoEqSearchSheet(),
                  );
                },
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: profile != null
                        ? p.accent.withValues(alpha: 0.14)
                        : p.surfaceContainer,
                    borderRadius: AppRadii.r12All,
                    border: Border.all(
                      color: profile != null
                          ? p.accent.withValues(alpha: 0.4)
                          : p.hairline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.headphones_rounded,
                        size: 18,
                        color: profile != null ? p.accent : p.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              profile != null
                                  ? context.l10n.dspAutoEqVerified
                                  : context.l10n.autoEqLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w800,
                                color: profile != null
                                    ? p.accent
                                    : p.textSecondary,
                              ),
                            ),
                            Text(
                              profile?.name ?? context.l10n.autoEqSearch,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w600,
                                color: p.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (profile != null)
                        IconButton(
                          tooltip: context.l10n.reset,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget,
                          ),
                          icon: Icon(Icons.close_rounded,
                              size: 16, color: p.textSecondary),
                          onPressed: () => cubit.resetToFlat(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // A/B Bypass Toggle (hold to compare flat vs active EQ)
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.minTouchTarget,
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Center(
            child: Semantics(
              button: true,
              toggled: _effectiveIsAbComparing,
              label: context.l10n.abFlat,
              child: _buildAbCompareToggle(
                cubit: cubit,
                p: p,
                dspBlocked: dspBlocked,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickPresetCarousel({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required PulsrPalette p,
    required String? dspBlocked,
  }) {
    final preset = state.eqPreset;
    final simplifiedPresets = _quickPresets(context);
    final isStandardPreset =
        ['Flat', 'Bass Boost', 'Vocal Boost', 'Treble'].contains(preset.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.eqSoundProfiles,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w800,
            letterSpacing: AppTracking.wide,
            color: p.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: AppSpacing.minTouchTarget,
          child: ListView.separated(
            key: const ValueKey('eq_quick_preset_carousel'),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: simplifiedPresets.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, index) {
              final entry = simplifiedPresets[index];
              final key = entry.$1;
              final label = entry.$2;
              final itemPreset = entry.$3;
              final bool isSelected = key == 'Custom'
                  ? !isStandardPreset
                  : (preset.name == itemPreset.name ||
                      (key == 'Vocal' && preset.name == 'Vocal Boost'));

              return ChoiceChip(
                label: Text(label),
                selected: isSelected,
                selectedColor: p.accent.withValues(alpha: 0.22),
                backgroundColor: p.surfaceContainer,
                side: BorderSide(
                  color: isSelected
                      ? p.accent.withValues(alpha: 0.5)
                      : p.hairline,
                ),
                labelStyle: TextStyle(
                  color: isSelected ? p.accent : p.textSecondary,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: AppFontSize.label,
                ),
                onSelected: dspBlocked != null
                    ? null
                    : (_) {
                        PulsrHaptics.selectionClick();
                        if (!state.isEqEnabled) {
                          cubit.setEqualizerEnabled(true);
                        }
                        if (key == 'Custom') {
                          cubit.applyPreset(EqPreset(
                              name: 'Custom',
                              gains: List<double>.from(state.eqPreset.gains)));
                        } else {
                          cubit.applyPreset(itemPreset);
                        }
                      },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOpenProStudioPill(BuildContext context, PulsrPalette p) {
    return SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        child: OutlinedButton.icon(
          key: const ValueKey('eq_open_pro_studio_pill'),
          style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
            side: BorderSide(color: p.accent.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          ),
          icon: Icon(Icons.tune_rounded, size: 18, color: p.accent),
          label: Text(
            context.l10n.eqUnlockStudioConsole,
            style: TextStyle(
              fontSize: AppFontSize.bodySmall,
              fontWeight: FontWeight.w700,
              color: p.accent,
            ),
          ),
          onPressed: () {
            PulsrHaptics.lightImpact();
            _setStudioMode(context, true);
          },
        ),
      ),
    );
  }

  Widget _buildEssentialControlsPane(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dspBlocked != null) ...[
          _conflictBanner(dspBlocked, p),
          const SizedBox(height: AppSpacing.xs),
        ],
        _buildQuickStatusRow(
          context: context,
          cubit: cubit,
          state: state,
          p: p,
          dspBlocked: dspBlocked,
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildQuickPresetCarousel(
          context: context,
          cubit: cubit,
          state: state,
          p: p,
          dspBlocked: dspBlocked,
        ),
        const SizedBox(height: AppSpacing.md),
        _buildOpenProStudioPill(context, p),
      ],
    );
  }

  Widget _buildEssentialSlidersPane(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    final effectiveEnabled = state.isEqEnabled && dspBlocked == null;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 76,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.s6),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: BlocSelector<PlayerCubit, PlayerState, List<double>>(
              selector: (s) => s.eqPreset.gains,
              builder: (context, gains) => RepaintBoundary(
                child: EqCurveVisualizer(
                  gains: gains,
                  activeColor: effectiveEnabled ? p.accent : p.textTertiary,
                  height: 64,
                  selectedBandIndex: _activeDraggedBandIndex,
                  onGainChanged: dspBlocked == null
                      ? (idx, gain) {
                          if (!state.isEqEnabled) {
                            cubit.setEqualizerEnabled(true);
                          }
                          cubit.setBandGain(idx, gain);
                        }
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildMacroSliders(context, cubit, p, spacing: AppSpacing.s8),
        ],
      ),
    );
  }

}
