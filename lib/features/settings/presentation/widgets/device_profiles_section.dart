// lib/features/settings/presentation/widgets/device_profiles_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';

import '../../../../core/services/device_profile_service.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../core/services/hires_audio_service.dart';
import '../../../../core/services/settings_profiles_service.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../player/cubit/player_cubit.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

/// Phase 3: per-output-device profile links and the auto-switch master
/// toggle. Read/write goes through [DeviceProfileService]; applying a
/// profile goes through [PlayerCubit.applyProfile] so the cubit's guarded
/// setters (and conflict rules) stay the single application path.
class DeviceProfilesSection extends StatefulWidget {
  const DeviceProfilesSection({super.key});

  @override
  State<DeviceProfilesSection> createState() => _DeviceProfilesSectionState();
}

class _DeviceProfilesSectionState extends State<DeviceProfilesSection> {
  List<SettingsProfile> _profiles = const [];
  List<DeviceProfileEntry> _devices = const [];
  Map<String, DeviceProfileLink> _links = const {};
  bool _autoEnabled = true;
  bool _loading = true;
  String? _currentDeviceKey;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  DeviceProfileService get _deviceService =>
      getIt.isRegistered<DeviceProfileService>()
          ? getIt<DeviceProfileService>()
          : DeviceProfileService();

  Future<void> _reload() async {
    try {
      final profilesService = getIt<SettingsProfilesService>();
      final deviceService = _deviceService;
      final profiles = await profilesService.getProfiles();
      final devices = await deviceService.registryDevices();
      final links = await deviceService.getLinks();
      final autoEnabled = await deviceService.isAutoSwitchEnabled();
      String? currentKey;
      try {
        final info = getIt<HiResAudioService>().currentOutputInfo;
        if (info != null) currentKey = DeviceProfileService.deviceKeyFromInfo(info);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _devices = devices;
        _links = links;
        _autoEnabled = autoEnabled;
        _currentDeviceKey = currentKey;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setAutoEnabled(bool value) async {
    await _deviceService.setAutoSwitchEnabled(value);
    if (!mounted) return;
    setState(() => _autoEnabled = value);
  }

  Future<void> _assignProfile(String deviceKey, String deviceLabel, String? profileId) async {
    final deviceService = _deviceService;
    if (profileId == null) {
      await deviceService.forgetLink(deviceKey);
    } else {
      await deviceService.rememberLink(
        deviceKey: deviceKey,
        deviceLabel: deviceLabel,
        profileId: profileId,
      );
    }
    await _reload();
  }

  Future<void> _applyForDevice(DeviceProfileEntry device) async {
    final link = _links[device.deviceKey];
    if (link == null) return;
    SettingsProfile? profile;
    for (final p in _profiles) {
      if (p.id == link.profileId) {
        profile = p;
        break;
      }
    }
    if (profile == null) return;
    final l10n = context.l10n;
    await context.read<PlayerCubit>().applyProfile(profile, manual: true);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.appliedProfileTpl(l10n.applyProfileNow, profile.name))),
    );
  }

  /// Captures the player's current EQ/volume as a reusable custom profile so
  /// the device-profile dropdown can offer more than the built-ins
  /// (SettingsProfilesService.saveProfile was previously unreachable).
  Future<void> _createProfileFromCurrent() async {
    final name = await PulsrDialogHelper.showInputDialog(
      context,
      title: context.l10n.customProfilesTitle,
      hintText: context.l10n.profileNameHint,
      icon: Icons.library_add_rounded,
      confirmLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final player = context.read<PlayerCubit>().state;
    final profile = SettingsProfile(
      id: 'profile_custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      type: ProfileType.custom,
      eqPresetName: player.eqPreset.name,
      volumeBoost: player.volumeBoost,
    );
    await getIt<SettingsProfilesService>().saveProfile(profile);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.profileCreated(profile.name))),
    );
  }

  Future<void> _deleteProfile(SettingsProfile profile) async {
    if (SettingsProfile.defaultProfiles.any((p) => p.id == profile.id)) return;
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: context.l10n.profileDeleteConfirm(profile.name),
      message: context.l10n.browseCannotBeUndone,
      icon: Icons.delete_outline_rounded,
      confirmLabel: context.l10n.delete,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    await getIt<SettingsProfilesService>().deleteProfile(profile.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
          child: Text(
            l10n.deviceProfilesSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.autoDeviceSwitch),
          value: _autoEnabled,
          onChanged: _setAutoEnabled,
        ),
        if (_devices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              l10n.noDevicesSeen,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final device in _devices)
            _deviceRow(context, device, l10n),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.customProfilesTitle,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xxs),
        for (final profile in _profiles)
          _profileRow(context, profile, l10n),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _createProfileFromCurrent,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(l10n.profileCreateFromCurrent),
          ),
        ),
      ],
    );
  }

  Widget _profileRow(
      BuildContext context, SettingsProfile profile, AppLocalizations l10n) {
    final isBuiltIn =
        SettingsProfile.defaultProfiles.any((p) => p.id == profile.id);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.equalizer_rounded, size: 20),
      title: Text(profile.name),
      subtitle: Text(isBuiltIn ? l10n.profileBuiltIn : profile.eqPresetName),
      trailing: isBuiltIn
          ? null
          : IconButton(
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: () => _deleteProfile(profile),
            ),
    );
  }

  Widget _deviceRow(
      BuildContext context, DeviceProfileEntry device, AppLocalizations l10n) {
    final link = _links[device.deviceKey];
    final isCurrent = device.deviceKey == _currentDeviceKey;
    final linkedId = link?.profileId;
    final hasLinkedProfile =
        linkedId != null && _profiles.any((p) => p.id == linkedId);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(
                    device.deviceLabel,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (isCurrent)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: AppSpacing.s6),
                    child: Text(
                      l10n.currentDeviceBadge,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ]),
              DropdownButton<String>(
                isExpanded: true,
                underline: const SizedBox.shrink(),
                hint: Text(l10n.profileDropdownLabel,
                    style: Theme.of(context).textTheme.bodySmall),
                value: hasLinkedProfile ? linkedId : null,
                items: [
                  for (final p in _profiles)
                    DropdownMenuItem<String>(value: p.id, child: Text(p.name)),
                ],
                onChanged: (profileId) =>
                    _assignProfile(device.deviceKey, device.deviceLabel, profileId),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: l10n.applyProfileNow,
          icon: const Icon(Icons.play_circle_outline_rounded),
          onPressed: link == null ? null : () => _applyForDevice(device),
        ),
        IconButton(
          tooltip: l10n.forgetDevice,
          icon: const Icon(Icons.link_off_rounded),
          onPressed: link == null
              ? null
              : () => _assignProfile(device.deviceKey, device.deviceLabel, null),
        ),
      ],
    );
  }
}