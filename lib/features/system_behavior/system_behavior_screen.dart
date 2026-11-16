// lib/features/system_behavior/system_behavior_screen.dart
//
// Settings screen for the system-behaviour pack. It only edits
// SystemBehaviorSettings: no platform call, no playback control, no decision
// logic lives here. Rows that the current platform cannot honour stay visible
// but disabled, with the reason in place of their explanation.

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/platform_capabilities.dart';
import '../../core/widgets/pulsr_segmented_control.dart';
import '../../core/widgets/pulsr_slider.dart';
import '../../core/widgets/pulsr_switch.dart';
import 'system_behavior_settings.dart';
import 'system_behavior_strings.dart';

/// Lets the user shape how playback reacts to focus loss, notification
/// sounds, unplugs, task removal, volume keys and fades.
class SystemBehaviorScreen extends StatefulWidget {
  /// Creates the screen over [settings]; load them before or let the screen
  /// load them on first build.
  const SystemBehaviorScreen({super.key, required this.settings});

  /// Live settings store the rows read and write.
  final SystemBehaviorSettings settings;

  @override
  State<SystemBehaviorScreen> createState() => _SystemBehaviorScreenState();
}

class _SystemBehaviorScreenState extends State<SystemBehaviorScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.settings.isLoaded) unawaited(widget.settings.load());
  }

  @override
  Widget build(BuildContext context) {
    final bool android = PlatformCapabilities.isAndroid;
    return Scaffold(
      appBar: AppBar(title: const Text(SystemBehaviorStrings.screenTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.settings,
          builder: (BuildContext context, Widget? child) => ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            children: <Widget>[
              const _SectionHeader(title: SystemBehaviorStrings.sectionFocus),
              _NotificationSoundRow(settings: widget.settings),
              _ResumeRow(settings: widget.settings),
              const _SectionHeader(title: SystemBehaviorStrings.sectionUsb),
              _UsbReleaseRow(settings: widget.settings, android: android),
              _CloseUsbRow(settings: widget.settings, android: android),
              const _SectionHeader(
                title: SystemBehaviorStrings.sectionVolume,
              ),
              _VolumeRockerRow(settings: widget.settings, android: android),
              _CurveRow(settings: widget.settings),
              _VolumeStepRow(settings: widget.settings),
              const _SectionHeader(
                title: SystemBehaviorStrings.sectionLifecycle,
              ),
              _FadeRow(settings: widget.settings),
              _TaskRemovedRow(settings: widget.settings, android: android),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title of one group of rows.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final PulsrPalette p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.md,
        end: AppSpacing.md,
        top: AppSpacing.md,
        bottom: AppSpacing.s4,
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: AppFontSize.caption,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: p.textTertiary,
        ),
      ),
    );
  }
}

/// A switch row that writes straight through to the settings store.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.disabledReason,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final PulsrPalette p = context.palette;
    final bool disabled = disabledReason != null;
    return PulsrSwitchListTile(
      leading: Icon(
        icon,
        size: 20,
        color: disabled ? p.textTertiary : p.accent,
      ),
      title: Text(title),
      subtitle: Text(
        disabled ? disabledReason! : subtitle,
        style: TextStyle(fontSize: AppFontSize.bodySmall, color: p.textSecondary),
      ),
      value: value,
      onChanged: disabled ? null : onChanged,
      disabledReason: disabledReason,
    );
  }
}

