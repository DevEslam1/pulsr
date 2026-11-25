part of '../equalizer_sheet.dart';

/// Hardware output device profile selector bar for [EqualizerSheet].
extension _EqDeviceProfileBar on _EqualizerSheetState {
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
      ),
      width: double.infinity,
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
            child: _buildDeviceTypeChip(
              context: context,
              label: context.l10n.dspHeadset,
              icon: Icons.headphones_rounded,
              isActive: isWired,
              p: p,
              onTap: () {
                if (state.currentSong != null) {
                  AudioQualitySheet.show(context, state.currentSong!, p.accent);
                }
              },
            ),
          ),
          Expanded(
            child: _buildDeviceTypeChip(
              context: context,
              label: context.l10n.dspSpeaker,
              icon: Icons.volume_up_rounded,
              isActive: isSpeaker,
              p: p,
              onTap: () {
                if (state.currentSong != null) {
                  AudioQualitySheet.show(context, state.currentSong!, p.accent);
                }
              },
            ),
          ),
          Expanded(
            child: _buildDeviceTypeChip(
              context: context,
              label: context.l10n.outputBluetooth,
              icon: Icons.bluetooth_audio_rounded,
              isActive: isBt,
              p: p,
              onTap: () {
                if (state.currentSong != null) {
                  AudioQualitySheet.show(context, state.currentSong!, p.accent);
                }
              },
            ),
          ),
          Expanded(
            child: _buildDeviceTypeChip(
              context: context,
              label: context.l10n.outputUsbDac,
              icon: Icons.album_rounded,
              isActive: isUsb,
              p: p,
              onTap: () {
                if (state.currentSong != null) {
                  AudioQualitySheet.show(context, state.currentSong!, p.accent);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTypeChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isActive,
    required PulsrPalette p,
    required VoidCallback onTap,
  }) {
    final animate = PulsrMotion.shouldAnimate(context);
    return Semantics(
      button: true,
      selected: isActive,
      label: '$label, ${isActive ? "active" : "inactive"}',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            PulsrHaptics.selectionClick();
            onTap();
          },
          borderRadius: AppRadii.r16All,
          child: AnimatedContainer(
            duration: animate ? context.motionMs(200) : Duration.zero,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive
                  ? p.accent.withValues(alpha: 0.18)
                  : p.surfaceContainer.withValues(alpha: 0.0),
              borderRadius: AppRadii.r16All,
              border: Border.all(
                color: isActive ? p.accent : p.hairline.withValues(alpha: 0.0),
                width: 1.2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: isActive ? p.accent : p.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w600,
                              color: isActive ? p.accent : p.textSecondary,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 3),
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
