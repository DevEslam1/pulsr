// lib/core/constants/channels.dart

/// Centralized platform channel names used across Flutter and native Android plugins.
abstract final class PulsrChannels {
  static const audioEffects = 'com.pulsr.music/audio_effects';
  static const tagEditor = 'com.pulsr.music/tag_editor';
  static const visualizer = 'com.pulsr.music/visualizer';
  static const visualizerStream = 'com.pulsr.music/visualizer_stream';
  static const ringtone = 'com.pulsr.music/ringtone';
  static const scrobbler = 'com.pulsr.music/scrobbler';
  static const ytm = 'com.pulsr.music/ytm';
  static const ytDownload = 'com.pulsr.music/yt_download';
  static const waveform = 'com.pulsr.music/waveform';
  static const proxy = 'com.pulsr.music/proxy';
  static const hiresDac = 'com.pulsr.music/hires_dac';
  static const hiresDacEvents = 'com.pulsr.music/hires_dac_events';
  static const fileOpener = 'com.pulsr.music/file_opener';
  static const lyrics = 'com.pulsr.music/lyrics';
  static const battery = 'com.pulsr.music/battery_optimization';
  static const roomCorrection = 'com.pulsr.music/room_correction';
  static const roomCorrectionPcm = 'com.pulsr.music/room_correction_pcm';
}

typedef Channels = PulsrChannels;
