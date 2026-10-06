// test/support/fake_audio_session.dart
import 'dart:async';
import 'package:audio_session/audio_session.dart';

class FakeAudioSession {
  final StreamController<AudioInterruptionEvent> _interruptionController =
      StreamController<AudioInterruptionEvent>.broadcast();
  final StreamController<void> _becomingNoisyController =
      StreamController<void>.broadcast();
  final StreamController<List<AudioDevice>> _devicesController =
      StreamController<List<AudioDevice>>.broadcast();

  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      _interruptionController.stream;
  Stream<void> get becomingNoisyEventStream => _becomingNoisyController.stream;
  Stream<List<AudioDevice>> get devicesStream => _devicesController.stream;

  void emitInterruption({required bool begin, required AudioInterruptionType type}) {
    _interruptionController.add(AudioInterruptionEvent(begin, type));
  }

  void emitBecomingNoisy() {
    _becomingNoisyController.add(null);
  }

  void emitDevices(List<AudioDevice> devices) {
    _devicesController.add(devices);
  }

  Future<void> dispose() async {
    await _interruptionController.close();
    await _becomingNoisyController.close();
    await _devicesController.close();
  }
}
