part of '../audio_quality_sheet.dart';

/// Output tab content for [AudioQualitySheet]: hardware device routing, Cast
/// tile, and collapsible route-specific drawers (Bluetooth vs USB DAC vs
/// Internal).
extension _AudioQualityOutputTab on AudioQualitySheet {
  List<Widget> _buildOutputChildren({
    required BuildContext context,
    required AudioOutputInfo? outputDevice,
    required SettingsCubit? settingsCubit,
    required AudioQualityInfo info,
    required BitPerfectState state,
    required UsbExclusiveStatus usbStatus,
    required PulsrPalette p,
  }) {
    final isBt = (outputDevice?.isBluetooth == true) ||
        (outputDevice?.btA2dpPresent == true);
    final isUsb = outputDevice?.isUsbDac == true || usbStatus.attached;

    final formatControls = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.targetSampleRate,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            letterSpacing: AppTracking.wide,
            fontWeight: FontWeight.w800,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildSampleRateSelector(
          context,
          outputDevice,
          settingsCubit,
          p,
          activeColor,
          info,
          state,
        ),
        const SizedBox(height: AppSpacing.s20),
        Text(
          context.l10n.targetBitPerfect,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            letterSpacing: AppTracking.wide,
            fontWeight: FontWeight.w800,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildBitDepthSelector(
          context,
          outputDevice,
          settingsCubit,
          p,
          activeColor,
          info,
          state,
        ),
      ],
    );

