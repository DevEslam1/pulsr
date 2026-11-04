import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import '../../data/audio/audio_effects_channel.dart';

/// Outcome of a custody verification, and the ONLY thing the UI may present as a
/// claim about output integrity.
enum CustodyVerdict {
  /// The captured bytes leaving the chain were byte-identical to those entering
  /// it. Measured, not inferred from which stages are enabled.
  bitExactMeasured,

  /// The chain demonstrably moved samples. The output digest is reported as the
  /// chain fingerprint instead of a bit-exactness claim.
  chainModifiedMeasured,

  /// No capture window completed. Never presented as a pass.
  unverified,

  /// The platform has no native capture path (non-Android).
  notSupported,
}

/// One measured capture window, as reported by the native engine.
class CustodyMeasurement {
  final int frames;
  final int channels;
  final double sampleRate;
  final double windowMs;
  final int activeStages;
  final int snapshotGeneration;
  final bool bitPerfectAtArm;
  final bool bypassCompareAtArm;

  /// True when the window ended early (oversized block, or a channel-layout or
  /// parameter change mid-capture). The digests still describe exactly what was
  /// captured, but the window certifies fewer frames than requested.
  final bool truncated;
  final String inputSha256;
  final String outputSha256;

  /// Digests of the two halves are equal: the chain provably did not alter these
  /// samples.
  final bool bitExactMeasured;

  const CustodyMeasurement({
    required this.frames,
    required this.channels,
    required this.sampleRate,
    required this.windowMs,
    required this.activeStages,
    required this.snapshotGeneration,
    required this.bitPerfectAtArm,
    required this.bypassCompareAtArm,
    required this.truncated,
    required this.inputSha256,
    required this.outputSha256,
    required this.bitExactMeasured,
  });

  factory CustodyMeasurement.fromWindowMap(Map<String, dynamic> map) {
    final inputSha = (map['inputSha256'] as String?) ?? '';
    final outputSha = (map['outputSha256'] as String?) ?? '';
    return CustodyMeasurement(
      frames: (map['frames'] as num?)?.toInt() ?? 0,
      channels: (map['channels'] as num?)?.toInt() ?? 0,
      sampleRate: (map['sampleRate'] as num?)?.toDouble() ?? 0.0,
      windowMs: (map['windowMs'] as num?)?.toDouble() ?? 0.0,
      activeStages: (map['activeStages'] as num?)?.toInt() ?? 0,
      snapshotGeneration: (map['snapshotGeneration'] as num?)?.toInt() ?? 0,
      bitPerfectAtArm: map['bitPerfectAtArm'] as bool? ?? false,
      bypassCompareAtArm: map['bypassCompareAtArm'] as bool? ?? false,
      truncated: map['truncated'] as bool? ?? false,
      inputSha256: inputSha,
      outputSha256: outputSha,
      // Recomputed here rather than trusted from the bridge: two empty digests
      // would otherwise read as "identical".
      bitExactMeasured: inputSha.isNotEmpty && inputSha == outputSha,
    );
  }

  Map<String, dynamic> toJson() => {
        'frames': frames,
        'channels': channels,
        'sampleRate': sampleRate,
        'windowMs': windowMs,
        'activeStages': activeStages,
        'snapshotGeneration': snapshotGeneration,
        'bitPerfectAtArm': bitPerfectAtArm,
        'bypassCompareAtArm': bypassCompareAtArm,
        'truncated': truncated,
        'inputSha256': inputSha256,
        'outputSha256': outputSha256,
        'bitExactMeasured': bitExactMeasured,
      };
}

/// Immutable report describing one signal chain, together with the evidence its
/// certificate is built from.
class ChainOfCustodyReport {
  final String trackId;
  final String trackTitle;

  /// SHA-256 over the ENTIRE track file. This is the content identity the
  /// certificate binds measurements to; null when the file was unreadable or
  /// hashing was declined (see [limitations]).
  final String? contentSha256;

  /// Fallback identity when no whole-file digest exists: a digest over the header
  /// bytes, URI or track id. Kept in its own field so it can never be mistaken
  /// for content identity.
  final String sourceIdentitySha256;
  final int? fileSizeBytes;
  final int? fileModifiedMs;

