// test/data/audio/bit_perfect_volume_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/collaborators/playback_volume_controller.dart';

PlaybackVolumeController _controller() => PlaybackVolumeController(
      getActivePlayer: () => throw UnimplementedError('no player in unit test'),
      getInactivePlayer: () =>
          throw UnimplementedError('no player in unit test'),
    );

void main() {
  group('bit-perfect software volume', () {
    test('keeps the user volume when no DAC hardware volume is active', () {
      final controller = _controller()
        ..updateSettings(
          userVolume: 0.4,
          bitPerfectBypass: true,
          hardwareVolumeActive: false,
        );

      expect(controller.calculateTargetVolume(null), closeTo(0.4, 0.001));
    });

    test('locks software volume at unity when the DAC owns attenuation', () {
      final controller = _controller()
        ..updateSettings(
          userVolume: 0.4,
          bitPerfectBypass: true,
          hardwareVolumeActive: true,
        );

      expect(controller.calculateTargetVolume(null), 1.0);
    });

    test('hardware volume only affects the bit-perfect path', () {
      final controller = _controller()
        ..updateSettings(
          userVolume: 0.4,
          bitPerfectBypass: false,
          hardwareVolumeActive: true,
        );

      expect(controller.calculateTargetVolume(null), closeTo(0.4, 0.001));
    });

    test('DoP still wins with unity gain', () {
      final controller = _controller()
        ..updateSettings(
          userVolume: 0.4,
          bitPerfectBypass: true,
          hardwareVolumeActive: false,
          isDopActive: true,
        );

      expect(controller.calculateTargetVolume(null), 1.0);
    });

    test('turning hardware volume off restores the user volume', () {
      final controller = _controller()
        ..updateSettings(
          userVolume: 0.4,
          bitPerfectBypass: true,
          hardwareVolumeActive: true,
        );
      expect(controller.calculateTargetVolume(null), 1.0);

      controller.updateSettings(hardwareVolumeActive: false);
      expect(controller.calculateTargetVolume(null), closeTo(0.4, 0.001));
    });
  });
}
