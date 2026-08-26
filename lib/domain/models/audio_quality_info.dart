// lib/domain/models/audio_quality_info.dart
import 'package:flutter/material.dart';
import '../../data/db/app_database.dart';
import '../../features/settings/cubit/settings_state.dart';

enum AudioQualityTier {
  hiResLossless,
  lossless,
  highQuality,
  standardQuality,
  compact,
}

class AudioQualityInfo {
  final String format;
  final String codecName;
  final int? bitrateKbps;
  final String sampleRate;
  final String bitDepth;
  final String channels;
  final AudioQualityTier tier;
  final String tierLabel;
  final String shortBadgeLabel;
  final String description;
  final Color badgeColor;
  final IconData icon;

  const AudioQualityInfo({
    required this.format,
    required this.codecName,
    required this.bitrateKbps,
    required this.sampleRate,
    required this.bitDepth,
    required this.channels,
    required this.tier,
    required this.tierLabel,
    required this.shortBadgeLabel,
    required this.description,
    required this.badgeColor,
    required this.icon,
  });

  /// The audio rendering pipeline configuration based on source format and bit-depth.
  String get renderEngineDescription {
    if (tier == AudioQualityTier.hiResLossless || tier == AudioQualityTier.lossless) {
      return 'ExoPlayer Media3 • 32-bit Float PCM';
    } else if (format == 'AAC' || codecName.contains('AAC')) {
      return 'ExoPlayer Media3 • Hardware Offload (AAC / DSP)';
    } else if (format == 'MP3' || format == 'OPUS' || format == 'OGG') {
      return 'ExoPlayer Media3 • Hardware Offload ($format / DSP)';
    } else {
      return 'ExoPlayer Media3 • Direct AudioSink';
    }
  }

  factory AudioQualityInfo.fromSong(
    SongsTableData? song, {
    int? explicitSampleRate,
    int? explicitBitDepth,
    int? explicitBitrateKbps,
    String? explicitFormat,
    YtmAudioQuality? streamingQuality,
  }) {
    if (song == null) {
      return const AudioQualityInfo(
        format: 'AUDIO',
        codecName: 'Standard Audio',
        bitrateKbps: null,
        sampleRate: '44.1 kHz',
        bitDepth: '16-bit',
        channels: 'Stereo',
        tier: AudioQualityTier.standardQuality,
        tierLabel: 'Standard Audio',
        shortBadgeLabel: 'STANDARD',
        description: 'Standard stereo audio playback',
        badgeColor: Color(0xFF64748B),
        icon: Icons.graphic_eq_rounded,
      );
    }

    final path = song.path.toLowerCase();

    // YouTube Music online streaming track
    if (song.source == SongSource.youtube || song.source == 'youtube' || path.startsWith('ytmusic://')) {
      final defaultKbps = streamingQuality == YtmAudioQuality.low
          ? 64
          : streamingQuality == YtmAudioQuality.medium
              ? 128
              : 256;
      final kbps = explicitBitrateKbps ?? defaultKbps;
      final tier = kbps >= 160
          ? AudioQualityTier.highQuality
          : kbps >= 128
              ? AudioQualityTier.standardQuality
              : AudioQualityTier.compact;
      return AudioQualityInfo(
        format: 'AAC',
        codecName: 'YouTube Music Stream (AAC / Opus)',
        bitrateKbps: kbps,
        sampleRate: '48.0 kHz',
        bitDepth: '16-bit',
        channels: 'Stereo (2.0)',
        tier: tier,
        tierLabel: kbps >= 160
            ? 'High Quality Stream'
            : kbps >= 128
                ? 'Medium Quality Stream'
                : 'Data Saver Stream',
        shortBadgeLabel: 'AAC • ${kbps}k',
        description: 'Online YouTube Music audio stream ($kbps kbps)',
        badgeColor: const Color(0xFFE11D48),
        icon: Icons.wifi_tethering_rounded,
      );
    }

    String ext = '';
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < path.length - 1) {
      ext = path.substring(dotIndex + 1);
    }

    // Prefer real, cached header values (read from the file via the tag
    // channel) over anything inferred from the filename. Explicit args (a live
    // read) win over both.
    final int? realSampleRate = explicitSampleRate ?? song.sampleRate;
    final int? realBitDepth = explicitBitDepth ?? song.bitDepth;
    final String? realCodec = (explicitFormat ?? song.codec)?.toLowerCase();
    final bool hasRealHeader =
        song.codec != null || song.sampleRate != null || song.bitDepth != null;