  final String decoderCodec;
  final int sourceSampleRate;
  final int sourceBitDepth;
  final int outputSampleRate;
  final int bufferSize;
  final List<String> activeDspStages;
  final bool isBitPerfectActive;
  final bool isBypassCompareActive;
  final double rollingRtf;
  final double estimatedLatencyMs;
  final int thermalStatus;

  final CustodyMeasurement? measurement;
  final List<String> limitations;
  final DateTime verifiedAt;

  const ChainOfCustodyReport({
    required this.trackId,
    required this.trackTitle,
    required this.contentSha256,
    required this.sourceIdentitySha256,
    required this.fileSizeBytes,
    required this.fileModifiedMs,
    required this.decoderCodec,
    required this.sourceSampleRate,
    required this.sourceBitDepth,
    required this.outputSampleRate,
    required this.bufferSize,
    required this.activeDspStages,
    required this.isBitPerfectActive,
    required this.isBypassCompareActive,
    required this.rollingRtf,
    required this.estimatedLatencyMs,
    required this.thermalStatus,
    required this.measurement,
    required this.limitations,
    required this.verifiedAt,
  });

  CustodyVerdict get verdict {
    final measured = measurement;
    if (measured == null) {
      return notSupportedPlatform
          ? CustodyVerdict.notSupported
          : CustodyVerdict.unverified;
    }
    return measured.bitExactMeasured
        ? CustodyVerdict.bitExactMeasured
        : CustodyVerdict.chainModifiedMeasured;
  }

  /// Non-Android builds have no native capture path at all, which is a different
  /// statement from "we tried and no window completed".
  bool get notSupportedPlatform =>
      limitations.contains('captureUnsupported:unsupportedPlatform');

  /// Human-readable verdict. Every branch that says "bit-exact" is backed by a
  /// measurement; configuration alone never produces that wording.
  String get verificationBadge {
    switch (verdict) {
      case CustodyVerdict.bitExactMeasured:
        final measured = measurement!;
        return measured.truncated
            ? 'Bit-Exact on a short ${measured.frames}-frame capture (partial window)'
            : 'Bit-Exact Output — measured identical over ${measured.frames} frames';
      case CustodyVerdict.chainModifiedMeasured:
        final measured = measurement!;
        final stageCount = activeDspStages.length;
        return 'Chain Modified Samples — $stageCount stage'
            '${stageCount == 1 ? '' : 's'} active'
            '${measured.truncated ? ' (partial window)' : ''}';
      case CustodyVerdict.notSupported:
        return 'Not Verified — no native capture on this platform';
      case CustodyVerdict.unverified:
        return 'Not Verified — no capture window completed';
    }
  }

  /// SHA-256 over the canonical serialization of every field except this one.
  /// Editing any field in the exported JSON changes this digest, so a tampered
  /// certificate is detectable without trusting the app that wrote it.
  String get certificateSha256 {
    final canonical = _canonicalize(toJson(includeCertificate: false));
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  Map<String, dynamic> toJson({bool includeCertificate = true}) {
    final json = <String, dynamic>{
      'trackId': trackId,
      'trackTitle': trackTitle,
      'contentSha256': contentSha256,
      'sourceIdentitySha256': sourceIdentitySha256,
      'fileSizeBytes': fileSizeBytes,
      'fileModifiedMs': fileModifiedMs,
      'decoderCodec': decoderCodec,
      'sourceSampleRate': sourceSampleRate,
      'sourceBitDepth': sourceBitDepth,
      'outputSampleRate': outputSampleRate,
      'bufferSize': bufferSize,
      'activeDspStages': activeDspStages,
      'isBitPerfectActive': isBitPerfectActive,
      'isBypassCompareActive': isBypassCompareActive,
      'rollingRtf': rollingRtf,
      'estimatedLatencyMs': estimatedLatencyMs,
      'thermalStatus': thermalStatus,
      'measurement': measurement?.toJson(),
      'limitations': limitations,
      'verdict': verdict.name,
      'verificationBadge': verificationBadge,
      'verifiedAt': verifiedAt.toUtc().toIso8601String(),
    };
    if (includeCertificate) json['certificateSha256'] = certificateSha256;
    return json;
  }

  /// JSON with sorted keys at every depth, so two equivalent reports serialize to
  /// the same bytes regardless of map insertion order.
  static String _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final parts = keys.map((key) => '"$key":${_canonicalize(value[key])}');
      return '{${parts.join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalize).join(',')}]';
    }
    return jsonEncode(value);
  }
}

