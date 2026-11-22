part of '../equalizer_sheet.dart';

/// 10/32/64-band selector toolbar and vertical band slider bank for Pro Rack Tab 0.
extension _EqParametricToolbar on _EqualizerSheetState {
  Widget _buildBandPlanToolbar({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required PulsrPalette p,
    required String? dspBlocked,
  }) {
    return LayoutBuilder(
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
                              if (_activeBandCount(state) == bandCount) return;
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
                              : p.surfaceContainer.withValues(alpha: 0.0),
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
                      horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.12),
                    borderRadius: AppRadii.r8All,
                    border: Border.all(color: p.accent.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    state.eqPreset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                      color: p.accent,
                    ),
                  ),
                ),
              ),
            ],
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: _autoPreampEnabled
                      ? context.l10n.autoPreampActiveClipping
                      : context.l10n.autoPreampOffHint,
                  child: InkWell(
                    borderRadius: AppRadii.r8All,
                    onTap: dspBlocked != null
                        ? null
                        : () {
                            PulsrHaptics.selectionClick();
                            _setStateSafe(() {
                              _autoPreampEnabled = !_autoPreampEnabled;
                              if (_autoPreampEnabled) {
                                cubit.setPreamp(EqSheetMath.autoPreampFor(
                                    cubit.state.eqPreset.gains));
                              }
                            });
                          },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? AppSpacing.s8 : AppSpacing.s6,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: _autoPreampEnabled
                            ? p.accent.withValues(alpha: 0.16)
                            : p.surfaceContainer,
                        borderRadius: AppRadii.r8All,
                        border: Border.all(
                          color: _autoPreampEnabled ? p.accent : p.hairline,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _autoPreampEnabled
                                ? Icons.shield_rounded
                                : Icons.shield_outlined,
                            size: 16,
                            color: _autoPreampEnabled
                                ? p.accent
                                : p.textSecondary,
                          ),
                          if (isWide) ...[
                            const SizedBox(width: AppSpacing.xxs),
                            Text(
                              context.l10n.eqAutoPreamp,
                              style: TextStyle(
                                fontSize: AppFontSize.caption,
                                color: _autoPreampEnabled
                                    ? p.accent
                                    : p.textSecondary,
                                fontWeight: FontWeight.w700,
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
                  message: context.l10n.resetToFlat,
                  child: InkWell(
                    borderRadius: AppRadii.r8All,
                    onTap: dspBlocked != null
                        ? null
                        : () {
                            PulsrHaptics.selectionClick();
                            cubit.resetToFlat();
                          },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? AppSpacing.s8 : AppSpacing.s6,
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
                          Icon(Icons.restart_alt_rounded,
                              size: 16, color: p.textSecondary),
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
                            PulsrHaptics.lightImpact();
                            _showCustomFrequencyEditor(cubit, state);
                          },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? AppSpacing.s8 : AppSpacing.s6,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.12),
                        borderRadius: AppRadii.r8All,
                        border:
                            Border.all(color: p.accent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, size: 16, color: p.accent),
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
    );
  }

  Widget _buildBandSlidersContainer({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required PulsrPalette p,
    required bool effectiveEnabled,
  }) {
    return Container(
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
          const minBandWidth = AppSpacing.minTouchTarget;
          final fitsWithoutScroll = bandCount <= 10 &&
              (context.isTabletLandscape ||
                  constraints.maxWidth >= bandCount * minBandWidth);

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
                    : SizedBox(width: minBandWidth + 4.0, child: control);
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
    );
  }
}
