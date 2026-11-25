part of '../equalizer_sheet.dart';

/// Top bar, mode switcher, master EQ/DSP toggle cards, and hardware device
/// profile bar shared by portrait and landscape layouts of [EqualizerSheet].
extension _EqShellHeader on _EqualizerSheetState {
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

  Widget _buildModeSwitcher(
      BuildContext context, PulsrPalette p, bool isStudio) {
    final animate = PulsrMotion.shouldAnimate(context);
    final dur = animate ? context.motionMs(200) : Duration.zero;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        height: PulsrLayoutMetrics.fieldHeight(context),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: AppRadii.r20All,
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                selected: !isStudio,
                label: context.l10n.eqModeEssential,
                child: GestureDetector(
                  onTap: () {
                    PulsrHaptics.selectionClick();
                    _setStudioMode(context, false);
                  },
                  child: AnimatedContainer(
                    duration: dur,
                    decoration: BoxDecoration(
                      color: !isStudio
                          ? p.accent
                          : p.surfaceContainer.withValues(alpha: 0.0),
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
                          Flexible(
                            child: Text(
                              context.l10n.eqModeEssential,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: !isStudio
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: !isStudio ? p.onAccent : p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Semantics(
                button: true,
                selected: isStudio,
                label: context.l10n.eqModeStudioPro,
                child: GestureDetector(
                  onTap: () {
                    PulsrHaptics.selectionClick();
                    _setStudioMode(context, true);
                  },
                  child: AnimatedContainer(
                    duration: dur,
                    decoration: BoxDecoration(
                      color: isStudio
                          ? p.accent
                          : p.surfaceContainer.withValues(alpha: 0.0),
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
                          Flexible(
                            child: Text(
                              context.l10n.eqModeStudioPro,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: isStudio
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isStudio ? p.onAccent : p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildEqualizerToggleCard(
    BuildContext context,
    PlayerCubit cubit,
    PlayerState state,
    PulsrPalette p,
    String? dspBlockedGlobal,
  ) {
    return Material(
      type: MaterialType.transparency,
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
                          Flexible(
                            child: Container(
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w800,
                                  color: dspBlockedGlobal != null
                                      ? p.error
                                      : (state.isEqEnabled
                                          ? p.accent
                                          : p.textTertiary),
                                ),
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
                    value: state.isEqEnabled,
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
      type: MaterialType.transparency,
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
                  _setDspMasterEnabled(cubit, !state.isDspEffectsActive);
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
                          Flexible(
                            child: Container(
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w800,
                                  color: dspBlockedGlobal != null
                                      ? p.error
                                      : (state.isDspEffectsActive
                                          ? p.accent
                                          : p.textTertiary),
                                ),
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
                            : (val) => _setDspMasterEnabled(cubit, val),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