typedef ContentHasher = Future<String?> Function(String path, int sizeBytes);

/// Collects the single [Digest] a chunked SHA-256 conversion emits, so a file can
/// be hashed in stream chunks without pulling in another package for a sink.
class _DigestCollector implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}

/// Generates measured chain-of-custody certificates for playback integrity.
class ChainOfCustodyService {
  static const int defaultWindowFrames = 2048;
  static const Duration defaultCollectTimeout = Duration(milliseconds: 2500);

  /// Hashing a whole file is the expensive half of a certificate. Above this size
  /// the report declines and records a limitation instead of stalling for seconds
  /// on a multi-GB image.
  static const int maxHashableBytes = 512 * 1024 * 1024;

  final AudioEffectsChannel _effectsChannel;
  final ContentHasher _hashContents;

  ChainOfCustodyService({
    AudioEffectsChannel? effectsChannel,
    ContentHasher? contentHasher,
  })  : _effectsChannel = effectsChannel ?? AudioEffectsChannel(),
        _hashContents = contentHasher ?? hashFileContents;

  /// Streams a file through SHA-256 on a worker isolate, so a 40 MB FLAC never
  /// costs the UI thread its frame budget and the whole file never sits in RAM.
  static Future<String?> hashFileContents(String path, int sizeBytes) async {
    if (sizeBytes > maxHashableBytes) return null;
    return Isolate.run(() async {
      final collector = _DigestCollector();
      final input = sha256.startChunkedConversion(collector);
      await for (final chunk in File(path).openRead()) {
        input.add(chunk);
      }
      input.close();
      return collector.digest?.toString();
    });
  }

  /// Builds a report from engine configuration only — no capture, so the verdict
  /// is always unverified. Kept for diagnostics panels that want the live stage
  /// list without pausing to measure.
  Future<ChainOfCustodyReport> generateReport({
    required String trackId,
    required String trackTitle,
    String? trackUri,
    List<int>? fileHeaderBytes,
    String decoderCodec = 'Unknown',
    int sourceSampleRate = 44100,
    int sourceBitDepth = 16,
  }) async {
    final nativeReport = await _effectsChannel.getChainOfCustodyReport();
    return _assemble(
      trackId: trackId,
      trackTitle: trackTitle,
      trackUri: trackUri,
      fileHeaderBytes: fileHeaderBytes,
      decoderCodec: decoderCodec,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      nativeReport: nativeReport,
      contentSha256: null,
      fileSizeBytes: null,
      fileModifiedMs: null,
      measurement: null,
      limitations: const ['noCaptureWindowAttempted'],
    );
  }

  /// Measures the live chain: captures one window of PCM on both sides of the DSP
  /// engine, digests both halves, and binds them to the file's content hash.
  ///
  /// Requires running playback — an idle engine produces no blocks and therefore
  /// no window, which is reported as unverified rather than guessed at.
  Future<ChainOfCustodyReport> verifyChain({
    required String trackId,
    required String trackTitle,
    String? filePath,
    String? trackUri,
    List<int>? fileHeaderBytes,
    String decoderCodec = 'Unknown',
    int sourceSampleRate = 44100,
    int sourceBitDepth = 16,
    int frames = defaultWindowFrames,
    Duration timeout = defaultCollectTimeout,
    bool hashFile = true,
  }) async {
    final limitations = <String>[];
    final nativeReport = await _effectsChannel.getChainOfCustodyReport();

    // Read from the engine rather than the caller: what the user has switched on
    // is a fact the native report already owns, and a caller-supplied flag could
    // only ever disagree with it.
    final bitPerfectActive = nativeReport['isBitPerfectActive'] as bool? ?? false;
    final bypassCompareActive =
        nativeReport['isBypassCompareActive'] as bool? ?? false;

    String? contentSha256;
    int? fileSizeBytes;
    int? fileModifiedMs;
    if (hashFile) {
      if (filePath == null || filePath.isEmpty) {
        limitations.add('contentHashDeclined:noLocalFile');
      } else {
        try {
          final stat = await FileStat.stat(filePath);
          if (stat.type == FileSystemEntityType.notFound) {
            limitations.add('contentHashFailed:fileNotFound');
          } else {
            fileSizeBytes = stat.size;
            fileModifiedMs = stat.modified.millisecondsSinceEpoch;
            if (stat.size > maxHashableBytes) {
              limitations.add('contentHashDeclined:fileTooLarge');
            } else {
              contentSha256 = await _hashContents(filePath, stat.size);
              if (contentSha256 == null) {
                limitations.add('contentHashFailed:hasherReturnedNull');
              }
            }
          }
        } catch (error) {
          limitations.add('contentHashFailed:$error');
        }
      }
    }

    final armResult = await _effectsChannel.armCustodyWindow(
      frames: frames,
      sampleRate: sourceSampleRate.toDouble(),
      bitPerfect: bitPerfectActive,
      bypassCompare: bypassCompareActive,
    );
    final armed = armResult['armed'] == true;
    if (!armed) {
      final reason = armResult['reason'] ?? 'unknown';
      limitations.add('captureArmFailed:$reason');
      if (reason == 'unsupportedPlatform') {
        limitations.add('captureUnsupported:unsupportedPlatform');
      }
    }

    CustodyMeasurement? measurement;
    if (armed) {
      measurement = await _awaitWindow(timeout);
      if (measurement == null) {
        await _effectsChannel.cancelCustodyWindow();
        limitations.add('noCaptureWindow:playbackIdleOrEngineUnloaded');
      }
    }

    return _assemble(
      trackId: trackId,
      trackTitle: trackTitle,
      trackUri: trackUri,
      fileHeaderBytes: fileHeaderBytes,
      decoderCodec: decoderCodec,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      nativeReport: nativeReport,
      contentSha256: contentSha256,
      fileSizeBytes: fileSizeBytes,
      fileModifiedMs: fileModifiedMs,
      measurement: measurement,
      limitations: limitations,
    );
  }

