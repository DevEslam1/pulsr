import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

void main() {
  test('aaudioTargetBufferMs defaults to 120 ms to prevent exclusive XRuns', () {
    const state = SettingsState();
    expect(state.aaudioTargetBufferMs, 120);
  });

  test('shouldForwardSystemVolumeToOutput forwards only when OS mixer is bypassed', () {
    // Normal shared AudioTrack: OS STREAM_MUSIC already scales hardware output.
    expect(
      PulsrAudioHandler.shouldForwardSystemVolumeToOutput(
        bitPerfectBypass: false,
        aaudioOutputEnabled: false,
        directUsbStreaming: false,
      ),
      isFalse,
    );

    // Bit-perfect bypass (Android 14+ direct mixer / exclusive route).
    expect(
      PulsrAudioHandler.shouldForwardSystemVolumeToOutput(
        bitPerfectBypass: true,
        aaudioOutputEnabled: false,
        directUsbStreaming: false,
      ),
      isTrue,
    );

    // AAudio Exclusive output.
    expect(
      PulsrAudioHandler.shouldForwardSystemVolumeToOutput(
        bitPerfectBypass: false,
        aaudioOutputEnabled: true,
        directUsbStreaming: false,
      ),
      isTrue,
    );

    // Direct USB exclusive transfer.
    expect(
      PulsrAudioHandler.shouldForwardSystemVolumeToOutput(
        bitPerfectBypass: false,
        aaudioOutputEnabled: false,
        directUsbStreaming: true,
      ),
      isTrue,
    );
  });
}
