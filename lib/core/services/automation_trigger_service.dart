// lib/core/services/automation_trigger_service.dart
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/models/audio_output_info.dart';
import '../../domain/services/device_profile_service.dart';
import '../../domain/services/hires_audio_service.dart';
import '../../domain/services/settings_profiles_service.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../di/injection.dart';
import '../utils/error_logger.dart';
import 'automation_rules_service.dart';

/// Runtime trigger source for [AutomationRulesService].
///
/// Reliability note: Bluetooth and wired-headphone connects are observed from
/// the existing hi-res output-device stream, so they need no new native code.
/// Charging ([AutomationTrigger.deviceCharging]) is **not** wired here because
/// the app has no reliable charging-state observer in Dart; it is reported as
/// unsupported by [supportsTrigger] so the UI can gate it instead of faking it.
class AutomationTriggerService with WidgetsBindingObserver {
  AutomationTriggerService({
    AutomationRulesService? rulesService,
    SettingsProfilesService? profilesService,
    HiResAudioService? hiResAudioService,
  })  : _rulesService =
            rulesService ?? _resolve(() => AutomationRulesService()),
        _profilesService =
            profilesService ?? _resolve(() => SettingsProfilesService()),
        _hiResAudioService =
            hiResAudioService ?? _resolve(() => HiResAudioService());

  final AutomationRulesService _rulesService;
  final SettingsProfilesService _profilesService;
  final HiResAudioService _hiResAudioService;

  StreamSubscription<AudioOutputInfo>? _outputSub;
  String? _lastDeviceKey;
  bool _initialized = false;
  bool _started = false;

  static T _resolve<T extends Object>(T Function() fallback) {
    try {
      if (getIt.isRegistered<T>()) return getIt<T>();
    } catch (_) {}
    return fallback();
  }

  /// Triggers that can be reliably detected from Dart today.
  static bool supportsTrigger(AutomationTrigger trigger) =>
      trigger != AutomationTrigger.deviceCharging;

  void start() {
    if (_started) return;
    _started = true;
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
    try {
      _outputSub = _hiResAudioService.outputDeviceStream.listen(
        _onOutputChanged,
        onError: (Object e, StackTrace st) {
          ErrorLogger.log('Automation output stream error',
              error: e, stackTrace: st, category: 'AutomationTriggerService');
        },
      );
      final current = _hiResAudioService.currentOutputInfo;
      if (current != null) _onOutputChanged(current);
    } catch (e, st) {
      ErrorLogger.log('Failed to observe output devices for automation',
          error: e, stackTrace: st, category: 'AutomationTriggerService');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final current = _hiResAudioService.currentOutputInfo;
    if (current != null) _onOutputChanged(current);
  }

  void _onOutputChanged(AudioOutputInfo info) {
    final key = DeviceProfileService.deviceKeyFromInfo(info);
    if (key == _lastDeviceKey) return;
    _lastDeviceKey = key;
    // The first observation is the already-active route at startup; only
    // transitions that happen while the app is running are "connects".
    if (!_initialized) {
      _initialized = true;
      return;
    }
    if (info.isBluetooth) {
      unawaited(_fire(AutomationTrigger.bluetoothConnected));
    } else if (_isWiredHeadphones(info)) {
      unawaited(_fire(AutomationTrigger.headphonesPlugged));
    }
  }

  static bool _isWiredHeadphones(AudioOutputInfo info) {
    if (info.isBluetooth) return false;
    final type = info.activeDeviceType.trim().toLowerCase();
    return type == 'wired' || type == 'hearing_aid';
  }

  Future<void> _fire(AutomationTrigger trigger) async {
    if (!supportsTrigger(trigger)) return;
    try {
      final rules = await _rulesService.getRules();
      final matching = rules
          .where((r) => r.enabled && r.trigger == trigger)
          .toList(growable: false);
      if (matching.isEmpty) return;
      if (!getIt.isRegistered<PlayerCubit>()) return;
      final player = getIt<PlayerCubit>();
      final profiles = await _profilesService.getProfiles();
      for (final rule in matching) {
        SettingsProfile? profile;
        for (final p in profiles) {
          if (p.id == rule.targetProfileId) {
            profile = p;
            break;
          }
        }
        if (profile == null) continue;
        await player.applyProfile(profile, manual: true);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply automation rule for ${trigger.name}',
          error: e, stackTrace: st, category: 'AutomationTriggerService');
    }
  }

  void dispose() {
    _outputSub?.cancel();
    _outputSub = null;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _started = false;
  }
}
