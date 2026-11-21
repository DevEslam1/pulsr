part of 'equalizer_sheet.dart';

/// Thin orchestrator for [EqualizerSheet]: holds shared state/macro/preamp
/// helpers and delegates Normal mode to [_EqQuickSoundView] and Professional
/// mode to [_EqProRackView] across portrait and landscape surfaces.
extension _EqSheetShell on _EqualizerSheetState {
  void _setStudioMode(BuildContext context, bool studio) {
    _setStateSafe(() => _isStudioModeOverride = studio);
    try {
      context.read<SettingsCubit>().setExperienceMode(
            studio ? ExperienceMode.professional : ExperienceMode.normal,
          );
    } catch (_) {}
  }

  double _getBassGain(PlayerState state) => EqSheetMath.macroGain(
        state.eqPreset.gains,
        _activeFrequencies(state),
        62.0,
      );

  double _getMidGain(PlayerState state) => EqSheetMath.macroGain(
        state.eqPreset.gains,
        _activeFrequencies(state),
        1000.0,
      );

  double _getTrebleGain(PlayerState state) => EqSheetMath.macroGain(
        state.eqPreset.gains,
        _activeFrequencies(state),
        8000.0,
      );

  /// Preamp slider coalescing: keep the thumb responsive with a local preview
  /// while pushing at most one native write per 60ms.
  void _schedulePreamp(
    PlayerCubit cubit,
    double value,
    VoidCallback setCardState,
  ) {
    _preampPreview = value;
    setCardState();
    _preampDebounce?.cancel();
    _preampDebounce = Timer(const Duration(milliseconds: 60), () {
      _preampPreview = null;
      unawaited(cubit.setPreamp(value));
    });
  }

  void _setPreampImmediate(PlayerCubit cubit, double value) {
    _preampDebounce?.cancel();
    _preampDebounce = null;
    _preampPreview = null;
    unawaited(cubit.setPreamp(value));
  }

  void _setBassMacro(PlayerCubit cubit, PlayerState state, double val) {
    if (!cubit.state.isEqEnabled) cubit.setEqualizerEnabled(true);
    final freqs = _activeFrequencies(state);
    final count = cubit.state.eqPreset.gains.length;
    if (count == 10) {
      cubit.setBandGain(0, val);
      cubit.setBandGain(1, (val * 0.85).clamp(-12.0, 12.0));
      cubit.setBandGain(2, (val * 0.65).clamp(-12.0, 12.0));
    } else {
      for (int i = 0; i < freqs.length && i < count; i++) {
        final f = freqs[i];
        if (f <= 250.0) {
          final weight = EqSheetMath.bassMacroWeight(f);
          cubit.setBandGain(i, (val * weight).clamp(-12.0, 12.0));
        }
      }
    }
    cubit.setBassBoost(val > 0 ? (val / 12.0).clamp(0.0, 1.0) : 0.0);
  }

  void _setMidMacro(PlayerCubit cubit, PlayerState state, double val) {
    if (!cubit.state.isEqEnabled) cubit.setEqualizerEnabled(true);
    final freqs = _activeFrequencies(state);
    final count = cubit.state.eqPreset.gains.length;
    if (count == 10) {
      cubit.setBandGain(3, (val * 0.5).clamp(-12.0, 12.0));
      cubit.setBandGain(4, (val * 0.8).clamp(-12.0, 12.0));
      cubit.setBandGain(5, val);
      cubit.setBandGain(6, (val * 0.85).clamp(-12.0, 12.0));
    } else {
      for (int i = 0; i < freqs.length && i < count; i++) {
        final f = freqs[i];
        if (f >= 250.0 && f <= 3500.0) {
          final weight = EqSheetMath.midMacroWeight(f);
          cubit.setBandGain(i, (val * weight).clamp(-12.0, 12.0));
        }
      }
    }
  }

