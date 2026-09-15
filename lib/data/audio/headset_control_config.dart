// lib/data/audio/headset_control_config.dart
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/prefs_keys.dart';

/// Action bound to a headset/earbud click count.
enum HeadsetClickAction {
  playPause('playPause'),
  next('next'),
  previous('previous'),
  stop('stop'),
  seekForward('seekForward'),
  seekBackward('seekBackward'),
  none('none');

  const HeadsetClickAction(this.wireValue);
  final String wireValue;

  static HeadsetClickAction fromWire(String? wire) {
    for (final a in HeadsetClickAction.values) {
      if (a.wireValue == wire) return a;
    }
    return HeadsetClickAction.none;
  }
}

/// Persisted headset click mapping + timing. Read by [PulsrAudioHandler.click].
class HeadsetControlConfig {
  final HeadsetClickAction singleClick;
  final HeadsetClickAction doubleClick;
  final HeadsetClickAction tripleClick;
  final int clickWindowMs;
  final int seekSeconds;

  const HeadsetControlConfig({
    this.singleClick = HeadsetClickAction.playPause,
    this.doubleClick = HeadsetClickAction.next,
    this.tripleClick = HeadsetClickAction.previous,
    this.clickWindowMs = 350,
    this.seekSeconds = 10,
  });

  static const HeadsetControlConfig defaults = HeadsetControlConfig();

  HeadsetClickAction actionForCount(int count) {
    if (count <= 1) return singleClick;
    if (count == 2) return doubleClick;
    return tripleClick;
  }

  static Future<HeadsetControlConfig> load([SharedPreferences? prefs]) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      HeadsetClickAction parse(String key, HeadsetClickAction fallback) {
        final raw = p.getString(key);
        if (raw == null) return fallback;
        // Unknown values fall back instead of disabling the button.
        final parsed = HeadsetClickAction.fromWire(raw);
        if (parsed == HeadsetClickAction.none && raw != 'none') {
          return fallback;
        }
        return parsed;
      }

      final window = p.getInt(PrefsKeys.headsetClickWindowMs) ?? 350;
      final seek = p.getInt(PrefsKeys.headsetSeekSeconds) ?? 10;
      return HeadsetControlConfig(
        singleClick:
            parse(PrefsKeys.headsetSingleClick, HeadsetClickAction.playPause),
        doubleClick:
            parse(PrefsKeys.headsetDoubleClick, HeadsetClickAction.next),
        tripleClick:
            parse(PrefsKeys.headsetTripleClick, HeadsetClickAction.previous),
        clickWindowMs: window.clamp(150, 800),
        seekSeconds: seek.clamp(5, 60),
      );
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(PrefsKeys.headsetSingleClick, singleClick.wireValue);
    await p.setString(PrefsKeys.headsetDoubleClick, doubleClick.wireValue);
    await p.setString(PrefsKeys.headsetTripleClick, tripleClick.wireValue);
    await p.setInt(PrefsKeys.headsetClickWindowMs, clickWindowMs);
    await p.setInt(PrefsKeys.headsetSeekSeconds, seekSeconds);
  }
}
