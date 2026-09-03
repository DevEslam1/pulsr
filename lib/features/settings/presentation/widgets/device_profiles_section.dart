// lib/features/settings/presentation/widgets/device_profiles_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';

import '../../../../domain/services/device_profile_service.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../domain/services/hires_audio_service.dart';
import '../../../../domain/services/settings_profiles_service.dart';
import '../../../player/cubit/player_cubit.dart';

import '../../../../core/utils/error_logger.dart';
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
      } catch (e, st) {
        ErrorLogger.log('_reload failed', error: e, stackTrace: st, category: 'DeviceProfilesSection');
      }
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _devices = devices;
        _links = links;
        _autoEnabled = autoEnabled;
        _currentDeviceKey = currentKey;
        _loading = false;
      });
    } catch (e, st) {
      ErrorLogger.log('_reload failed, using fallback', error: e, stackTrace: st, category: 'DeviceProfilesSection');
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
    final profile = _profiles.where((p) => p.id == link.profileId).firstOrNull;
    if (profile == null) return;
    final l10n = context.l10n;
    await context.read<PlayerCubit>().applyProfile(profile, manual: true);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('${l10n.applyProfileNow}: ${profile.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
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
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.noDevicesSeen,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final device in _devices)
            _deviceRow(context, device, l10n),
      ],
    );
  }

  Widget _deviceRow(
      BuildContext context, DeviceProfileEntry device, AppLocalizations l10n) {
    final link = _links[device.deviceKey];
    final isCurrent = device.deviceKey == _currentDeviceKey;
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
                    padding: const EdgeInsets.only(left: 6),
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
                value: link?.profileId,
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