import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('es')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Pulsr Music'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Pure Offline Sound'**
  String get appTagline;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get navPlaylists;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navYtmSearch.
  ///
  /// In en, this message translates to:
  /// **'Online Search'**
  String get navYtmSearch;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get goodMorning;

  /// No description provided for @goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get goodAfternoon;

  /// No description provided for @goodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get goodEvening;

  /// No description provided for @recentlyPlayed.
  ///
  /// In en, this message translates to:
  /// **'Recently Played'**
  String get recentlyPlayed;

  /// No description provided for @recentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently Added'**
  String get recentlyAdded;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @dailyDrive.
  ///
  /// In en, this message translates to:
  /// **'Daily Drive'**
  String get dailyDrive;

  /// No description provided for @focusFlow.
  ///
  /// In en, this message translates to:
  /// **'Focus Flow'**
  String get focusFlow;

  /// No description provided for @mostPlayed.
  ///
  /// In en, this message translates to:
  /// **'Most Played'**
  String get mostPlayed;

  /// No description provided for @quickMix.
  ///
  /// In en, this message translates to:
  /// **'Quick Mix'**
  String get quickMix;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @stats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get stats;

  /// No description provided for @songs.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get songs;

  /// No description provided for @albums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albums;

  /// No description provided for @artists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get artists;

  /// No description provided for @playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @genres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get genres;

  /// No description provided for @folders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get folders;

  /// No description provided for @years.
  ///
  /// In en, this message translates to:
  /// **'Years'**
  String get years;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search songs, artists, albums...'**
  String get searchPlaceholder;

  /// No description provided for @searchOnline.
  ///
  /// In en, this message translates to:
  /// **'Search YouTube Music...'**
  String get searchOnline;

  /// No description provided for @recentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent Searches'**
  String get recentSearches;

  /// No description provided for @clearSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearSearchHistory;

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No music found'**
  String get noResultsFound;

  /// No description provided for @noResultsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term or check spelling'**
  String get noResultsSubtitle;

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now Playing'**
  String get nowPlaying;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Up Next'**
  String get queue;

  /// No description provided for @clearQueue.
  ///
  /// In en, this message translates to:
  /// **'Clear Queue'**
  String get clearQueue;

  /// No description provided for @saveQueueAsPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Save Queue as Playlist'**
  String get saveQueueAsPlaylist;

  /// No description provided for @playingFrom.
  ///
  /// In en, this message translates to:
  /// **'Playing from'**
  String get playingFrom;

  /// No description provided for @lyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyrics;

  /// No description provided for @syncedLyrics.
  ///
  /// In en, this message translates to:
  /// **'Synced Lyrics'**
  String get syncedLyrics;

  /// No description provided for @plainLyrics.
  ///
  /// In en, this message translates to:
  /// **'Plain Lyrics'**
  String get plainLyrics;

  /// No description provided for @fetchingLyrics.
  ///
  /// In en, this message translates to:
  /// **'Searching for lyrics...'**
  String get fetchingLyrics;

  /// No description provided for @noLyricsFound.
  ///
  /// In en, this message translates to:
  /// **'No lyrics found for this track'**
  String get noLyricsFound;

  /// No description provided for @equalizer.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get equalizer;

  /// No description provided for @equalizerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'10-band EQ, bass boost, presets'**
  String get equalizerSubtitle;

  /// No description provided for @sleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep Timer'**
  String get sleepTimer;

  /// No description provided for @sleepTimerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto pause with gentle fade-out'**
  String get sleepTimerSubtitle;

  /// No description provided for @audioQuality.
  ///
  /// In en, this message translates to:
  /// **'Audio Quality'**
  String get audioQuality;

  /// No description provided for @speedAndPitch.
  ///
  /// In en, this message translates to:
  /// **'Speed & Pitch'**
  String get speedAndPitch;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @shuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @repeatOff.
  ///
  /// In en, this message translates to:
  /// **'Repeat Off'**
  String get repeatOff;

  /// No description provided for @repeatAll.
  ///
  /// In en, this message translates to:
  /// **'Repeat All'**
  String get repeatAll;

  /// No description provided for @repeatOne.
  ///
  /// In en, this message translates to:
  /// **'Repeat One'**
  String get repeatOne;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @tagEditor.
  ///
  /// In en, this message translates to:
  /// **'Edit Audio Tags'**
  String get tagEditor;

  /// No description provided for @setRingtone.
  ///
  /// In en, this message translates to:
  /// **'Set as Ringtone'**
  String get setRingtone;

  /// No description provided for @ringtoneSetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Ringtone set successfully'**
  String get ringtoneSetSuccess;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @noSongsFound.
  ///
  /// In en, this message translates to:
  /// **'No Songs Found'**
  String get noSongsFound;

  /// No description provided for @noSongsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan your local storage to find all offline music files.'**
  String get noSongsSubtitle;

  /// No description provided for @rescanLibrary.
  ///
  /// In en, this message translates to:
  /// **'Rescan Media Library'**
  String get rescanLibrary;

  /// No description provided for @rescanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan local storage for music files'**
  String get rescanSubtitle;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning audio files...'**
  String get scanning;

  /// No description provided for @scanCompleted.
  ///
  /// In en, this message translates to:
  /// **'Scan completed'**
  String get scanCompleted;

  /// No description provided for @permissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Permission Required'**
  String get permissionRequired;

  /// No description provided for @audioAccessRequired.
  ///
  /// In en, this message translates to:
  /// **'Audio access is required to display your music library.'**
  String get audioAccessRequired;

  /// No description provided for @grantAccess.
  ///
  /// In en, this message translates to:
  /// **'Grant Access'**
  String get grantAccess;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// No description provided for @privacyGuarantee.
  ///
  /// In en, this message translates to:
  /// **'100% Offline • Zero Telemetry • Local Storage'**
  String get privacyGuarantee;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Private & Offline'**
  String get onboardingTitle;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your music never leaves your device. No ads, no tracking, no accounts.'**
  String get onboardingSubtitle;

  /// No description provided for @createPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New Playlist'**
  String get createPlaylist;

  /// No description provided for @createSmartPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New Smart Playlist'**
  String get createSmartPlaylist;

  /// No description provided for @smartPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Smart Playlists'**
  String get smartPlaylists;

  /// No description provided for @editPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Edit Playlist'**
  String get editPlaylist;

  /// No description provided for @deletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete Playlist'**
  String get deletePlaylist;

  /// No description provided for @deletePlaylistPrompt.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this playlist?'**
  String get deletePlaylistPrompt;

  /// No description provided for @emptyPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No playlists created yet'**
  String get emptyPlaylists;

  /// No description provided for @emptyPlaylistsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create custom or smart playlists to organize your tracks'**
  String get emptyPlaylistsSubtitle;

  /// No description provided for @playlistName.
  ///
  /// In en, this message translates to:
  /// **'Playlist Name'**
  String get playlistName;

  /// No description provided for @enterPlaylistName.
  ///
  /// In en, this message translates to:
  /// **'Enter playlist name'**
  String get enterPlaylistName;

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to Playlist'**
  String get addToPlaylist;

  /// No description provided for @addedToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Added to playlist'**
  String get addedToPlaylist;

  /// No description provided for @removedFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Removed from playlist'**
  String get removedFromPlaylist;

  /// No description provided for @smartRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get smartRules;

  /// No description provided for @matchAllRules.
  ///
  /// In en, this message translates to:
  /// **'Match All Rules'**
  String get matchAllRules;

  /// No description provided for @matchAnyRule.
  ///
  /// In en, this message translates to:
  /// **'Match Any Rule'**
  String get matchAnyRule;

  /// No description provided for @addRule.
  ///
  /// In en, this message translates to:
  /// **'Add Rule'**
  String get addRule;

  /// No description provided for @ruleGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get ruleGenre;

  /// No description provided for @ruleYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get ruleYear;

  /// No description provided for @rulePlayCount.
  ///
  /// In en, this message translates to:
  /// **'Play Count'**
  String get rulePlayCount;

  /// No description provided for @ruleDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get ruleDuration;

  /// No description provided for @ruleRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get ruleRating;

  /// No description provided for @trackNumber.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get trackNumber;

  /// No description provided for @discNumber.
  ///
  /// In en, this message translates to:
  /// **'Disc'**
  String get discNumber;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year;

  /// No description provided for @genre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get genre;

  /// No description provided for @artist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get artist;

  /// No description provided for @albumArtist.
  ///
  /// In en, this message translates to:
  /// **'Album Artist'**
  String get albumArtist;

  /// No description provided for @album.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get album;

  /// No description provided for @songTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get songTitle;

  /// No description provided for @chooseArtwork.
  ///
  /// In en, this message translates to:
  /// **'Choose Artwork'**
  String get chooseArtwork;

  /// No description provided for @removeArtwork.
  ///
  /// In en, this message translates to:
  /// **'Remove Artwork'**
  String get removeArtwork;

  /// No description provided for @tagsSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Tags updated successfully'**
  String get tagsSavedSuccess;

  /// No description provided for @tagsSaveError.
  ///
  /// In en, this message translates to:
  /// **'Failed to update tags'**
  String get tagsSaveError;

  /// No description provided for @fileInfo.
  ///
  /// In en, this message translates to:
  /// **'File Information'**
  String get fileInfo;

  /// No description provided for @filePath.
  ///
  /// In en, this message translates to:
  /// **'File Path'**
  String get filePath;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @bitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get bitrate;

  /// No description provided for @sampleRate.
  ///
  /// In en, this message translates to:
  /// **'Sample Rate'**
  String get sampleRate;

  /// No description provided for @fileSize.
  ///
  /// In en, this message translates to:
  /// **'File Size'**
  String get fileSize;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Theme & Appearance'**
  String get appearance;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get appLanguage;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get arabic;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get spanish;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeAmoled.
  ///
  /// In en, this message translates to:
  /// **'Pure Black (AMOLED)'**
  String get themeAmoled;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get themeSystem;

  /// No description provided for @colorPalette.
  ///
  /// In en, this message translates to:
  /// **'Accent Color Source'**
  String get colorPalette;

  /// No description provided for @paletteMonet.
  ///
  /// In en, this message translates to:
  /// **'System Wallpaper (Material You)'**
  String get paletteMonet;

  /// No description provided for @paletteArtwork.
  ///
  /// In en, this message translates to:
  /// **'Album Artwork Accent'**
  String get paletteArtwork;

  /// No description provided for @paletteCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom Accent Color'**
  String get paletteCustom;

  /// No description provided for @customAccentColor.
  ///
  /// In en, this message translates to:
  /// **'Custom Accent Color'**
  String get customAccentColor;

  /// No description provided for @playerTheme.
  ///
  /// In en, this message translates to:
  /// **'Now Playing Style'**
  String get playerTheme;

  /// No description provided for @playerThemeClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic Deck'**
  String get playerThemeClassic;

  /// No description provided for @playerThemeCard.
  ///
  /// In en, this message translates to:
  /// **'Floating Card'**
  String get playerThemeCard;

  /// No description provided for @playerThemeCircle.
  ///
  /// In en, this message translates to:
  /// **'Vinyl Circle'**
  String get playerThemeCircle;

  /// No description provided for @playerThemeMinimal.
  ///
  /// In en, this message translates to:
  /// **'Pure Minimal'**
  String get playerThemeMinimal;

  /// No description provided for @visualizerStyle.
  ///
  /// In en, this message translates to:
  /// **'Audio Visualizer'**
  String get visualizerStyle;

  /// No description provided for @visualizerBar.
  ///
  /// In en, this message translates to:
  /// **'Frequency Bars'**
  String get visualizerBar;

  /// No description provided for @visualizerWave.
  ///
  /// In en, this message translates to:
  /// **'Smooth Wave'**
  String get visualizerWave;

  /// No description provided for @visualizerCircle.
  ///
  /// In en, this message translates to:
  /// **'Radial Pulse'**
  String get visualizerCircle;

  /// No description provided for @visualizerParticles.
  ///
  /// In en, this message translates to:
  /// **'Ambient Particles'**
  String get visualizerParticles;

  /// No description provided for @audioSettings.
  ///
  /// In en, this message translates to:
  /// **'Audio & Playback'**
  String get audioSettings;

  /// No description provided for @gaplessPlayback.
  ///
  /// In en, this message translates to:
  /// **'Gapless Playback'**
  String get gaplessPlayback;

  /// No description provided for @gaplessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Continuous audio without silence'**
  String get gaplessSubtitle;

  /// No description provided for @crossfade.
  ///
  /// In en, this message translates to:
  /// **'Crossfade Duration'**
  String get crossfade;

  /// No description provided for @resumeAfterInterruption.
  ///
  /// In en, this message translates to:
  /// **'Resume After Interruption'**
  String get resumeAfterInterruption;

  /// No description provided for @resumeAfterInterruptionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Resume after phone calls & notifications'**
  String get resumeAfterInterruptionSubtitle;

  /// No description provided for @waveformSeekBar.
  ///
  /// In en, this message translates to:
  /// **'Waveform Seek Bar'**
  String get waveformSeekBar;

  /// No description provided for @waveformSeekBarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Waveform visualization in the player'**
  String get waveformSeekBarSubtitle;

  /// No description provided for @replayGain.
  ///
  /// In en, this message translates to:
  /// **'ReplayGain Normalization'**
  String get replayGain;

  /// No description provided for @replayGainTrack.
  ///
  /// In en, this message translates to:
  /// **'Track Gain'**
  String get replayGainTrack;

  /// No description provided for @replayGainAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album Gain'**
  String get replayGainAlbum;

  /// No description provided for @replayGainOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get replayGainOff;

  /// No description provided for @preampWithRg.
  ///
  /// In en, this message translates to:
  /// **'Preamp with ReplayGain'**
  String get preampWithRg;

  /// No description provided for @preampWithoutRg.
  ///
  /// In en, this message translates to:
  /// **'Preamp without ReplayGain'**
  String get preampWithoutRg;

  /// No description provided for @librarySettings.
  ///
  /// In en, this message translates to:
  /// **'Library & Storage'**
  String get librarySettings;

  /// No description provided for @minDuration.
  ///
  /// In en, this message translates to:
  /// **'Minimum Track Duration'**
  String get minDuration;

  /// No description provided for @minDurationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide audio clips shorter than'**
  String get minDurationSubtitle;

  /// No description provided for @autoHideSystemMedia.
  ///
  /// In en, this message translates to:
  /// **'Auto-hide System Ringtone & Notifications'**
  String get autoHideSystemMedia;

  /// No description provided for @autoHideSystemMediaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Filter out non-music audio files'**
  String get autoHideSystemMediaSubtitle;

  /// No description provided for @hiddenFolders.
  ///
  /// In en, this message translates to:
  /// **'Excluded Folders'**
  String get hiddenFolders;

  /// No description provided for @hiddenFoldersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage excluded and hidden music folders'**
  String get hiddenFoldersSubtitle;

  /// No description provided for @networkAndProxy.
  ///
  /// In en, this message translates to:
  /// **'Network & Proxy'**
  String get networkAndProxy;

  /// No description provided for @proxySettings.
  ///
  /// In en, this message translates to:
  /// **'Proxy Settings'**
  String get proxySettings;

  /// No description provided for @enableProxy.
  ///
  /// In en, this message translates to:
  /// **'Enable Proxy'**
  String get enableProxy;

  /// No description provided for @proxyType.
  ///
  /// In en, this message translates to:
  /// **'Proxy Type'**
  String get proxyType;

  /// No description provided for @proxyHost.
  ///
  /// In en, this message translates to:
  /// **'Proxy Host'**
  String get proxyHost;

  /// No description provided for @proxyPort.
  ///
  /// In en, this message translates to:
  /// **'Proxy Port'**
  String get proxyPort;

  /// No description provided for @proxyUsername.
  ///
  /// In en, this message translates to:
  /// **'Username (Optional)'**
  String get proxyUsername;

  /// No description provided for @proxyPassword.
  ///
  /// In en, this message translates to:
  /// **'Password (Optional)'**
  String get proxyPassword;

  /// No description provided for @proxyBypass.
  ///
  /// In en, this message translates to:
  /// **'Bypass Hosts'**
  String get proxyBypass;

  /// No description provided for @testProxy.
  ///
  /// In en, this message translates to:
  /// **'Test Proxy Connection'**
  String get testProxy;

  /// No description provided for @proxySuccess.
  ///
  /// In en, this message translates to:
  /// **'Proxy connection successful'**
  String get proxySuccess;

  /// No description provided for @proxyFailed.
  ///
  /// In en, this message translates to:
  /// **'Proxy connection failed'**
  String get proxyFailed;

  /// No description provided for @extractorBackend.
  ///
  /// In en, this message translates to:
  /// **'Extractor & Backend Engine'**
  String get extractorBackend;

  /// No description provided for @backendUrl.
  ///
  /// In en, this message translates to:
  /// **'Backend Server URL'**
  String get backendUrl;

  /// No description provided for @backendToken.
  ///
  /// In en, this message translates to:
  /// **'Backend API Token'**
  String get backendToken;

  /// No description provided for @testBackend.
  ///
  /// In en, this message translates to:
  /// **'Test Backend Connection'**
  String get testBackend;

  /// No description provided for @backendSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backend connected successfully'**
  String get backendSuccess;

  /// No description provided for @backendFailed.
  ///
  /// In en, this message translates to:
  /// **'Backend connection failed'**
  String get backendFailed;

  /// No description provided for @engineAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic Selection'**
  String get engineAuto;

  /// No description provided for @engineRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote Yt-dlp Server'**
  String get engineRemote;

  /// No description provided for @engineOnDevice.
  ///
  /// In en, this message translates to:
  /// **'On-Device Extractor'**
  String get engineOnDevice;

  /// No description provided for @cloudSync.
  ///
  /// In en, this message translates to:
  /// **'Cloud Sync & Backup'**
  String get cloudSync;

  /// No description provided for @cloudSyncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync favorites, playlists, and settings across devices'**
  String get cloudSyncSubtitle;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign In with Google'**
  String get signInWithGoogle;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as'**
  String get signedInAs;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get syncNow;

  /// No description provided for @lastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced'**
  String get lastSynced;

  /// No description provided for @neverSynced.
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get neverSynced;

  /// No description provided for @backupToCloud.
  ///
  /// In en, this message translates to:
  /// **'Backup to Cloud'**
  String get backupToCloud;

  /// No description provided for @restoreFromCloud.
  ///
  /// In en, this message translates to:
  /// **'Restore from Cloud'**
  String get restoreFromCloud;

  /// No description provided for @exportBackupJson.
  ///
  /// In en, this message translates to:
  /// **'Export Backup File (JSON)'**
  String get exportBackupJson;

  /// No description provided for @importBackupJson.
  ///
  /// In en, this message translates to:
  /// **'Import Backup File (JSON)'**
  String get importBackupJson;

  /// No description provided for @backupCreated.
  ///
  /// In en, this message translates to:
  /// **'Backup created successfully'**
  String get backupCreated;

  /// No description provided for @backupRestored.
  ///
  /// In en, this message translates to:
  /// **'Backup restored successfully'**
  String get backupRestored;

  /// No description provided for @batteryOptimization.
  ///
  /// In en, this message translates to:
  /// **'Battery Optimization'**
  String get batteryOptimization;

  /// No description provided for @batteryOptimizationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Allow unrestricted background playback'**
  String get batteryOptimizationSubtitle;

  /// No description provided for @batteryOptimizationPrompt.
  ///
  /// In en, this message translates to:
  /// **'Disable battery restrictions for uninterrupted playback'**
  String get batteryOptimizationPrompt;

  /// No description provided for @requestWhitelist.
  ///
  /// In en, this message translates to:
  /// **'Disable Restrictions'**
  String get requestWhitelist;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About Pulsr'**
  String get about;

  /// No description provided for @aboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Premium offline music player'**
  String get aboutSubtitle;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get sourceCode;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @sortTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get sortTitle;

  /// No description provided for @sortArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get sortArtist;

  /// No description provided for @sortAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get sortAlbum;

  /// No description provided for @sortDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get sortDuration;

  /// No description provided for @sortDateAdded.
  ///
  /// In en, this message translates to:
  /// **'Date Added'**
  String get sortDateAdded;

  /// No description provided for @sortYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get sortYear;

  /// No description provided for @sortTrackCount.
  ///
  /// In en, this message translates to:
  /// **'Track Count'**
  String get sortTrackCount;

  /// No description provided for @sortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sortAscending;

  /// No description provided for @sortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sortDescending;

  /// No description provided for @playAll.
  ///
  /// In en, this message translates to:
  /// **'Play All'**
  String get playAll;

  /// No description provided for @shuffleAll.
  ///
  /// In en, this message translates to:
  /// **'Shuffle All'**
  String get shuffleAll;

  /// No description provided for @tracksCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 tracks} =1{1 track} other{{count} tracks}}'**
  String tracksCount(int count);

  /// No description provided for @albumsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 albums} =1{1 album} other{{count} albums}}'**
  String albumsCount(int count);

  /// No description provided for @durationFormat.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String durationFormat(int minutes, int seconds);

  /// No description provided for @scanResult.
  ///
  /// In en, this message translates to:
  /// **'Found {count} songs'**
  String scanResult(int count);

  /// No description provided for @deleteSongConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete this song from your device?'**
  String get deleteSongConfirmation;

  /// No description provided for @deleteMultipleConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete {count} songs from your device?'**
  String deleteMultipleConfirmation(int count);

  /// No description provided for @songDeleted.
  ///
  /// In en, this message translates to:
  /// **'Song deleted'**
  String get songDeleted;

  /// No description provided for @songsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Songs deleted'**
  String get songsDeleted;

  /// No description provided for @unknownSong.
  ///
  /// In en, this message translates to:
  /// **'Unknown Track'**
  String get unknownSong;

  /// No description provided for @unknownArtist.
  ///
  /// In en, this message translates to:
  /// **'Unknown Artist'**
  String get unknownArtist;

  /// No description provided for @unknownAlbum.
  ///
  /// In en, this message translates to:
  /// **'Unknown Album'**
  String get unknownAlbum;

  /// No description provided for @unknownGenre.
  ///
  /// In en, this message translates to:
  /// **'Unknown Genre'**
  String get unknownGenre;

  /// No description provided for @localMusic.
  ///
  /// In en, this message translates to:
  /// **'Local Music'**
  String get localMusic;

  /// No description provided for @onlineStream.
  ///
  /// In en, this message translates to:
  /// **'Online Stream'**
  String get onlineStream;

  /// No description provided for @likedTracks.
  ///
  /// In en, this message translates to:
  /// **'Liked tracks'**
  String get likedTracks;

  /// No description provided for @autoMix.
  ///
  /// In en, this message translates to:
  /// **'Auto-mix'**
  String get autoMix;

  /// No description provided for @topPlayedTracks.
  ///
  /// In en, this message translates to:
  /// **'Top played'**
  String get topPlayedTracks;

  /// No description provided for @audioAndPlayback.
  ///
  /// In en, this message translates to:
  /// **'Audio & Playback'**
  String get audioAndPlayback;

  /// No description provided for @playback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get playback;

  /// No description provided for @audioAndSound.
  ///
  /// In en, this message translates to:
  /// **'Audio & Sound'**
  String get audioAndSound;

  /// No description provided for @equalizerAndSoundEffects.
  ///
  /// In en, this message translates to:
  /// **'Equalizer & Sound Effects'**
  String get equalizerAndSoundEffects;

  /// No description provided for @themeAndAppearance.
  ///
  /// In en, this message translates to:
  /// **'Theme & Appearance'**
  String get themeAndAppearance;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get accentColor;

  /// No description provided for @nowPlayingTheme.
  ///
  /// In en, this message translates to:
  /// **'Now Playing Style'**
  String get nowPlayingTheme;

  /// No description provided for @colorSource.
  ///
  /// In en, this message translates to:
  /// **'Color Source'**
  String get colorSource;

  /// No description provided for @gestures.
  ///
  /// In en, this message translates to:
  /// **'Gestures'**
  String get gestures;

  /// No description provided for @miniPlayerSwipeLeft.
  ///
  /// In en, this message translates to:
  /// **'Mini Player Swipe Left'**
  String get miniPlayerSwipeLeft;

  /// No description provided for @miniPlayerSwipeRight.
  ///
  /// In en, this message translates to:
  /// **'Mini Player Swipe Right'**
  String get miniPlayerSwipeRight;

  /// No description provided for @nowPlayingDoubleTap.
  ///
  /// In en, this message translates to:
  /// **'Now Playing Double-Tap'**
  String get nowPlayingDoubleTap;

  /// No description provided for @artworkSwipe.
  ///
  /// In en, this message translates to:
  /// **'Artwork Swipe'**
  String get artworkSwipe;

  /// No description provided for @libraryAndScanning.
  ///
  /// In en, this message translates to:
  /// **'Library & Scanning'**
  String get libraryAndScanning;

  /// No description provided for @hiddenAndExcludedFolders.
  ///
  /// In en, this message translates to:
  /// **'Hidden & Excluded Folders'**
  String get hiddenAndExcludedFolders;

  /// No description provided for @shortAudioFilter.
  ///
  /// In en, this message translates to:
  /// **'Short Audio Filter'**
  String get shortAudioFilter;

  /// No description provided for @filterShortAudio.
  ///
  /// In en, this message translates to:
  /// **'Filter Short Audio'**
  String get filterShortAudio;

  /// No description provided for @excludeTracksUnder.
  ///
  /// In en, this message translates to:
  /// **'Exclude tracks under {seconds} seconds (filters voice notes):'**
  String excludeTracksUnder(int seconds);

  /// No description provided for @ignoreFilesUnder.
  ///
  /// In en, this message translates to:
  /// **'Ignore files under {seconds}s'**
  String ignoreFilesUnder(int seconds);

  /// No description provided for @youtubeMusicAndOnline.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music & Online'**
  String get youtubeMusicAndOnline;

  /// No description provided for @connectYtmAccount.
  ///
  /// In en, this message translates to:
  /// **'Connect YouTube Music Account'**
  String get connectYtmAccount;

  /// No description provided for @connectYtmSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to auto-sync your Liked Music library'**
  String get connectYtmSubtitle;

  /// No description provided for @ytmConnected.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music Connected'**
  String get ytmConnected;

  /// No description provided for @openYtmWeb.
  ///
  /// In en, this message translates to:
  /// **'Open YouTube Music Web'**
  String get openYtmWeb;

  /// No description provided for @openYtmWebSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse web player, explore charts, library & playlists'**
  String get openYtmWebSubtitle;

  /// No description provided for @offlineOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'Offline Only Mode'**
  String get offlineOnlyMode;

  /// No description provided for @offlineOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Disable online features, streaming & web queries'**
  String get offlineOnlySubtitle;

  /// No description provided for @wifiOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Only Mode'**
  String get wifiOnlyMode;

  /// No description provided for @wifiOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only stream and download when on Wi-Fi'**
  String get wifiOnlySubtitle;

  /// No description provided for @searchYtm.
  ///
  /// In en, this message translates to:
  /// **'Search YouTube Music'**
  String get searchYtm;

  /// No description provided for @searchYtmSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Search, stream & download songs'**
  String get searchYtmSubtitle;

  /// No description provided for @streamingQuality.
  ///
  /// In en, this message translates to:
  /// **'Streaming Quality'**
  String get streamingQuality;

  /// No description provided for @downloadQuality.
  ///
  /// In en, this message translates to:
  /// **'Download Quality'**
  String get downloadQuality;

  /// No description provided for @extractionEngine.
  ///
  /// In en, this message translates to:
  /// **'Extraction Engine'**
  String get extractionEngine;

  /// No description provided for @ytdlpConfig.
  ///
  /// In en, this message translates to:
  /// **'yt-dlp Server Config'**
  String get ytdlpConfig;

  /// No description provided for @storageAndCache.
  ///
  /// In en, this message translates to:
  /// **'Storage & Cache'**
  String get storageAndCache;

  /// No description provided for @privacyAndData.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Data'**
  String get privacyAndData;

  /// No description provided for @privacyGuaranteeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'100% offline. Zero telemetry, zero tracking.'**
  String get privacyGuaranteeSubtitle;

  /// No description provided for @aboutAppSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version 1.0.0 • Pure Offline Sound'**
  String get aboutAppSubtitle;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @lastSyncedJustNow.
  ///
  /// In en, this message translates to:
  /// **'Last synced: Just now'**
  String get lastSyncedJustNow;

  /// No description provided for @lastSyncedMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'Last synced: {minutes}m ago'**
  String lastSyncedMinutesAgo(int minutes);

  /// No description provided for @lastSyncedHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'Last synced: {hours}h ago'**
  String lastSyncedHoursAgo(int hours);

  /// No description provided for @connectedReadyToSync.
  ///
  /// In en, this message translates to:
  /// **'Connected • Ready to sync'**
  String get connectedReadyToSync;

  /// No description provided for @downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloaded;

  /// No description provided for @exploreOnlineMusic.
  ///
  /// In en, this message translates to:
  /// **'Explore Online Music'**
  String get exploreOnlineMusic;

  /// No description provided for @noDownloadsYet.
  ///
  /// In en, this message translates to:
  /// **'No Downloads Yet'**
  String get noDownloadsYet;

  /// No description provided for @noDownloadsYetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download your favorite songs from YouTube Music to listen offline anywhere.'**
  String get noDownloadsYetSubtitle;

  /// No description provided for @offlineDownloads.
  ///
  /// In en, this message translates to:
  /// **'Offline Downloads'**
  String get offlineDownloads;

  /// No description provided for @local.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get local;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @syncYouTubeMusic.
  ///
  /// In en, this message translates to:
  /// **'Sync YouTube Music'**
  String get syncYouTubeMusic;

  /// No description provided for @importByPlaylistLink.
  ///
  /// In en, this message translates to:
  /// **'Import by Playlist Link'**
  String get importByPlaylistLink;

  /// No description provided for @noLocalFavorites.
  ///
  /// In en, this message translates to:
  /// **'No Local Favorites'**
  String get noLocalFavorites;

  /// No description provided for @noLocalFavoritesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart icon on any of your local tracks to add them here.'**
  String get noLocalFavoritesSubtitle;

  /// No description provided for @noOnlineFavorites.
  ///
  /// In en, this message translates to:
  /// **'No Online Favorites'**
  String get noOnlineFavorites;

  /// No description provided for @scanStorage.
  ///
  /// In en, this message translates to:
  /// **'Scan Storage'**
  String get scanStorage;

  /// No description provided for @noFoldersFound.
  ///
  /// In en, this message translates to:
  /// **'No Folders Found'**
  String get noFoldersFound;

  /// No description provided for @noFoldersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan device storage to discover music directories and organize by path.'**
  String get noFoldersSubtitle;

  /// No description provided for @playNext.
  ///
  /// In en, this message translates to:
  /// **'Play Next'**
  String get playNext;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @importM3u.
  ///
  /// In en, this message translates to:
  /// **'Import M3U'**
  String get importM3u;

  /// No description provided for @syncOnlineLibrary.
  ///
  /// In en, this message translates to:
  /// **'Sync Online Library'**
  String get syncOnlineLibrary;

  /// No description provided for @addPlaylistUrl.
  ///
  /// In en, this message translates to:
  /// **'Add Playlist URL'**
  String get addPlaylistUrl;

  /// No description provided for @addYouTubePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add YouTube Playlist'**
  String get addYouTubePlaylist;

  /// No description provided for @playlistImported.
  ///
  /// In en, this message translates to:
  /// **'Playlist Imported'**
  String get playlistImported;

  /// No description provided for @tracksMatched.
  ///
  /// In en, this message translates to:
  /// **'{matched} of {total} tracks matched.'**
  String tracksMatched(int matched, int total);

  /// No description provided for @fetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get fetch;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @tracksCountPlural.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{track} other{tracks}}'**
  String tracksCountPlural(int count);

  /// No description provided for @noTrackSelected.
  ///
  /// In en, this message translates to:
  /// **'No Track Selected'**
  String get noTrackSelected;

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback Speed'**
  String get playbackSpeed;

  /// No description provided for @vinylCircle.
  ///
  /// In en, this message translates to:
  /// **'Vinyl Circle'**
  String get vinylCircle;

  /// No description provided for @sortAndFilter.
  ///
  /// In en, this message translates to:
  /// **'Sort & Filter'**
  String get sortAndFilter;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @qualityAndCodec.
  ///
  /// In en, this message translates to:
  /// **'QUALITY & CODEC'**
  String get qualityAndCodec;

  /// No description provided for @audioFormat.
  ///
  /// In en, this message translates to:
  /// **'Audio Format'**
  String get audioFormat;

  /// No description provided for @channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channels;

  /// No description provided for @playCount.
  ///
  /// In en, this message translates to:
  /// **'Play Count'**
  String get playCount;

  /// No description provided for @ringtone.
  ///
  /// In en, this message translates to:
  /// **'Ringtone'**
  String get ringtone;

  /// No description provided for @editTags.
  ///
  /// In en, this message translates to:
  /// **'Edit Tags'**
  String get editTags;

  /// No description provided for @setAudioAs.
  ///
  /// In en, this message translates to:
  /// **'Set Audio As'**
  String get setAudioAs;

  /// No description provided for @phoneRingtone.
  ///
  /// In en, this message translates to:
  /// **'Phone Ringtone'**
  String get phoneRingtone;

  /// No description provided for @notificationSound.
  ///
  /// In en, this message translates to:
  /// **'Notification Sound'**
  String get notificationSound;

  /// No description provided for @alarmSound.
  ///
  /// In en, this message translates to:
  /// **'Alarm Sound'**
  String get alarmSound;

  /// No description provided for @turnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn Off'**
  String get turnOff;

  /// No description provided for @presets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presets;

  /// No description provided for @customTime.
  ///
  /// In en, this message translates to:
  /// **'Custom Time'**
  String get customTime;

  /// No description provided for @stopAtSpecificTime.
  ///
  /// In en, this message translates to:
  /// **'Stop at specific time'**
  String get stopAtSpecificTime;

  /// No description provided for @currentSpeed.
  ///
  /// In en, this message translates to:
  /// **'Current speed: {speed}'**
  String currentSpeed(String speed);

  /// No description provided for @addedTo.
  ///
  /// In en, this message translates to:
  /// **'Added to {name}'**
  String addedTo(String name);

  /// No description provided for @playCountTimes.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{time} other{times}}'**
  String playCountTimes(int count);

  /// No description provided for @pastePlaylistUrl.
  ///
  /// In en, this message translates to:
  /// **'Paste YouTube Playlist URL or ID'**
  String get pastePlaylistUrl;

  /// No description provided for @hideCustomFolder.
  ///
  /// In en, this message translates to:
  /// **'Hide Custom Folder'**
  String get hideCustomFolder;

  /// No description provided for @hideFolderDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter the full directory path you want to hide from your music library:'**
  String get hideFolderDesc;

  /// No description provided for @hideFolder.
  ///
  /// In en, this message translates to:
  /// **'Hide Folder'**
  String get hideFolder;

  /// No description provided for @confirmRestore.
  ///
  /// In en, this message translates to:
  /// **'Confirm Restore'**
  String get confirmRestore;

  /// No description provided for @confirmRestoreDesc.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to restore backup data from this file?'**
  String get confirmRestoreDesc;

  /// No description provided for @existingLibraryUpdateNotice.
  ///
  /// In en, this message translates to:
  /// **'Existing library matching tracks will be updated.'**
  String get existingLibraryUpdateNotice;

  /// No description provided for @audioVisualizerPermission.
  ///
  /// In en, this message translates to:
  /// **'Audio Visualizer Permission'**
  String get audioVisualizerPermission;

  /// No description provided for @audioVisualizerPermissionDesc.
  ///
  /// In en, this message translates to:
  /// **'The visualizer reads audio output, not your microphone. Android requires the Record Audio permission to process frequency data.'**
  String get audioVisualizerPermissionDesc;

  /// No description provided for @useSimulation.
  ///
  /// In en, this message translates to:
  /// **'Use Simulation'**
  String get useSimulation;

  /// No description provided for @visualizerSimulationNotice.
  ///
  /// In en, this message translates to:
  /// **'Visualizer permission denied — showing a simulated animation instead.'**
  String get visualizerSimulationNotice;

  /// No description provided for @ytmAccount.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music Account'**
  String get ytmAccount;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @openWebPlayer.
  ///
  /// In en, this message translates to:
  /// **'Open Web Player'**
  String get openWebPlayer;

  /// No description provided for @ytdlpServerConfig.
  ///
  /// In en, this message translates to:
  /// **'yt-dlp Server Config'**
  String get ytdlpServerConfig;

  /// No description provided for @ytdlpServerDesc.
  ///
  /// In en, this message translates to:
  /// **'Connects Pulsr to a remote yt-dlp backend with rotating proxies to bypass YouTube bot detection and IP bans.'**
  String get ytdlpServerDesc;

  /// No description provided for @downloadsTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadsTitle;

  /// No description provided for @noDownloadsTitle.
  ///
  /// In en, this message translates to:
  /// **'No downloads yet'**
  String get noDownloadsTitle;

  /// No description provided for @noDownloadsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Songs downloaded for offline playback will appear here.'**
  String get noDownloadsSubtitle;

  /// No description provided for @statusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get statusQueued;

  /// No description provided for @statusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get statusDownloading;

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get statusPaused;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @storageUsed.
  ///
  /// In en, this message translates to:
  /// **'Storage Used'**
  String get storageUsed;

  /// No description provided for @storageFree.
  ///
  /// In en, this message translates to:
  /// **'Free Space'**
  String get storageFree;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @downloadErrorNoSpace.
  ///
  /// In en, this message translates to:
  /// **'Storage full — free up space and retry'**
  String get downloadErrorNoSpace;

  /// No description provided for @downloadErrorStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage full — free up space and retry'**
  String get downloadErrorStorage;

  /// No description provided for @downloadErrorPermission.
  ///
  /// In en, this message translates to:
  /// **'Storage permission denied. Please grant permission in Settings.'**
  String get downloadErrorPermission;

  /// No description provided for @downloadErrorInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Download was interrupted. Tap to resume.'**
  String get downloadErrorInterrupted;

  /// No description provided for @downloadErrorDisabled.
  ///
  /// In en, this message translates to:
  /// **'Downloads are disabled or unavailable in this build.'**
  String get downloadErrorDisabled;

  /// No description provided for @downloadErrorTransition.
  ///
  /// In en, this message translates to:
  /// **'Invalid download state transition.'**
  String get downloadErrorTransition;

  /// No description provided for @downloadErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'YouTube is busy. Cooling down…'**
  String get downloadErrorRateLimited;

  /// No description provided for @downloadErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your network.'**
  String get downloadErrorNetwork;

  /// No description provided for @downloadErrorBotChallenge.
  ///
  /// In en, this message translates to:
  /// **'YouTube verification triggered. Retrying…'**
  String get downloadErrorBotChallenge;

  /// No description provided for @downloadErrorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This track is unavailable.'**
  String get downloadErrorUnavailable;

  /// No description provided for @downloadWifiOnly.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi Only Mode is active. Connect to Wi-Fi to download.'**
  String get downloadWifiOnly;

  /// No description provided for @downloadErrorAlreadyQueued.
  ///
  /// In en, this message translates to:
  /// **'This song is already in the download queue.'**
  String get downloadErrorAlreadyQueued;

  /// No description provided for @downloadErrorCorrupt.
  ///
  /// In en, this message translates to:
  /// **'Downloaded file was corrupted or incomplete. Please retry.'**
  String get downloadErrorCorrupt;

  /// No description provided for @downloadErrorInvalidTransition.
  ///
  /// In en, this message translates to:
  /// **'Invalid download state transition.'**
  String get downloadErrorInvalidTransition;

  /// No description provided for @downloadErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Download timed out. Please retry.'**
  String get downloadErrorTimeout;

  /// No description provided for @dspEnginePreference.
  ///
  /// In en, this message translates to:
  /// **'DSP Engine Preference'**
  String get dspEnginePreference;

  /// No description provided for @dspEnginePreferenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose real-time DSP engine or OEM system sound effects'**
  String get dspEnginePreferenceSubtitle;

  /// No description provided for @dspEngineNative.
  ///
  /// In en, this message translates to:
  /// **'Native Studio DSP (Zero Latency)'**
  String get dspEngineNative;

  /// No description provided for @dspEngineOem.
  ///
  /// In en, this message translates to:
  /// **'OEM / System AudioFX'**
  String get dspEngineOem;

  /// No description provided for @dspEngineAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic (Prefer Native)'**
  String get dspEngineAuto;

  /// No description provided for @audioStageDegraded.
  ///
  /// In en, this message translates to:
  /// **'Audio stage \"{stage}\" was bypassed to prevent stutter under high load.'**
  String audioStageDegraded(String stage);

  /// No description provided for @stageEq.
  ///
  /// In en, this message translates to:
  /// **'Parametric EQ'**
  String get stageEq;

  /// No description provided for @stageReverb.
  ///
  /// In en, this message translates to:
  /// **'Convolution Reverb'**
  String get stageReverb;

  /// No description provided for @stageCrossfeed.
  ///
  /// In en, this message translates to:
  /// **'Crossfeed'**
  String get stageCrossfeed;

  /// No description provided for @stageLimiter.
  ///
  /// In en, this message translates to:
  /// **'Lookahead Limiter'**
  String get stageLimiter;

  /// No description provided for @stageResampler.
  ///
  /// In en, this message translates to:
  /// **'Resampler'**
  String get stageResampler;

  /// No description provided for @stagePanner.
  ///
  /// In en, this message translates to:
  /// **'Spatial Panner'**
  String get stagePanner;

  /// No description provided for @dspSaturationTitle.
  ///
  /// In en, this message translates to:
  /// **'Harmonic Saturation'**
  String get dspSaturationTitle;

  /// No description provided for @dspSaturationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tube/tape-style harmonic exciter'**
  String get dspSaturationSubtitle;

  /// No description provided for @dspSaturationDrive.
  ///
  /// In en, this message translates to:
  /// **'Drive'**
  String get dspSaturationDrive;

  /// No description provided for @dspSaturationMix.
  ///
  /// In en, this message translates to:
  /// **'Mix'**
  String get dspSaturationMix;

  /// No description provided for @dspSaturationTilt.
  ///
  /// In en, this message translates to:
  /// **'Tilt Emphasis'**
  String get dspSaturationTilt;

  /// No description provided for @dspStereoWidthTitle.
  ///
  /// In en, this message translates to:
  /// **'Stereo Width'**
  String get dspStereoWidthTitle;

  /// No description provided for @dspStereoWidthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Independent Mid/Side field control'**
  String get dspStereoWidthSubtitle;

  /// No description provided for @dspStereoWidthAmount.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get dspStereoWidthAmount;

  /// No description provided for @dspLoudnessTitle.
  ///
  /// In en, this message translates to:
  /// **'Loudness Contour'**
  String get dspLoudnessTitle;

  /// No description provided for @dspLoudnessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fletcher–Munson volume-linked tone compensation'**
  String get dspLoudnessSubtitle;

  /// No description provided for @dspLoudnessIntensity.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get dspLoudnessIntensity;

  /// No description provided for @dspLoudnessReplayGainNote.
  ///
  /// In en, this message translates to:
  /// **'Complements ReplayGain: ReplayGain levels loudness across tracks, while this contour adapts tone to your listening volume.'**
  String get dspLoudnessReplayGainNote;

  /// No description provided for @dspSubCrossoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Subwoofer Crossover'**
  String get dspSubCrossoverTitle;

  /// No description provided for @dspSubCrossoverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bass redirection into a summed mono sub tap'**
  String get dspSubCrossoverSubtitle;

  /// No description provided for @dspSubCrossoverCorner.
  ///
  /// In en, this message translates to:
  /// **'Crossover Corner'**
  String get dspSubCrossoverCorner;

  /// No description provided for @dspSubCrossoverSubLevel.
  ///
  /// In en, this message translates to:
  /// **'Sub Level'**
  String get dspSubCrossoverSubLevel;

  /// No description provided for @dspSubCrossoverNote.
  ///
  /// In en, this message translates to:
  /// **'Bass redirection: a low-passed mono sum is added to both channels — this is not true multichannel LFE routing.'**
  String get dspSubCrossoverNote;

  /// No description provided for @dspDynamicEqTitle.
  ///
  /// In en, this message translates to:
  /// **'Dynamic EQ'**
  String get dspDynamicEqTitle;

  /// No description provided for @dspDynamicEqSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cuts resonances only when band energy exceeds the threshold'**
  String get dspDynamicEqSubtitle;

  /// No description provided for @dspDynamicEqFrequency.
  ///
  /// In en, this message translates to:
  /// **'Band Frequency'**
  String get dspDynamicEqFrequency;

  /// No description provided for @dspDynamicEqThreshold.
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get dspDynamicEqThreshold;

  /// No description provided for @dspDynamicEqRatio.
  ///
  /// In en, this message translates to:
  /// **'Ratio'**
  String get dspDynamicEqRatio;

  /// No description provided for @dspDynamicEqAttack.
  ///
  /// In en, this message translates to:
  /// **'Attack'**
  String get dspDynamicEqAttack;

  /// No description provided for @dspDynamicEqRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get dspDynamicEqRelease;

  /// No description provided for @dspDynamicEqMaxCut.
  ///
  /// In en, this message translates to:
  /// **'Max Cut'**
  String get dspDynamicEqMaxCut;

  /// No description provided for @blockedByBitPerfectShort.
  ///
  /// In en, this message translates to:
  /// **'Blocked by Bit-Perfect'**
  String get blockedByBitPerfectShort;

  /// No description provided for @rcTitle.
  ///
  /// In en, this message translates to:
  /// **'Room Correction'**
  String get rcTitle;

  /// No description provided for @rcSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Measure your room with a short tone sweep and fit an EQ that flattens the response'**
  String get rcSubtitle;

  /// No description provided for @rcStart.
  ///
  /// In en, this message translates to:
  /// **'Start measurement'**
  String get rcStart;

  /// No description provided for @rcMeasuring.
  ///
  /// In en, this message translates to:
  /// **'Measuring - stay quiet...'**
  String get rcMeasuring;

  /// No description provided for @rcResult.
  ///
  /// In en, this message translates to:
  /// **'Measured response (top) and fitted correction (bottom)'**
  String get rcResult;

  /// No description provided for @rcApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get rcApply;

  /// No description provided for @rcDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get rcDiscard;

  /// No description provided for @rcMicNeeded.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required for the measurement'**
  String get rcMicNeeded;

  /// No description provided for @rcQuietHint.
  ///
  /// In en, this message translates to:
  /// **'Keep the room quiet and let the sweep play out loud at your normal listening level'**
  String get rcQuietHint;

  /// No description provided for @rcKeepPlayerPaused.
  ///
  /// In en, this message translates to:
  /// **'Music playback stays paused while Room Correction is active'**
  String get rcKeepPlayerPaused;

  /// No description provided for @rcApplied.
  ///
  /// In en, this message translates to:
  /// **'Room Correction preset applied'**
  String get rcApplied;

  /// No description provided for @deviceProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Device Profiles'**
  String get deviceProfilesTitle;

  /// No description provided for @deviceProfilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sound settings remembered per output device'**
  String get deviceProfilesSubtitle;

  /// No description provided for @autoDeviceSwitch.
  ///
  /// In en, this message translates to:
  /// **'Auto-switch on device change'**
  String get autoDeviceSwitch;

  /// No description provided for @noDevicesSeen.
  ///
  /// In en, this message translates to:
  /// **'No output devices seen yet'**
  String get noDevicesSeen;

  /// No description provided for @applyProfileNow.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyProfileNow;

  /// No description provided for @forgetDevice.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get forgetDevice;

  /// No description provided for @currentDeviceBadge.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get currentDeviceBadge;

  /// No description provided for @profileDropdownLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileDropdownLabel;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @downloadDeletedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{title}\"'**
  String downloadDeletedSnackbar(String title);

  /// No description provided for @statusEmbedding.
  ///
  /// In en, this message translates to:
  /// **'Embedding tags…'**
  String get statusEmbedding;

  /// No description provided for @etaLabel.
  ///
  /// In en, this message translates to:
  /// **'ETA: {seconds}s'**
  String etaLabel(int seconds);

  /// No description provided for @downloadTileSemantics.
  ///
  /// In en, this message translates to:
  /// **'{title} {artist} {status} {progress}'**
  String downloadTileSemantics(
      String title, String artist, String status, String progress);

  /// No description provided for @downloadActionsSemantics.
  ///
  /// In en, this message translates to:
  /// **'Download actions for {title}'**
  String downloadActionsSemantics(String title);

  /// No description provided for @systemEffectsTitle.
  ///
  /// In en, this message translates to:
  /// **'System Audio Effects (Dolby Atmos / DAP)'**
  String get systemEffectsTitle;

  /// No description provided for @systemEffectsSubtitleBypassed.
  ///
  /// In en, this message translates to:
  /// **'✓ Bypassed: System effects disabled on output-mix session'**
  String get systemEffectsSubtitleBypassed;

  /// No description provided for @systemEffectsSubtitleActive.
  ///
  /// In en, this message translates to:
  /// **'Active: OEM sound effects are processing audio'**
  String get systemEffectsSubtitleActive;

  /// No description provided for @systemEffectsSubtitleUnsupported.
  ///
  /// In en, this message translates to:
  /// **'No OEM Dolby/DAP detected on this device'**
  String get systemEffectsSubtitleUnsupported;

  /// No description provided for @systemEffectsAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get systemEffectsAuto;

  /// No description provided for @systemEffectsTryDisable.
  ///
  /// In en, this message translates to:
  /// **'Try to disable'**
  String get systemEffectsTryDisable;

  /// No description provided for @systemEffectsLeaveOn.
  ///
  /// In en, this message translates to:
  /// **'Leave on'**
  String get systemEffectsLeaveOn;

  /// No description provided for @bluetoothLatencyTitle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth Latency Sync (AVRCP / Lyrics)'**
  String get bluetoothLatencyTitle;

  /// No description provided for @bluetoothLatencySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Compensates for Bluetooth audio codec buffer latency ({offset} ms). Volume deferral: AVRCP absolute volume active.'**
  String bluetoothLatencySubtitle(int offset);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
