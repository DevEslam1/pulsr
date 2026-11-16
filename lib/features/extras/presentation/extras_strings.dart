// lib/features/extras/presentation/extras_strings.dart
//
// Single translation point for the "Tools & extras" hub. Keeping the English
// copy here means a future `app_en.arb` migration touches one file.
abstract final class ExtrasStrings {
  static const String title = 'Tools & extras';
  static const String loading = 'Loading tools…';
  static const String loadFailed =
      'Some tools could not start. Their rows stay disabled; reopen this screen '
      'to retry.';
  static const String unknownDevice = 'Unknown output device';

  static const String settingsCategoryTitle = 'Tools & extras';
  static const String settingsCategorySubtitle =
      'Announcements, system behaviour, USB DAC ergonomics, network output, '
      'profiles and diagnostics.';

  static const String playbackTitle = 'Playback extras';
  static const String playbackSubtitle =
      'Announcements, system behaviour and USB DAC ergonomics.';

  static const String announcementsTitle = 'Track announcements';
  static const String announcementsSubtitle =
      'Speak the title, artist and album when a track starts.';

  static const String systemBehaviorTitle = 'System behaviour';
  static const String systemBehaviorSubtitle =
      'Audio-focus release, notification pausing, fade-out and volume steps.';

  static const String usbTitle = 'USB DAC ergonomics';
  static const String usbSubtitle =
      'Start-of-track silence, alt-setting reset, force 16-bit, HID keys and '
      'bus-speed probe per device.';

  static const String outputTitle = 'Network & output';
  static const String outputSubtitle =
      'Play on DLNA/UPnP renderers or browse SMB/WebDAV/FTP libraries.';

  static const String dlnaTitle = 'DLNA / UPnP output';
  static const String dlnaSubtitle =
      'Discover AVRs, Sonos, Kodi and TVs on the local network.';

  static const String remoteTitle = 'Network libraries';
  static const String remoteSubtitle =
      'SMB2/3, WebDAV and FTP shares as playable sources, with a local cache.';

  static const String supportTitle = 'Setups & support';
  static const String supportSubtitle =
      'Move a tuned setup between devices, or export a diagnostics bundle.';

  static const String profilesTitle = 'Audio profiles';
  static const String profilesSubtitle =
      'Capture the DSP chain, EQ, crossfeed and output mode as one file.';

  static const String diagnosticsTitle = 'Diagnostics & safe mode';
  static const String diagnosticsSubtitle =
      'Output path counters, recent logs, and automatic fallback after '
      'repeated sink failures.';

  static const String remoteUnavailableTitle = 'Network libraries unavailable';
  static const String remoteUnavailableBody =
      'Pulsr could not open the local streaming port. Close other VPN or proxy '
      'apps and try again.';
  static const String remotePlaybackFailed =
      'That file could not be played from the share. Check the connection and '
      'try again.';
  static const String remoteAlbumLabel = 'Network library';
}
