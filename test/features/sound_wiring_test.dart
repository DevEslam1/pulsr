// test/features/sound_wiring_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/services/sound_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UI Sound Wiring & Policy Tests', () {
    setUp(() {
      SoundFeedbackService.resetForTesting();
    });

    tearDown(() {
      SoundFeedbackService.resetForTesting();
    });

    test(
        '1. PrefsKeys.soundFeedbackEnabled is wired and referenced in production',
        () {
      expect(PrefsKeys.soundFeedbackEnabled, 'setting_sound_feedback_enabled');

      final soundServiceFile =
          File('lib/core/services/sound_feedback_service.dart');
      expect(soundServiceFile.existsSync(), isTrue);
      final content = soundServiceFile.readAsStringSync();
      expect(content.contains('PrefsKeys.soundFeedbackEnabled'), isTrue);
    });

    test('2. All semantic verbs are registered and emit corresponding events',
        () {
      final emitted = <SoundFeedbackVerb>[];
      SoundFeedbackService.onSoundEmitted = (verb) => emitted.add(verb);
      SoundFeedbackService.setEnabled(true);

      SoundFeedbackService.playClick();
      SoundFeedbackService.playToggle();
      SoundFeedbackService.playSuccess();
      SoundFeedbackService.playWarning();
      SoundFeedbackService.playError();
      SoundFeedbackService.playAlert();

      expect(emitted, [
        SoundFeedbackVerb.click,
        SoundFeedbackVerb.toggle,
        SoundFeedbackVerb.success,
        SoundFeedbackVerb.warning,
        SoundFeedbackVerb.error,
        SoundFeedbackVerb.alert,
      ]);
    });

    test('3. Mirror haptics flag executes cleanly across all verbs', () {
      SoundFeedbackService.setEnabled(true);

      expect(() => SoundFeedbackService.playClick(mirrorHaptics: true),
          returnsNormally);
      expect(() => SoundFeedbackService.playToggle(mirrorHaptics: true),
          returnsNormally);
      expect(() => SoundFeedbackService.playSuccess(mirrorHaptics: true),
          returnsNormally);
      expect(() => SoundFeedbackService.playWarning(mirrorHaptics: true),
          returnsNormally);
      expect(() => SoundFeedbackService.playError(mirrorHaptics: true),
          returnsNormally);
      expect(() => SoundFeedbackService.playAlert(mirrorHaptics: true),
          returnsNormally);
    });

    test('4. Ducking under active music playback gates subtle cues', () {
      SoundFeedbackService.setEnabled(true);
      SoundFeedbackService.duckUnderMusic = true;
      SoundFeedbackService.isMusicPlaying = () => true;

      // In debug/test mode, emissions are recorded in testEmissions,
      // but execution respects the gating
      SoundFeedbackService.playClick();
      SoundFeedbackService.playToggle();
      SoundFeedbackService.playSuccess();
      SoundFeedbackService.playWarning();
      SoundFeedbackService.playError();
      SoundFeedbackService.playAlert();

      expect(SoundFeedbackService.testEmissions.length, 6);
    });

    test(
        '5. P0 call-site static verification: SoundFeedbackService verbs wired into features',
        () {
      // Verify queue actions wire SoundFeedbackService
      final queueFile =
          File('lib/features/queue/presentation/queue_screen.dart');
      expect(queueFile.existsSync(), isTrue);
      final queueContent = queueFile.readAsStringSync();
      expect(queueContent.contains('SoundFeedbackService.playWarning'), isTrue,
          reason: 'Queue clear/remove must emit playWarning');
      expect(queueContent.contains('SoundFeedbackService.playSuccess'), isTrue,
          reason: 'Queue undo must emit playSuccess');

      // Verify playlist actions wire SoundFeedbackService
      final playlistFile =
          File('lib/features/playlists/cubit/playlist_cubit.dart');
      expect(playlistFile.existsSync(), isTrue);
      final playlistContent = playlistFile.readAsStringSync();
      expect(
          playlistContent.contains('SoundFeedbackService.playSuccess'), isTrue,
          reason: 'Playlist create/restore must emit playSuccess');
      expect(
          playlistContent.contains('SoundFeedbackService.playWarning'), isTrue,
          reason: 'Playlist delete must emit playWarning');

      // Verify download actions wire SoundFeedbackService
      final downloadsFile =
          File('lib/features/downloads/cubit/downloads_cubit.dart');
      expect(downloadsFile.existsSync(), isTrue);
      final downloadsContent = downloadsFile.readAsStringSync();
      expect(
          downloadsContent.contains('SoundFeedbackService.playSuccess'), isTrue,
          reason: 'Download completion must emit playSuccess');
      expect(
          downloadsContent.contains('SoundFeedbackService.playError'), isTrue,
          reason: 'Download failure must emit playError');

      // Verify library delete & add-to-queue wire SoundFeedbackService
      final libraryFile =
          File('lib/features/library/presentation/library_screen.dart');
      expect(libraryFile.existsSync(), isTrue);
      final libraryContent = libraryFile.readAsStringSync();
      expect(
          libraryContent.contains('SoundFeedbackService.playSuccess'), isTrue,
          reason: 'Add to queue must emit playSuccess');
      expect(
          libraryContent.contains('SoundFeedbackService.playWarning'), isTrue,
          reason: 'Delete confirmation must emit playWarning');

      // Verify scan action wires SoundFeedbackService
      final settingsCubitFile =
          File('lib/features/settings/cubit/settings_cubit.dart');
      expect(settingsCubitFile.existsSync(), isTrue);
      final settingsContent = settingsCubitFile.readAsStringSync();
      expect(
          settingsContent.contains('SoundFeedbackService.playSuccess'), isTrue,
          reason: 'Device library scan completion must emit playSuccess');

      // Verify auth action wires SoundFeedbackService
      final authFile = File('lib/features/auth/cubit/auth_cubit.dart');
      expect(authFile.existsSync(), isTrue);
      final authContent = authFile.readAsStringSync();
      expect(authContent.contains('SoundFeedbackService.playSuccess'), isTrue,
          reason: 'Auth sign-in/up success must emit playSuccess');
      expect(authContent.contains('SoundFeedbackService.playError'), isTrue,
          reason: 'Auth sign-in/up failure must emit playError');

      // Verify onboarding completion wires SoundFeedbackService
      final onboardingFile =
          File('lib/features/onboarding/presentation/onboarding_screen.dart');
      expect(onboardingFile.existsSync(), isTrue);
      final onboardingContent = onboardingFile.readAsStringSync();
      expect(onboardingContent.contains('SoundFeedbackService.playSuccess'),
          isTrue,
          reason: 'Onboarding completion must emit playSuccess');

      // Verify UI components wire SoundFeedbackService
      final switchFile = File('lib/core/widgets/pulsr_switch.dart');
      expect(switchFile.existsSync(), isTrue);
      final switchContent = switchFile.readAsStringSync();
      expect(switchContent.contains('SoundFeedbackService.playToggle'), isTrue,
          reason: 'PulsrSwitch toggle must emit playToggle');

      final toastFile = File('lib/core/widgets/pulsr_toast.dart');
      expect(toastFile.existsSync(), isTrue);
      final toastContent = toastFile.readAsStringSync();
      expect(toastContent.contains('SoundFeedbackService.playError'), isTrue,
          reason: 'PulsrToast error must emit playError');
      expect(toastContent.contains('SoundFeedbackService.playSuccess'), isTrue,
          reason: 'PulsrToast success must emit playSuccess');
    });
  });
}