    // Calculate bitrate if fileSize and durationMs are available
    int? calculatedBitrate = explicitBitrateKbps ?? song.bitrateKbps;
    if (calculatedBitrate == null && song.fileSize != null && song.fileSize! > 0 && song.durationMs > 0) {
      final seconds = song.durationMs / 1000.0;
      final bits = song.fileSize! * 8.0;
      calculatedBitrate = (bits / seconds / 1000.0).round();
    }

    // When a real codec string is known, gate format on it so a mislabeled
    // extension (e.g. a 128k MP3 renamed to .flac) cannot fake a higher tier.
    bool codecIs(String needle) => realCodec != null && realCodec.contains(needle);
    final bool isFlac = realCodec != null ? codecIs('flac') : ext == 'flac';
    final bool isWav = realCodec != null
        ? (codecIs('wav') || codecIs('riff') || codecIs('pcm'))
        : ext == 'wav';
    final bool isAlac = realCodec != null
        ? (codecIs('alac') || codecIs('apple lossless'))
        : (ext == 'alac' || (ext == 'm4a' && (calculatedBitrate ?? 0) > 600));
    final bool isAiff =
        realCodec != null ? codecIs('aiff') : (ext == 'aiff' || ext == 'aif');
    final bool isDsd = realCodec != null
        ? (codecIs('dsd') || codecIs('dsf') || codecIs('dff'))
        : (ext == 'dsf' || ext == 'dff');
    final bool isLosslessFormat = isFlac || isWav || isAlac || isAiff || isDsd;

    final bool hasRealHiRes = (realBitDepth != null && realBitDepth >= 24) ||
        (realSampleRate != null && realSampleRate > 48000);

    final bool isHiRes = isLosslessFormat &&
        (hasRealHiRes ||
            // Filename heuristics are a last resort, used only when no real
            // header is available to trust.
            (!hasRealHeader &&
                ((calculatedBitrate != null && calculatedBitrate >= 1411) ||
                    path.contains('24bit') ||
                    path.contains('hi-res') ||
                    path.contains('hires') ||
                    path.contains('master') ||
                    RegExp(r'[\s_\-\.\/]96k(?:hz)?[\s_\-\.\/]', caseSensitive: false).hasMatch(path) ||
                    RegExp(r'[\s_\-\.\/]192k(?:hz)?[\s_\-\.\/]', caseSensitive: false).hasMatch(path))));

    final AudioQualityTier tier;
    final String tierLabel;
    final String shortBadgeLabel;
    final String description;
    final Color badgeColor;
    final IconData icon;
    final String formatLabel;
    final String codecName;
    final String sampleRate;
    final String bitDepth;

    final String resolvedSampleRate = realSampleRate != null
        ? '${(realSampleRate / 1000).toStringAsFixed(1)} kHz'
        : (isHiRes ? '96.0 kHz / 192.0 kHz' : '44.1 kHz');

    final String resolvedBitDepth = realBitDepth != null
        ? '$realBitDepth-bit'
        : (isHiRes ? '24-bit' : '16-bit');

