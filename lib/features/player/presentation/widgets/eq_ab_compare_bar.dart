part of 'equalizer_sheet.dart';

extension _EqAbCompareBar on _EqualizerSheetState {
  Widget _buildAbCompareToggle({
    required PlayerCubit cubit,
    required PulsrPalette p,
    required String? dspBlocked,
  }) {
    return IgnorePointer(
      ignoring: dspBlocked != null,
      child: Opacity(
        opacity: dspBlocked != null ? 0.45 : 1.0,
        child: GestureDetector(
          onTapDown: (_) {
            PulsrHaptics.selectionClick();
            _setStateSafe(() => _isAbComparing = true);
            cubit.startAbComparison();
          },
          onTapUp: (_) {
            PulsrHaptics.selectionClick();
            _setStateSafe(() => _isAbComparing = false);
            cubit.endAbComparison();
          },
          onTapCancel: () {
            _setStateSafe(() => _isAbComparing = false);
            cubit.endAbComparison();
          },
          child: AnimatedContainer(
            duration: context.motionMs(150),
            curve: context.motionCurve(PulsrMotion.enter),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: _isAbComparing ? p.accent : p.surfaceContainer,
              borderRadius: AppRadii.r10All,
              border: Border.all(color: _isAbComparing ? p.accent : p.hairline),
            ),
            child: Text(
              context.l10n.abFlat,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w700,
                color: _isAbComparing ? p.onAccent : p.textSecondary,
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
              final isSelected = _activeComparisonSlot == slot;
              final label = switch (slot) {
                ComparisonSlot.slotA => 'A',
                ComparisonSlot.slotB => 'B',
                ComparisonSlot.slotC => 'C',
                ComparisonSlot.slotD => 'D',
              };
              return InkWell(
                onTap: () {
                  PulsrHaptics.selectionClick();
                  _setStateSafe(() => _activeComparisonSlot = slot);
                  cubit.switchComparisonSlot(slot);
                },
                borderRadius: AppRadii.r8All,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
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
              );
            }),
          ],
        ],
      ),
    );
  }
}
