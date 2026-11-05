// lib/data/audio/dac_voicing_service.dart
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/prefs_keys.dart';
import '../../core/utils/platform_capabilities.dart';
import 'audio_effects_channel.dart';

/// Reconstruction filter characters the native voicing stage offers.
///
/// The indices are the wire values the native stage expects (Sharp=0, Slow=1,
/// MinimumPhase=2), so they must stay in this order.
enum DacVoicingCharacter {
  /// Steep linear-phase windowed sinc: accurate, symmetric pre- and post-ring.
  sharp,

  /// Gentle roll-off, NOS-like: less pre-ring, more high-frequency attenuation.
  slow,

  /// Same magnitude as [sharp] with all ringing moved after the transient.
  minimumPhase,
}

/// Owns the opt-in DAC voicing preference and pushes it to the native stage.
///
/// The stage emulates what a premium DAC's selectable reconstruction filter and
/// even-order harmonic tail sound like: 4x-oversampled, so the harmonic images
/// land above base Nyquist and the same filter removes them. It adds latency
/// when enabled, which is why it is off by default and reported as a delaying
/// stage rather than folded into the zero-latency group.
///
/// Kept out of the per-stage EqualizerManager bookkeeping deliberately: it is an
/// output property (like dither), not part of the EQ chain that degrade/restore
/// and device profiles reorder.
class DacVoicingService {
  DacVoicingService._();

  static final DacVoicingService instance = DacVoicingService._();

  bool enabled = false;
  DacVoicingCharacter character = DacVoicingCharacter.sharp;
  double amount = 0.0;

  /// True once [load] has read the saved preference. A UI that opens before
  /// playback startup must not present shipped defaults for a saved choice, so
  /// it checks this and loads itself.
  bool loaded = false;

  /// Reads the saved preference and asserts it into the native stage. Called
  /// once at playback startup, like the other output-path preferences; without
  /// it a saved choice would sit in prefs until the user opens the sheet again.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(PrefsKeys.dacVoicingEnabled) ?? false;
      final index = prefs.getInt(PrefsKeys.dacVoicingCharacter) ?? 0;
      character = DacVoicingCharacter
          .values[index.clamp(0, DacVoicingCharacter.values.length - 1)];
      amount = (prefs.getDouble(PrefsKeys.dacVoicingAmount) ?? 0.0)
          .clamp(0.0, 1.0);
      loaded = true;
      await _push();
    } catch (_) {
      // A failed read leaves voicing off, which is the shipped default.
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    await _persistAndPush();
  }

  Future<void> setCharacter(DacVoicingCharacter value) async {
    character = value;
    await _persistAndPush();
  }

  /// Even-order voicing strength, 0..1. Zero changes only the filter character
  /// and adds no harmonics.
  Future<void> setAmount(double value) async {
    amount = value.clamp(0.0, 1.0);
    await _persistAndPush();
  }

  Future<void> _persistAndPush() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.dacVoicingEnabled, enabled);
      await prefs.setInt(PrefsKeys.dacVoicingCharacter, character.index);
      await prefs.setDouble(PrefsKeys.dacVoicingAmount, amount);
    } catch (_) {
      // Persistence failure must not leave the audible state and the write
      // order inconsistent, so the push still runs.
    }
    await _push();
  }

  /// Parameters first, then the enable edge: the stage reads its character when
  /// it is switched on, so a newly enabled stage can never render one block
  /// with the previously selected filter.
  Future<void> _push() async {
    if (!PlatformCapabilities.isAndroid) return;
    final effects = AudioEffectsChannel();
    await effects.setDacVoicingParams(
      character: character.index,
      voicingAmount: amount,
    );
    await effects.setDacVoicingEnabled(enabled);
  }
}
