// lib/core/services/abx_report_export.dart
import 'dart:convert';
import 'dart:io';

import '../../domain/models/abx_session.dart';

/// Output hardware context captured when an ABX listening session finishes.
class AbxOutputDeviceInfo {
  final String name;
  final String type;
  final bool isUsbDac;
  final int? sampleRate;
  final int? bitDepth;
  final bool? isBitPerfectActive;

  const AbxOutputDeviceInfo({
    required this.name,
    required this.type,
    required this.isUsbDac,
    this.sampleRate,
    this.bitDepth,
    this.isBitPerfectActive,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'type': type,
        'isUsbDac': isUsbDac,
        'sampleRate': sampleRate,
        'bitDepth': bitDepth,
        'isBitPerfectActive': isBitPerfectActive,
      };
}

/// Redaction utility to scrub personal identifiable information (paths, URLs,
/// user names, serial numbers, UUIDs, MAC addresses) from ABX export strings.
class AbxRedactor {
  static final RegExp _windowsPathRegex = RegExp(
    r'[a-zA-Z]:\\[^\s"<>|?*]+',
    caseSensitive: false,
  );

  static final RegExp _unixPathRegex = RegExp(
    r'(?:/(?:storage|Users|home|data|private|var|etc|usr|opt|media|mnt))/[^\s"<>|?*]+',
    caseSensitive: false,
  );

  static final RegExp _urlRegex = RegExp(
    r'(?:https?|ftp|file|smb)://[^\s"<>]+',
    caseSensitive: false,
  );

  static final RegExp _uuidRegex = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
  );

  static final RegExp _serialRegex = RegExp(
    r'(?:SN|Serial|S/N|SerialNo|SerialNumber)[\s:=]+([A-Za-z0-9_-]+)',
    caseSensitive: false,
  );

  static final RegExp _macRegex = RegExp(
    r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b',
  );

  /// Scrubs all identified sensitive patterns (paths, URLs, serials, UUIDs, MACs)
  /// from [text]. Returns null if [text] is null.
  static String? redact(String? text) {
    if (text == null) return null;
    var scrubbed = text;
    scrubbed = scrubbed.replaceAll(_urlRegex, '[URL_REDACTED]');
    scrubbed = scrubbed.replaceAll(_windowsPathRegex, '[PATH_REDACTED]');
    scrubbed = scrubbed.replaceAll(_unixPathRegex, '[PATH_REDACTED]');
    scrubbed = scrubbed.replaceAll(_uuidRegex, '[UUID_REDACTED]');
    scrubbed = scrubbed.replaceAllMapped(_serialRegex, (m) {
      final whole = m.group(0)!;
      final num = m.group(1)!;
      final prefix = whole.substring(0, whole.indexOf(num));
      return '$prefix[SERIAL_REDACTED]';
    });
    scrubbed = scrubbed.replaceAll(_macRegex, '[MAC_REDACTED]');
    return scrubbed;
  }
}

/// Structured, self-contained JSON report for a completed blind ABX session.
///
/// Deliberately excludes local filesystem paths so exported reports can be
/// shared publicly without leaking where the listener keeps their library.
class AbxReport {
  static const int currentSchemaVersion = 1;
  static const String reportKind = 'abx_report';

  final int schemaVersion;
  final String kind;
  final DateTime exportedAt;
  final String conditionA;
  final String conditionB;
  final int totalTrials;
  final int answeredTrials;
  final int correctCount;
  final double proportionCorrect;
  final double pValue;
  final double twoSidedPValue;
  final double confidence;
  final String verdict;
  final AbxOutputDeviceInfo outputDevice;
  final int? sampleRate;
  final String? codec;
  final String? trackTitle;
  final String? trackArtist;
  final int? sourceSampleRate;
  final int? sourceBitDepth;
  final List<AbxTrial> trials;

  const AbxReport({
    this.schemaVersion = currentSchemaVersion,
    this.kind = reportKind,
    required this.exportedAt,
    this.conditionA = 'bypass',
    this.conditionB = 'dsp',
    required this.totalTrials,
    required this.answeredTrials,
    required this.correctCount,
    required this.proportionCorrect,
    required this.pValue,
    double? twoSidedPValue,
    required this.confidence,
    required this.verdict,
    required this.outputDevice,
    required this.sampleRate,
    required this.codec,
    required this.trackTitle,
    required this.trackArtist,
    required this.sourceSampleRate,
    required this.sourceBitDepth,
    required this.trials,
  }) : twoSidedPValue = twoSidedPValue ?? ((pValue * 2.0) > 1.0 ? 1.0 : (pValue * 2.0));

