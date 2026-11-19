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
  });

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
    return AbxReport(
      exportedAt: (exportedAt ?? DateTime.now()).toUtc(),
      conditionA: conditionA,
      conditionB: conditionB,
      totalTrials: session.trialCount,
      answeredTrials: session.answeredCount,
      correctCount: session.correctCount,
      proportionCorrect: session.proportionCorrect,
      pValue: session.pValue,
      confidence: session.confidence,
      verdict: session.verdictKey,
      outputDevice: outputDevice,
      sampleRate: resolvedRate,
      codec: codec,
      trackTitle: trackTitle,
      trackArtist: trackArtist,
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
