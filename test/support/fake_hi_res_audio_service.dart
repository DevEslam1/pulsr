// test/support/fake_hi_res_audio_service.dart
import 'dart:async';
import 'package:pulsr/data/services/hires_audio_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';

class FakeHiResAudioService extends HiResAudioService {
  AudioOutputInfo? stubbedInfo;

  FakeHiResAudioService([this.stubbedInfo]) : super();

  @override
  AudioOutputInfo? get currentOutputInfo => stubbedInfo;

  @override
  Future<AudioOutputInfo> getAudioOutputInfo() async {
    return stubbedInfo ??
        const AudioOutputInfo(
          deviceName: 'Speaker',
          isUsbDac: false,
          sampleRate: 48000,
          bitDepth: 16,
          isBitPerfectActive: false,
        );
  }

  void updateOutputInfo(AudioOutputInfo info) {
    stubbedInfo = info;
  }
}
