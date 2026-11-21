// lib/features/onboarding/presentation/onboarding_steps_part.dart
part of 'onboarding_screen.dart';

extension _OnboardingStepsPart on _OnboardingScreenState {
  // ===========================================================================
  // Step 2: Interactive Experience Mode + Top 4 Player Themes Live Preview
  // ===========================================================================
  Widget _buildStep2(BuildContext context) {
    final p = context.palette;
    final isLandscape = context.isLandscape;
    final l10n = context.l10n;
    final cubit = context.read<SettingsCubit>();
    final experienceMode = context.select<SettingsCubit, ExperienceMode>(
      (c) => c.state.experienceMode,
    );
    final selectedTheme = context.select<SettingsCubit, PlayerThemeMode>(
      (c) => c.state.playerThemeMode,
    );
    final selectedAccent = context.select<SettingsCubit, int>(
      (c) => c.state.customAccentColorValue,
    );
    final isPro = experienceMode == ExperienceMode.professional;
    final shouldAnimate = PulsrMotion.shouldAnimate(context);

    final themes = <({PlayerThemeMode mode, String title, IconData icon})>[
      (
        mode: PlayerThemeMode.classic,
        title: l10n.settingsThemeClassicStandard,
        icon: Icons.crop_square_rounded,
      ),
      (
        mode: PlayerThemeMode.card,
        title: l10n.settingsThemeCardGlass,
        icon: Icons.layers_rounded,
      ),
      (
        mode: PlayerThemeMode.vinyl,
        title: l10n.settingsThemeVinylTurntable,
        icon: Icons.album_rounded,
      ),
      (
        mode: PlayerThemeMode.waveform,
        title: l10n.settingsThemeFullBleed,
        icon: Icons.waves_rounded,
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s28,
            vertical: isLandscape ? AppSpacing.xxs : AppSpacing.sm,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.onboardingBeautiful,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: AppTracking.heading,
                        color: p.textPrimary,
                      ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                l10n.onboardingBeautifulDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: p.textSecondary,
                      height: 1.4,
                    ),
              ),
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.md),

