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
            _abCompareTimer?.cancel();
            _setStateSafe(() => _isAbComparing = true);
            cubit.startAbComparison();
            _abCompareTimer = Timer(const Duration(seconds: 10), () {
              if (mounted) {
                _setStateSafe(() => _isAbComparing = false);
              }
              cubit.endAbComparison();
            });
          },
          onTapUp: (_) {
            _abCompareTimer?.cancel();
            _abCompareTimer = null;
            _setStateSafe(() => _isAbComparing = false);
            cubit.endAbComparison();
          },
          onTapCancel: () {
            _abCompareTimer?.cancel();
            _abCompareTimer = null;
            _setStateSafe(() => _isAbComparing = false);
            cubit.endAbComparison();
          },
          child: Container(
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
            InkWell(
              onTap: () => cubit.switchComparisonSlot(slot),
              borderRadius: AppRadii.r8All,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: AppRadii.r8All,
                ),
                child: Text(
                  slot.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
