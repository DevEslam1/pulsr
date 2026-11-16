// lib/features/audio_profiles/audio_profile_strings.dart
//
// Single translation point for the audio-profiles module. Every user-visible
// string the profile model, service and screen emit lives here, so the module
// can be localized by translating one class.

/// English copy for the audio-profiles feature.
abstract final class AudioProfileStrings {
  static const String screenTitle = 'Audio profiles';
  static const String captureAction = 'Capture current setup';
  static const String importAction = 'Import';
  static const String refreshTooltip = 'Reload profiles';

  static const String deviceLabelPrefix = 'Current device';
  static const String deviceUnknown = 'No output device detected';

  static const String captureDialogTitle = 'Name this profile';
  static const String captureDialogMessage =
      'Saves the current EQ, DSP, output and bit-perfect settings as one file '
      'you can share.';
  static const String captureDialogHint = 'e.g. USB DAC - neutral';
  static const String captureConfirm = 'Save';
  static const String nameRequired = 'Enter a name for the profile.';
  static const String captureSaved = 'Profile saved.';
  static const String captureFailed = 'Saving the profile failed.';

  static const String importSaved = 'Profile imported.';
  static const String importFailed = 'Could not import that profile file.';
  static const String importMissing = 'That file no longer exists.';

  static const String applyConfirm = 'Apply';
  static const String applyDialogTitle = 'Apply profile?';
  static const String applyFailed = 'Applying the profile failed.';
  static const String applyTooltip = 'Apply profile';
  static const String shareTooltip = 'Share profile';
  static const String deleteTooltip = 'Delete profile';

  static const String deleteConfirm = 'Delete';
  static const String deleteDialogTitle = 'Delete profile?';
  static const String deleted = 'Profile deleted.';
  static const String deleteFailed = 'Deleting the profile failed.';

  static const String shareFailed = 'Sharing the profile failed.';

  static const String emptyTitle = 'No audio profiles yet';
  static const String emptySubtitle =
      'Capture your current setup to reuse it on another device or headphone.';
  static const String errorTitle = 'Profiles could not be loaded';
  static const String errorSubtitle =
      'App storage may be unavailable. Try again in a moment.';
  static const String retry = 'Retry';

  static const String formatCorrupt =
      'This file is not a valid Pulsr audio profile.';
  static const String formatMissingVersion =
      'The profile is missing its format version.';
  static const String formatTooLarge =
      'The profile file is larger than the 512 KB limit.';
  static const String formatTooManyValues =
      'The profile contains more than 200 settings.';
  static const String formatEmptyKey =
      'The profile contains an empty setting name.';
  static const String formatInvalidId = 'The profile identifier is invalid.';
  static const String storeFailed = 'The profile could not be saved.';

  /// Body of the confirmation dialog shown before applying a profile.
  static String applyDialogBody(String name) =>
      'This replaces your current audio settings with "$name". A backup of '
      'the current setup is saved automatically first, so a partial failure '
      'can be rolled back.';

  /// Success message after applying [count] settings.
  static String applyDone(int count) =>
      count == 1 ? 'Applied 1 setting.' : 'Applied $count settings.';

  /// Confirmation body for deleting a profile called [name].
  static String deleteDialogBody(String name) =>
      '"$name" will be removed from this device. This cannot be undone.';

  /// Share-sheet body for a profile called [name].
  static String shareText(String name) => 'Pulsr audio profile: $name';

  /// Subtitle of a saved profile row.
  static String profileSummary(int settings) =>
      settings == 1 ? '1 setting' : '$settings settings';

  /// Name given to the automatic pre-apply backup of [name].
  static String backupOf(String name) => 'Before $name';

  /// Message for a profile written by a newer app version.
  static String formatNewerVersion(int version) =>
      'This profile uses format $version, which is newer than this build '
      'supports. Update Pulsr to import it.';

  /// Message for a numeric format version this build does not accept.
  static String formatInvalidVersionNumber(int version) =>
      'Format $version is not a supported profile version.';

  /// Message for a single setting whose value has an unsupported type.
  static String formatInvalidValue(String key) =>
      'The setting "$key" has a value this build cannot read.';
}
