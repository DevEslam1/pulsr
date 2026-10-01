import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
      'M-21: AudioVisualizer isTesting detection robust against runtimeType stringification',
      () {
    tearDown(() {
      AudioVisualizer.isTestingOverride = null;
    });

    test(
        'isTesting returns true in test environment via binding/platform detection',
        () {
      AudioVisualizer.isTestingOverride = null;
      expect(AudioVisualizer.isTesting, isTrue);
    });

    test(
        'isTestingOverride allows deterministic test overrides without fragile string checks',
        () {
      AudioVisualizer.isTestingOverride = false;
      expect(AudioVisualizer.isTesting, isFalse);

      AudioVisualizer.isTestingOverride = true;
      expect(AudioVisualizer.isTesting, isTrue);

      AudioVisualizer.isTestingOverride = null;
      expect(AudioVisualizer.isTesting, isTrue);
    });
  });
}