  void _setTrebleMacro(PlayerCubit cubit, PlayerState state, double val) {
    if (!cubit.state.isEqEnabled) cubit.setEqualizerEnabled(true);
    final freqs = _activeFrequencies(state);
    final count = cubit.state.eqPreset.gains.length;
    if (count == 10) {
      cubit.setBandGain(7, (val * 0.75).clamp(-12.0, 12.0));
      cubit.setBandGain(8, val);
      cubit.setBandGain(9, (val * 0.9).clamp(-12.0, 12.0));
    } else {
      for (int i = 0; i < freqs.length && i < count; i++) {
        final f = freqs[i];
        if (f >= 3500.0) {
          final weight = EqSheetMath.trebleMacroWeight(f);
          cubit.setBandGain(i, (val * weight).clamp(-12.0, 12.0));
        }
      }
    }
  }

  /// Surfaces the native DSP auto-degrade safety net: show ONE snack per
  /// degraded session so the user understands why effects stopped.
  void _listenForDspAutoDegrade() {
    try {
      _degradedSessionSub =
          AudioEffectsChannel().onAutoDegradedSessionStarted.listen(
        (mask) {
          if (!mounted) return;
          _degradeSnackQueued = true;
          _setStateSafe(() {});
        },
      );
    } catch (_) {}
  }

  Future<void> _loadHeadphoneProfiles() async {
    await _headphoneRepo.loadProfiles();
    if (mounted) {
      _setStateSafe(() {
        _isLoadingProfiles = false;
      });
    }
  }

  String? _dspBlockedReason(BuildContext context) {
    try {
      final settings = context.watch<SettingsCubit>().state;
      return AudioConflicts.dspBlockedByBitPerfect(
        bitPerfectOutput: settings.bitPerfectOutput,
        bypassDspOnBitPerfect: settings.bypassDspOnBitPerfect,
        device: settings.currentOutputDevice,
        aaudioEnabled: settings.aaudioOutputEnabled,
        dsdDopActive: DsdDecoderHelper.dsdDopActive,
      );
    } catch (_) {
      return null;
    }
  }

  bool get _nativePcmEffectsAvailable => AudioEffectsChannel().hasPcmDspPath;

  bool _spatializerToggleAvailable(PlayerState state) =>
      state.isSpatializerSupported || state.isVirtualizerSupported;

  EqualizerManager? _equalizerManagerOrNull() => _cachedEqualizerManager;

  int _activeBandCount(PlayerState state) {
    final manager = _equalizerManagerOrNull();
    if (manager != null) return manager.activeFrequencies.length;
    return EqSheetMath.normalizedBandCount(state.eqPreset.gains.length);
  }

  List<double> _activeFrequencies(PlayerState state) {
    final manager = _equalizerManagerOrNull();
    if (manager != null) return manager.activeFrequencies;
    final n = state.eqPreset.gains.length;
    if (n == 64) return EqPreset.iso64Frequencies;
    if (n == 32) return EqPreset.iso32Frequencies;
    return EqPreset.centerFrequencies;
  }

  String _formatHz(double hz) => EqSheetMath.formatHz(hz);