  /// Polls for the window to fill. 60 ms keeps the wait off the frame budget while
  /// staying well inside one block of playback at common buffer sizes.
  Future<CustodyMeasurement?> _awaitWindow(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final window = await _effectsChannel.collectCustodyWindow();
      if (window['available'] == true) {
        return CustodyMeasurement.fromWindowMap(window);
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    return null;
  }

  ChainOfCustodyReport _assemble({
    required String trackId,
    required String trackTitle,
    required String? trackUri,
    required List<int>? fileHeaderBytes,
    required String decoderCodec,
    required int sourceSampleRate,
    required int sourceBitDepth,
    required Map<String, dynamic> nativeReport,
    required String? contentSha256,
    required int? fileSizeBytes,
    required int? fileModifiedMs,
    required CustodyMeasurement? measurement,
    required List<String> limitations,
  }) {
    // Identity fallback, used only when there is no whole-file digest: header
    // bytes or a URI string do NOT identify file contents, which is exactly why
    // they get their own field instead of being reported as content identity.
    final String sourceIdentity;
    if (fileHeaderBytes != null && fileHeaderBytes.isNotEmpty) {
      sourceIdentity = sha256.convert(fileHeaderBytes).toString();
    } else {
      sourceIdentity =
          sha256.convert(utf8.encode(trackUri ?? trackId)).toString();
    }

    final outputSampleRate =
        (nativeReport['sampleRate'] as num?)?.toDouble() ??
            sourceSampleRate.toDouble();
    final activeStagesRaw = nativeReport['activeStages'] as List<dynamic>?;

    return ChainOfCustodyReport(
      trackId: trackId,
      trackTitle: trackTitle,
      contentSha256: contentSha256,
      sourceIdentitySha256: sourceIdentity,
      fileSizeBytes: fileSizeBytes,
      fileModifiedMs: fileModifiedMs,
      decoderCodec: decoderCodec,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate.round(),
      bufferSize: (nativeReport['bufferSize'] as num?)?.toInt() ?? 0,
      activeDspStages:
          activeStagesRaw?.map((e) => e.toString()).toList() ?? const [],
      isBitPerfectActive: nativeReport['isBitPerfectActive'] as bool? ?? false,
      isBypassCompareActive:
          nativeReport['isBypassCompareActive'] as bool? ?? false,
      rollingRtf: (nativeReport['rollingRtf'] as num?)?.toDouble() ?? 0.0,
      estimatedLatencyMs:
          (nativeReport['estimatedLatencyMs'] as num?)?.toDouble() ?? 0.0,
      thermalStatus: (nativeReport['thermalStatus'] as num?)?.toInt() ?? 0,
      measurement: measurement,
      limitations: limitations,
      verifiedAt: DateTime.now(),
    );
  }
}
