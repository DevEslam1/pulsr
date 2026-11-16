// lib/features/system_behavior/system_behavior_screen.dart
//
// Settings screen for the system-behaviour pack. It only edits
// SystemBehaviorSettings: no platform call, no playback control, no decision
// logic lives here. Only controls with a live consumer are shown; fade ramps,
// volume-key skipping and software-curve shaping have no platform supplier yet
// and are deliberately absent instead of persisting prefs nothing reads.

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/platform_capabilities.dart';
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
              _CloseUsbRow(settings: widget.settings, android: android),
              const _SectionHeader(
                title: SystemBehaviorStrings.sectionLifecycle,
              ),
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
