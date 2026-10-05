// Tests for the extended DSP conflict guards: AAudio Direct and DSD-over-PCM
// must block sample processing with an explanation, like bit-perfect does.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_feature_info.dart';

void main() {
  test('AAudio Direct blocks DSP with an AAudio-specific reason', () {
    final reason = AudioConflicts.dspBlockedByBitPerfect(
      bitPerfectOutput: false,
      bypassDspOnBitPerfect: false,
      device: null,
      aaudioEnabled: true,
    );
    expect(reason, isNotNull);
    expect(reason, contains('AAudio Direct'));
  });

  test('a live DoP carrier blocks DSP with a DoP-specific reason', () {
    final reason = AudioConflicts.dspBlockedByBitPerfect(
      bitPerfectOutput: false,
      bypassDspOnBitPerfect: false,
      device: null,
      dsdDopActive: true,
    );
    expect(reason, isNotNull);
    expect(reason, contains('DoP'));
  });

  test('AAudio Direct blocks crossfade', () {
    final reason = AudioConflicts.crossfadeBlockedByBitPerfect(
      bitPerfectOutput: false,
      bypassDspOnBitPerfect: false,
      device: null,
      aaudioEnabled: true,
    );
    expect(reason, isNotNull);
    expect(reason, contains('AAudio Direct'));
  });

  test('nothing active reports no conflict', () {
    expect(
      AudioConflicts.dspBlockedByBitPerfect(
        bitPerfectOutput: false,
        bypassDspOnBitPerfect: false,
        device: null,
      ),
      isNull,
    );
    expect(
      AudioConflicts.crossfadeBlockedByBitPerfect(
        bitPerfectOutput: false,
        bypassDspOnBitPerfect: false,
        device: null,
      ),
      isNull,
    );
  });
}
