import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/data/audio/collaborators/playback_volume_controller.dart';
import 'package:pulsr/data/audio/audio_memory_manager.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';

class _FakeAudioPlayer extends Fake implements AudioPlayer {
  double _vol = 1.0;
  @override
  double get volume => _vol;
  @override
  Future<void> setVolume(double volume) async {
    _vol = volume;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UX & Notification Controls Audit Remediation Tests', () {
    test('B-06: PlaybackVolumeController respects DVC mode without double-attenuating', () async {
      final fakePlayer = _FakeAudioPlayer();
      final controller = PlaybackVolumeController(
        getActivePlayer: () => fakePlayer,
        getInactivePlayer: () => fakePlayer,
      );
      expect(controller.dvcEnabled, isFalse);

      controller.updateSettings(userVolume: 0.8, duckFactor: 0.5);
      await controller.setDucked(true, null);

      // Normal mode with duck active: 0.8 * 0.5 = 0.4
      final normalVol = controller.calculateTargetVolume(null);
      expect(normalVol, closeTo(0.4, 0.001));

      // Enable DVC mode
      controller.setDvcEnabled(true);
      expect(controller.dvcEnabled, isTrue);

      // In DVC mode, hardware/native volume handles user volume, so player volume shouldn't multiply it:
      // effectiveUserVolume = 1.0 * duckFactor (0.5) = 0.5
      final dvcVol = controller.calculateTargetVolume(null);
      expect(dvcVol, closeTo(0.5, 0.001));
    });

    test('B-13: MediaScannerService.isSystemIgnoredPath uses segment matching', () {
      // Legitimate user folders that contain 'Recordings' as substring or part of title
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Music/My Recordings/track.mp3'), isFalse);
      expect(MediaScannerService.isSystemIgnoredPath('/sdcard/Music/Recordings Studio/song.flac'), isFalse);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Music/Alarms and Themes/chime.wav'), isFalse);

      // Actual system ignored folders
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Recordings/voice_memo.m4a'), isTrue);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Android/media/com.whatsapp/voice.opus'), isTrue);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/.cache/temp.mp3'), isTrue);
      expect(MediaScannerService.isSystemIgnoredPath('C:\\Users\\User\\Music\\.thumbnails\\cover.jpg'), isTrue);
    });

    test('B-17: AudioMemoryManager.computeAdaptiveBudget adapts to core count', () {
      final budget = AudioMemoryManager.computeAdaptiveBudget();
      expect(budget, greaterThanOrEqualTo(16 * 1024 * 1024));
      expect(budget, lessThanOrEqualTo(32 * 1024 * 1024));

      final cores = Platform.numberOfProcessors;
      if (cores <= 4) {
        expect(budget, 16 * 1024 * 1024);
      } else if (cores <= 6) {
        expect(budget, 24 * 1024 * 1024);
      } else {
        expect(budget, 32 * 1024 * 1024);
      }
    });

    test('B-28: CrossfadeManager.auditionCurveProgress emits smooth curve steps', () async {
      final manager = CrossfadeManager()..curve = CrossfadeCurve.equalPower;
      final stream = manager.auditionCurveProgress(
        duration: const Duration(milliseconds: 50),
        steps: 10,
      );

      final points = await stream.toList();
      expect(points.length, greaterThanOrEqualTo(5));
      expect(points.first.$1, closeTo(1.0, 0.05)); // oldGain
      expect(points.first.$2, closeTo(0.0, 0.05)); // newGain
      expect(points.last.$1, closeTo(0.0, 0.05));  // oldGain
      expect(points.last.$2, closeTo(1.0, 0.05));  // newGain
    });
  });
}
