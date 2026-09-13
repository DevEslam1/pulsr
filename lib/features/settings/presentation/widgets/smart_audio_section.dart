// lib/features/settings/presentation/widgets/smart_audio_section.dart
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/hires_audio_service.dart';
import '../../../../core/services/smart_audio_service.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../domain/services/smart_audio_plan.dart';
import '../../../../data/audio/headphone_profiles_repository.dart';
import '../../../../domain/services/device_profile_service.dart';

/// Settings surface for the Smart Audio coordinator.
///
/// Auto: automatically match the connected headphones to an AutoEQ correction
/// and negotiate the best output quality the device supports.
/// Manual: leave the user's EQ/effects/output choices untouched.
class SmartAudioSection extends StatefulWidget {
  const SmartAudioSection({super.key});

  @override
  State<SmartAudioSection> createState() => _SmartAudioSectionState();
}

class _SmartAudioSectionState extends State<SmartAudioSection> {
  SmartAudioService get _service => getIt.isRegistered<SmartAudioService>()
      ? getIt<SmartAudioService>()
      : SmartAudioService();

  SmartAudioMode _mode = SmartAudioMode.auto;
  bool _loading = true;
  String? _deviceName;
  String? _matchedProfileName;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final mode = await _service.getMode();
      String? deviceName;
      String? matchedName;
      try {
        final info =
            getIt.isRegistered<HiResAudioService>()
                ? getIt<HiResAudioService>().currentOutputInfo
                : null;
        if (info != null) {
          deviceName = info.deviceName;
          final key = DeviceProfileService.deviceKeyFromInfo(info);
          final link = await _service.linkForDeviceKey(key);
          if (link != null) {
            final repo = HeadphoneProfilesRepository();
            await repo.loadProfiles();
            matchedName = repo.getProfileById(link.profileId)?.name;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _deviceName = deviceName;
        _matchedProfileName = matchedName;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setMode(SmartAudioMode mode) async {
    await _service.setMode(mode);
    if (!mounted) return;
    setState(() => _mode = mode);
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
    final isAuto = _mode == SmartAudioMode.auto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.smartAudioSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        SegmentedButton<SmartAudioMode>(
          segments: [
            ButtonSegment<SmartAudioMode>(
              value: SmartAudioMode.auto,
              label: Text(l10n.smartAudioAuto),
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
            ButtonSegment<SmartAudioMode>(
              value: SmartAudioMode.manual,
              label: Text(l10n.smartAudioManual),
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) _setMode(selection.first);
          },
        ),
        const SizedBox(height: 8),
        Text(
          isAuto ? l10n.smartAudioAutoDesc : l10n.smartAudioManualDesc,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (isAuto && _deviceName != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.headphones_rounded, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.smartAudioDetectedDevice(_deviceName!),
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _matchedProfileName != null
                  ? l10n.smartAudioMatchedProfile(_matchedProfileName!)
                  : l10n.smartAudioNoMatch,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}
