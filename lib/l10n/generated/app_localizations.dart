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
  /// **'Size'**
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
