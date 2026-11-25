part of 'equalizer_sheet.dart';

extension _EqAbCompareBar on _EqualizerSheetState {
  Future<void> _setAbComparing(PlayerCubit cubit, bool enable) async {
    final prevError = cubit.state.errorMessage;
    try {
      if (enable) {
        await cubit.startAbComparison();
      } else {
        await cubit.endAbComparison();
      }
      if (!mounted) return;
      final after = cubit.state;
      final failed =
          after.errorMessage != null && after.errorMessage != prevError;
      final confirmed = !failed &&
          (_cachedEqualizerManager == null ||
              _cachedEqualizerManager!.isAbComparisonActive == enable);
      _setStateSafe(() {
        _fallbackAbComparing = confirmed
            ? enable
            : (_cachedEqualizerManager?.isAbComparisonActive ?? false);
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to update A/B comparison state',
          error: e, stackTrace: st, category: 'EqualizerSheet');
      if (mounted) {
        _setStateSafe(() {
          _fallbackAbComparing =
              _cachedEqualizerManager?.isAbComparisonActive ?? false;
        });
      }
    }
  }

  Widget _buildAbCompareToggle({
    required PlayerCubit cubit,
    required PulsrPalette p,
    required String? dspBlocked,
  }) {
    final isComparing = _effectiveIsAbComparing;
    return IgnorePointer(
      ignoring: dspBlocked != null,
      child: Opacity(
        opacity: dspBlocked != null ? 0.45 : 1.0,
        child: GestureDetector(
          onTapDown: (_) {
            PulsrHaptics.selectionClick();
            unawaited(_setAbComparing(cubit, true));
          },
          onTapUp: (_) {
            PulsrHaptics.selectionClick();
            unawaited(_setAbComparing(cubit, false));
          },
          onTapCancel: () {
            unawaited(_setAbComparing(cubit, false));
          },
          child: AnimatedContainer(
            duration: context.motionMs(120),
            curve: context.motionCurve(PulsrMotion.enter),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: isComparing ? p.accent : p.surfaceContainer,
              borderRadius: AppRadii.r10All,
              border: Border.all(color: isComparing ? p.accent : p.hairline),
            ),
            child: Text(
              context.l10n.abFlat,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w700,
                color: isComparing ? p.onAccent : p.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAbSlotSelector({
    required PlayerCubit cubit,
    required PulsrPalette p,
  }) {
    final currentSlot = _effectiveComparisonSlot;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r10All,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          for (final slot in ComparisonSlot.values) ...[
            Builder(builder: (context) {
              final isSelected = currentSlot == slot;
              final label = switch (slot) {
                ComparisonSlot.slotA => 'A',
                ComparisonSlot.slotB => 'B',
                ComparisonSlot.slotC => 'C',
                ComparisonSlot.slotD => 'D',
              };
              return Semantics(
                button: true,
                selected: isSelected,
                label: 'EQ $label',
                child: InkWell(
                  onTap: () async {
                    PulsrHaptics.selectionClick();
                    final prevError = cubit.state.errorMessage;
                    await cubit.switchComparisonSlot(slot);
                    if (!mounted) return;
                    final after = cubit.state;
                    final failed = after.errorMessage != null &&
                        after.errorMessage != prevError;
                    if (!failed) {
                      _setStateSafe(() {
                        _fallbackComparisonSlot =
                            _cachedEqualizerManager?.activeComparisonSlot ??
                                slot;
                      });
                    }
                  },
                  borderRadius: AppRadii.r8All,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s10,
                            vertical: AppSpacing.xxs),
                        decoration: BoxDecoration(
                          color: isSelected ? p.accent : Colors.transparent,
                          borderRadius: AppRadii.r8All,
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? p.onAccent : p.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