    if (isDsd) {
      formatLabel = 'DSD';
      codecName = 'Direct Stream Digital';
      tier = AudioQualityTier.hiResLossless;
      tierLabel = 'Ultra Hi-Res DSD';
      shortBadgeLabel = 'DSD • HI-RES';
      description = '1-bit High Density Studio Master audio stream';
      badgeColor = const Color(0xFFFFB800);
      icon = Icons.stars_rounded;
      sampleRate = explicitSampleRate != null ? resolvedSampleRate : '2.8 MHz / 5.6 MHz';
      bitDepth = '1-bit DSD';
    } else if (isHiRes) {
      formatLabel = isFlac ? 'FLAC' : (isWav ? 'WAV' : (explicitFormat ?? 'HI-RES'));
      codecName = isFlac
          ? 'Free Lossless Audio Codec (Hi-Res)'
          : (isWav ? 'Waveform Audio File (Hi-Res PCM)' : 'Lossless Audio');
      tier = AudioQualityTier.hiResLossless;
      tierLabel = 'Hi-Res Lossless';
      shortBadgeLabel = calculatedBitrate != null
          ? '$formatLabel • ${calculatedBitrate}k'
          : '$formatLabel • HI-RES';
      description = 'Studio Master 24-bit • Up to 192 kHz lossless bit-perfect stream';
      badgeColor = const Color(0xFFFFB800); // Gold Shimmer
      icon = Icons.workspace_premium_rounded;
      sampleRate = resolvedSampleRate;
      bitDepth = resolvedBitDepth;
    } else if (isLosslessFormat) {
      formatLabel = isFlac ? 'FLAC' : (isWav ? 'WAV' : (isAlac ? 'ALAC' : 'AIFF'));
      codecName = isFlac
          ? 'Free Lossless Audio Codec (Lossless)'
          : (isWav ? 'Pulse-Code Modulation (Uncompressed)' : 'Apple Lossless Audio');
      tier = AudioQualityTier.lossless;
      tierLabel = 'Lossless Audio';
      shortBadgeLabel = calculatedBitrate != null
          ? '$formatLabel • ${calculatedBitrate}k'
          : '$formatLabel • LOSSLESS';
      description = 'CD Quality 16-bit / 44.1 kHz • Exact bit-perfect reproduction';
      badgeColor = const Color(0xFF00F2FF); // Electric Cyan
      icon = Icons.diamond_rounded;
      sampleRate = resolvedSampleRate;
      bitDepth = resolvedBitDepth;
    } else if (ext == 'aac' || ext == 'm4a') {
      formatLabel = 'AAC';
      codecName = 'Advanced Audio Coding (AAC-LC)';
      tier = (calculatedBitrate ?? 256) >= 256
          ? AudioQualityTier.highQuality
          : AudioQualityTier.standardQuality;
      tierLabel = tier == AudioQualityTier.highQuality ? 'High Quality AAC' : 'Standard AAC';
      shortBadgeLabel = calculatedBitrate != null ? 'AAC • ${calculatedBitrate}k' : 'AAC HQ';
      description = 'High Efficiency perceptual audio compression';
      badgeColor = const Color(0xFF38BDF8);
      icon = Icons.high_quality_rounded;
      sampleRate = '44.1 kHz / 48.0 kHz';
      bitDepth = '16-bit equivalent';
    } else if (ext == 'ogg' || ext == 'opus') {
      formatLabel = ext.toUpperCase();
      codecName = ext == 'opus' ? 'Opus Interactive Audio' : 'Ogg Vorbis Audio';
      tier = (calculatedBitrate ?? 256) >= 192
          ? AudioQualityTier.highQuality
          : AudioQualityTier.standardQuality;
      tierLabel = '$formatLabel HQ Audio';
      shortBadgeLabel = calculatedBitrate != null ? '$formatLabel • ${calculatedBitrate}k' : formatLabel;
      description = 'Modern high-performance variable bitrate audio codec';
      badgeColor = const Color(0xFF818CF8);
      icon = Icons.graphic_eq_rounded;
      sampleRate = '48.0 kHz';
      bitDepth = '16-bit equivalent';
    } else {
      // Default to MP3 / general audio
      formatLabel = 'MP3';
      codecName = 'MPEG-1 Audio Layer III';
      final kbps = calculatedBitrate ?? 320;
      if (kbps >= 256) {
        tier = AudioQualityTier.highQuality;
        tierLabel = 'High Quality MP3';
        shortBadgeLabel = 'MP3 • ${kbps}k';
        description = 'Full-frequency 320 kbps MP3 playback';
        badgeColor = const Color(0xFF60A5FA);
        icon = Icons.high_quality_rounded;
      } else if (kbps >= 160) {
        tier = AudioQualityTier.standardQuality;
        tierLabel = 'Standard Quality MP3';
        shortBadgeLabel = 'MP3 • ${kbps}k';
        description = 'Standard compression audio stream';
        badgeColor = const Color(0xFF94A3B8);
        icon = Icons.graphic_eq_rounded;
      } else {
        tier = AudioQualityTier.compact;
        tierLabel = 'Compact MP3';
        shortBadgeLabel = 'MP3 • ${kbps}k';
        description = 'Compact size encoded audio';
        badgeColor = const Color(0xFF64748B);
        icon = Icons.audiotrack_rounded;
      }
      sampleRate = '44.1 kHz';
      bitDepth = '16-bit equivalent';
    }

    return AudioQualityInfo(
      format: formatLabel,
      codecName: codecName,
      bitrateKbps: calculatedBitrate,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      channels: 'Stereo (2.0)',
      tier: tier,
      tierLabel: tierLabel,
      shortBadgeLabel: shortBadgeLabel,
      description: description,
      badgeColor: badgeColor,
      icon: icon,
    );
  }
}