              // 1. Interactive Experience Mode Card (Normal vs Professional)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: p.surfaceCard,
                  borderRadius: AppRadii.r20All,
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isPro
                              ? Icons.tune_rounded
                              : Icons.auto_awesome_rounded,
                          color: p.accent,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            l10n.experienceModeTitle,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.bodySmall,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      width: double.infinity,
                      child: PulsrSegmentedControl(
                        segments: [
                          PulsrSegment(
                            label: l10n.experienceModeNormal,
                            icon: Icons.auto_awesome_rounded,
                          ),
                          PulsrSegment(
                            label: l10n.experienceModeProfessional,
                            icon: Icons.tune_rounded,
                          ),
                        ],
                        selectedIndex: isPro ? 1 : 0,
                        onChanged: (index) {
                          final nextMode = index == 1
                              ? ExperienceMode.professional
                              : ExperienceMode.normal;
                          cubit.setExperienceMode(nextMode);
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      isPro
                          ? l10n.experienceModeProfessionalDesc
                          : l10n.experienceModeNormalDesc,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // 2. Top 4 Player Themes Interactive Live Preview Card
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: p.surfaceCard,
                  borderRadius: AppRadii.r20All,
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.palette_rounded, color: p.accent, size: 18),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            l10n.onboardingThemes,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.bodySmall,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    // 2x2 Interactive Theme Cards with Live Preview
                    for (int row = 0; row < 2; row++) ...[
                      if (row > 0) const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          for (int col = 0; col < 2; col++) ...[
                            if (col > 0) const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final item = themes[row * 2 + col];
                                  final isSelected = selectedTheme == item.mode;
                                  return _buildThemePreviewCard(
                                    context,
                                    mode: item.mode,
                                    title: item.title,
                                    icon: item.icon,
                                    isSelected: isSelected,
                                    shouldAnimate: shouldAnimate,
                                    onTap: () {
                                      PulsrHaptics.selectionClick();
                                      cubit.setPlayerThemeMode(item.mode);
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    // Custom Accent Color Swatches (>= 48x48dp hit targets)
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      alignment: WrapAlignment.center,
                      children: AppColors.customAccents.indexed.map((entry) {
                        final index = entry.$1;
                        final color = entry.$2;
                        final isSelected = selectedAccent == color.toARGB32();
                        return Semantics(
                          button: true,
                          selected: isSelected,
                          label: '${l10n.customAccentColor} ${index + 1}',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              PulsrHaptics.selection();
                              SoundFeedbackService.playClick();
                              cubit.setCustomAccentColor(color);
                            },
                            child: SizedBox(
                              width: AppSpacing.minTouchTarget,
                              height: AppSpacing.minTouchTarget,
                              child: Center(
                                child: AnimatedContainer(
                                  duration: shouldAnimate
                                      ? context.motionMs(200)
                                      : Duration.zero,
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? p.textPrimary
                                          : Colors.transparent,
                                      width: isSelected ? 2.5 : 1,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Icon(
                                          Icons.check_rounded,
                                          color: AppColors.textOnAccent(color),
                                          size: 20,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemePreviewCard(
    BuildContext context, {
    required PlayerThemeMode mode,
    required String title,
    required IconData icon,
    required bool isSelected,
    required bool shouldAnimate,
    required VoidCallback onTap,
  }) {
    final p = context.palette;
    final livePreview = _tryBuildLiveThemePreview(
      context,
      mode,
      const Size(44, 68),
    );

    return Semantics(
      button: true,
      selected: isSelected,
      label: title,
      child: PulsrPressable(
        pressedScale: 0.98,
        onTap: onTap,
        child: AnimatedContainer(
          key: ValueKey('onboarding_theme_${mode.name}'),
          duration: shouldAnimate ? context.motionMs(200) : Duration.zero,
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: isSelected
                ? p.accent.withValues(alpha: 0.14)
                : p.surfaceContainer,
            borderRadius: AppRadii.r14All,
            border: Border.all(
              color: isSelected ? p.accent : p.hairline,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: AppRadii.r8All,
                child: livePreview ??
                    Container(
                      width: 36,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            p.accent
                                .withValues(alpha: isSelected ? 0.35 : 0.18),
                            p.surfaceContainerHigh,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: AppRadii.r8All,
                      ),
                      child: Icon(
                        icon,
                        size: 18,
                        color: isSelected ? p.accent : p.textSecondary,
                      ),
                    ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? p.accent : p.textPrimary,
                    fontSize: AppFontSize.caption,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 16,
                color: isSelected ? p.accent : p.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _tryBuildLiveThemePreview(
    BuildContext context,
    PlayerThemeMode mode,
    Size slot,
  ) {
    try {
      PlayerCubit? playerCubit;
      try {
        playerCubit = context.read<PlayerCubit>();
      } catch (_) {
        if (getIt.isRegistered<PlayerCubit>()) {
          playerCubit = getIt<PlayerCubit>();
        }
      }
      if (playerCubit == null) return null;
      final p = context.palette;
      final props = PlayerThemeProps(
        state: playerCubit.state,
        cubit: playerCubit,
        activeColor: p.accent,
        bgColor: p.bg,
      );
      const canvas = Size(360, 760);
      final scale = math.min(
        slot.width / canvas.width,
        slot.height / canvas.height,
      );
      return ThemeRegistry.preview(
        mode,
        props,
        scale: scale,
        canvasSize: canvas,
        isPreview: true,
      );
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  // Step 3: Optional 1-Tap AudioSetupWizard Launch or "Start Listening"
  // ===========================================================================
  Widget _buildStep3(BuildContext context) {
    final p = context.palette;
    final isLandscape = context.isLandscape;
    final l10n = context.l10n;
    final cubit = context.read<SettingsCubit>();
    final shouldAnimate = PulsrMotion.shouldAnimate(context);

    final wizardCard = Semantics(
      button: true,
      label: l10n.settingsSetUpSound,
      child: PulsrPressable(
        pressedScale: 0.985,
        onTap: () {
          PulsrHaptics.selectionClick();
          AudioSetupWizardSheet.show(context, cubit: cubit);
        },
        child: Container(
          key: const ValueKey('onboarding_audio_wizard_btn'),
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: p.surfaceCard,
            borderRadius: AppRadii.r20All,
            border: Border.all(
              color: p.accent.withValues(alpha: 0.35),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: p.accent.withValues(alpha: 0.14),
                blurRadius: 28,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.16),
                  borderRadius: AppRadii.r14All,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: p.accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsSetUpSound,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.body,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      l10n.settingsSetUpSoundDesc,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.tune_rounded,
                color: p.accent,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );

    final enginePreviewCard = AnimatedContainer(
      duration: shouldAnimate ? context.motionMs(260) : Duration.zero,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: AppRadii.r20All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: AppRadii.r12All,
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  color: p.onAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.onboardingAudioEngine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.bodySmall,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      '24-bit / 192kHz • FLAC',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: p.accent,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.verified_rounded,
                color: p.accent,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            alignment: WrapAlignment.center,
            children: [
              _FeatureBadge(
                icon: Icons.graphic_eq_rounded,
                label: l10n.browseTenBandGraphicEq,
              ),
              _FeatureBadge(
                icon: Icons.compare_arrows_rounded,
                label: l10n.browseSmoothCrossfade,
              ),
              _FeatureBadge(
                icon: Icons.all_inclusive_rounded,
                label: l10n.gaplessPlayback,
              ),
            ],
          ),
        ],
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s28,
            vertical: isLandscape ? AppSpacing.xxs : AppSpacing.sm,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.onboardingPersonalizeTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: AppTracking.heading,
                        color: p.textPrimary,
                      ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                l10n.onboardingPersonalizeDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: p.textSecondary,
                      height: 1.45,
                    ),
              ),
              SizedBox(height: isLandscape ? AppSpacing.xs : AppSpacing.md),
              _animateIfEnabled(
                context,
                wizardCard,
                (a) => a
                    .fadeIn(duration: context.motionMs(320))
                    .scale(begin: const Offset(0.96, 0.96)),
              ),
              const SizedBox(height: AppSpacing.sm),
              _animateIfEnabled(
                context,
                enginePreviewCard,
                (a) => a.fadeIn(delay: context.motionMs(200)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(
                      AppSpacing.minTouchTarget,
                      AppSpacing.minTouchTarget,
                    ),
                  ),
                  onPressed: () {
                    PulsrHaptics.selectionClick();
                    GesturesSheet.show(context);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.gesture_rounded, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          l10n.viewAllGestures,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r20All,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: p.accent),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.label,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
