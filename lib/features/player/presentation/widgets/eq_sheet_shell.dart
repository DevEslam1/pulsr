part of 'equalizer_sheet.dart';

extension _EqSheetShell on _EqualizerSheetState {
  bool _isStudio(BuildContext context) {
    if (_isStudioModeOverride != null) return _isStudioModeOverride!;
    try {
      final settings = context.watch<SettingsCubit>().state;
      return settings.isProfessional;
    } catch (_) {
      return false;
    }
  }

  void _setStudioMode(BuildContext context, bool studio) {
    _setStateSafe(() => _isStudioModeOverride = studio);
    try {
      context.read<SettingsCubit>().setExperienceMode(
            studio ? ExperienceMode.professional : ExperienceMode.normal,
          );
    } catch (_) {}
  }

  double _getBassGain(PlayerState state) {
    final gains = state.eqPreset.gains;
    if (gains.isEmpty) return 0.0;
    return gains[0].clamp(-12.0, 12.0);
  }

  double _getMidGain(PlayerState state) {
    final gains = state.eqPreset.gains;
    if (gains.isEmpty) return 0.0;
    if (gains.length >= 10) {
      return gains[5].clamp(-12.0, 12.0);
    } else if (gains.length >= 3) {
      return gains[gains.length ~/ 2].clamp(-12.0, 12.0);
    }
    return 0.0;
  }

  double _getTrebleGain(PlayerState state) {
    final gains = state.eqPreset.gains;
    if (gains.isEmpty) return 0.0;
    if (gains.length >= 10) {
      return gains[8].clamp(-12.0, 12.0);
    } else if (gains.length >= 3) {
      return gains.last.clamp(-12.0, 12.0);
    }
    return 0.0;
  }

  void _setBassMacro(PlayerCubit cubit, PlayerState state, double val) {
    if (!cubit.state.isEqEnabled) cubit.setEqualizerEnabled(true);
    final count = cubit.state.eqPreset.gains.length;
    if (count >= 10) {
      cubit.setBandGain(0, val);
      cubit.setBandGain(1, (val * 0.85).clamp(-12.0, 12.0));
      cubit.setBandGain(2, (val * 0.65).clamp(-12.0, 12.0));
    } else if (count > 0) {
      cubit.setBandGain(0, val);
    }
    cubit.setBassBoost(val > 0 ? (val / 12.0).clamp(0.0, 1.0) : 0.0);
  }

  void _setMidMacro(PlayerCubit cubit, PlayerState state, double val) {
    if (!cubit.state.isEqEnabled) cubit.setEqualizerEnabled(true);
    final count = cubit.state.eqPreset.gains.length;
    if (count >= 10) {
      cubit.setBandGain(3, (val * 0.5).clamp(-12.0, 12.0));
      cubit.setBandGain(4, (val * 0.8).clamp(-12.0, 12.0));
      cubit.setBandGain(5, val);
      cubit.setBandGain(6, (val * 0.85).clamp(-12.0, 12.0));
    } else if (count >= 3) {
      cubit.setBandGain(count ~/ 2, val);
    }
  }

  void _setTrebleMacro(PlayerCubit cubit, PlayerState state, double val) {
    if (!cubit.state.isEqEnabled) cubit.setEqualizerEnabled(true);
    final count = cubit.state.eqPreset.gains.length;
    if (count >= 10) {
      cubit.setBandGain(7, (val * 0.75).clamp(-12.0, 12.0));
      cubit.setBandGain(8, val);
      cubit.setBandGain(9, (val * 0.9).clamp(-12.0, 12.0));
    } else if (count >= 3) {
      cubit.setBandGain(count - 1, val);
    }
  }

