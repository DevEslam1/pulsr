// test/data/audio/playback_volume_mixer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/playback_volume_mixer.dart';
import '../../support/fake_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackVolumeMixer Unit Tests (Phase 2)', () {
    late FakeAudioPlayer playerA;
    late FakeAudioPlayer playerB;
    late PlaybackVolumeMixer mixer;

    setUp(() {
      playerA = FakeAudioPlayer(playing: true, volume: 1.0);
      playerB = FakeAudioPlayer(playing: false, volume: 0.0);
      mixer = PlaybackVolumeMixer(
        getActivePlayer: () => playerA,
        getInactivePlayer: () => playerB,
      );
    });

    tearDown(() async {
      await playerA.dispose();
      await playerB.dispose();
    });

    test('1. Normal user volume and factor composition', () async {
      mixer.setUserVolume(0.8);
      mixer.setActiveTargetFactor(1.0);
      await mixer.apply();

      expect(mixer.calculatedActiveVolume, closeTo(0.8, 0.001));
      expect(playerA.volume, closeTo(0.8, 0.001));
      expect(mixer.calculatedInactiveVolume, 0.0);
    });

    test('2. Ducking factor reduces volume without pre-duck snapshot state',
        () async {
      mixer.setUserVolume(1.0);
      mixer.setDuckFactor(0.3);
      await mixer.apply();

      expect(playerA.volume, closeTo(0.3, 0.001));

      // Duck ends -> clears factor
      mixer.clearDuck();
      await mixer.apply();
      expect(playerA.volume, closeTo(1.0, 0.001));
    });

    test(
        '3. Crossfade gains apply proportionally to active and inactive players',
        () async {
      mixer.setUserVolume(1.0);
      mixer.setCrossfadeGains(
        outgoingGain: 0.6,
        incomingGain: 0.4,
        isCrossfading: true,
      );
      await mixer.apply();

      expect(playerA.volume, closeTo(0.6, 0.001));
      expect(playerB.volume, closeTo(0.4, 0.001));

      // Duck during crossfade
      mixer.setDuckFactor(0.5);
      await mixer.apply();
      expect(playerA.volume, closeTo(0.3, 0.001));
      expect(playerB.volume, closeTo(0.2, 0.001));
    });

    test('4. Sleep fade factor composes with ducking and user volume',
        () async {
      mixer.setUserVolume(0.8);
      mixer.setDuckFactor(0.5); // 0.4
      mixer.setSleepFadeFactor(0.5); // 0.2
      await mixer.apply();

      expect(playerA.volume, closeTo(0.2, 0.001));

      // Clear duck while sleep fade is still active
      mixer.clearDuck();
      await mixer.apply();
      expect(playerA.volume, closeTo(0.4, 0.001));
    });

    test('5. DVC mode forces effective user volume to 1.0 (handled natively)',
        () async {
      mixer.setUserVolume(0.5);
      mixer.setDvcEnabled(true);
      mixer.setDuckFactor(0.5);
      await mixer.apply();

      // In DVC, effective user volume is 1.0, duck is 0.5 -> 0.5
      expect(playerA.volume, closeTo(0.5, 0.001));
    });
  });
}