/// A slider row with a value readout and an explanation.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final PulsrPalette p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.s10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 20, color: p.accent),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w700,
                    letterSpacing: AppTracking.title,
                    color: p.textPrimary,
                  ),
                ),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  fontSize: AppFontSize.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: AppFontSize.bodySmall,
              height: 1.35,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          PulsrSlider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            semanticLabel: title,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A pick-one row backed by [PulsrSegmentedControl].
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.disabledReason,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<PulsrSegment> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final PulsrPalette p = context.palette;
    final bool disabled = disabledReason != null;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.s10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                icon,
                size: 20,
                color: disabled ? p.textTertiary : p.accent,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w700,
                    letterSpacing: AppTracking.title,
                    color: disabled ? p.textTertiary : p.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            disabled ? disabledReason! : subtitle,
            style: TextStyle(
              fontSize: AppFontSize.bodySmall,
              height: 1.35,
              color: p.textSecondary,
            ),
          ),
          if (!disabled) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            PulsrSegmentedControl(
              segments: segments,
              selectedIndex: selectedIndex,
              onChanged: onChanged,
              fitLabels: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationSoundRow extends StatelessWidget {
  const _NotificationSoundRow({required this.settings});

  final SystemBehaviorSettings settings;

  @override
  Widget build(BuildContext context) {
    return _SwitchRow(
      icon: Icons.notifications_active_rounded,
      title: SystemBehaviorStrings.pauseOnNotificationSoundTitle,
      subtitle: SystemBehaviorStrings.pauseOnNotificationSoundSubtitle,
      value: settings.pauseOnNotificationSound,
      onChanged: (bool value) =>
          unawaited(settings.setPauseOnNotificationSound(value)),
    );
  }
}

class _ResumeRow extends StatelessWidget {
  const _ResumeRow({required this.settings});

  final SystemBehaviorSettings settings;

  @override
  Widget build(BuildContext context) {
    return _SwitchRow(
      icon: Icons.phone_callback_rounded,
      title: SystemBehaviorStrings.resumeAfterCallTitle,
      subtitle: SystemBehaviorStrings.resumeAfterCallSubtitle,
      value: settings.resumeAfterCall,
      onChanged: (bool value) => unawaited(settings.setResumeAfterCall(value)),
    );
  }
}

class _UsbReleaseRow extends StatelessWidget {
  const _UsbReleaseRow({required this.settings, required this.android});

  final SystemBehaviorSettings settings;
  final bool android;

  @override
  Widget build(BuildContext context) {
    return _ChoiceRow(
      icon: Icons.usb_rounded,
      title: SystemBehaviorStrings.usbReleaseOnFocusLossTitle,
      subtitle: SystemBehaviorStrings.usbReleaseOnFocusLossSubtitle,
      disabledReason: android ? null : SystemBehaviorStrings.usbOnlyLimit,
      segments: const <PulsrSegment>[
        PulsrSegment(
          label: SystemBehaviorStrings.usbReleaseNever,
          icon: Icons.block_rounded,
        ),
        PulsrSegment(
          label: SystemBehaviorStrings.usbReleasePermanent,
          icon: Icons.pause_circle_outline_rounded,
        ),
        PulsrSegment(
          label: SystemBehaviorStrings.usbReleaseTransient,
          icon: Icons.swap_horiz_rounded,
        ),
      ],
      selectedIndex:
          UsbReleaseOnFocusLoss.values.indexOf(settings.usbReleaseOnFocusLoss),
      onChanged: (int index) => unawaited(
        settings.setUsbReleaseOnFocusLoss(
          UsbReleaseOnFocusLoss.values[index],
        ),
      ),
    );
  }
}

class _CloseUsbRow extends StatelessWidget {
  const _CloseUsbRow({required this.settings, required this.android});

  final SystemBehaviorSettings settings;
  final bool android;

  @override
  Widget build(BuildContext context) {
    return _SwitchRow(
      icon: Icons.power_settings_new_rounded,
      title: SystemBehaviorStrings.closeUsbWhenBackgroundedTitle,
      subtitle: SystemBehaviorStrings.closeUsbWhenBackgroundedSubtitle,
      value: settings.closeUsbWhenBackgrounded,
      disabledReason: android ? null : SystemBehaviorStrings.usbOnlyLimit,
      onChanged: (bool value) =>
          unawaited(settings.setCloseUsbWhenBackgrounded(value)),
    );
  }
}

class _VolumeRockerRow extends StatelessWidget {
  const _VolumeRockerRow({required this.settings, required this.android});

  final SystemBehaviorSettings settings;
  final bool android;

  @override
  Widget build(BuildContext context) {
    return _SwitchRow(
      icon: Icons.volume_up_rounded,
      title: SystemBehaviorStrings.volumeRockerTrackSwitchTitle,
      subtitle: SystemBehaviorStrings.volumeRockerTrackSwitchSubtitle,
      value: settings.volumeRockerTrackSwitch,
      disabledReason: android ? null : SystemBehaviorStrings.volumeRockerLimit,
      onChanged: (bool value) =>
          unawaited(settings.setVolumeRockerTrackSwitch(value)),
    );
  }
}

class _CurveRow extends StatelessWidget {
  const _CurveRow({required this.settings});

  final SystemBehaviorSettings settings;

  @override
  Widget build(BuildContext context) {
    return _ChoiceRow(
      icon: Icons.show_chart_rounded,
      title: SystemBehaviorStrings.softwareVolumeCurveTitle,
      subtitle: SystemBehaviorStrings.softwareVolumeCurveSubtitle,
      segments: const <PulsrSegment>[
        PulsrSegment(
          label: SystemBehaviorStrings.curveLinear,
          icon: Icons.trending_flat_rounded,
        ),
        PulsrSegment(
          label: SystemBehaviorStrings.curveLogarithmic,
          icon: Icons.trending_up_rounded,
        ),
      ],
      selectedIndex:
          SoftwareVolumeCurve.values.indexOf(settings.softwareVolumeCurve),
      onChanged: (int index) => unawaited(
        settings.setSoftwareVolumeCurve(SoftwareVolumeCurve.values[index]),
      ),
    );
  }
}

class _VolumeStepRow extends StatelessWidget {
  const _VolumeStepRow({required this.settings});

  final SystemBehaviorSettings settings;

  @override
  Widget build(BuildContext context) {
    return _SliderRow(
      icon: Icons.tune_rounded,
      title: SystemBehaviorStrings.volumeStepPercentTitle,
      subtitle: SystemBehaviorStrings.volumeStepPercentSubtitle,
      value: settings.volumeStepPercent.toDouble(),
      min: SystemBehaviorSettingsSnapshot.minVolumeStepPercent.toDouble(),
      max: SystemBehaviorSettingsSnapshot.maxVolumeStepPercent.toDouble(),
      divisions: SystemBehaviorSettingsSnapshot.maxVolumeStepPercent -
          SystemBehaviorSettingsSnapshot.minVolumeStepPercent,
      valueLabel: SystemBehaviorStrings.volumeStepValue(
        settings.volumeStepPercent,
      ),
      onChanged: (double value) =>
          unawaited(settings.setVolumeStepPercent(value.round())),
    );
  }
}

class _FadeRow extends StatelessWidget {
  const _FadeRow({required this.settings});

  final SystemBehaviorSettings settings;

  @override
  Widget build(BuildContext context) {
    return _SliderRow(
      icon: Icons.gradient_rounded,
      title: SystemBehaviorStrings.fadeOutOnPauseMsTitle,
      subtitle: SystemBehaviorStrings.fadeOutOnPauseMsSubtitle,
      value: settings.fadeOutOnPauseMs.toDouble(),
      min: SystemBehaviorSettingsSnapshot.minFadeOutOnPauseMs.toDouble(),
      max: SystemBehaviorSettingsSnapshot.maxFadeOutOnPauseMs.toDouble(),
      divisions: 100,
      valueLabel: SystemBehaviorStrings.fadeValue(settings.fadeOutOnPauseMs),
      onChanged: (double value) =>
          unawaited(settings.setFadeOutOnPauseMs(value.round())),
    );
  }
}

class _TaskRemovedRow extends StatelessWidget {
  const _TaskRemovedRow({required this.settings, required this.android});

  final SystemBehaviorSettings settings;
  final bool android;

  @override
  Widget build(BuildContext context) {
    return _SwitchRow(
      icon: Icons.layers_clear_rounded,
      title: SystemBehaviorStrings.stopWhenTaskRemovedTitle,
      subtitle: SystemBehaviorStrings.stopWhenTaskRemovedSubtitle,
      value: settings.stopWhenTaskRemoved,
      disabledReason: android ? null : SystemBehaviorStrings.androidOnlyLimit,
      onChanged: (bool value) =>
          unawaited(settings.setStopWhenTaskRemoved(value)),
    );
  }
}
