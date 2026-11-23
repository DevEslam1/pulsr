// lib/features/audio_profiles/audio_profile_strings.dart
//
// Localized copy for the audio-profiles module, backed by ARB
// (`AppLocalizations`) with automatic English fallback in headless tests.

import 'dart:ui' show Locale;

import '../../core/utils/l10n_holder.dart';
import '../../l10n/generated/app_localizations.dart';

/// User-facing copy for the audio-profiles feature.
abstract final class AudioProfileStrings {
  static final AppLocalizations _fallback =
      lookupAppLocalizations(const Locale('en'));

  static AppLocalizations _l10n([AppLocalizations? l10n]) =>
      l10n ?? L10nHolder.current ?? _fallback;

  static String get screenTitle => _l10n().audioProfScreenTitle;
  static String get captureAction => _l10n().audioProfCaptureAction;
  static String get importAction => _l10n().audioProfImportAction;
  static String get refreshTooltip => _l10n().audioProfRefreshTooltip;

  static String get deviceLabelPrefix => _l10n().audioProfDeviceLabelPrefix;
  static String get deviceUnknown => _l10n().audioProfDeviceUnknown;

  static String get captureDialogTitle => _l10n().audioProfCaptureDialogTitle;
  static String get captureDialogMessage =>
      _l10n().audioProfCaptureDialogMessage;
  static String get captureDialogHint => _l10n().audioProfCaptureDialogHint;
  static String get captureConfirm => _l10n().audioProfCaptureConfirm;
  static String get nameRequired => _l10n().audioProfNameRequired;
  static String get captureSaved => _l10n().audioProfCaptureSaved;
  static String get captureFailed => _l10n().audioProfCaptureFailed;

  static String get importSaved => _l10n().audioProfImportSaved;
  static String get importFailed => _l10n().audioProfImportFailed;
  static String get importMissing => _l10n().audioProfImportMissing;

  static String get applyConfirm => _l10n().audioProfApplyConfirm;
  static String get applyDialogTitle => _l10n().audioProfApplyDialogTitle;
  static String get applyFailed => _l10n().audioProfApplyFailed;
  static String get applyTooltip => _l10n().audioProfApplyTooltip;
  static String get shareTooltip => _l10n().audioProfShareTooltip;
  static String get deleteTooltip => _l10n().audioProfDeleteTooltip;

  static String get defaultTooltip => _l10n().audioProfDefaultTooltip;
  static String get defaultDialogTitle => _l10n().audioProfDefaultDialogTitle;
  static String get defaultDialogMessage =>
      _l10n().audioProfDefaultDialogMessage;
  static String get defaultNone => _l10n().audioProfDefaultNone;
  static String get defaultSaved => _l10n().audioProfDefaultSaved;
  static String get defaultCleared => _l10n().audioProfDefaultCleared;
  static String get defaultMissing => _l10n().audioProfDefaultMissing;
  static String get defaultBadge => _l10n().audioProfDefaultBadge;
  static String get cancelAction => _l10n().audioProfCancelAction;

  static String get deleteConfirm => _l10n().audioProfDeleteConfirm;
  static String get deleteDialogTitle => _l10n().audioProfDeleteDialogTitle;
  static String get deleted => _l10n().audioProfDeleted;
  static String get deleteFailed => _l10n().audioProfDeleteFailed;

  static String get shareFailed => _l10n().audioProfShareFailed;

  static String get emptyTitle => _l10n().audioProfEmptyTitle;
  static String get emptySubtitle => _l10n().audioProfEmptySubtitle;
  static String get errorTitle => _l10n().audioProfErrorTitle;
  static String get errorSubtitle => _l10n().audioProfErrorSubtitle;
  static String get retry => _l10n().audioProfRetry;

  static String get formatCorrupt => _l10n().audioProfFormatCorrupt;
  static String get formatMissingVersion =>
      _l10n().audioProfFormatMissingVersion;
  static String get formatTooLarge => _l10n().audioProfFormatTooLarge;
  static String get formatTooManyValues => _l10n().audioProfFormatTooManyValues;
  static String get formatEmptyKey => _l10n().audioProfFormatEmptyKey;
  static String get formatInvalidId => _l10n().audioProfFormatInvalidId;
  static String get storeFailed => _l10n().audioProfStoreFailed;

  /// Body of the confirmation dialog shown before applying a profile.
  static String applyDialogBody(String name, [AppLocalizations? l10n]) =>
      _l10n(l10n).audioProfApplyDialogBody(name);

  /// Success message after applying [count] settings.
  static String applyDone(int count, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    return count == 1
        ? l.audioProfApplyDoneOne
        : l.audioProfApplyDoneMany(count);
  }

  /// Success message when [skipped] settings were outside the whitelist.
  static String applyDoneWithSkipped(
    int applied,
    int skipped, [
    AppLocalizations? l10n,
  ]) {
    final l = _l10n(l10n);
    final appliedMsg = applyDone(applied, l);
    return skipped == 1
        ? l.audioProfApplyDoneWithSkippedOne(appliedMsg)
        : l.audioProfApplyDoneWithSkippedMany(appliedMsg, skipped);
  }

  /// Failure message when [failed] settings were rejected and the previous
  /// values were restored.
  static String applyFailedRolledBack(int failed, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    return failed == 1
        ? l.audioProfApplyFailedRolledBackOne
        : l.audioProfApplyFailedRolledBackMany(failed);
  }

  /// Failure message when [failed] settings were rejected and the rollback was
  /// only partially successful.
  static String applyFailedRollbackIncomplete(
    int failed, [
    AppLocalizations? l10n,
  ]) {
    final l = _l10n(l10n);
    return failed == 1
        ? l.audioProfApplyFailedRollbackIncompleteOne
        : l.audioProfApplyFailedRollbackIncompleteMany(failed);
  }

  /// Import message when [skipped] unsupported or corrupt settings were
  /// dropped from the imported file.
  static String importSavedSkipped(int skipped, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    return skipped == 1
        ? l.audioProfImportSavedSkippedOne
        : l.audioProfImportSavedSkippedMany(skipped);
  }

  /// Confirmation body for deleting a profile called [name].
  static String deleteDialogBody(String name, [AppLocalizations? l10n]) =>
      _l10n(l10n).audioProfDeleteDialogBody(name);

  /// Share-sheet body for a profile called [name].
  static String shareText(String name, [AppLocalizations? l10n]) =>
      _l10n(l10n).audioProfShareText(name);

  /// Subtitle of a saved profile row.
  static String profileSummary(int settings, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    return settings == 1
        ? l.audioProfSummaryOne
        : l.audioProfSummaryMany(settings);
  }

  /// Name given to the automatic pre-apply backup of [name].
  static String backupOf(String name, [AppLocalizations? l10n]) =>
      _l10n(l10n).audioProfBackupOf(name);

  /// Message for a profile written by a newer app version.
  static String formatNewerVersion(int version, [AppLocalizations? l10n]) =>
      _l10n(l10n).audioProfFormatNewerVersion(version);

  /// Message for a numeric format version this build does not accept.
  static String formatInvalidVersionNumber(
    int version, [
    AppLocalizations? l10n,
  ]) =>
      _l10n(l10n).audioProfFormatInvalidVersionNumber(version);

  /// Message for a single setting whose value has an unsupported type.
  static String formatInvalidValue(String key, [AppLocalizations? l10n]) =>
      _l10n(l10n).audioProfFormatInvalidValue(key);
}