    return <Widget>[
      // Hardware Output Routing
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              context.l10n.hwOutputRouting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                letterSpacing: AppTracking.wide,
                fontWeight: FontWeight.w800,
                color: p.textSecondary,
              ),
            ),
          ),
          if (outputDevice?.isUsbDac == true) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s6,
                vertical: AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: AppColors.dacGold.withValues(alpha: 0.18),
                borderRadius: AppRadii.r6All,
              ),
              child: Text(
                context.l10n.usbDacAttached,
                style: const TextStyle(
                  color: AppColors.dacGold,
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: AppSpacing.s10),
      _buildOutputDevicesSelector(
        context,
        outputDevice,
        settingsCubit,
        p,
        activeColor,
      ),
      const SizedBox(height: AppSpacing.s10),
      _buildCastOutputTile(context, p, activeColor),
      const SizedBox(height: AppSpacing.md),

      // Route-specific collapsible drawers (Bluetooth vs USB DAC vs Internal)
      if (isBt) ...[
        AudioRouteDrawer(
          key: const ValueKey('audio_route_drawer_bluetooth'),
          icon: Icons.bluetooth_audio_rounded,
          title: context.l10n.wizardBluetoothTitle,
          subtitle: outputDevice?.deviceName ?? context.l10n.outputBluetooth,
          statusPill: outputDevice?.btCodecName ?? context.l10n.activeLabel,
          accentColor: AppColors.accentCyan,
          isActiveRoute: true,
          initiallyExpanded: true,
          child: _buildBluetoothCodecSection(
            context,
            outputDevice,
            settingsCubit,
            p,
            activeColor,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],

      if (isUsb)
        AudioRouteDrawer(
          key: const ValueKey('audio_route_drawer_usb_dac'),
          icon: Icons.usb_rounded,
          title: context.l10n.outputDeviceUsbHiResDac,
          subtitle: _outputStreamDescription(context, outputDevice),
          statusPill: state.isVerified
              ? context.l10n.activeLabel
              : (outputDevice?.usbAudioClass != null &&
                      outputDevice!.usbAudioClass > 0
                  ? 'UAC${outputDevice.usbAudioClass}'
                  : context.l10n.activeLabel),
          accentColor: AppColors.dacGold,
          isActiveRoute: true,
          initiallyExpanded: true,
          child: formatControls,
        )
      else
        AudioRouteDrawer(
          key: const ValueKey('audio_route_drawer_internal'),
          icon: Icons.speaker_rounded,
          title: context.l10n.outputDeviceInternalDac,
          subtitle: _outputStreamDescription(context, outputDevice),
          statusPill: !isBt
              ? context.l10n.activeLabel
              : context.l10n.audioQualityStandard,
          accentColor: activeColor,
          isActiveRoute: !isBt,
          initiallyExpanded: true,
          child: formatControls,
        ),
    ];
  }

  Widget _buildOutputDevicesSelector(
    BuildContext context,
    AudioOutputInfo? outputDevice,
    SettingsCubit? cubit,
    PulsrPalette p,
    Color activeColor,
  ) {
    final devices = outputDevice?.availableDevices ?? [];
    final animate = PulsrMotion.shouldAnimate(context);

    if (devices.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: activeColor.withValues(alpha: 0.12),
          borderRadius: AppRadii.r14All,
          border: Border.all(color: activeColor, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                outputDevice?.isUsbDac == true
                    ? Icons.usb_rounded
                    : Icons.volume_up_rounded,
                color: activeColor,
                size: 18,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    outputDevice?.deviceName ??
                        context.l10n.outputRouteUnverified,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: AppFontSize.bodySmall,
                    ),
                  ),
                  Text(
                    _outputStreamDescription(context, outputDevice),
                    style: TextStyle(
                        color: p.textSecondary, fontSize: AppFontSize.caption),
                  ),
                ],
              ),
            ),
            Icon(Icons.check_circle_rounded, color: activeColor, size: 20),
          ],
        ),
      );
    }

    final hasExplicitCurrent = devices.any((d) => d.isCurrent);
    final hasExplicitPreferred = devices.any((d) => d.isPreferred);
    final fallbackTarget = !hasExplicitCurrent && !hasExplicitPreferred
        ? devices
                .where((d) =>
                    outputDevice?.deviceName != null &&
                    outputDevice!.deviceName.isNotEmpty &&
                    outputDevice.deviceName != 'Default Audio Output' &&
                    outputDevice.deviceName != 'Output route unverified' &&
                    d.name.trim().toLowerCase() ==
                        outputDevice.deviceName.trim().toLowerCase())
                .firstOrNull ??
            devices.firstOrNull
        : null;

    return Column(
      children: [
        ...devices.map((dev) {
          final isSelected = dev.isCurrent ||
              (!hasExplicitCurrent && dev.isPreferred) ||
              (fallbackTarget != null && dev.id == fallbackTarget.id);
          final devIcon = _getDeviceIcon(dev.type);

          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: AnimatedContainer(
              duration: animate ? context.motionMs(200) : Duration.zero,
              decoration: BoxDecoration(
                color: isSelected
                    ? activeColor.withValues(alpha: 0.12)
                    : p.surfaceContainer,
                borderRadius: AppRadii.r14All,
                border: Border.all(
                  color: isSelected ? activeColor : p.hairline,
                  width: isSelected ? 1.5 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: AppRadii.r14All,
                  onTap: () async {
                    PulsrHaptics.selectionClick();
                    final applied =
                        await cubit?.selectOutputDevice(dev.id) ?? false;
                    if (!applied && context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                        content: Text(
                            context.l10n.audioQualityOutputSwitchUnavailable),
                      ));
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s14,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? activeColor.withValues(alpha: 0.2)
                                : p.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            devIcon,
                            size: 18,
                            color: isSelected ? activeColor : p.textSecondary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dev.name,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: AppFontSize.bodySmall,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              Text(
                                isSelected
                                    ? (dev.isPreferred && !dev.isCurrent
                                        ? context
                                            .l10n.audioRouteRequestedWaiting
                                        : context.l10n.audioRouteActive(
                                            _outputStreamDescription(
                                                context, outputDevice)))
                                    : context.l10n
                                        .audioRouteAvailable(dev.typeName),
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.caption,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedSwitcher(
                          duration:
                              animate ? context.motionMs(120) : Duration.zero,
                          child: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  key: const ValueKey('checked'),
                                  color: activeColor,
                                  size: 20,
                                )
                              : Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  key: const ValueKey('unchecked'),
                                  color: p.textTertiary,
                                  size: 20,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () {
              PulsrHaptics.selectionClick();
              cubit?.openOutputSwitcher();
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: Text(
              context.l10n.switchOutputPanel,
              style: const TextStyle(
                  fontSize: AppFontSize.caption, fontWeight: FontWeight.w700),
            ),
            style: TextButton.styleFrom(
              foregroundColor: p.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              minimumSize: const Size(AppSpacing.minTouchTarget,
                  AppSpacing.minTouchTarget),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCastOutputTile(
    BuildContext context,
    PulsrPalette p,
    Color activeColor,
  ) {
    return ValueListenableBuilder<CastSessionStatus>(
      valueListenable: CastService().sessionStatusListenable,
      builder: (context, session, _) {
        final isConnected = session.connected;

        return InkWell(
          borderRadius: AppRadii.r14All,
          onTap: () => PulsrCastSheet.show(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
            decoration: BoxDecoration(
              color: isConnected
                  ? activeColor.withValues(alpha: 0.14)
                  : p.surfaceContainer,
              borderRadius: AppRadii.r14All,
              border: Border.all(
                color: isConnected ? activeColor : p.hairline,
                width: isConnected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? activeColor.withValues(alpha: 0.20)
                        : p.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isConnected
                        ? Icons.cast_connected_rounded
                        : Icons.cast_rounded,
                    size: 18,
                    color: isConnected ? activeColor : p.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected
                            ? context.l10n.castCastingTo(
                                session.deviceName ?? context.l10n.castDevice)
                            : context.l10n.castToSpeakerDisplay,
                        style: TextStyle(
                          color: isConnected ? activeColor : p.textPrimary,
                          fontSize: AppFontSize.bodySmall,
                          fontWeight:
                              isConnected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      Text(
                        isConnected
                            ? context.l10n.castManageHint
                            : context.l10n.castStreamHint,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isConnected ? activeColor : p.textTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getDeviceIcon(int type) {
    switch (type) {
      case 2: // TYPE_BUILTIN_SPEAKER
        return Icons.volume_up_rounded;
      case 3: // TYPE_WIRED_HEADSET
      case 4: // TYPE_WIRED_HEADPHONES
        return Icons.headphones_rounded;
      case 7: // TYPE_BLUETOOTH_SCO
      case 8: // TYPE_BLUETOOTH_A2DP
      case 26: // TYPE_BLE_HEADSET
      case 27: // TYPE_BLE_SPEAKER
      case 30: // TYPE_BLE_BROADCAST
        return Icons.bluetooth_audio_rounded;
      case 23: // TYPE_HEARING_AID
        return Icons.hearing_rounded;
      case 9: // TYPE_HDMI
      case 10: // TYPE_HDMI_ARC
      case 29: // TYPE_HDMI_EARC
        return Icons.tv_rounded;
      case 11: // TYPE_USB_DEVICE
      case 22: // TYPE_USB_HEADSET
      case 12: // TYPE_USB_ACCESSORY
        return Icons.usb_rounded;
      case 13: // TYPE_DOCK
        return Icons.dock_rounded;
      default:
        return Icons.speaker_rounded;
    }
  }
}
