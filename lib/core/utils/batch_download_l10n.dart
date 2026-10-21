import '../../l10n/generated/app_localizations.dart';

/// Suffix for a batch-download toast describing tracks that were not queued.
///
/// Callers append it to their localized success/already-downloaded message so
/// a capped, skipped, or failed batch can never be reported as fully
/// successful.
String describeBatchOutcomeExtras(
  AppLocalizations l10n, {
  required int capped,
  required int failed,
  String? firstError,
  int skippedLocal = 0,
}) {
  final parts = <String>[];
  if (capped > 0) {
    parts.add(l10n.batchCappedTracks(capped));
  }
  if (skippedLocal > 0) {
    parts.add(l10n.batchSkippedLocalTracks(skippedLocal));
  }
  if (failed > 0) {
    final error = firstError?.trim();
    parts.add(
      error != null && error.isNotEmpty
          ? l10n.batchFailedTracksWithError(failed, error)
          : l10n.batchFailedTracks(failed),
    );
  }
  if (parts.isEmpty) return '';
  return ' ${parts.join('; ')}.';
}
