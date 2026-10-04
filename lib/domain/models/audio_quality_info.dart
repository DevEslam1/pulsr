// lib/domain/models/audio_quality_info.dart
import 'package:flutter/material.dart';
import '../../core/constants/audio_formats.dart';
import '../../data/audio/mqa_decoder_helper.dart';
import '../../data/db/app_database.dart';
import 'ytm_audio_quality.dart';
import 'package:pulsr/core/constants/app_colors.dart';

enum AudioQualityTier {
  hiResLossless,
  lossless,
  highQuality,
  standardQuality,
  compact,
}

class AudioQualityInfo {
  /// Whether the most recent DSD (DSF/DFF) track was routed through the DoP
  /// (DSD over PCM) encoder rather than decoded to PCM. Written by
  /// [DsdDecoderHelper] only after it has confirmed a compatible USB DAC, so
  /// the quality sheet reports the transport that is actually in use.
  static bool dsdDopActive = false;

  final String format;
  final String codecName;
  final int? bitrateKbps;
  final bool bitrateEstimated;
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
    this.bitrateEstimated = false,
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
    if (AudioFormats.requiresNativeDecoder(format)) {
      return 'Unavailable • native decoder not bundled in this build';
    }
    return 'ExoPlayer Media3 • output details shown below';
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
        sampleRate: 'Unknown',
        bitDepth: 'Unknown',
        channels: 'Not verified',
        tier: AudioQualityTier.standardQuality,
        tierLabel: 'Standard Audio',
        shortBadgeLabel: 'STANDARD',
        description: 'Standard stereo audio playback',
        badgeColor: AppColors.slate,
        icon: Icons.graphic_eq_rounded,
      );
    }

    final path = song.path.toLowerCase();

    // YouTube Music online streaming track (not yet downloaded)
    if ((song.source == SongSource.youtube || path.startsWith('ytmusic://')) &&
        song.isDownloaded != true) {
      const defaultKbps = 0;
      final kbps = explicitBitrateKbps ??
          (song.bitrateKbps != null && song.bitrateKbps! > 0
              ? song.bitrateKbps!
              : defaultKbps);
      final rawCodec = explicitFormat ?? song.codec;
      final format = rawCodec == null
          ? 'Unknown'
          : rawCodec.toUpperCase().contains('OPUS') ||
                  rawCodec.toUpperCase().contains('WEBM')
              ? 'OPUS'
              : rawCodec.toUpperCase();
      final tier = kbps >= 160
          ? AudioQualityTier.highQuality
          : kbps >= 128
              ? AudioQualityTier.standardQuality
              : AudioQualityTier.compact;
      return AudioQualityInfo(
        format: format,
        codecName: 'YouTube Music Stream ($format)',
        bitrateKbps: kbps > 0 ? kbps : null,
        sampleRate: song.sampleRate != null && song.sampleRate! > 0
            ? '${(song.sampleRate! / 1000).toStringAsFixed(1)} kHz'
            : 'Unknown',
        bitDepth: song.bitDepth != null && song.bitDepth! > 0
            ? '${song.bitDepth}-bit'
            : 'Unknown',
        channels: 'Not verified',
        tier: tier,
        tierLabel: kbps <= 0
            ? 'Stream quality unverified'
            : kbps >= 160
                ? 'High Quality Stream'
                : kbps >= 128
                    ? 'Medium Quality Stream'
                    : 'Data Saver Stream',
        shortBadgeLabel:
            kbps > 0 ? '$format • ${kbps}k' : '$format • rate unknown',
        description: kbps > 0
            ? 'Online YouTube Music audio stream ($kbps kbps $format)'
            : 'Online stream • actual bitrate is unverified',
        badgeColor: AppColors.qualityBadgeRose,
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

    // Calculate bitrate if fileSize and durationMs are available
    int? calculatedBitrate = explicitBitrateKbps ?? song.bitrateKbps;
    if (calculatedBitrate == null &&
        song.fileSize != null &&
        song.fileSize! > 0 &&
        song.durationMs > 0) {
      final seconds = song.durationMs / 1000.0;
      final bits = song.fileSize! * 8.0;
      calculatedBitrate = (bits / seconds / 1000.0).round();
    }

    // When a real codec string is known, gate format on it so a mislabeled
    // extension (e.g. a 128k MP3 renamed to .flac) cannot fake a higher tier.
    bool codecIs(String needle) =>
        realCodec != null && realCodec.contains(needle);
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

    // MQA is carried inside a lossless container (usually FLAC). A confirmed
    // signature scan wins; otherwise fall back to a filename/tag heuristic so
    // the badge never silently presents MQA material as plain lossless.
    final bool isMqa = (realCodec != null && realCodec.contains('mqa')) ||
        MqaDecoderHelper.isConfirmedMqaPath(song.path) ||
        RegExp(r'(?:^|[\s_\-\.\/])mqa(?:$|[\s_\-\.\/])', caseSensitive: false)
            .hasMatch(path);

    final bool hasRealHiRes = (realBitDepth != null && realBitDepth >= 24) ||
        (realSampleRate != null && realSampleRate > 48000);

    final bool isHiRes = isLosslessFormat && hasRealHiRes;

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
      shortBadgeLabel = dsdDopActive ? 'DSD → DoP' : 'DSD • HI-RES';
      description = dsdDopActive
          ? 'DSD → DoP: 1-bit High Density Studio Master framed as DSD over PCM '
              '(0x05/0xFA markers) for a compatible USB DAC — no PCM conversion.'
          : 'DSD → PCM: 1-bit High Density Studio Master decoded to PCM. '
              'DoP output is off, or no compatible USB DAC is connected.';
      badgeColor = AppColors.amberDeep;
      icon = Icons.stars_rounded;
      sampleRate =
          explicitSampleRate != null ? resolvedSampleRate : '2.8 MHz / 5.6 MHz';
      bitDepth = '1-bit DSD';
    } else if (isHiRes) {
      formatLabel =
          isFlac ? 'FLAC' : (isWav ? 'WAV' : (explicitFormat ?? 'HI-RES'));
      codecName = isFlac
          ? 'Free Lossless Audio Codec (Hi-Res)'
          : (isWav ? 'Waveform Audio File (Hi-Res PCM)' : 'Lossless Audio');
      tier = AudioQualityTier.hiResLossless;
      tierLabel = 'Hi-Res Lossless';
      shortBadgeLabel = calculatedBitrate != null
          ? '$formatLabel • ${calculatedBitrate}k'
          : '$formatLabel • HI-RES';
      description =
          'Lossless source • output fidelity depends on the active playback path';
      badgeColor = AppColors.amberDeep; // Gold Shimmer
      icon = Icons.workspace_premium_rounded;
      sampleRate = resolvedSampleRate;
      bitDepth = resolvedBitDepth;
    } else if (isLosslessFormat) {
      formatLabel =
          isFlac ? 'FLAC' : (isWav ? 'WAV' : (isAlac ? 'ALAC' : 'AIFF'));
      codecName = isFlac
          ? 'Free Lossless Audio Codec (Lossless)'
          : (isWav
              ? 'Pulse-Code Modulation (Uncompressed)'
              : 'Apple Lossless Audio');
      tier = AudioQualityTier.lossless;
      tierLabel = 'Lossless Audio';
      shortBadgeLabel = calculatedBitrate != null
          ? '$formatLabel • ${calculatedBitrate}k'
          : '$formatLabel • LOSSLESS';
      description =
          'Lossless source • output fidelity depends on the active playback path';
      badgeColor = AppColors.qualityBadgeCyan; // Electric Cyan
      icon = Icons.diamond_rounded;
      sampleRate = resolvedSampleRate;
      bitDepth = resolvedBitDepth;
    } else if (realCodec != null
        ? (codecIs('aac') || codecIs('mp4a'))
        : (ext == 'aac' || ext == 'm4a')) {
      formatLabel = 'AAC';
      codecName = 'Advanced Audio Coding (AAC-LC)';
      final kbps = calculatedBitrate ?? 128;
      tier = kbps >= 128
          ? AudioQualityTier.highQuality
          : AudioQualityTier.standardQuality;
      tierLabel = tier == AudioQualityTier.highQuality
          ? 'High Quality AAC'
          : 'Standard AAC';
      shortBadgeLabel =
          calculatedBitrate != null ? 'AAC • ${calculatedBitrate}k' : 'AAC HQ';
      description = 'High Efficiency perceptual audio compression';
      badgeColor = AppColors.qualityBadgeSky;
      icon = Icons.high_quality_rounded;
      sampleRate =
          resolvedSampleRate.isNotEmpty && resolvedSampleRate != '44.1 kHz'
              ? resolvedSampleRate
              : '44.1 kHz';
      bitDepth = resolvedBitDepth;
    } else if (realCodec != null
        ? (codecIs('opus') ||
            codecIs('ogg') ||
            codecIs('vorbis') ||
            codecIs('webm'))
        : (ext == 'ogg' ||
            ext == 'opus' ||
            ext == 'oga' ||
            ext == 'webm' ||
            path.contains('.webm') ||
            path.contains('.opus'))) {
      final isOpus = realCodec != null
          ? (codecIs('opus') || codecIs('webm'))
          : (ext == 'opus' ||
              ext == 'webm' ||
              path.contains('.webm') ||
              path.contains('.opus'));
      formatLabel = isOpus ? 'OPUS' : 'OGG';
      codecName = isOpus ? 'Opus Interactive Audio' : 'Ogg Vorbis Audio';
      final kbps = calculatedBitrate ?? (isOpus ? 160 : 192);
      tier = kbps >= 140
          ? AudioQualityTier.highQuality
          : kbps >= 96
              ? AudioQualityTier.standardQuality
              : AudioQualityTier.compact;
      tierLabel =
          '$formatLabel ${tier == AudioQualityTier.highQuality ? "HQ" : "Standard"} Audio';
      shortBadgeLabel = '$formatLabel • ${kbps}k';
      description = isOpus
          ? 'Modern high-performance Opus audio stream ($kbps kbps)'
          : 'Ogg Vorbis variable bitrate audio';
      badgeColor = AppColors.qualityBadgeIndigo;
      icon = Icons.graphic_eq_rounded;
      sampleRate =
          resolvedSampleRate.isNotEmpty && resolvedSampleRate != '44.1 kHz'
              ? resolvedSampleRate
              : '48.0 kHz';
      bitDepth = resolvedBitDepth;
    } else if (AudioFormats.requiresNativeDecoder(ext)) {
      formatLabel = ext.toUpperCase();
      codecName = '$formatLabel (decoder required)';
      tier = AudioQualityTier.standardQuality;
      tierLabel = 'Decoder Required';
      shortBadgeLabel = '$formatLabel • DECODER';
      description =
          'Recognized $formatLabel file. Playback requires a native decoder '
          'that is not bundled in this build, so it is not playable.';
      badgeColor = AppColors.slate;
      icon = Icons.extension_off_rounded;
      sampleRate = 'Unavailable';
      bitDepth = 'Unavailable';
    } else {
      // Default to MP3 / general audio
      final isRealMp3 = realCodec != null
          ? (codecIs('mp3') || codecIs('mpeg') || codecIs('mp2'))
          : ext == 'mp3';
      formatLabel = isRealMp3
          ? 'MP3'
          : (realCodec?.toUpperCase() ??
              (ext.isNotEmpty ? ext.toUpperCase() : 'MP3'));
      codecName = isRealMp3 ? 'MPEG-1 Audio Layer III' : '$formatLabel Audio';
      final kbps = calculatedBitrate ?? 320;
      if (kbps >= 256) {
        tier = AudioQualityTier.highQuality;
        tierLabel = 'High Quality $formatLabel';
        shortBadgeLabel = '$formatLabel • ${kbps}k';
        description = 'Full-frequency $kbps kbps $formatLabel playback';
        badgeColor = AppColors.qualityBadgeBlue;
        icon = Icons.high_quality_rounded;
      } else if (kbps >= 160) {
        tier = AudioQualityTier.standardQuality;
        tierLabel = 'Standard Quality $formatLabel';
        shortBadgeLabel = '$formatLabel • ${kbps}k';
        description = 'Standard compression audio stream';
        badgeColor = AppColors.qualityBadgeSlate;
        icon = Icons.graphic_eq_rounded;
      } else {
        tier = AudioQualityTier.compact;
        tierLabel = 'Compact $formatLabel';
        shortBadgeLabel = '$formatLabel • ${kbps}k';
        description = 'Compact size encoded audio';
        badgeColor = AppColors.slate;
        icon = Icons.audiotrack_rounded;
      }
      sampleRate = resolvedSampleRate;
      bitDepth = resolvedBitDepth;
    }

    return AudioQualityInfo(
      format: isMqa ? 'MQA' : formatLabel,
      codecName: isMqa ? 'Master Quality Authenticated (MQA)' : codecName,
      bitrateKbps: calculatedBitrate,
      bitrateEstimated: explicitBitrateKbps == null &&
          song.bitrateKbps == null &&
          calculatedBitrate != null,
      sampleRate:
          realSampleRate != null && realSampleRate > 0 ? sampleRate : 'Unknown',
      bitDepth: isDsd
          ? '1-bit DSD'
          : realBitDepth != null && realBitDepth > 0
              ? bitDepth
              : 'Unknown',
      channels: 'Not verified',
      tier: !isLosslessFormat && calculatedBitrate == null
          ? AudioQualityTier.standardQuality
          : tier,
      tierLabel: !isLosslessFormat && calculatedBitrate == null
          ? 'Source quality unverified'
          : isMqa
              ? 'MQA (core unfold)'
              : tierLabel,
      shortBadgeLabel: !isLosslessFormat && calculatedBitrate == null
          ? '$formatLabel • bitrate unknown'
          : isMqa
              ? 'MQA'
              : shortBadgeLabel,
      description: isMqa
          ? 'MQA-encoded stream. Core unfold is handled in-app; full '
              'authenticated/native MQA rendering is not available in this '
              'build, so no authenticated MQA output is claimed.'
          : description,
      badgeColor: isMqa ? AppColors.qualityBadgeAmber : badgeColor,
      icon: isMqa ? Icons.verified_rounded : icon,
    );
  }
}
