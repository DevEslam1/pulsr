// lib/features/settings/presentation/widgets/headset_controls_section.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../data/audio/headset_control_config.dart';
import 'settings_section.dart';
import 'settings_slider_row.dart';
import 'settings_tiles.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';

/// Headset / earbuds + background-service controls.
///
/// Self-contained (SharedPreferences directly) so no SettingsState/freezed
/// regeneration is needed. Bridges to PulsrAudioHandler only through prefs:
/// the handler re-reads them on every click/route event, and
/// `keepNotificationOnPause` takes effect on the next cold start
/// (AudioServiceConfig is init-time only).
class HeadsetControlsSection extends StatefulWidget {
  const HeadsetControlsSection({super.key});

  @override
  State<HeadsetControlsSection> createState() => _HeadsetControlsSectionState();
}

class _HeadsetControlsSectionState extends State<HeadsetControlsSection> {
  bool _autoResume = false;
  int _autoResumeTimeout = 90;
  bool _keepNotification = false;
  HeadsetControlConfig _config = HeadsetControlConfig.defaults;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cfg = await HeadsetControlConfig.load(prefs);
      if (!mounted) return;
      setState(() {
        _config = cfg;
        _autoResume = prefs.getBool(PrefsKeys.autoResumeOnReconnect) ?? false;
        _autoResumeTimeout = prefs.getInt(PrefsKeys.autoResumeTimeoutSec) ?? 90;
        _keepNotification =
            prefs.getBool(PrefsKeys.keepNotificationOnPause) ?? true;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _setAutoResume(bool v) async {
    setState(() => _autoResume = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.autoResumeOnReconnect, v);
    } catch (_) {}
  }

  Future<void> _setKeepNotification(bool v) async {
    setState(() => _keepNotification = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.keepNotificationOnPause, v);
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Takes effect after an app restart.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _setAction(
      String key, HeadsetClickAction Function(HeadsetControlConfig) get,
      HeadsetClickAction v) async {
    final next = HeadsetControlConfig(
      singleClick: key == PrefsKeys.headsetSingleClick ? v : _config.singleClick,
      doubleClick: key == PrefsKeys.headsetDoubleClick ? v : _config.doubleClick,
      tripleClick: key == PrefsKeys.headsetTripleClick ? v : _config.tripleClick,
      clickWindowMs: _config.clickWindowMs,
      seekSeconds: _config.seekSeconds,
    );
    setState(() => _config = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, v.wireValue);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!_loaded) return const SizedBox.shrink();
    return SettingsSection(
      icon: Icons.headset_rounded,
      title: 'Headset & background',
      children: [
        SettingsSwitchTile(
          Icons.replay_rounded,
          'Auto-resume on reconnect',
          _autoResume
              ? 'Resume within $_autoResumeTimeout s when the headset reconnects.'
              : 'Stay paused when headphones unplug.',
          value: _autoResume,
          onChanged: _setAutoResume,
        ),
        if (_autoResume)
          SettingSliderRow(
            label: 'Resume window',
            value: _autoResumeTimeout.toDouble(),
            min: 15,
            max: 300,
            divisions: 19,
            defaultValue: 90,
            formatValue: (v) => '${v.round()} s',
            onChanged: (v) async {
              setState(() => _autoResumeTimeout = v.round());
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt(
                    PrefsKeys.autoResumeTimeoutSec, v.round());
              } catch (_) {}
            },
          ),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.notifications_paused_rounded,
          'Keep notification when paused',
          _keepNotification
              ? 'Controls stay in the shade after pause (restart required).'
              : 'Notification is removed on pause to save battery.',
          value: _keepNotification,
          onChanged: _setKeepNotification,
        ),
        settingsCardDivider(p),
        _ClickActionTile(
          icon: Icons.touch_app_rounded,
          title: 'Single press',
          value: _config.singleClick,
          onChanged: (v) =>
              _setAction(PrefsKeys.headsetSingleClick, (c) => c.singleClick, v),
        ),
        settingsCardDivider(p),
        _ClickActionTile(
          icon: Icons.touch_app_rounded,
          title: 'Double press',
          value: _config.doubleClick,
          onChanged: (v) =>
              _setAction(PrefsKeys.headsetDoubleClick, (c) => c.doubleClick, v),
        ),
        settingsCardDivider(p),
        _ClickActionTile(
          icon: Icons.touch_app_rounded,
          title: 'Triple press',
          value: _config.tripleClick,
          onChanged: (v) =>
              _setAction(PrefsKeys.headsetTripleClick, (c) => c.tripleClick, v),
        ),
        settingsCardDivider(p),
        SettingSliderRow(
          label: 'Multi-press window',
          subtitle: 'How long presses are grouped into double/triple.',
          value: _config.clickWindowMs.toDouble(),
          min: 150,
          max: 800,
          divisions: 13,
          defaultValue: 350,
          formatValue: (v) => '${v.round()} ms',
          onChanged: (v) async {
            setState(() => _config = HeadsetControlConfig(
                  singleClick: _config.singleClick,
                  doubleClick: _config.doubleClick,
                  tripleClick: _config.tripleClick,
                  clickWindowMs: v.round(),
                  seekSeconds: _config.seekSeconds,
                ));
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt(
                  PrefsKeys.headsetClickWindowMs, v.round());
            } catch (_) {}
          },
        ),
        SettingSliderRow(
          label: 'Seek step',
          subtitle: 'Used when a press is mapped to seek forward/back.',
          value: _config.seekSeconds.toDouble(),
          min: 5,
          max: 60,
          divisions: 11,
          defaultValue: 10,
          formatValue: (v) => '${v.round()} s',
          onChanged: (v) async {
            setState(() => _config = HeadsetControlConfig(
                  singleClick: _config.singleClick,
                  doubleClick: _config.doubleClick,
                  tripleClick: _config.tripleClick,
                  clickWindowMs: _config.clickWindowMs,
                  seekSeconds: v.round(),
                ));
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt(PrefsKeys.headsetSeekSeconds, v.round());
            } catch (_) {}
          },
        ),
      ],
    );
  }
}

class _ClickActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final HeadsetClickAction value;
  final ValueChanged<HeadsetClickAction> onChanged;

  const _ClickActionTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  static const _labels = {
    HeadsetClickAction.playPause: 'Play / pause',
    HeadsetClickAction.next: 'Next track',
    HeadsetClickAction.previous: 'Previous track',
    HeadsetClickAction.stop: 'Stop',
    HeadsetClickAction.seekForward: 'Seek forward',
    HeadsetClickAction.seekBackward: 'Seek back',
    HeadsetClickAction.none: 'Do nothing',
  };

  void _showPicker(BuildContext context) {
    final p = context.palette;
    PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...HeadsetClickAction.values.map((action) {
                final isSelected = action == value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: isSelected
                        ? p.accent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      title: Text(
                        _labels[action] ?? action.wireValue,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? p.accent : p.textPrimary,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: p.accent)
                          : null,
                      onTap: () {
                        onChanged(action);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsNavTile(
      icon,
      title,
      _labels[value] ?? value.wireValue,
      onTap: () => _showPicker(context),
    );
  }
}