  /// Builds an export report from a completed [AbxSession].
  ///
  /// Throws [StateError] when [session] is still incomplete so partial runs
  /// are never exported as finished ABX verdicts.
  factory AbxReport.fromSession(
    AbxSession session, {
    required AbxOutputDeviceInfo outputDevice,
    int? sampleRate,
    String? codec,
    String? trackTitle,
    String? trackArtist,
    int? sourceSampleRate,
    int? sourceBitDepth,
    DateTime? exportedAt,
    String conditionA = 'bypass',
    String conditionB = 'dsp',
    bool scrubPii = true,
  }) {
    if (!session.isComplete) {
      throw StateError(
        'Cannot export an incomplete ABX session '
        '(${session.answeredCount}/${session.trialCount}).',
      );
    }
    final resolvedRate = (sampleRate != null && sampleRate > 0)
        ? sampleRate
        : ((outputDevice.sampleRate != null && outputDevice.sampleRate! > 0)
            ? outputDevice.sampleRate
            : sourceSampleRate);

    final cleanTitle = scrubPii ? AbxRedactor.redact(trackTitle) : trackTitle;
    final cleanArtist = scrubPii ? AbxRedactor.redact(trackArtist) : trackArtist;
    final cleanCondA = scrubPii ? (AbxRedactor.redact(conditionA) ?? conditionA) : conditionA;
    final cleanCondB = scrubPii ? (AbxRedactor.redact(conditionB) ?? conditionB) : conditionB;
    final cleanDevice = scrubPii
        ? AbxOutputDeviceInfo(
            name: AbxRedactor.redact(outputDevice.name) ?? outputDevice.name,
            type: outputDevice.type,
            isUsbDac: outputDevice.isUsbDac,
            sampleRate: outputDevice.sampleRate,
            bitDepth: outputDevice.bitDepth,
            isBitPerfectActive: outputDevice.isBitPerfectActive,
          )
        : outputDevice;

    return AbxReport(
      exportedAt: (exportedAt ?? DateTime.now()).toUtc(),
      conditionA: cleanCondA,
      conditionB: cleanCondB,
      totalTrials: session.trialCount,
      answeredTrials: session.answeredCount,
      correctCount: session.correctCount,
      proportionCorrect: session.proportionCorrect,
      pValue: session.pValue,
      twoSidedPValue: (session.pValue * 2.0).clamp(0.0, 1.0),
      confidence: session.confidence,
      verdict: session.verdictKey,
      outputDevice: cleanDevice,
      sampleRate: resolvedRate,
      codec: codec,
      trackTitle: cleanTitle,
      trackArtist: cleanArtist,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      trials: List<AbxTrial>.unmodifiable(session.trials),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'kind': kind,
        'exportedAt': exportedAt.toIso8601String(),
        'conditionA': conditionA,
        'conditionB': conditionB,
        'totalTrials': totalTrials,
        'answeredTrials': answeredTrials,
        'correctCount': correctCount,
        'proportionCorrect': proportionCorrect,
        'pValue': pValue,
        'twoSidedPValue': twoSidedPValue,
        'confidence': confidence,
        'verdict': verdict,
        'outputDevice': outputDevice.toJson(),
        'sampleRate': sampleRate,
        'codec': codec,
        'track': <String, dynamic>{
          'title': trackTitle,
          'artist': trackArtist,
          'codec': codec,
          'sourceSampleRate': sourceSampleRate,
          'sourceBitDepth': sourceBitDepth,
        },
        'trials': <Map<String, dynamic>>[
          for (final AbxTrial trial in trials)
            <String, dynamic>{
              'index': trial.index,
              'trialNumber': trial.index + 1,
              'hiddenX': trial.hiddenX.name,
              'answer': trial.answer?.name,
              'correct': trial.correct,
            },
        ],
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Written ABX report file together with its exact JSON text and model.
class AbxReportArtifact {
  final File file;
  final String jsonText;
  final AbxReport report;

  const AbxReportArtifact({
    required this.file,
    required this.jsonText,
    required this.report,
  });
}

/// Writes [report] as a pretty-printed JSON artifact inside [directory] and
/// verifies the written payload before returning.
Future<AbxReportArtifact> exportAbxReport(
  AbxReport report, {
  required Directory directory,
}) async {
  final jsonText = report.toPrettyJson();
  final name =
      'pulsr-abx-report-${report.exportedAt.toUtc().millisecondsSinceEpoch}.json';
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsString(jsonText, flush: true);

  final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final trials = decoded['trials'] as List<dynamic>?;
  if (decoded['kind'] != AbxReport.reportKind ||
      trials == null ||
      trials.length != report.totalTrials) {
    throw StateError('ABX report round-trip verification failed for $name');
  }

  return AbxReportArtifact(
    file: file,
    jsonText: jsonText,
    report: report,
  );
}