  Widget _effectNotAppliedNotice(String effectKey, PulsrPalette p) {
    final manager = _equalizerManagerOrNull();
    if (manager == null) return const SizedBox.shrink();
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: manager.effectStatusNotifier,
      builder: (context, status, _) {
        if (!status.containsKey(effectKey)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, size: 13, color: p.error),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  context.l10n.notAppliedWarn,
                  style: TextStyle(
                    color: p.error,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFeatureInfo(BuildContext context, AudioFeatureInfo info,
      {String? conflictReason}) {
    final p = context.palette;
    final localized = info.localized(context.l10n);
    PulsrDialogHelper.showPulsrDialog<void>(
      context,
      icon: Icon(Icons.info_outline_rounded, color: p.accent, size: 26),
      title: Text(localized.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(localized.subtitle,
                style: TextStyle(
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: AppFontSize.label)),
            const SizedBox(height: AppSpacing.s10),
            Text(localized.description,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.bodySmall,
                    height: 1.4)),
            if (localized.conflictsWith != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.s10),
                decoration: BoxDecoration(
                    color: p.warning.withValues(alpha: 0.12),
                    borderRadius: AppRadii.r10All,
                    border:
                        Border.all(color: p.warning.withValues(alpha: 0.4))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: p.warning, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        context.l10n
                            .conflictsWith(localized.conflictsWith ?? ''),
                        style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (conflictReason != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.s10),
                decoration: BoxDecoration(
                    color: p.error.withValues(alpha: 0.12),
                    borderRadius: AppRadii.r10All,
                    border: Border.all(color: p.error.withValues(alpha: 0.4))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.block_rounded, color: p.error, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        conflictReason,
                        style: TextStyle(
                            color: p.error,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: Text(context.l10n.gotIt),
        ),
      ],
    );
  }

  Widget _conflictBanner(String reason, PulsrPalette p) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.12),
          borderRadius: AppRadii.r10All,
          border: Border.all(color: p.error.withValues(alpha: 0.3))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.block_rounded, color: p.error, size: 16),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
            child: Text(reason,
                style: TextStyle(
                    color: p.error,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600)))
      ]),
    );
  }

  /// Drives the master DSP switch and explains the "nothing to restore" case.
  void _setDspMasterEnabled(PlayerCubit cubit, bool enabled) {
    if (enabled && !cubit.hasDspEffectsSnapshot) {
      PulsrToast.show(
        context,
        message: context.l10n.dspMasterNoSnapshotNotice,
        icon: Icons.info_outline_rounded,
      );
    }
    cubit.setDspEffectsEnabled(enabled);
  }

  // ---------------------------------------------------------------------------
  // Portrait & Landscape Layout Builders
  // ---------------------------------------------------------------------------
  Widget _buildPortraitLayout(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlockedGlobal,
    bool isStudio,
  ) {
    return Column(
      children: [
        _buildTopBar(context, cubit, state, p, dspBlockedGlobal),
        const SizedBox(height: AppSpacing.s6),
        _buildModeSwitcher(context, p, isStudio),
        const SizedBox(height: AppSpacing.s6),
        if (!isStudio)
          Expanded(
            child: _buildQuickSoundView(
              context,
              cubit,
              state,
              p,
              dspBlockedGlobal,
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: LayoutBuilder(
              builder: (context, cardConstraints) {
                final isWide = cardConstraints.maxWidth >= 440;
                final eqCard = _buildEqualizerToggleCard(
                    context, cubit, state, p, dspBlockedGlobal);
                final dspCard = _buildDspToggleCard(
                    context, cubit, state, p, dspBlockedGlobal);
                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: eqCard),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(child: dspCard),
                    ],
                  );
                }
                return Column(
                  children: [
                    eqCard,
                    const SizedBox(height: AppSpacing.s6),
                    dspCard,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          _buildHardwareDeviceProfileBar(context, cubit, state, p),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: _buildProRackWorkspace(context, cubit, state, p),
          ),
        ],
      ],
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlockedGlobal,
    bool isStudio,
  ) {
    return Column(
      children: [
        _buildTopBar(context, cubit, state, p, dspBlockedGlobal),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left control rack
              SizedBox(
                width: 270,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.md, 0, AppSpacing.sm, AppSpacing.sm),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildModeSwitcher(context, p, isStudio),
                      const SizedBox(height: AppSpacing.xs),
                      if (isStudio) ...[
                        _buildEqualizerToggleCard(
                            context, cubit, state, p, dspBlockedGlobal),
                        const SizedBox(height: AppSpacing.xs),
                        _buildDspToggleCard(
                            context, cubit, state, p, dspBlockedGlobal),
                        const SizedBox(height: AppSpacing.xs),
                        _buildHardwareDeviceProfileBar(context, cubit, state, p,
                            compact: true),
                      ] else ...[
                        _buildEssentialControlsPane(
                            context, cubit, state, p, dspBlockedGlobal),
                      ],
                    ],
                  ),
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: p.hairline),
              // Right workspace
              Expanded(
                child: isStudio
                    ? _buildProRackWorkspace(
                        context,
                        cubit,
                        state,
                        p,
                        tabBarPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xxs),
                      )
                    : _buildEssentialSlidersPane(
                        context, cubit, state, p, dspBlockedGlobal),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
