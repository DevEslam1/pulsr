part of '../audio_quality_sheet.dart';

/// Bluetooth permission, LE Audio, and proxy-initializing banners for
/// [AudioQualitySheet].
extension _BluetoothStatusBanners on AudioQualitySheet {
  static const _btAccent = AppColors.accentCyan;
  static const _ldacAccent = AppColors.ldacViolet;
  static const _warnAccent = AppColors.warning;

  Widget _buildLdacQualityCard({
    required BuildContext context,
    required SettingsCubit? cubit,
    required PulsrPalette p,
    required int ldacMode,
    required List<(int, String, String)> ldacModes,
    required bool canConfigure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: _ldacAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.s6),
            Text(
              context.l10n.ldacQuality,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                letterSpacing: AppTracking.wide,
                fontWeight: FontWeight.w700,
                color: _ldacAccent.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s6),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s14, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: _ldacAccent.withValues(alpha: 0.12),
            borderRadius: AppRadii.r10All,
            border: Border.all(color: _ldacAccent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Text(
                ldacModes[ldacMode.clamp(0, 3)].$2,
                style: const TextStyle(
                  color: _ldacAccent,
                  fontSize: AppFontSize.bodySmall,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                ldacModes[ldacMode.clamp(0, 3)].$3,
                style: TextStyle(
                    color: p.textTertiary, fontSize: AppFontSize.label),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  4,
                  (i) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: !canConfigure
                        ? null
                        : () async {
                            PulsrHaptics.selectionClick();
                            final ok =
                                await cubit?.setBluetoothLdacQuality(i) ??
                                    false;
                            if (!ok && context.mounted) {
                              _showBtRefused(context, cubit);
                            }
                          },
                    child: Container(
                      width: AppSpacing.minTouchTarget,
                      height: AppSpacing.minTouchTarget,
                      alignment: Alignment.center,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= ldacMode ? _ldacAccent : p.hairline,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBtDevOptionsTile(
      BuildContext context, SettingsCubit? cubit, PulsrPalette p) {
    return GestureDetector(
      onTap: () async {
        unawaited(PulsrHaptics.mediumImpact());
        await cubit?.openBluetoothDevOptions();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _btAccent.withValues(alpha: 0.12),
              _ldacAccent.withValues(alpha: 0.08),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: AppRadii.r14All,
          border: Border.all(color: _btAccent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _btAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.developer_mode_rounded,
                color: _btAccent,
                size: 16,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.changeBtCodec,
                    style: const TextStyle(
                      color: _btAccent,
                      fontSize: AppFontSize.bodySmall,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    context.l10n.devOptionsBtCodec,
                    style: TextStyle(
                        color: p.textTertiary, fontSize: AppFontSize.caption),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              color: _btAccent.withValues(alpha: 0.7),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _showBtRefused(BuildContext context, SettingsCubit? cubit) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(context.l10n.switchPrefFailed),
        action: SnackBarAction(
          label: context.l10n.devOptionsBtCodec,
          onPressed: () => cubit?.openBluetoothDevOptions(),
        ),
      ),
    );
  }

  Future<void> _showBtOptionPicker({
    required BuildContext context,
    required SettingsCubit? cubit,
    required String title,
    required List<int> options,
    required int current,
    required String Function(int value) label,
    required Future<bool> Function(int value) onPick,
  }) async {
    final sorted = List<int>.of(options)..sort();
    final selected = await PulsrSheetHelper.showPulsrSheet<int>(
      context: context,
      builder: (sheetCtx) {
        final sp = sheetCtx.palette;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20,
                    AppSpacing.sm, AppSpacing.s20, AppSpacing.xxs),
                child: Text(
                  title,
                  style: TextStyle(
                    color: sp.textPrimary,
                    fontSize: AppFontSize.callout,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final opt in sorted)
                ListTile(
                  title: Text(
                    label(opt),
                    style: TextStyle(
                      color: opt == current ? _btAccent : sp.textPrimary,
                      fontWeight:
                          opt == current ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  trailing: opt == current
                      ? const Icon(Icons.check_rounded,
                          color: _btAccent, size: 20)
                      : null,
                  onTap: () => Navigator.of(sheetCtx).pop(opt),
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
    if (selected == null || selected == current || !context.mounted) return;
    PulsrHaptics.selectionClick();
    final ok = await onPick(selected);
    if (!ok && context.mounted) _showBtRefused(context, cubit);
  }

  Widget _buildPermissionBanner(
    BuildContext context,
    SettingsCubit? cubit,
    PulsrPalette p,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _warnAccent.withValues(alpha: 0.1),
        borderRadius: AppRadii.r16All,
        border: Border.all(color: _warnAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bluetooth_audio_rounded,
                size: 14,
                color: _btAccent,
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                context.l10n.btAudioCodec,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  letterSpacing: AppTracking.wide,
                  fontWeight: FontWeight.w800,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: _warnAccent,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Text(
                  context.l10n.nearbyPermDesc,
                  style: TextStyle(
                      color: p.textSecondary, fontSize: AppFontSize.label),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              unawaited(PulsrHaptics.mediumImpact());
              await _requestBluetoothPermission(context, cubit);
            },
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.minTouchTarget,
                minWidth: AppSpacing.minTouchTarget,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: _warnAccent.withValues(alpha: 0.15),
                borderRadius: AppRadii.r10All,
                border: Border.all(color: _warnAccent.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.settings_bluetooth_rounded,
                    color: _warnAccent,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    context.l10n.grantBtPerm,
                    style: const TextStyle(
                      color: _warnAccent,
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeAudioBanner(
    BuildContext context,
    SettingsCubit? cubit,
    PulsrPalette p,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bluetooth_audio_rounded,
                size: 14, color: _btAccent),
            const SizedBox(width: AppSpacing.s6),
            Text(
              context.l10n.leAudio,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                letterSpacing: AppTracking.wide,
                fontWeight: FontWeight.w800,
                color: p.textSecondary,
              ),
            ),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                PulsrHaptics.selectionClick();
                cubit?.refreshOutputDevice();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                child: Center(
                  child: Icon(Icons.refresh_rounded,
                      size: 16, color: p.textTertiary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s14),
          decoration: BoxDecoration(
            color: _btAccent.withValues(alpha: 0.10),
            borderRadius: AppRadii.r16All,
            border: Border.all(color: _btAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: _btAccent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hearing_rounded,
                    color: _btAccent, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LC3',
                      style: TextStyle(
                        fontSize: AppFontSize.bodyLarge,
                        fontWeight: FontWeight.w900,
                        color: _btAccent,
                        letterSpacing: AppTracking.medium,
                      ),
                    ),
                    Text(
                      context.l10n.lc3Negotiation,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProxyLoadingBanner(
    BuildContext context,
    SettingsCubit? cubit,
    PulsrPalette p,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: _btAccent.withValues(alpha: 0.07),
        borderRadius: AppRadii.r16All,
        border: Border.all(color: _btAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_audio_rounded, size: 14, color: _btAccent),
          const SizedBox(width: AppSpacing.s6),
          Expanded(
            child: Text(
              context.l10n.connectingBt,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.label,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              PulsrHaptics.selectionClick();
              cubit?.refreshOutputDevice();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              child: Center(
                child: Text(
                  context.l10n.retry,
                  style: const TextStyle(
                    color: _btAccent,
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestBluetoothPermission(
    BuildContext context,
    SettingsCubit? cubit,
  ) async {
    try {
      await cubit?.requestBluetoothPermission();
    } catch (e, st) {
      ErrorLogger.log('Failed to request bluetooth permission',
          error: e, stackTrace: st, category: 'AudioQualitySheet');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await cubit?.refreshOutputDevice();
  }
}