  /// Surfaces the native DSP auto-degrade safety net: when the engine bypasses
  /// stages to prevent stutter, show ONE snack per degraded session (re-arms after
  /// full recovery) so the user understands why effects stopped.
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
        dsdDopActive: AudioQualityInfo.dsdDopActive,
      );
    } catch (_) {
      return null;
    }
  }

  /// The C++ stages (crossfeed, saturation, stereo width, sub crossover,
  /// dynamic EQ, convolution reverb, mono/balance) exist only in libpulsr_dsp,
  /// so they need the native chain spliced into ExoPlayer's audio sink.
  /// HAL-backed stages (limiter, EQ, bass, virtualizer, volume boost) ignore
  /// this and stay available.
  bool get _nativePcmEffectsAvailable => AudioEffectsChannel().hasPcmDspPath;

  /// The spatializer toggle falls back to the hardware virtualizer on devices
  /// without a Spatializer API, so it is only reachable when at least one of
  /// the two exists. Shared by both tabs so their gating stays identical.
  bool _spatializerToggleAvailable(PlayerState state) =>
      state.isSpatializerSupported || state.isVirtualizerSupported;

  /// The EqualizerManager singleton, when DI has registered it. Widget tests
  /// that do not register it must not crash the sheet, so this is defensive.
  EqualizerManager? _equalizerManagerOrNull() => _cachedEqualizerManager;

  /// F-32: active band plan length (10, 32 or 64). The manager is the source of
  /// truth; fall back to the emitted preset length when DI is not registered.
  int _activeBandCount(PlayerState state) {
    final manager = _equalizerManagerOrNull();
    if (manager != null) return manager.activeFrequencies.length;
    final n = state.eqPreset.gains.length;
    return (n == 32 || n == 64) ? n : 10;
  }

  /// F-32: center frequencies matching [_activeBandCount].
  List<double> _activeFrequencies(PlayerState state) {
    final manager = _equalizerManagerOrNull();
    if (manager != null) return manager.activeFrequencies;
    final n = state.eqPreset.gains.length;
    if (n == 64) return EqPreset.iso64Frequencies;
    if (n == 32) return EqPreset.iso32Frequencies;
    return EqPreset.centerFrequencies;
  }

  String _formatHz(double hz) {
    if (hz >= 1000) {
      final k = hz / 1000.0;
      final s =
          k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '${s}K';
    }
    return hz == hz.roundToDouble()
        ? hz.toStringAsFixed(0)
        : hz.toStringAsFixed(1);
  }

  /// Truthful native status: shown under an effect control when the engine
  /// reported it could not be applied (unsupported / build failure / no
  /// session), so an "on" control cannot silently mean "no audible effect".
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
                    fontSize: AppFontSize.tiny,
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
    PulsrDialogHelper.showPulsrDialog<void>(
      context,
      icon: Icon(Icons.info_outline_rounded, color: p.accent, size: 26),
      title: Text(info.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(info.subtitle,
                style: TextStyle(
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: AppFontSize.label)),
            const SizedBox(height: AppSpacing.s10),
            Text(info.description,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.bodySmall,
                    height: 1.4)),
            if (info.conflictsWith != null) ...[
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
                                    .conflictsWith(info.conflictsWith ?? ''),
                                style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.caption,
                                    fontWeight: FontWeight.w600)))
                      ])),
            ],
            if (conflictReason != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                  padding: const EdgeInsets.all(AppSpacing.s10),
                  decoration: BoxDecoration(
                      color: p.error.withValues(alpha: 0.12),
                      borderRadius: AppRadii.r10All,
                      border:
                          Border.all(color: p.error.withValues(alpha: 0.4))),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.block_rounded, color: p.error, size: 18),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                            child: Text(conflictReason,
                                style: TextStyle(
                                    color: p.error,
                                    fontSize: AppFontSize.caption,
                                    fontWeight: FontWeight.w600)))
                      ])),
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
            child: _buildEssentialView(
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
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: AppRadii.r20All,
                      border: Border.all(color: p.hairline),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      tabAlignment: TabAlignment.fill,
                      indicator: BoxDecoration(
                        color: p.accent,
                        borderRadius: AppRadii.r20All,
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: p.onAccent,
                      unselectedLabelColor: p.textSecondary,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.label),
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(text: context.l10n.equalizer),
                        Tab(text: 'AutoEq'),
                        Tab(text: context.l10n.dspSpatialTab),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildEqualizerTab(context, cubit, state, p),
                      _buildAutoEqTab(context, cubit, state, p),
                      _buildSpatialDynamicsTab(context, cubit, state, p),
                    ],
                  ),
                ),
              ],
            ),
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
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: p.hairline,
              ),
              // Right workspace (tabs + active panel)
              Expanded(
                child: isStudio
                    ? Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs),
                            child: Container(
                              height: 34,
                              decoration: BoxDecoration(
                                color: p.surfaceContainer,
                                borderRadius: AppRadii.r20All,
                                border: Border.all(color: p.hairline),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                tabAlignment: TabAlignment.fill,
                                indicator: BoxDecoration(
                                  color: p.accent,
                                  borderRadius: AppRadii.r20All,
                                ),
                                indicatorSize: TabBarIndicatorSize.tab,
                                labelColor: p.onAccent,
                                unselectedLabelColor: p.textSecondary,
                                labelStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: AppFontSize.label),
                                dividerColor: Colors.transparent,
                                tabs: [
                                  Tab(text: context.l10n.equalizer),
                                  Tab(text: 'AutoEq'),
                                  Tab(text: context.l10n.dspSpatialTab),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _buildEqualizerTab(context, cubit, state, p),
                                _buildAutoEqTab(context, cubit, state, p),
                                _buildSpatialDynamicsTab(
                                    context, cubit, state, p),
                              ],
                            ),
                          ),
                        ],
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

  // ---------------------------------------------------------------------------
  // Modular Top Bar & Toggle Cards
  // ---------------------------------------------------------------------------
  Widget _buildTopBar(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlockedGlobal,
  ) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md, AppSpacing.s8, AppSpacing.md, AppSpacing.xxs),
      child: Row(
        children: [
          IconButton(
            tooltip: context.l10n.dspResetAllEqTooltip,
            icon: Icon(Icons.restart_alt_rounded,
                color: dspBlockedGlobal != null
                    ? p.textTertiary.withValues(alpha: 0.4)
                    : p.accent,
                size: 20),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            onPressed: dspBlockedGlobal != null
                ? null
                : () => _resetAllDspDefaults(context, cubit),
          ),
          const Spacer(),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: p.hairline,
              borderRadius: AppRadii.r2All,
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: context.l10n.dspPresetOptions,
            icon: Icon(Icons.more_vert_rounded, color: p.accent, size: 20),
            color: p.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: AppRadii.r16All),
            onSelected: (value) {
              switch (value) {
                case 'save':
                  _showSaveCustomPresetDialog(cubit, state);
                  break;
                case 'export':
                  _exportCurrentPreset(context, cubit);
                  break;
                case 'import':
                  _importPresetDialog(context, cubit);
                  break;
                case 'inspector':
                  DspInspectorSheet.show(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'save',
                child: Row(
                  children: [
                    Icon(Icons.save_rounded, size: 18, color: p.textPrimary),
                    const SizedBox(width: AppSpacing.s10),
                    Text(context.l10n.saveCustomEqPreset,
                        style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.bodySmall)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.upload_rounded, size: 18, color: p.textPrimary),
                    const SizedBox(width: AppSpacing.s10),
                    Text(context.l10n.exportPresetJson,
                        style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.bodySmall)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded,
                        size: 18, color: p.textPrimary),
                    const SizedBox(width: AppSpacing.s10),
                    Text(context.l10n.importPresetJson,
                        style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.bodySmall)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'inspector',
                child: Row(
                  children: [
                    Icon(Icons.sensors_rounded, size: 18, color: p.accent),
                    const SizedBox(width: AppSpacing.s10),
                    Text(context.l10n.dspInspector,
                        style: TextStyle(
                            color: p.accent, fontSize: AppFontSize.bodySmall)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEqualizerToggleCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlockedGlobal,
  ) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: state.isEqEnabled
              ? p.accent.withValues(alpha: 0.08)
              : p.surfaceContainer,
          borderRadius: AppRadii.r12All,
          border: Border.all(
            color: state.isEqEnabled
                ? p.accent.withValues(alpha: 0.35)
                : p.hairline,
          ),
        ),
        child: InkWell(
          borderRadius: AppRadii.r12All,
          onTap: dspBlockedGlobal != null && !state.isEqEnabled
              ? null
              : () {
                  cubit.setEqualizerEnabled(!state.isEqEnabled);
                  _tabController.animateTo(0);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s6),
                  decoration: BoxDecoration(
                    color: state.isEqEnabled
                        ? p.accent.withValues(alpha: 0.2)
                        : p.surfaceContainerHigh,
                    borderRadius: AppRadii.r8All,
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: state.isEqEnabled ? p.accent : p.textSecondary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              context.l10n.equalizerTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.bodySmall,
                                fontWeight: FontWeight.w700,
                                color: p.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6,
                                vertical: AppSpacing.s2),
                            decoration: BoxDecoration(
                              color: state.isEqEnabled
                                  ? (dspBlockedGlobal != null
                                      ? p.error.withValues(alpha: 0.15)
                                      : p.accent.withValues(alpha: 0.2))
                                  : p.surfaceContainerHigh,
                              borderRadius: AppRadii.r4All,
                            ),
                            child: Text(
                              dspBlockedGlobal != null
                                  ? context.l10n.dspBlocked
                                  : (state.isEqEnabled
                                      ? context.l10n.dspStatOn
                                      : context.l10n.dspStatOff),
                              style: TextStyle(
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w800,
                                color: dspBlockedGlobal != null
                                    ? p.error
                                    : (state.isEqEnabled
                                        ? p.accent
                                        : p.textTertiary),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        dspBlockedGlobal != null
                            ? context.l10n.dspBlockedBitPerfect
                            : (state.isEqEnabled
                                ? (state.selectedHeadphoneProfile != null
                                    ? '${context.l10n.dspTunedFor} ${state.selectedHeadphoneProfile!.name}'
                                    : '${context.l10n.dspPresetLabel} ${state.eqPreset.name}')
                                : context.l10n.dspEqCurvesBypassed),
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: dspBlockedGlobal != null
                              ? p.error
                              : p.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.info_outline_rounded,
                      size: 16, color: p.textTertiary),
                  visualDensity: VisualDensity.compact,
                  tooltip: context.l10n.dspAboutEqualizer,
                  onPressed: () => _showFeatureInfo(
                    context,
                    AudioFeatureRegistry.equalizer,
                    conflictReason: dspBlockedGlobal,
                  ),
                ),
                Opacity(
                  opacity: dspBlockedGlobal != null && !state.isEqEnabled
                      ? 0.45
                      : 1.0,
                  child: Switch.adaptive(
                    value: dspBlockedGlobal == null && state.isEqEnabled,
                    activeTrackColor: p.accent,
                    activeThumbColor: p.onAccent,
                    onChanged: dspBlockedGlobal != null && !state.isEqEnabled
                        ? null
                        : (val) => cubit.setEqualizerEnabled(val),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDspToggleCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlockedGlobal,
  ) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: state.isDspEffectsActive
              ? p.accent.withValues(alpha: 0.08)
              : p.surfaceContainer,
          borderRadius: AppRadii.r12All,
          border: Border.all(
            color: state.isDspEffectsActive
                ? p.accent.withValues(alpha: 0.35)
                : p.hairline,
          ),
        ),
        child: InkWell(
          borderRadius: AppRadii.r12All,
          onTap: dspBlockedGlobal != null && !state.isDspEffectsActive
              ? null
              : () {
                  cubit.setDspEffectsEnabled(!state.isDspEffectsActive);
                  _tabController.animateTo(2);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s6),
                  decoration: BoxDecoration(
                    color: state.isDspEffectsActive
                        ? p.accent.withValues(alpha: 0.2)
                        : p.surfaceContainerHigh,
                    borderRadius: AppRadii.r8All,
                  ),
                  child: Icon(
                    Icons.multitrack_audio_rounded,
                    color:
                        state.isDspEffectsActive ? p.accent : p.textSecondary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              context.l10n.dspSpatialTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.bodySmall,
                                fontWeight: FontWeight.w700,
                                color: p.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6,
                                vertical: AppSpacing.s2),
                            decoration: BoxDecoration(
                              color: state.isDspEffectsActive
                                  ? (dspBlockedGlobal != null
                                      ? p.error.withValues(alpha: 0.15)
                                      : p.accent.withValues(alpha: 0.2))
                                  : p.surfaceContainerHigh,
                              borderRadius: AppRadii.r4All,
                            ),
                            child: Text(
                              dspBlockedGlobal != null
                                  ? context.l10n.dspBlocked
                                  : (state.isDspEffectsActive
                                      ? context.l10n.dspStatOn
                                      : context.l10n.dspStatOff),
                              style: TextStyle(
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w800,
                                color: dspBlockedGlobal != null
                                    ? p.error
                                    : (state.isDspEffectsActive
                                        ? p.accent
                                        : p.textTertiary),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        dspBlockedGlobal != null
                            ? context.l10n.dspBlockedBitPerfect
                            : (state.isDspEffectsActive
                                ? '${state.activeDspEffectStagesCount} ${context.l10n.dspActiveEffects}'
                                : context.l10n.dspAllEffectsBypassed),
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: dspBlockedGlobal != null
                              ? p.error
                              : p.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.info_outline_rounded,
                      size: 16, color: p.textTertiary),
                  visualDensity: VisualDensity.compact,
                  tooltip: context.l10n.dspAboutDspEngine,
                  onPressed: () => _showFeatureInfo(
                    context,
                    AudioFeatureRegistry.spatializer,
                    conflictReason: dspBlockedGlobal,
                  ),
                ),
                Opacity(
                  opacity: dspBlockedGlobal != null && !state.isDspEffectsActive
                      ? 0.45
                      : 1.0,
                  child: Switch.adaptive(
                    value: state.isDspEffectsActive,
                    activeTrackColor: p.accent,
                    activeThumbColor: p.onAccent,
                    onChanged:
                        dspBlockedGlobal != null && !state.isDspEffectsActive
                            ? null
                            : (val) => cubit.setDspEffectsEnabled(val),
                  ),
                ),
              ],
            ),
          ),
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
    final preset = state.eqPreset;
    final simplifiedPresets = <(String, EqPreset)>[
      ('Flat', EqPreset.defaultPresets.firstWhere((p) => p.name == 'Flat')),
      (
        'Bass Boost',
        EqPreset.defaultPresets.firstWhere((p) => p.name == 'Bass Boost')
      ),
      (
        'Vocal',
        EqPreset.defaultPresets.firstWhere((p) => p.name == 'Vocal Boost',
            orElse: () => EqPreset.defaultPresets.first)
      ),
      (
        'Treble',
        const EqPreset(
            name: 'Treble',
            gains: [-1, -0.5, 0, 0, 1, 2, 3.5, 5, 6, 6.5],
            bassBoost: 0.0)
      ),
      ('Custom', EqPreset(name: 'Custom', gains: List.filled(10, 0.0))),
    ];
    final isStandardPreset =
        ['Flat', 'Bass Boost', 'Vocal Boost', 'Treble'].contains(preset.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dspBlocked != null) ...[
          _conflictBanner(dspBlocked, p),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(
          context.l10n.eqSoundProfiles,
          style: TextStyle(
            fontSize: AppFontSize.tiny,
            fontWeight: FontWeight.w800,
            letterSpacing: AppTracking.wide,
            color: p.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: simplifiedPresets.map((entry) {
            final label = entry.$1;
            final itemPreset = entry.$2;
            final bool isSelected = label == 'Custom'
                ? !isStandardPreset
                : (preset.name == itemPreset.name ||
                    (label == 'Vocal' && preset.name == 'Vocal Boost'));

            return ChoiceChip(
              label: Text(label),
              selected: isSelected,
              selectedColor: p.accent.withValues(alpha: 0.22),
              backgroundColor: p.surfaceContainer,
              side: BorderSide(
                color:
                    isSelected ? p.accent.withValues(alpha: 0.5) : p.hairline,
              ),
              labelStyle: TextStyle(
                color: isSelected ? p.accent : p.textSecondary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: AppFontSize.label,
              ),
              onSelected: dspBlocked != null
                  ? null
                  : (_) {
                      HapticFeedback.selectionClick();
                      if (!state.isEqEnabled) {
                        cubit.setEqualizerEnabled(true);
                      }
                      if (label == 'Custom') {
                        cubit.applyPreset(EqPreset(
                            name: 'Custom',
                            gains: List<double>.from(state.eqPreset.gains)));
                      } else {
                        cubit.applyPreset(itemPreset);
                      }
                    },
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: Text(context.l10n.eqUnlockStudioConsole,
                style: const TextStyle(fontSize: AppFontSize.label)),
            onPressed: () {
              HapticFeedback.lightImpact();
              _setStudioMode(context, true);
            },
          ),
        ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      physics: const BouncingScrollPhysics(),
      child: _buildMacroSliders(context, cubit, p, spacing: AppSpacing.s8),
    );
  }

  Widget _buildMacroSliders(
    BuildContext context,
    PlayerCubit cubit,
    PulsrPalette p, {
    double spacing = AppSpacing.s10,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.eqQuickToneDials,
          style: TextStyle(
            fontSize: AppFontSize.tiny,
            fontWeight: FontWeight.w800,
            letterSpacing: AppTracking.wide,
            color: p.textTertiary,
          ),
        ),
        SizedBox(height: spacing),
        BlocSelector<PlayerCubit, PlayerState, double>(
          selector: _getBassGain,
          builder: (context, val) => _buildMacroSliderRow(
            context: context,
            icon: Icons.speaker_rounded,
            title: context.l10n.eqMacroBassTitle,
            subtitle: context.l10n.eqMacroBassDesc,
            value: val,
            accentColor: p.accent,
            p: p,
            onChanged: (v) => _setBassMacro(cubit, cubit.state, v),
          ),
        ),
        SizedBox(height: spacing),
        BlocSelector<PlayerCubit, PlayerState, double>(
          selector: _getMidGain,
          builder: (context, val) => _buildMacroSliderRow(
            context: context,
            icon: Icons.mic_rounded,
            title: context.l10n.eqMacroMidTitle,
            subtitle: context.l10n.eqMacroMidDesc,
            value: val,
            accentColor: AppColors.accentCyan,
            p: p,
            onChanged: (v) => _setMidMacro(cubit, cubit.state, v),
          ),
        ),
        SizedBox(height: spacing),
        BlocSelector<PlayerCubit, PlayerState, double>(
          selector: _getTrebleGain,
          builder: (context, val) => _buildMacroSliderRow(
            context: context,
            icon: Icons.auto_awesome_rounded,
            title: context.l10n.eqMacroTrebleTitle,
            subtitle: context.l10n.eqMacroTrebleDesc,
            value: val,
            accentColor: AppColors.warning,
            p: p,
            onChanged: (v) => _setTrebleMacro(cubit, cubit.state, v),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Essential / Studio Mode Switcher
  // ---------------------------------------------------------------------------
  Widget _buildModeSwitcher(
      BuildContext context, PulsrPalette p, bool isStudio) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: AppRadii.r20All,
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _setStudioMode(context, false);
                },
                child: AnimatedContainer(
                  duration: context.motionMs(200),
                  decoration: BoxDecoration(
                    color: !isStudio ? p.accent : Colors.transparent,
                    borderRadius: AppRadii.r16All,
                    boxShadow: !isStudio
                        ? [
                            BoxShadow(
                              color: p.glow.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: !isStudio ? p.onAccent : p.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.s6),
                        Text(
                          context.l10n.eqModeEssential,
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight:
                                !isStudio ? FontWeight.w800 : FontWeight.w600,
                            color: !isStudio ? p.onAccent : p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _setStudioMode(context, true);
                },
                child: AnimatedContainer(
                  duration: context.motionMs(200),
                  decoration: BoxDecoration(
                    color: isStudio ? p.accent : Colors.transparent,
                    borderRadius: AppRadii.r16All,
                    boxShadow: isStudio
                        ? [
                            BoxShadow(
                              color: p.glow.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: isStudio ? p.onAccent : p.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.s6),
                        Text(
                          context.l10n.eqModeStudioPro,
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight:
                                isStudio ? FontWeight.w800 : FontWeight.w600,
                            color: isStudio ? p.onAccent : p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Essential (Curated / Low Cognitive Load) View
  // ---------------------------------------------------------------------------
  Widget _buildEssentialView(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlocked,
  ) {
    final preset = state.eqPreset;

    final simplifiedPresets = <(String, EqPreset)>[
      ('Flat', EqPreset.defaultPresets.firstWhere((p) => p.name == 'Flat')),
      (
        'Bass Boost',
        EqPreset.defaultPresets.firstWhere((p) => p.name == 'Bass Boost')
      ),
      (
        'Vocal',
        EqPreset.defaultPresets.firstWhere((p) => p.name == 'Vocal Boost',
            orElse: () => EqPreset.defaultPresets.first)
      ),
      (
        'Treble',
        const EqPreset(
            name: 'Treble',
            gains: [-1, -0.5, 0, 0, 1, 2, 3.5, 5, 6, 6.5],
            bassBoost: 0.0)
      ),
      ('Custom', EqPreset(name: 'Custom', gains: List.filled(10, 0.0))),
    ];

    final isStandardPreset =
        ['Flat', 'Bass Boost', 'Vocal Boost', 'Treble'].contains(preset.name);

    return SingleChildScrollView(
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

          // 1. Preset Chips (Flat, Bass Boost, Vocal, Treble, Custom)
          Text(
            context.l10n.eqSoundProfiles,
            style: TextStyle(
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w800,
              letterSpacing: AppTracking.wide,
              color: p.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: simplifiedPresets.map((entry) {
              final label = entry.$1;
              final itemPreset = entry.$2;
              final bool isSelected = label == 'Custom'
                  ? !isStandardPreset
                  : (preset.name == itemPreset.name ||
                      (label == 'Vocal' && preset.name == 'Vocal Boost'));

              return ChoiceChip(
                label: Text(label),
                selected: isSelected,
                selectedColor: p.accent.withValues(alpha: 0.22),
                backgroundColor: p.surfaceContainer,
                side: BorderSide(
                  color:
                      isSelected ? p.accent.withValues(alpha: 0.5) : p.hairline,
                ),
                labelStyle: TextStyle(
                  color: isSelected ? p.accent : p.textSecondary,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: AppFontSize.label,
                ),
                onSelected: dspBlocked != null
                    ? null
                    : (_) {
                        HapticFeedback.selectionClick();
                        if (!state.isEqEnabled) {
                          cubit.setEqualizerEnabled(true);
                        }
                        if (label == 'Custom') {
                          cubit.applyPreset(EqPreset(
                              name: 'Custom',
                              gains: List<double>.from(state.eqPreset.gains)));
                        } else {
                          cubit.applyPreset(itemPreset);
                        }
                      },
              );
            }).toList(),
          ),

          const SizedBox(height: AppSpacing.lg),

          // 2. Three Macro Sliders (Bass, Mid, Treble)
          _buildMacroSliders(context, cubit, p, spacing: AppSpacing.s10),

          const SizedBox(height: AppSpacing.xl),

          // 3. Single "Advanced" Button to open full sheet
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.tune_rounded, size: 20),
              label: Text(context.l10n.eqUnlockStudioConsole),
              onPressed: () {
                HapticFeedback.lightImpact();
                _setStudioMode(context, true);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroSliderRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required Color accentColor,
    required PulsrPalette p,
    required ValueChanged<double> onChanged,
  }) {
    final sign = value > 0 ? '+' : '';
    final gainText = '$sign${value.toStringAsFixed(1)} dB';

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.s14, AppSpacing.sm, AppSpacing.s14, AppSpacing.xs),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.s6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: AppRadii.r8All,
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppFontSize.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: AppFontSize.tiny, color: p.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: AppRadii.r8All,
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  gainText,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accentColor,
              thumbColor: Colors.white,
              overlayColor: accentColor.withValues(alpha: 0.18),
              trackHeight: 4,
            ),
            child: Semantics(
              label: title,
              value: gainText,
              child: Slider(
                value: value.clamp(-12.0, 12.0),
                min: -12.0,
                max: 12.0,
                divisions: 48,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 1. Equalizer Tab
  Widget _buildEqualizerTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    final preset = state.eqPreset;
    final isEnabled = state.isEqEnabled;
    final dspBlocked = _dspBlockedReason(context);
    final effectiveEnabled = isEnabled && dspBlocked == null;
    final spatializerAvailable = _spatializerToggleAvailable(state);

    // Gain staging calculations for Volume Boost
    final preampDb = state.selectedHeadphoneProfile?.preampGain ?? 0.0;
    final safeMaxBoost = ((6.0 - preampDb) / 10.0).clamp(0.0, 1.0);
    final isOverSafe = state.volumeBoost > safeMaxBoost;

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.s20, AppSpacing.xs, AppSpacing.s20, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dspBlocked != null) _conflictBanner(dspBlocked, p),
          if (dspBlocked != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  IconButton(
                      constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget),
                      icon: Icon(Icons.info_outline_rounded,
                          size: 18, color: p.accent),
                      tooltip: context.l10n.learnMore,
                      onPressed: () => _showFeatureInfo(
                          context, AudioFeatureRegistry.equalizer,
                          conflictReason: dspBlocked)),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                      child: Text(context.l10n.dspDisabledBp,
                          style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.caption))),
                ],
              ),
            ),
          // Presets Carousel & Actions Header
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 460;
              return Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        itemCount: EqPreset.defaultPresets.length,
                        itemBuilder: (context, index) {
                          final presetItem = EqPreset.defaultPresets[index];
                          final isSelected =
                              state.selectedHeadphoneProfile == null &&
                                  preset.name == presetItem.name;
                          return Padding(
                            padding: const EdgeInsetsDirectional.only(
                                end: AppSpacing.xs),
                            child: ChoiceChip(
                              label: Text(presetItem.name),
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
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.label,
                              ),
                              onSelected: dspBlocked != null
                                  ? null
                                  : (_) {
                                      HapticFeedback.selectionClick();
                                      if (!state.isEqEnabled) {
                                        cubit.setEqualizerEnabled(true);
                                      }
                                      cubit.applyPreset(presetItem);
                                    },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // A/B Comparison Toggle
                  _buildAbCompareToggle(
                    cubit: cubit,
                    p: p,
                    dspBlocked: dspBlocked,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  // Save Custom Preset button
                  if (isCompact)
                    IconButton(
                      tooltip: context.l10n.saveCustomEqPreset,
                      onPressed: dspBlocked != null
                          ? null
                          : () => _showSaveCustomPresetDialog(cubit, state),
                      icon: Icon(Icons.bookmark_add_rounded,
                          size: 18, color: p.accent),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget),
                    )
                  else
                    TextButton.icon(
                      onPressed: dspBlocked != null
                          ? null
                          : () => _showSaveCustomPresetDialog(cubit, state),
                      icon: Icon(Icons.bookmark_add_rounded,
                          size: 16, color: p.accent),
                      label: Text(context.l10n.save,
                          style: TextStyle(
                              fontSize: AppFontSize.caption,
                              color: p.accent,
                              fontWeight: FontWeight.w700)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.s10),

          // A/B/C/D 4-Slot Comparison & Studio Tools Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // A/B/C/D Slot Selector
                _buildAbSlotSelector(cubit: cubit, p: p),
                const SizedBox(width: AppSpacing.xs),

                // AutoEQ Online Search
                ActionChip(
                  avatar: Icon(Icons.search_rounded, size: 14, color: p.accent),
                  label: Text(context.l10n.autoEqSearch,
                      style: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
                  onPressed: () {
                    PulsrSheetHelper.showPulsrSheet<void>(
                      context: context,
                      wrapWithContainer: false,
                      builder: (_) => const AutoEqSearchSheet(),
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.xs),

                // Studio Dynamics Compressor
                ActionChip(
                  avatar:
                      Icon(Icons.compress_rounded, size: 14, color: p.primary),
                  label: Text(context.l10n.dynamicsCompressor,
                      style: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
                  onPressed: () {
                    final blocked = _dspBlockedReason(context);
                    if (blocked != null) {
                      // This sheet drives EqualizerManager directly, bypassing
                      // PlayerCubit's guard; refuse it here so the compressor
                      // cannot be toggled while bit-perfect/AAudio/DoP is active.
                      PulsrToast.show(
                        context,
                        message: blocked,
                        icon: Icons.error_outline_rounded,
                        isError: true,
                      );
                      return;
                    }
                    CompressorLimiterSheet.show(
                      context,
                      equalizerManager: getIt<EqualizerManager>(),
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.xs),

                // F-37: room-correction entry with FIR export.
                ActionChip(
                  avatar:
                      Icon(Icons.graphic_eq_rounded, size: 14, color: p.accent),
                  label: Text(context.l10n.roomCorrection,
                      style: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
                  onPressed: dspBlocked != null
                      ? null
                      : () => _showRoomCorrectionActions(cubit),
                ),
                const SizedBox(width: AppSpacing.xs),

                // ViPER-DDC
                ActionChip(
                  avatar: Icon(Icons.headphones_rounded,
                      size: 14,
                      color:
                          state.isViperDdcEnabled ? p.accent : p.textSecondary),
                  label: Text(
                    state.isViperDdcEnabled &&
                            state.viperDdcProfileName.isNotEmpty
                        ? 'DDC: ${state.viperDdcProfileName}'
                        : 'ViPER-DDC',
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                      color: state.isViperDdcEnabled ? p.accent : p.textPrimary,
                    ),
                  ),
                  backgroundColor: state.isViperDdcEnabled
                      ? p.accent.withValues(alpha: 0.15)
                      : p.surfaceContainer,
                  side: BorderSide(
                    color: state.isViperDdcEnabled ? p.accent : p.hairline,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
                  onPressed: () {
                    PulsrSheetHelper.showPulsrSheet<void>(
                      context: context,
                      wrapWithContainer: false,
                      builder: (_) => const ViperDdcSheet(),
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.xs),

                // Arbitrary Response EQ
                ActionChip(
                  avatar: Icon(Icons.auto_graph_rounded,
                      size: 14,
                      color: state.isArbitraryEqEnabled
                          ? p.accent
                          : p.textSecondary),
                  label: Text(
                    context.l10n.arbitraryEq,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                      color:
                          state.isArbitraryEqEnabled ? p.accent : p.textPrimary,
                    ),
                  ),
                  backgroundColor: state.isArbitraryEqEnabled
                      ? p.accent.withValues(alpha: 0.15)
                      : p.surfaceContainer,
                  side: BorderSide(
                    color: state.isArbitraryEqEnabled ? p.accent : p.hairline,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
                  onPressed: () {
                    PulsrSheetHelper.showPulsrSheet<void>(
                      context: context,
                      wrapWithContainer: false,
                      builder: (_) => const ArbitraryEqSheet(),
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.xs),

                // Live Programmable DSP
                ActionChip(
                  avatar: Icon(Icons.terminal_rounded,
                      size: 14,
                      color:
                          state.isLiveProgEnabled ? p.accent : p.textSecondary),
                  label: Text(
                    context.l10n.liveProgDsp,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                      color: state.isLiveProgEnabled ? p.accent : p.textPrimary,
                    ),
                  ),
                  backgroundColor: state.isLiveProgEnabled
                      ? p.accent.withValues(alpha: 0.15)
                      : p.surfaceContainer,
                  side: BorderSide(
                    color: state.isLiveProgEnabled ? p.accent : p.hairline,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
                  onPressed: () {
                    PulsrSheetHelper.showPulsrSheet<void>(
                      context: context,
                      wrapWithContainer: false,
                      builder: (_) => const LiveProgSheet(),
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.xs),

                // Dynamic Bass
                ActionChip(
                  avatar: Icon(Icons.speaker_group_rounded,
                      size: 14,
                      color: state.isDynamicBassEnabled
                          ? p.accent
                          : p.textSecondary),
                  label: Text(
                    context.l10n.dynamicBass,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                      color:
                          state.isDynamicBassEnabled ? p.accent : p.textPrimary,
                    ),
                  ),
                  backgroundColor: state.isDynamicBassEnabled
                      ? p.accent.withValues(alpha: 0.15)
                      : p.surfaceContainer,
                  side: BorderSide(
                    color: state.isDynamicBassEnabled ? p.accent : p.hairline,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
                  onPressed: dspBlocked != null || !_nativePcmEffectsAvailable
                      ? null
                      : () {
                          _tabController.animateTo(1);
                          cubit.setDynamicBass(!state.isDynamicBassEnabled);
                        },
                ),
                const SizedBox(width: AppSpacing.xs),

                // DSP Inspector
                ActionChip(
                  avatar:
                      Icon(Icons.insights_rounded, size: 14, color: p.accent),
                  label: Text(context.l10n.dspChain,
                      style: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700)),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(color: p.hairline),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.r10All),
                  onPressed: () => DspInspectorSheet.show(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s14),

          // Active Profile Banner if AutoEq is selected
          // OEM Audio Double-Processing Warning Banner
          if (state.hasOemAudio &&
              (state.isEqEnabled ||
                  state.isCrossfeedEnabled ||
                  state.isLimiterEnabled ||
                  state.isVirtualizerEnabled ||
                  state.isDynamicsEnabled)) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: p.warning.withValues(alpha: 0.12),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: p.warning, size: 20),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${state.detectedOemEngines.join(", ")} ${context.l10n.activeLabel}',
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w700,
                            color: p.warning,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          context.l10n.systemFxActive,
                          style: TextStyle(
                              fontSize: AppFontSize.caption,
                              color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          if (state.selectedHeadphoneProfile != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.headphones_rounded, color: p.accent, size: 20),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AutoEq: ${state.selectedHeadphoneProfile!.name}',
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w700,
                            color: p.accent,
                          ),
                        ),
                        Text(
                          '${state.selectedHeadphoneProfile!.brand} • '
                          '${context.l10n.preampLabel}: ${state.selectedHeadphoneProfile!.preampGain.toStringAsFixed(1)} dB',
                          style: TextStyle(
                              fontSize: AppFontSize.tiny,
                              color: p.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => cubit.resetToFlat(),
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      minimumSize: Size.zero,
                    ),
                    child: Text(context.l10n.reset,
                        style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.caption)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Real-time Frequency Response Curve Visualizer.
          // F-10/F-24: the gains come from a dedicated BlocSelector (band
          // drags repaint only the curve), and the RepaintBoundary keeps the
          // curve repaint inside its own layer instead of propagating to the
          // ancestor layers during drags.
          Container(
            height: 64,
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
                  height: 52,
                  onGainChanged: effectiveEnabled
                      ? (idx, gain) {
                          context.read<PlayerCubit>().setBandGain(idx, gain);
                        }
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s14),

          // F-32: 10 / 32 / 64-band mode toggle + custom frequency editor & reset actions.
          // Anchored, jitter-free responsive toolbar:
          // The Reset EQ and Edit Frequency actions are firmly pinned to the right edge via Spacer,
          // with no dynamic-width flexible item between them.
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 480;
              final canFitBadge = constraints.maxWidth >= 540;
              return Row(
                children: [
                  Text(
                    context.l10n.bandsLabel,
                    style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w700,
                        color: p.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s2),
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: AppRadii.r8All,
                      border: Border.all(color: p.hairline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final bandCount in const [10, 32, 64])
                          InkWell(
                            borderRadius: AppRadii.r8All,
                            onTap: dspBlocked != null
                                ? null
                                : () async {
                                    if (_activeBandCount(state) == bandCount) {
                                      return;
                                    }
                                    _mutedBands.clear();
                                    _soloedBands.clear();
                                    await cubit.setBandMode(bandCount);
                                    if (mounted) _setStateSafe(() {});
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s10,
                                  vertical: AppSpacing.xxs),
                              decoration: BoxDecoration(
                                color: _activeBandCount(state) == bandCount
                                    ? p.accent
                                    : Colors.transparent,
                                borderRadius: AppRadii.r8All,
                              ),
                              child: Text(
                                '$bandCount',
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w800,
                                  color: _activeBandCount(state) == bandCount
                                      ? p.onAccent
                                      : p.textSecondary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (canFitBadge) ...[
                    const SizedBox(width: AppSpacing.xs),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xxs),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.12),
                          borderRadius: AppRadii.r8All,
                          border: Border.all(
                              color: p.accent.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          state.eqPreset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.tiny,
                            fontWeight: FontWeight.w700,
                            color: p.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Anchored actions: Reset EQ & Edit Frequency
                  // Firmly pinned to the right edge via Spacer with no unbounded flex neighbor.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: context.l10n.resetToFlat,
                        child: InkWell(
                          borderRadius: AppRadii.r8All,
                          onTap: dspBlocked != null
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  cubit.resetToFlat();
                                },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal:
                                  isWide ? AppSpacing.s8 : AppSpacing.s6,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: p.surfaceContainer,
                              borderRadius: AppRadii.r8All,
                              border: Border.all(color: p.hairline),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.restart_alt_rounded,
                                  size: 16,
                                  color: p.textSecondary,
                                ),
                                if (isWide) ...[
                                  const SizedBox(width: AppSpacing.xxs),
                                  Text(
                                    context.l10n.resetToFlat,
                                    style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Tooltip(
                        message: context.l10n.frequencies,
                        child: InkWell(
                          borderRadius: AppRadii.r8All,
                          onTap: dspBlocked != null
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  _showCustomFrequencyEditor(cubit, state);
                                },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal:
                                  isWide ? AppSpacing.s8 : AppSpacing.s6,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.12),
                              borderRadius: AppRadii.r8All,
                              border: Border.all(
                                  color: p.accent.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 16,
                                  color: p.accent,
                                ),
                                if (isWide) ...[
                                  const SizedBox(width: AppSpacing.xxs),
                                  Text(
                                    context.l10n.frequencies,
                                    style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),

          // Equalizer band sliders — 10-band ISO, 32-band 1/3-octave or
          // 64-band log-spaced. Responsive layout with smooth horizontal scroll
          // when band count exceeds viewport or on compact devices.
          Container(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md, horizontal: AppSpacing.s6),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bandCount = _activeBandCount(state);
                final frequencies = _activeFrequencies(state);
                const minBandWidth = 38.0;
                final fitsWithoutScroll = bandCount <= 10 &&
                    constraints.maxWidth >= bandCount * minBandWidth;

                Widget buildSliders() {
                  return Row(
                    mainAxisAlignment: fitsWithoutScroll
                        ? MainAxisAlignment.spaceEvenly
                        : MainAxisAlignment.start,
                    children: List.generate(bandCount, (index) {
                      final control = _buildBandControl(
                        index: index,
                        label: index < frequencies.length
                            ? _formatHz(frequencies[index])
                            : '',
                        isEnabled: effectiveEnabled,
                        accentColor: p.accent,
                        trackColor: p.hairline,
                        surfaceColor: p.surface,
                        textColor: p.textPrimary,
                        errorColor: p.error,
                        state: state,
                        cubit: cubit,
                      );
                      return fitsWithoutScroll
                          ? Expanded(child: control)
                          : SizedBox(width: minBandWidth + 2.0, child: control);
                    }),
                  );
                }

                if (fitsWithoutScroll) return buildSliders();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: buildSliders(),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // F-33: manual preamp / gain staging with clipping warning.
          Builder(
            builder: (context) => StatefulBuilder(
              builder: (context, setCardState) {
                final manager = _equalizerManagerOrNull();
                final currentPreamp = manager?.preampDb ??
                    (state.selectedHeadphoneProfile?.preampGain ?? 0.0);
                final maxBoost = state.eqPreset.gains.isEmpty
                    ? 0.0
                    : state.eqPreset.gains.reduce((a, b) => a > b ? a : b);
                final clipRisk = currentPreamp + maxBoost > 0.0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: AppRadii.cardRadius,
                    border: Border.all(
                      color: clipRisk
                          ? p.error.withValues(alpha: 0.45)
                          : p.hairline,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.xs),
                            decoration: BoxDecoration(
                              color: (clipRisk ? p.error : p.accent)
                                  .withValues(alpha: 0.15),
                              borderRadius: AppRadii.r8All,
                            ),
                            child: Icon(
                              Icons.vertical_align_center_rounded,
                              color: clipRisk ? p.error : p.accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.preampLabel,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.bodySmall,
                                      color: p.textPrimary),
                                ),
                                Text(
                                  state.selectedHeadphoneProfile != null
                                      ? 'Manual override (AutoEQ suggests '
                                          '${state.selectedHeadphoneProfile!.preampGain.toStringAsFixed(1)} dB)'
                                      : 'Output gain applied before the EQ',
                                  style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textTertiary),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: AppSpacing.xxs),
                            decoration: BoxDecoration(
                              color: (clipRisk
                                      ? p.error
                                      : (currentPreamp.abs() > 0.05
                                          ? p.accent
                                          : p.surface))
                                  .withValues(alpha: 0.15),
                              borderRadius: AppRadii.r8All,
                              border: Border.all(
                                color: clipRisk
                                    ? p.error.withValues(alpha: 0.4)
                                    : (currentPreamp.abs() > 0.05
                                        ? p.accent.withValues(alpha: 0.3)
                                        : p.hairline),
                              ),
                            ),
                            child: Text(
                              '${currentPreamp > 0 ? '+' : ''}${currentPreamp.toStringAsFixed(1)} dB',
                              style: TextStyle(
                                color: clipRisk
                                    ? p.error
                                    : (currentPreamp.abs() > 0.05
                                        ? p.accent
                                        : p.textSecondary),
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          IconButton(
                            icon: Icon(Icons.settings_backup_restore,
                                size: 16,
                                color: currentPreamp.abs() <= 0.05 ||
                                        dspBlocked != null
                                    ? p.textTertiary.withValues(alpha: 0.35)
                                    : p.accent),
                            tooltip: context.l10n.dspResetPreamp,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 24, minHeight: 24),
                            onPressed: currentPreamp.abs() <= 0.05 ||
                                    dspBlocked != null
                                ? null
                                : () {
                                    final target = state
                                            .selectedHeadphoneProfile
                                            ?.preampGain ??
                                        0.0;
                                    manager?.setPreamp(target);
                                    setCardState(() {});
                                  },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s6),
                      Semantics(
                        slider: true,
                        label: context.l10n.preampLabel,
                        value:
                            '${currentPreamp > 0 ? '+' : ''}${currentPreamp.toStringAsFixed(1)} dB',
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14),
                            activeTrackColor: clipRisk ? p.error : p.accent,
                            inactiveTrackColor: p.surface,
                            thumbColor: clipRisk ? p.error : p.accent,
                          ),
                          child: Slider(
                            value: currentPreamp.clamp(-12.0, 12.0),
                            min: -12.0,
                            max: 12.0,
                            divisions: 48,
                            onChanged: dspBlocked != null
                                ? null
                                : (val) {
                                    if (!state.isEqEnabled) {
                                      cubit.setEqualizerEnabled(true);
                                    }
                                    final rounded =
                                        (val * 10).roundToDouble() / 10.0;
                                    manager?.setPreamp(rounded);
                                    setCardState(() {});
                                  },
                          ),
                        ),
                      ),
                      if (clipRisk)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                              top: AppSpacing.s2, start: AppSpacing.xxs),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: p.error, size: 13),
                              const SizedBox(width: AppSpacing.s6),
                              Expanded(
                                child: Text(
                                  context.l10n.dspPreampClipWarning(
                                    '${currentPreamp > 0 ? '+' : ''}${currentPreamp.toStringAsFixed(1)}',
                                    maxBoost.toStringAsFixed(1),
                                  ),
                                  style: TextStyle(
                                      color: p.error,
                                      fontSize: AppFontSize.tiny,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (currentPreamp > 6.0)
                        Container(
                          margin: const EdgeInsets.only(top: AppSpacing.xs),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs),
                          decoration: BoxDecoration(
                            color: p.error.withValues(alpha: 0.15),
                            borderRadius: AppRadii.r10All,
                            border: Border.all(
                                color: p.error.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.hearing_disabled_rounded,
                                  color: p.error, size: 18),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  '${context.l10n.volume}: High volume boost (>+6dB) may cause audio distortion and permanent hearing damage.',
                                  style: TextStyle(
                                    color: p.error,
                                    fontSize: AppFontSize.caption,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Bass Boost Slider
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: AppRadii.r8All,
                      ),
                      child: Icon(Icons.speaker_group_rounded,
                          color: p.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  context.l10n.bassEnhancer,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.bodySmall,
                                      color: p.textPrimary),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.info_outline_rounded,
                                    size: 16, color: p.textTertiary),
                                visualDensity: VisualDensity.compact,
                                tooltip: context.l10n.dspAboutBassBoost,
                                onPressed: () => _showFeatureInfo(
                                    context, AudioFeatureRegistry.bassBoost,
                                    conflictReason: dspBlocked),
                              ),
                            ],
                          ),
                          Text(
                            preset.bassBoost > 0
                                ? '${(preset.bassBoost * 100).round()}% punch'
                                : 'Bass boost bypassed',
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                color: p.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: AppSpacing.xxs),
                          decoration: BoxDecoration(
                            color: (preset.bassBoost > 0 ? p.accent : p.surface)
                                .withValues(alpha: 0.15),
                            borderRadius: AppRadii.r8All,
                            border: Border.all(
                              color: preset.bassBoost > 0
                                  ? p.accent.withValues(alpha: 0.3)
                                  : p.hairline,
                            ),
                          ),
                          child: Text(
                            preset.bassBoost > 0
                                ? '${(preset.bassBoost * 100).round()}%'
                                : context.l10n.dspOff,
                            style: TextStyle(
                              color: preset.bassBoost > 0
                                  ? p.accent
                                  : p.textSecondary,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        IconButton(
                          icon: Icon(Icons.settings_backup_restore,
                              size: 16,
                              color: preset.bassBoost <= 0.001 ||
                                      dspBlocked != null
                                  ? p.textTertiary.withValues(alpha: 0.35)
                                  : p.accent),
                          tooltip: context.l10n.dspResetBassEnhancer,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: preset.bassBoost <= 0.001 ||
                                  dspBlocked != null ||
                                  !state.isBassBoostSupported
                              ? null
                              : () => cubit.setBassBoost(0.0),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s6),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: p.accent,
                    inactiveTrackColor: p.surface,
                    thumbColor: p.accent,
                  ),
                  child: Semantics(
                    slider: true,
                    label: context.l10n.bassEnhancer,
                    child: Slider(
                      value: preset.bassBoost.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      onChanged:
                          dspBlocked != null || !state.isBassBoostSupported
                              ? null
                              : (val) {
                                  if (!state.isEqEnabled) {
                                    cubit.setEqualizerEnabled(true);
                                  }
                                  cubit.setBassBoost(val);
                                },
                    ),
                  ),
                ),
                _effectNotAppliedNotice('bassBoost', p),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Volume Boost Slider (LoudnessEnhancer)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: (isOverSafe ? p.error : p.accent)
                            .withValues(alpha: 0.15),
                        borderRadius: AppRadii.r8All,
                      ),
                      child: Icon(
                        Icons.volume_up_rounded,
                        color: isOverSafe ? p.error : p.accent,
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
                              Expanded(
                                child: Text(
                                  context.l10n.volumeBoost,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppFontSize.bodySmall,
                                      color: p.textPrimary),
                                ),
                              ),
                              IconButton(
                                  icon: Icon(Icons.info_outline_rounded,
                                      size: 16, color: p.textTertiary),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: context.l10n.dspAboutVolumeBoost,
                                  onPressed: () => _showFeatureInfo(
                                      context, AudioFeatureRegistry.volumeBoost,
                                      conflictReason: dspBlocked)),
                            ],
                          ),
                          Text(
                            state.volumeBoost > 0
                                ? '+${(state.volumeBoost * 10).toStringAsFixed(1)} dB hardware gain'
                                : 'Hardware gain bypassed',
                            style: TextStyle(
                                fontSize: AppFontSize.caption,
                                color: p.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: AppSpacing.xxs),
                          decoration: BoxDecoration(
                            color: (isOverSafe
                                    ? p.error
                                    : (state.volumeBoost > 0
                                        ? p.accent
                                        : p.surface))
                                .withValues(alpha: 0.15),
                            borderRadius: AppRadii.r8All,
                            border: Border.all(
                              color: isOverSafe
                                  ? p.error.withValues(alpha: 0.4)
                                  : (state.volumeBoost > 0
                                      ? p.accent.withValues(alpha: 0.3)
                                      : p.hairline),
                            ),
                          ),
                          child: Text(
                            state.volumeBoost > 0
                                ? '+${(state.volumeBoost * 10).toStringAsFixed(1)} dB'
                                : context.l10n.dspOff,
                            style: TextStyle(
                              color: isOverSafe
                                  ? p.error
                                  : (state.volumeBoost > 0
                                      ? p.accent
                                      : p.textSecondary),
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        IconButton(
                          icon: Icon(Icons.settings_backup_restore,
                              size: 16,
                              color: state.volumeBoost <= 0.001 ||
                                      dspBlocked != null
                                  ? p.textTertiary.withValues(alpha: 0.35)
                                  : p.accent),
                          tooltip: context.l10n.dspResetVolumeBoost,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: state.volumeBoost <= 0.001 ||
                                  dspBlocked != null ||
                                  !state.isVolumeBoostSupported
                              ? null
                              : () => cubit.setVolumeBoost(0.0),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s6),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: isOverSafe ? p.error : p.accent,
                    inactiveTrackColor: p.surface,
                    thumbColor: isOverSafe ? p.error : p.accent,
                  ),
                  child: Semantics(
                    slider: true,
                    label: context.l10n.volumeBoost,
                    child: Slider(
                      value: state.volumeBoost.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      onChanged:
                          dspBlocked != null || !state.isVolumeBoostSupported
                              ? null
                              : (val) {
                                  if (!state.isEqEnabled) {
                                    cubit.setEqualizerEnabled(true);
                                  }
                                  cubit.setVolumeBoost(val);
                                },
                    ),
                  ),
                ),
                if (isOverSafe)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                        top: AppSpacing.s2, start: AppSpacing.xxs),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: p.error, size: 13),
                        const SizedBox(width: AppSpacing.s6),
                        Expanded(
                          child: Text(
                            context.l10n.dspVolumeClipWarning(
                                preampDb.toStringAsFixed(1)),
                            style: TextStyle(
                                color: p.error,
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (state.volumeBoost > 0.6)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                        top: AppSpacing.s2, start: AppSpacing.xxs),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: p.error, size: 13),
                        const SizedBox(width: AppSpacing.s6),
                        Expanded(
                          child: Text(
                            context.l10n.highBoostWarn,
                            style: TextStyle(
                                color: p.error,
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                _effectNotAppliedNotice('volumeBoost', p),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Honest Spatializer / Soundstage Widening Section
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.cardRadius,
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.15),
                    borderRadius: AppRadii.r8All,
                  ),
                  child: Icon(Icons.spatial_tracking_rounded,
                      color: p.accent, size: 20),
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
                              state.isSpatializerSupported
                                  ? 'Spatial Audio'
                                  : 'Soundstage Widening',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.bodySmall,
                                  color: p.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6,
                                vertical: AppSpacing.s2),
                            decoration: BoxDecoration(
                              color: (state.isSpatializerSupported
                                      ? p.accent
                                      : p.textTertiary)
                                  .withValues(alpha: 0.15),
                              borderRadius: AppRadii.r6All,
                            ),
                            child: Text(
                              state.isSpatializerSupported
                                  ? 'Spatial API'
                                  : 'Emulated',
                              style: TextStyle(
                                fontSize: AppFontSize.micro,
                                fontWeight: FontWeight.w700,
                                color: state.isSpatializerSupported
                                    ? p.accent
                                    : p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        state.isSpatializerSupported
                            ? 'Android Spatializer API with head tracking'
                            : 'Stereo field expansion via hardware virtualizer',
                        style: TextStyle(
                            fontSize: AppFontSize.caption,
                            color: p.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: dspBlocked == null && state.isSpatializerEnabled,
                  activeTrackColor: p.accent,
                  activeThumbColor: p.onAccent,
                  onChanged: dspBlocked != null || !spatializerAvailable
                      ? null
                      : (val) => cubit.setSpatializerEnabled(val),
                ),
              ],
            ),
          ),
          _effectNotAppliedNotice('spatializer', p),
        ],
      ),
    );
  }

  // 2. AutoEq Headphone Presets Tab
  Widget _buildAutoEqTab(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
  ) {
    if (_isLoadingProfiles) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }

    final categories = _headphoneRepo.getCategories();
    final filteredProfiles =
        _headphoneRepo.search(_searchQuery, category: _selectedCategory);

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.r12All,
              border: Border.all(color: p.hairline),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                _setStateSafe(() {
                  _searchQuery = val;
                });
              },
              style: TextStyle(
                  fontSize: AppFontSize.bodySmall, color: p.textPrimary),
              decoration: InputDecoration(
                hintText: context.l10n.dspSearchHeadphonesHint,
                hintStyle: TextStyle(
                    fontSize: AppFontSize.label, color: p.textTertiary),
                prefixIcon:
                    Icon(Icons.search_rounded, color: p.textTertiary, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget),
                        icon: Icon(Icons.clear_rounded,
                            color: p.textTertiary, size: 16),
                        tooltip: context.l10n.clear,
                        onPressed: () {
                          _searchController.clear();
                          _setStateSafe(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.s10),
              ),
            ),
          ),
        ),

        // Category Filter Chips
        SizedBox(
          height: 34,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.s6),
                child: FilterChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: p.accent.withValues(alpha: 0.2),
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(
                    color: isSelected
                        ? p.accent.withValues(alpha: 0.4)
                        : p.hairline,
                  ),
                  labelStyle: TextStyle(
                    color: isSelected ? p.accent : p.textSecondary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) {
                    _setStateSafe(() {
                      _selectedCategory = cat;
                    });
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // Active Profile Banner (if applied)
        if (state.selectedHeadphoneProfile != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.cardRadius,
                border: Border.all(color: p.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: p.accent, size: 18),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.appliedTuningProfile,
                          style: TextStyle(
                              fontSize: AppFontSize.tiny,
                              fontWeight: FontWeight.w700,
                              color: p.accent),
                        ),
                        Text(
                          state.selectedHeadphoneProfile!.name,
                          style: TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => cubit.resetToFlat(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer,
                        borderRadius: AppRadii.r12All,
                        border: Border.all(color: p.hairline),
                      ),
                      child: Text(
                        context.l10n.resetToFlat,
                        style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Profiles List
        Expanded(
          child: filteredProfiles.isEmpty
              ? Center(
                  child: Text(
                    context.l10n.noHpProfiles,
                    style: TextStyle(
                        color: p.textTertiary, fontSize: AppFontSize.bodySmall),
                  ),
                )
              : ListView.builder(
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md,
                      AppSpacing.xxs, AppSpacing.md, AppSpacing.lg),
                  itemCount: filteredProfiles.length,
                  itemBuilder: (context, index) {
                    final profile = filteredProfiles[index];
                    final isApplied =
                        state.selectedHeadphoneProfile?.id == profile.id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            if (isApplied) {
                              await cubit.resetToFlat();
                            } else {
                              if (!state.isEqEnabled) {
                                await cubit.setEqualizerEnabled(true);
                              }
                              await cubit.applyHeadphoneProfile(profile);
                            }
                          },
                          borderRadius: AppRadii.cardRadius,
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s14,
                                vertical: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: isApplied
                                  ? p.accent.withValues(alpha: 0.14)
                                  : p.surfaceContainer,
                              borderRadius: AppRadii.cardRadius,
                              border: Border.all(
                                color: isApplied ? p.accent : p.hairline,
                                width: isApplied ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color:
                                        (isApplied ? p.accent : p.textTertiary)
                                            .withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    profile.category == 'Over-Ear'
                                        ? Icons.headset_rounded
                                        : Icons.headphones_rounded,
                                    color:
                                        isApplied ? p.accent : p.textSecondary,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        profile.name,
                                        style: TextStyle(
                                          fontSize: AppFontSize.bodySmall,
                                          fontWeight: FontWeight.w700,
                                          color: isApplied
                                              ? p.accent
                                              : p.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: AppSpacing.s2),
                                      Text(
                                        '${profile.brand} • ${profile.category}',
                                        style: TextStyle(
                                            fontSize: AppFontSize.caption,
                                            color: p.textTertiary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (profile.id.startsWith('custom_')) ...[
                                  IconButton(
                                    icon: Icon(Icons.delete_outline_rounded,
                                        size: 18, color: p.error),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: context.l10n.dspDeleteCustomPreset,
                                    onPressed: () async {
                                      await _headphoneRepo
                                          .removeProfile(profile.id);
                                      if (isApplied) await cubit.resetToFlat();
                                      if (mounted) _setStateSafe(() {});
                                    },
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                ],
                                if (isApplied)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.s10,
                                        vertical: AppSpacing.s6),
                                    decoration: BoxDecoration(
                                      color: p.accent,
                                      borderRadius: AppRadii.r12All,
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              p.accent.withValues(alpha: 0.35),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_rounded,
                                            color: p.onAccent, size: 13),
                                        const SizedBox(width: AppSpacing.xxs),
                                        Text(
                                          context.l10n.activeLabel,
                                          style: TextStyle(
                                            color: p.onAccent,
                                            fontSize: AppFontSize.caption,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.s10,
                                        vertical: AppSpacing.s6),
                                    decoration: BoxDecoration(
                                      color: p.surfaceContainerHigh,
                                      borderRadius: AppRadii.r12All,
                                      border: Border.all(color: p.hairline),
                                    ),
                                    child: Text(
                                      context.l10n.apply,
                                      style: TextStyle(
                                        color: p.textSecondary,
                                        fontSize: AppFontSize.caption,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHardwareDeviceProfileBar(BuildContext context, PlayerCubit cubit,
      PlayerState state, PulsrPalette p,
      {bool compact = false}) {
    AudioOutputInfo? output;
    try {
      output = context.select<SettingsCubit?, AudioOutputInfo?>(
          (c) => c?.state.currentOutputDevice);
    } catch (_) {
      output = null;
    }
    final devType = output?.activeDeviceType.toLowerCase() ?? '';
    final devName = (output?.deviceName ?? '').toLowerCase();

    final isUsb =
        output?.isUsbDac == true || devType == 'usb' || devName.contains('usb');
    final isBt = output?.isBluetooth == true ||
        devType == 'bluetooth' ||
        devType == 'ble' ||
        devName.contains('bluetooth');
    final isWired = devType == 'wired' ||
        devName.contains('headphone') ||
        devName.contains('headset');
    final isSpeaker = (!isUsb && !isBt && !isWired) ||
        devType == 'builtin' ||
        devName.contains('speaker');

    return Container(
      margin: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.xxs : AppSpacing.md,
          vertical: AppSpacing.xxs),
      padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.xxs : AppSpacing.s6,
          vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.hairline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final row = Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDeviceTypeChip(
                label: context.l10n.dspHeadset,
                icon: Icons.headphones_rounded,
                isActive: isWired,
                p: p,
                onTap: () {
                  if (state.currentSong != null) {
                    AudioQualitySheet.show(
                        context, state.currentSong!, p.accent);
                  }
                },
              ),
              _buildDeviceTypeChip(
                label: context.l10n.dspSpeaker,
                icon: Icons.volume_up_rounded,
                isActive: isSpeaker,
                p: p,
                onTap: () {
                  if (state.currentSong != null) {
                    AudioQualitySheet.show(
                        context, state.currentSong!, p.accent);
                  }
                },
              ),
              _buildDeviceTypeChip(
                label: 'Bluetooth',
                icon: Icons.bluetooth_audio_rounded,
                isActive: isBt,
                p: p,
                onTap: () {
                  if (state.currentSong != null) {
                    AudioQualitySheet.show(
                        context, state.currentSong!, p.accent);
                  }
                },
              ),
              _buildDeviceTypeChip(
                label: 'USB DAC',
                icon: Icons.album_rounded,
                isActive: isUsb,
                p: p,
                onTap: () {
                  if (state.currentSong != null) {
                    AudioQualitySheet.show(
                        context, state.currentSong!, p.accent);
                  }
                },
              ),
            ],
          );
          if (constraints.maxWidth < 360) {
            return FittedBox(fit: BoxFit.scaleDown, child: row);
          }
          return row;
        },
      ),
    );
  }

  Widget _buildDeviceTypeChip({
    required String label,
    required IconData icon,
    required bool isActive,
    required PulsrPalette p,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.r12All,
      child: AnimatedContainer(
        duration: context.motionMs(200),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
        decoration: BoxDecoration(
          color:
              isActive ? p.accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: AppRadii.r12All,
          border: Border.all(
            color: isActive ? p.accent : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? p.accent : p.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? p.accent : p.textSecondary,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: AppSpacing.xxs),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
