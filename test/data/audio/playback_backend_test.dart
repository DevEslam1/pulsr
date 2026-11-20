// test/data/audio/playback_backend_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/data/audio/playback_backend.dart';
import 'package:pulsr/data/audio/local_pcm_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackendCapabilities Matrix (Section 5.1)', () {
    test('localPcm matches specification', () {
      const caps = BackendCapabilities.localPcm;
      expect(caps.canSeek, isTrue);
      expect(caps.canGapless, isTrue);
      expect(caps.canCrossfade, isTrue);
      expect(caps.canRateSwitch, isTrue);
      expect(caps.canSoftwareVolume, isTrue);
      expect(caps.canLocalDsp, isTrue);
      expect(caps.canReplayGain, isTrue);
      expect(caps.canSleepFade, isTrue);
      expect(caps.isRemote, isFalse);
    });

    test('localDsd matches specification', () {
      const caps = BackendCapabilities.localDsd;
      expect(caps.canSeek, isTrue);
      expect(caps.canGapless, isTrue);
      expect(caps.canCrossfade, isFalse);
      expect(caps.canRateSwitch, isTrue);
      expect(caps.canSoftwareVolume, isFalse);
      expect(caps.canLocalDsp, isFalse);
      expect(caps.canReplayGain, isFalse);
      expect(caps.canSleepFade, isFalse);
      expect(caps.isRemote, isFalse);
    });

    test('cast matches specification', () {
      const caps = BackendCapabilities.cast;
      expect(caps.canSeek, isTrue);
      expect(caps.canGapless, isFalse);
      expect(caps.canCrossfade, isFalse);
      expect(caps.canRateSwitch, isFalse);
      expect(caps.canSoftwareVolume, isFalse);
      expect(caps.canLocalDsp, isFalse);
      expect(caps.canReplayGain, isFalse);
      expect(caps.canSleepFade, isFalse);
      expect(caps.isRemote, isTrue);
    });

    test('upnp matches specification', () {
      const caps = BackendCapabilities.upnp;
      expect(caps.canSeek, isTrue);
      expect(caps.canGapless, isFalse);
      expect(caps.canCrossfade, isFalse);
      expect(caps.canRateSwitch, isFalse);
      expect(caps.canSoftwareVolume, isFalse);
      expect(caps.canLocalDsp, isFalse);
      expect(caps.canReplayGain, isFalse);
      expect(caps.canSleepFade, isFalse);
      expect(caps.isRemote, isTrue);
    });
  });

  group('LocalPcmBackend', () {
    test('exposes localPcm capabilities and wraps players', () {
      final pA = AudioPlayer();
      final pB = AudioPlayer();
      final backend = LocalPcmBackend(playerA: pA, playerB: pB);

      expect(backend.capabilities, equals(BackendCapabilities.localPcm));
      expect(backend.isPlayerAActive, isTrue);
      expect(backend.activePlayer, equals(pA));
      expect(backend.inactivePlayer, equals(pB));

      backend.switchActivePlayer();
      expect(backend.isPlayerAActive, isFalse);
      expect(backend.activePlayer, equals(pB));
      expect(backend.inactivePlayer, equals(pA));

      backend.dispose();
      pA.dispose();
      pB.dispose();
    });
  });
}
