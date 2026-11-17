// lib/features/announcements/announcement_strings.dart

import 'announcement_composer.dart';

/// Single translation point for every English string the announcements module
/// renders. Keeping them here means a localisation pass touches one file.
abstract final class AnnouncementStrings {
  /// App bar title of the announcements screen.
  static const String screenTitle = 'Announcements';

  /// Section header for the master switch.
  static const String sectionAnnouncements = 'Announcements';

  /// Master switch label.
  static const String masterTitle = 'Speak track details';

  /// Master switch explanation.
  static const String masterSubtitle =
      'Read the selected details aloud when a track starts.';

  /// Section header for the element toggles.
  static const String sectionElements = 'What to announce';

  /// Section subtitle for the element toggles.
  static const String elementsSubtitle =
      'Items are spoken in the order they are listed.';

  /// Section header for delay, volume and ducking.
  static const String sectionTiming = 'Timing and volume';

  /// Section subtitle for delay, volume and ducking.
  static const String sectionTimingSubtitle =
      'Applied to every announcement on this device.';

  /// Delay slider label.
  static const String delayLabel = 'Delay before speaking';

  /// Delay slider explanation.
  static const String delaySubtitle =
      'Waits briefly so the track is playing before the voice starts.';

  /// Volume slider label.
  static const String volumeLabel = 'Announcement volume';

  /// Volume slider explanation.
  static const String volumeSubtitle = 'Separate from the music volume.';

  /// Maximum announcement length slider label.
  static const String maxLengthLabel = 'Maximum length';

  /// Maximum announcement length slider explanation.
  static const String maxLengthSubtitle =
      'Longer details are shortened to this many characters.';

  /// Ducking switch label.
  static const String duckAudioTitle = 'Duck the music while speaking';

  /// Ducking switch explanation.
  static const String duckAudioSubtitle =
      'Lowers the music so the voice stays intelligible.';

  /// Section header for the skip rules.
  static const String sectionSkip = 'Skip announcements';

  /// Section subtitle for the skip rules.
  static const String sectionSkipSubtitle =
      'Some outputs should never be interrupted by a voice.';

  /// Casting skip switch label.
  static const String skipCastingTitle = 'While casting';

  /// Casting skip switch explanation.
  static const String skipCastingSubtitle =
      'Cast receivers already show the track details on screen.';

  /// Bit-perfect skip switch label.
  static const String skipBitPerfectTitle = 'During bit-perfect playback';

  /// Bit-perfect skip switch explanation.
  static const String skipBitPerfectSubtitle =
      'Keeps the exclusive output free of system audio.';

  /// Section header for voice selection.
  static const String sectionVoice = 'Voice';

  /// Section subtitle for voice selection.
  static const String sectionVoiceSubtitle =
      'Voices are provided by the platform speech engine.';

  /// Voice picker row label.
  static const String voiceLabel = 'System voice';

  /// Dropdown entry that keeps the platform default voice.
  static const String voiceSystemDefault = 'System default';

  /// Shown while the installed voices are being listed.
  static const String voiceLoading = 'Loading installed voices…';

  /// Shown when the platform reports no extra voices.
  static const String voiceNoneInstalled = 'No additional voices installed.';

  /// Test row label.
  static const String testTitle = 'Test announcement';

  /// Test row explanation.
  static const String testSubtitle =
      'Speaks the current selection with the saved volume.';

  /// Test button label.
  static const String testButton = 'Speak test';

  /// Sample track title read out by the test button when the screen was opened
  /// without a preview track.
  static const String previewTrackTitle = 'Pulsr Music';

  /// Sample artist read out by the test button.
  static const String previewTrackArtist = 'Announcement test';

  /// Shown when no element is selected, so there is nothing to say.
  static const String emptySelection = 'Select at least one item to announce.';

  /// Status line title when the platform cannot speak.
  static const String unavailableTitle = 'Not available on this platform';

  /// Status line body when the platform cannot speak.
  static const String unavailableBody =
      'Spoken announcements need the Android text-to-speech engine. '
      'Every other setting keeps working.';

  /// Label of [element] in the element toggle list.
  static String elementLabel(AnnouncementElement element) => switch (element) {
        AnnouncementElement.title => 'Title',
        AnnouncementElement.artist => 'Artist',
        AnnouncementElement.album => 'Album',
        AnnouncementElement.year => 'Year',
        AnnouncementElement.trackNumber => 'Track number',
      };

  /// Explanation under [element] in the element toggle list.
  static String elementSubtitle(AnnouncementElement element) =>
      switch (element) {
        AnnouncementElement.title => '“Blue in Green”',
        AnnouncementElement.artist => '“Miles Davis”',
        AnnouncementElement.album => '“Kind of Blue”',
        AnnouncementElement.year => 'Spoken as “from 1959”.',
        AnnouncementElement.trackNumber => 'Spoken as “track 4”.',
      };

  /// Formats the delay slider value: `Off` or tenths of a second.
  static String delayValue(int milliseconds) => milliseconds <= 0
      ? 'Off'
      : '${(milliseconds / 1000).toStringAsFixed(1)} s';

  /// Formats the volume slider value as a percentage.
  static String volumeValue(double value) => '${(value * 100).round()}%';

  /// Formats the maximum-length slider value in characters.
  static String maxLengthValue(int characters) => '$characters characters';

  /// Refresh action for the voice list.
  static const String voiceRefresh = 'Refresh voices';

  /// Formats one voice dropdown entry as `Name (locale)`.
  static String voiceOption(String name, String localeCode) =>
      localeCode.isEmpty ? name : '$name ($localeCode)';
}
