// lib/features/announcements/announcement_strings.dart
//
// Localized copy for the announcements module, backed by ARB
// (`AppLocalizations`) with automatic English fallback in headless tests.

import 'dart:ui' show Locale;

import '../../core/utils/l10n_holder.dart';
import '../../l10n/generated/app_localizations.dart';
import 'announcement_composer.dart';

/// User-facing copy for the announcements module.
abstract final class AnnouncementStrings {
  static final AppLocalizations _fallback =
      lookupAppLocalizations(const Locale('en'));

  static AppLocalizations _l10n([AppLocalizations? l10n]) =>
      l10n ?? L10nHolder.current ?? _fallback;

  /// App bar title of the announcements screen.
  static String get screenTitle => _l10n().annScreenTitle;

  /// Section header for the master switch.
  static String get sectionAnnouncements => _l10n().annSectionAnnouncements;

  /// Master switch label.
  static String get masterTitle => _l10n().annMasterTitle;

  /// Master switch explanation.
  static String get masterSubtitle => _l10n().annMasterSubtitle;

  /// Section header for the element toggles.
  static String get sectionElements => _l10n().annSectionElements;

  /// Section subtitle for the element toggles.
  static String get elementsSubtitle => _l10n().annElementsSubtitle;

  /// Section header for delay, volume and ducking.
  static String get sectionTiming => _l10n().annSectionTiming;

  /// Section subtitle for delay, volume and ducking.
  static String get sectionTimingSubtitle => _l10n().annSectionTimingSubtitle;

  /// Delay slider label.
  static String get delayLabel => _l10n().annDelayLabel;

  /// Delay slider explanation.
  static String get delaySubtitle => _l10n().annDelaySubtitle;

  /// Volume slider label.
  static String get volumeLabel => _l10n().annVolumeLabel;

  /// Volume slider explanation.
  static String get volumeSubtitle => _l10n().annVolumeSubtitle;

  /// Maximum announcement length slider label.
  static String get maxLengthLabel => _l10n().annMaxLengthLabel;

  /// Maximum announcement length slider explanation.
  static String get maxLengthSubtitle => _l10n().annMaxLengthSubtitle;

  /// Ducking switch label.
  static String get duckAudioTitle => _l10n().annDuckAudioTitle;

  /// Ducking switch explanation.
  static String get duckAudioSubtitle => _l10n().annDuckAudioSubtitle;

  /// Section header for the skip rules.
  static String get sectionSkip => _l10n().annSectionSkip;

  /// Section subtitle for the skip rules.
  static String get sectionSkipSubtitle => _l10n().annSectionSkipSubtitle;

  /// Casting skip switch label.
  static String get skipCastingTitle => _l10n().annSkipCastingTitle;

  /// Casting skip switch explanation.
  static String get skipCastingSubtitle => _l10n().annSkipCastingSubtitle;

  /// Bit-perfect skip switch label.
  static String get skipBitPerfectTitle => _l10n().annSkipBitPerfectTitle;

  /// Bit-perfect skip switch explanation.
  static String get skipBitPerfectSubtitle =>
      _l10n().annSkipBitPerfectSubtitle;

  /// Section header for voice selection.
  static String get sectionVoice => _l10n().annSectionVoice;

  /// Section subtitle for voice selection.
  static String get sectionVoiceSubtitle => _l10n().annSectionVoiceSubtitle;

  /// Voice picker row label.
  static String get voiceLabel => _l10n().annVoiceLabel;

  /// Dropdown entry that keeps the platform default voice.
  static String get voiceSystemDefault => _l10n().annVoiceSystemDefault;

  /// Shown while the installed voices are being listed.
  static String get voiceLoading => _l10n().annVoiceLoading;

  /// Shown when the platform reports no extra voices.
  static String get voiceNoneInstalled => _l10n().annVoiceNoneInstalled;

  /// Test row label.
  static String get testTitle => _l10n().annTestTitle;

  /// Test row explanation.
  static String get testSubtitle => _l10n().annTestSubtitle;

  /// Test button label.
  static String get testButton => _l10n().annTestButton;

  /// Sample track title read out by the test button when the screen was opened
  /// without a preview track.
  static String get previewTrackTitle => _l10n().annPreviewTrackTitle;

  /// Sample artist read out by the test button.
  static String get previewTrackArtist => _l10n().annPreviewTrackArtist;

  /// Shown when no element is selected, so there is nothing to say.
  static String get emptySelection => _l10n().annEmptySelection;

  /// Status line title when the platform cannot speak.
  static String get unavailableTitle => _l10n().annUnavailableTitle;

  /// Status line body when the platform cannot speak.
  static String get unavailableBody => _l10n().annUnavailableBody;

  /// Label of [element] in the element toggle list.
  static String elementLabel(
    AnnouncementElement element, [
    AppLocalizations? l10n,
  ]) {
    final l = _l10n(l10n);
    return switch (element) {
      AnnouncementElement.title => l.annElementTitle,
      AnnouncementElement.artist => l.annElementArtist,
      AnnouncementElement.album => l.annElementAlbum,
      AnnouncementElement.year => l.annElementYear,
      AnnouncementElement.trackNumber => l.annElementTrackNumber,
    };
  }

  /// Explanation under [element] in the element toggle list.
  static String elementSubtitle(
    AnnouncementElement element, [
    AppLocalizations? l10n,
  ]) {
    final l = _l10n(l10n);
    return switch (element) {
      AnnouncementElement.title => l.annElementSubtitleTitle,
      AnnouncementElement.artist => l.annElementSubtitleArtist,
      AnnouncementElement.album => l.annElementSubtitleAlbum,
      AnnouncementElement.year => l.annElementSubtitleYear,
      AnnouncementElement.trackNumber => l.annElementSubtitleTrackNumber,
    };
  }

  /// Formats the delay slider value: `Off` or tenths of a second.
  static String delayValue(int milliseconds, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    return milliseconds <= 0
        ? l.annDelayOff
        : l.annDelaySeconds((milliseconds / 1000).toStringAsFixed(1));
  }

  /// Formats the volume slider value as a percentage.
  static String volumeValue(double value) => '${(value * 100).round()}%';

  /// Formats the maximum-length slider value in characters.
  static String maxLengthValue(int characters, [AppLocalizations? l10n]) =>
      _l10n(l10n).annMaxLengthValue(characters);

  /// Refresh action for the voice list.
  static String get voiceRefresh => _l10n().annVoiceRefresh;

  /// Formats one voice dropdown entry as `Name (locale)`.
  static String voiceOption(String name, String localeCode) =>
      localeCode.isEmpty ? name : '$name ($localeCode)';
}
