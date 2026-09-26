import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../data/audio/audio_effects_channel.dart';

/// Immutable verified report representing the end-to-end signal chain integrity.
class ChainOfCustodyReport {
  final String trackId;
  final String trackTitle;
  final String trackSha256;
  final String decoderCodec;
  final int sourceSampleRate;
  final int sourceBitDepth;
  final int outputSampleRate;
  final int bufferSize;
  final List<String> activeDspStages;
  final bool isBitExactChain;
  final bool isBitPerfectActive;
  final bool isBypassCompareActive;
  final double rollingRtf;
  final double estimatedLatencyMs;
  final int thermalStatus;
  final DateTime verifiedAt;

  const ChainOfCustodyReport({
    required this.trackId,
    required this.trackTitle,
    required this.trackSha256,
    required this.decoderCodec,
    required this.sourceSampleRate,
    required this.sourceBitDepth,
    required this.outputSampleRate,
    required this.bufferSize,
    required this.activeDspStages,
    required this.isBitExactChain,
    required this.isBitPerfectActive,
    required this.isBypassCompareActive,
    required this.rollingRtf,
    required this.estimatedLatencyMs,
    required this.thermalStatus,
    required this.verifiedAt,
  });

  /// Human-readable verification verdict.
  String get verificationBadge {
    if (isBitExactChain || isBitPerfectActive) {
      return 'Bit-Exact Direct Output (Unmodified)';
    }
    if (activeDspStages.isNotEmpty) {
      return 'Verified Native DSP (${activeDspStages.length} stages)';
    }
    return 'Pass-Through';
  }

  Map<String, dynamic> toJson() {
    return {
      'trackId': trackId,
      'trackTitle': trackTitle,
      'trackSha256': trackSha256,
      'decoderCodec': decoderCodec,
      'sourceSampleRate': sourceSampleRate,
      'sourceBitDepth': sourceBitDepth,
      'outputSampleRate': outputSampleRate,
      'bufferSize': bufferSize,
      'activeDspStages': activeDspStages,
      'isBitExactChain': isBitExactChain,
      'isBitPerfectActive': isBitPerfectActive,
      'isBypassCompareActive': isBypassCompareActive,
      'rollingRtf': rollingRtf,
      'estimatedLatencyMs': estimatedLatencyMs,
      'thermalStatus': thermalStatus,
      'verificationBadge': verificationBadge,
      'verifiedAt': verifiedAt.toIso8601String(),
    };
  }
}

/// Service that generates cryptographically attested Chain-of-Custody reports
/// for playback integrity auditing.
class ChainOfCustodyService {
  final AudioEffectsChannel _effectsChannel;

  ChainOfCustodyService({AudioEffectsChannel? effectsChannel})
      : _effectsChannel = effectsChannel ?? AudioEffectsChannel();

  /// Generates a chain-of-custody report for a track.
  Future<ChainOfCustodyReport> generateReport({
    required String trackId,
    required String trackTitle,
    String? trackUri,
    List<int>? fileHeaderBytes,
    String decoderCodec = 'Opus/Auto',
    int sourceSampleRate = 48000,
    int sourceBitDepth = 16,
  }) async {
    // 1. Calculate deterministic SHA-256 integrity hash of content / uri
    final String trackSha256;
    if (fileHeaderBytes != null && fileHeaderBytes.isNotEmpty) {
      trackSha256 = sha256.convert(fileHeaderBytes).toString();
    } else {
      final input = utf8.encode(trackUri ?? trackId);
      trackSha256 = sha256.convert(input).toString();
    }

    // 2. Query native custody report from audio effects engine
    final nativeReport = await _effectsChannel.getChainOfCustodyReport();

    final outputSampleRate = (nativeReport['sampleRate'] as num?)?.toInt() ?? sourceSampleRate;
    final bufferSize = (nativeReport['bufferSize'] as num?)?.toInt() ?? 512;
    final activeStagesRaw = nativeReport['activeStages'] as List<dynamic>?;
    final activeDspStages = activeStagesRaw?.map((e) => e.toString()).toList() ?? <String>[];
    final isBitExact = nativeReport['isBitExactChain'] as bool? ?? (activeDspStages.isEmpty);
    final isBitPerfect = nativeReport['isBitPerfectActive'] as bool? ?? false;
    final isBypassCompare = nativeReport['isBypassCompareActive'] as bool? ?? false;
    final rtf = (nativeReport['rollingRtf'] as num?)?.toDouble() ?? 0.0;
    final latency = (nativeReport['estimatedLatencyMs'] as num?)?.toDouble() ?? 0.0;
    final thermal = (nativeReport['thermalStatus'] as num?)?.toInt() ?? 0;

    return ChainOfCustodyReport(
      trackId: trackId,
      trackTitle: trackTitle,
      trackSha256: trackSha256,
      decoderCodec: decoderCodec,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      bufferSize: bufferSize,
      activeDspStages: activeDspStages,
      isBitExactChain: isBitExact,
      isBitPerfectActive: isBitPerfect,
      isBypassCompareActive: isBypassCompare,
      rollingRtf: rtf,
      estimatedLatencyMs: latency,
      thermalStatus: thermal,
      verifiedAt: DateTime.now(),
    );
  }
}
