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

  /// No description provided for @customDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'Custom duration (minutes).'**
  String get customDurationMinutes;

  /// No description provided for @partialBatchDetected.
  ///
  /// In en, this message translates to:
  /// **'Partial batch detected'**
  String get partialBatchDetected;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @saveSearch.
  ///
  /// In en, this message translates to:
  /// **'Save Search'**
  String get saveSearch;

  /// No description provided for @savedSearches.
  ///
  /// In en, this message translates to:
  /// **'Saved Searches'**
  String get savedSearches;

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

  /// No description provided for @clearSearchQuery.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearchQuery;

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

  /// detail sort
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

  /// No description provided for @seekLabel.
  ///
  /// In en, this message translates to:
  /// **'Seek'**
  String get seekLabel;

  /// No description provided for @homeOfflineNotice.
  ///
  /// In en, this message translates to:
  /// **'Offline mode — online streaming is disabled in Settings.'**
  String get homeOfflineNotice;

  /// No description provided for @homePermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Permission Needed'**
  String get homePermissionNeeded;

  /// No description provided for @homePermissionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Grant audio or storage permission so Pulsr can index and play your offline music collection with bit-perfect quality.'**
  String get homePermissionSubtitle;

  /// No description provided for @homeGrantPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant Permission'**
  String get homeGrantPermission;

  /// No description provided for @homeScanningLabel.
  ///
  /// In en, this message translates to:
  /// **'Scanning...'**
  String get homeScanningLabel;

  /// No description provided for @homeScanProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}% indexed • Building your local music catalog'**
  String homeScanProgress(int percent);

  /// No description provided for @homeScanningStorageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Searching device directories for audio files...'**
  String get homeScanningStorageSubtitle;

  /// No description provided for @jumpToCategory.
  ///
  /// In en, this message translates to:
  /// **'Jump to Category'**
  String get jumpToCategory;

  /// No description provided for @sidebarBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get sidebarBrowse;

  /// No description provided for @sidebarCollection.
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get sidebarCollection;

  /// No description provided for @sidebarPanel.
  ///
  /// In en, this message translates to:
  /// **'Panel'**
  String get sidebarPanel;

  /// No description provided for @sidebarSidePanel.
  ///
  /// In en, this message translates to:
  /// **'Side Panel'**
  String get sidebarSidePanel;

  /// No description provided for @sidebarExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand sidebar'**
  String get sidebarExpand;

  /// No description provided for @sidebarCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar'**
  String get sidebarCollapse;

  /// No description provided for @exportFormatWinampLabel.
  ///
  /// In en, this message translates to:
  /// **'Winamp / Poweramp'**
  String get exportFormatWinampLabel;

  /// No description provided for @exportFormatWmpLabel.
  ///
  /// In en, this message translates to:
  /// **'Windows Media Player'**
  String get exportFormatWmpLabel;

  /// No description provided for @libraryGridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get libraryGridView;

  /// No description provided for @libraryListView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get libraryListView;

  /// No description provided for @pressBackAgainToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get pressBackAgainToExit;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @learnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn more'**
  String get learnMore;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// No description provided for @authUseCodeSignIn.
  ///
  /// In en, this message translates to:
  /// **'Having trouble? Use code sign-in instead'**
  String get authUseCodeSignIn;

  /// No description provided for @castAndroidOnly.
  ///
  /// In en, this message translates to:
  /// **'Casting is available on Android only in this build.'**
  String get castAndroidOnly;

  /// No description provided for @castDirectDeviceMode.
  ///
  /// In en, this message translates to:
  /// **'Direct device mode: casts the current track. Queue and remote volume need the Cast SDK.'**
  String get castDirectDeviceMode;

  /// No description provided for @playbackPresetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Playback presets'**
  String get playbackPresetsTitle;

  /// No description provided for @playbackPresetsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One-tap tuning for quality, balance or data saving'**
  String get playbackPresetsSubtitle;

  /// No description provided for @playbackPresetMaxQuality.
  ///
  /// In en, this message translates to:
  /// **'Max Quality'**
  String get playbackPresetMaxQuality;

  /// No description provided for @playbackPresetSmooth.
  ///
  /// In en, this message translates to:
  /// **'Smooth'**
  String get playbackPresetSmooth;

  /// No description provided for @playbackPresetDataSaver.
  ///
  /// In en, this message translates to:
  /// **'Data Saver'**
  String get playbackPresetDataSaver;

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

  /// No description provided for @visualizerCpuFallbackBadge.
  ///
  /// In en, this message translates to:
  /// **'CPU fallback — GPU visualiser unavailable'**
  String get visualizerCpuFallbackBadge;

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

  /// No description provided for @downloadOfflineOnly.
  ///
  /// In en, this message translates to:
  /// **'Offline Only Mode is active. Turn it off in Settings to download.'**
  String get downloadOfflineOnly;

  /// No description provided for @settingsDownloadConcurrent.
  ///
  /// In en, this message translates to:
  /// **'Concurrent downloads'**
  String get settingsDownloadConcurrent;

  /// No description provided for @settingsDownloadConcurrentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Maximum tracks downloading at the same time (1-5).'**
  String get settingsDownloadConcurrentSubtitle;

  /// No description provided for @settingsDownloadLocation.
  ///
  /// In en, this message translates to:
  /// **'Download location'**
  String get settingsDownloadLocation;

  /// No description provided for @settingsDownloadLocationUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Custom download locations are not supported yet. Files are saved to the Music folder.'**
  String get settingsDownloadLocationUnsupported;

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

  /// No description provided for @themeScheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Dark hours'**
  String get themeScheduleTitle;

  /// No description provided for @themeScheduleStartLabel.
  ///
  /// In en, this message translates to:
  /// **'Dark from'**
  String get themeScheduleStartLabel;

  /// No description provided for @themeScheduleEndLabel.
  ///
  /// In en, this message translates to:
  /// **'Light from'**
  String get themeScheduleEndLabel;

  /// No description provided for @themeScheduleHour.
  ///
  /// In en, this message translates to:
  /// **'{hour}:00'**
  String themeScheduleHour(int hour);

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

  /// No description provided for @customProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get customProfilesTitle;

  /// No description provided for @profileCreateFromCurrent.
  ///
  /// In en, this message translates to:
  /// **'Save current sound as profile'**
  String get profileCreateFromCurrent;

  /// No description provided for @profileNameHint.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get profileNameHint;

  /// No description provided for @profileCreated.
  ///
  /// In en, this message translates to:
  /// **'Profile \"{name}\" saved'**
  String profileCreated(String name);

  /// No description provided for @profileDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete profile \"{name}\"?'**
  String profileDeleteConfirm(String name);

  /// No description provided for @profileBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get profileBuiltIn;

  /// No description provided for @smartAudioTitle.
  ///
  /// In en, this message translates to:
  /// **'Smart Audio'**
  String get smartAudioTitle;

  /// No description provided for @smartAudioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically tune the sound to your headphones and track'**
  String get smartAudioSubtitle;

  /// No description provided for @smartAudioModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get smartAudioModeLabel;

  /// No description provided for @smartAudioAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get smartAudioAuto;

  /// No description provided for @smartAudioManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get smartAudioManual;

  /// No description provided for @smartAudioAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Detect the connected headphones, apply the matching AutoEQ correction, and use the highest output quality the device supports'**
  String get smartAudioAutoDesc;

  /// No description provided for @smartAudioManualDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep your EQ, effects and output quality exactly as you set them'**
  String get smartAudioManualDesc;

  /// No description provided for @smartAudioDetectedDevice.
  ///
  /// In en, this message translates to:
  /// **'Current output: {device}'**
  String smartAudioDetectedDevice(String device);

  /// No description provided for @smartAudioMatchedProfile.
  ///
  /// In en, this message translates to:
  /// **'Matched correction: {profile}'**
  String smartAudioMatchedProfile(String profile);

  /// No description provided for @smartAudioNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No headphone correction matched for this device'**
  String get smartAudioNoMatch;

  /// No description provided for @smartAudioAutoCatchAllHint.
  ///
  /// In en, this message translates to:
  /// **'Auto only adjusts sound when it recognises your headphones or a manual device profile; your choices are never overwritten in Manual mode'**
  String get smartAudioAutoCatchAllHint;

  /// No description provided for @experienceModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Experience Mode'**
  String get experienceModeTitle;

  /// No description provided for @experienceModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose how much control you want'**
  String get experienceModeSubtitle;

  /// No description provided for @experienceModeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get experienceModeNormal;

  /// No description provided for @experienceModeProfessional.
  ///
  /// In en, this message translates to:
  /// **'Professional'**
  String get experienceModeProfessional;

  /// No description provided for @experienceModeNormalDesc.
  ///
  /// In en, this message translates to:
  /// **'Smart and simple — Pulsr tunes the sound to your headphones and picks the best quality automatically'**
  String get experienceModeNormalDesc;

  /// No description provided for @experienceModeProfessionalDesc.
  ///
  /// In en, this message translates to:
  /// **'Full control over every DSP stage, output format and diagnostic option'**
  String get experienceModeProfessionalDesc;

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
  /// **'Compensates for Bluetooth audio codec buffer latency ({offset} ms). Media controls use the system notification; no AVRCP volume override.'**
  String bluetoothLatencySubtitle(int offset);

  /// No description provided for @pageNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Page Not Found'**
  String get pageNotFoundTitle;

  /// No description provided for @pageNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'No page found at {path}'**
  String pageNotFoundMessage(String path);

  /// No description provided for @goHome.
  ///
  /// In en, this message translates to:
  /// **'Go Home'**
  String get goHome;

  /// No description provided for @resetToDefault30s.
  ///
  /// In en, this message translates to:
  /// **'Reset to default (30s)'**
  String get resetToDefault30s;

  /// No description provided for @autoFilteringVoiceMemos.
  ///
  /// In en, this message translates to:
  /// **'Auto-filtering voice memos • Custom paths'**
  String get autoFilteringVoiceMemos;

  /// No description provided for @manageExcludedDirectories.
  ///
  /// In en, this message translates to:
  /// **'Manage excluded directories'**
  String get manageExcludedDirectories;

  /// No description provided for @scanningStorage.
  ///
  /// In en, this message translates to:
  /// **'Scanning storage…'**
  String get scanningStorage;

  /// No description provided for @lastScanTracks.
  ///
  /// In en, this message translates to:
  /// **'Last scan: {count} tracks'**
  String lastScanTracks(int count);

  /// No description provided for @scanDeviceStorageForAudio.
  ///
  /// In en, this message translates to:
  /// **'Scan device storage for audio'**
  String get scanDeviceStorageForAudio;

  /// No description provided for @removeMissingFiles.
  ///
  /// In en, this message translates to:
  /// **'Remove missing files'**
  String get removeMissingFiles;

  /// No description provided for @removeMissingFilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Delete indexed tracks whose files no longer exist'**
  String get removeMissingFilesSubtitle;

  /// No description provided for @removeMissingFilesConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove missing files?'**
  String get removeMissingFilesConfirmTitle;

  /// No description provided for @removeMissingFilesConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes indexed tracks whose files no longer exist on disk.'**
  String get removeMissingFilesConfirmBody;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @removedMissingTracks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No missing files found} =1{Removed 1 missing track} other{Removed {count} missing tracks}}'**
  String removedMissingTracks(int count);

  /// No description provided for @artworkCache.
  ///
  /// In en, this message translates to:
  /// **'Artwork Cache'**
  String get artworkCache;

  /// No description provided for @calculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get calculating;

  /// No description provided for @cacheUsedOfMax.
  ///
  /// In en, this message translates to:
  /// **'{used} used of {max} MB max'**
  String cacheUsedOfMax(String used, int max);

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @artworkCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Artwork cache cleared successfully'**
  String get artworkCacheCleared;

  /// No description provided for @youtubeStreamDiskCache.
  ///
  /// In en, this message translates to:
  /// **'YouTube Stream Disk Cache'**
  String get youtubeStreamDiskCache;

  /// No description provided for @streamCacheCachedForReplay.
  ///
  /// In en, this message translates to:
  /// **'{size} cached for zero-latency replay'**
  String streamCacheCachedForReplay(String size);

  /// No description provided for @streamCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Stream cache cleared successfully'**
  String get streamCacheCleared;

  /// No description provided for @maximumArtworkCacheLimit.
  ///
  /// In en, this message translates to:
  /// **'Maximum Artwork Cache Limit'**
  String get maximumArtworkCacheLimit;

  /// No description provided for @maxMbAutoEvicts.
  ///
  /// In en, this message translates to:
  /// **'{max} MB • Auto-evicts oldest artworks when full'**
  String maxMbAutoEvicts(int max);

  /// No description provided for @maximumCacheSize.
  ///
  /// In en, this message translates to:
  /// **'Maximum Cache Size'**
  String get maximumCacheSize;

  /// No description provided for @mbValue.
  ///
  /// In en, this message translates to:
  /// **'{mb} MB'**
  String mbValue(int mb);

  /// No description provided for @scrobblerSettings.
  ///
  /// In en, this message translates to:
  /// **'Scrobbler Settings'**
  String get scrobblerSettings;

  /// No description provided for @listenBrainzRestScrobbler.
  ///
  /// In en, this message translates to:
  /// **'ListenBrainz REST Scrobbler'**
  String get listenBrainzRestScrobbler;

  /// No description provided for @enableListenBrainz.
  ///
  /// In en, this message translates to:
  /// **'Enable ListenBrainz'**
  String get enableListenBrainz;

  /// No description provided for @userToken.
  ///
  /// In en, this message translates to:
  /// **'User Token'**
  String get userToken;

  /// No description provided for @enterListenBrainzUserToken.
  ///
  /// In en, this message translates to:
  /// **'Enter ListenBrainz User Token'**
  String get enterListenBrainzUserToken;

  /// No description provided for @lastFmRestScrobbler.
  ///
  /// In en, this message translates to:
  /// **'Last.fm REST Scrobbler'**
  String get lastFmRestScrobbler;

  /// No description provided for @enableLastFmDirectScrobbling.
  ///
  /// In en, this message translates to:
  /// **'Enable Last.fm Direct Scrobbling'**
  String get enableLastFmDirectScrobbling;

  /// No description provided for @lastFmApiKey.
  ///
  /// In en, this message translates to:
  /// **'Last.fm API Key'**
  String get lastFmApiKey;

  /// No description provided for @lastFmSharedSecret.
  ///
  /// In en, this message translates to:
  /// **'Last.fm Shared Secret'**
  String get lastFmSharedSecret;

  /// No description provided for @lastFmSessionKey.
  ///
  /// In en, this message translates to:
  /// **'Last.fm Session Key (sk)'**
  String get lastFmSessionKey;

  /// No description provided for @scrobblerConfigSaved.
  ///
  /// In en, this message translates to:
  /// **'Scrobbler configuration saved!'**
  String get scrobblerConfigSaved;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save Settings'**
  String get saveSettings;

  /// No description provided for @youtubeMusicWeb.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music Web'**
  String get youtubeMusicWeb;

  /// No description provided for @selectPageToOpen.
  ///
  /// In en, this message translates to:
  /// **'Select a page to open in the in-app browser'**
  String get selectPageToOpen;

  /// No description provided for @homePage.
  ///
  /// In en, this message translates to:
  /// **'Home Page'**
  String get homePage;

  /// No description provided for @homePageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized recommendations, mixes & quick picks'**
  String get homePageSubtitle;

  /// No description provided for @youtubeWeb.
  ///
  /// In en, this message translates to:
  /// **'YouTube Web'**
  String get youtubeWeb;

  /// No description provided for @youtubeWebSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse all music videos & playlists (no geo-restrictions)'**
  String get youtubeWebSubtitle;

  /// No description provided for @exploreAndCharts.
  ///
  /// In en, this message translates to:
  /// **'Explore & Charts'**
  String get exploreAndCharts;

  /// No description provided for @exploreAndChartsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Trending songs, top global charts & music videos'**
  String get exploreAndChartsSubtitle;

  /// No description provided for @yourLibrary.
  ///
  /// In en, this message translates to:
  /// **'Your Library'**
  String get yourLibrary;

  /// No description provided for @yourLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Saved playlists, albums, songs & subscribed artists'**
  String get yourLibrarySubtitle;

  /// No description provided for @likedMusic.
  ///
  /// In en, this message translates to:
  /// **'Liked Music'**
  String get likedMusic;

  /// No description provided for @likedMusicSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Thumbed-up songs synced with your Google account'**
  String get likedMusicSubtitle;

  /// No description provided for @newReleases.
  ///
  /// In en, this message translates to:
  /// **'New Releases'**
  String get newReleases;

  /// No description provided for @newReleasesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Latest album drops, EPs and trending single releases'**
  String get newReleasesSubtitle;

  /// No description provided for @listeningHistory.
  ///
  /// In en, this message translates to:
  /// **'Listening History'**
  String get listeningHistory;

  /// No description provided for @listeningHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recently played tracks and stations on your account'**
  String get listeningHistorySubtitle;

  /// No description provided for @bySongs.
  ///
  /// In en, this message translates to:
  /// **'By Songs'**
  String get bySongs;

  /// No description provided for @endOfTrack.
  ///
  /// In en, this message translates to:
  /// **'End of track'**
  String get endOfTrack;

  /// No description provided for @endOfQueue.
  ///
  /// In en, this message translates to:
  /// **'End of queue'**
  String get endOfQueue;

  /// No description provided for @songsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 song} other{{count} songs}}'**
  String songsCount(int count);

  /// No description provided for @musicWillStopEndOfTrack.
  ///
  /// In en, this message translates to:
  /// **'Music will stop at the end of this track'**
  String get musicWillStopEndOfTrack;

  /// No description provided for @musicWillStopAfterSongs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Music will stop after 1 song} other{Music will stop after {count} songs}}'**
  String musicWillStopAfterSongs(int count);

  /// No description provided for @musicWillStopEndOfQueue.
  ///
  /// In en, this message translates to:
  /// **'Music will stop at the end of the queue'**
  String get musicWillStopEndOfQueue;

  /// No description provided for @musicWillStopIn.
  ///
  /// In en, this message translates to:
  /// **'Music will stop in {minutes}m {seconds}s'**
  String musicWillStopIn(int minutes, int seconds);

  /// No description provided for @rcStackWithHeadphoneEq.
  ///
  /// In en, this message translates to:
  /// **'Stack with headphone AutoEQ'**
  String get rcStackWithHeadphoneEq;

  /// No description provided for @rcStackWithHeadphoneEqSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Combine this room correction with the selected headphone profile.'**
  String get rcStackWithHeadphoneEqSubtitle;

  /// No description provided for @rcMeasuredResponse.
  ///
  /// In en, this message translates to:
  /// **'Measured Response'**
  String get rcMeasuredResponse;

  /// No description provided for @rcFittedEqGain.
  ///
  /// In en, this message translates to:
  /// **'Fitted EQ Gain'**
  String get rcFittedEqGain;

  /// No description provided for @fetchMissingArtworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Fetch Missing Artwork?'**
  String get fetchMissingArtworkTitle;

  /// No description provided for @fetchMissingArtworkBody.
  ///
  /// In en, this message translates to:
  /// **'Pulsr will look up albums without artwork online and save the results to your library. This needs an internet connection.'**
  String get fetchMissingArtworkBody;

  /// No description provided for @fetchArtwork.
  ///
  /// In en, this message translates to:
  /// **'Fetch Artwork'**
  String get fetchArtwork;

  /// No description provided for @artworkServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Artwork service is unavailable'**
  String get artworkServiceUnavailable;

  /// No description provided for @noMissingArtworkFound.
  ///
  /// In en, this message translates to:
  /// **'No missing artwork found online'**
  String get noMissingArtworkFound;

  /// No description provided for @updatedArtworkForAlbums.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updated artwork for 1 album} other{Updated artwork for {count} albums}}'**
  String updatedArtworkForAlbums(int count);

  /// No description provided for @keepThisOne.
  ///
  /// In en, this message translates to:
  /// **'Keep this one'**
  String get keepThisOne;

  /// No description provided for @markAsCopyToKeep.
  ///
  /// In en, this message translates to:
  /// **'Mark \"{title}\" as the copy to keep'**
  String markAsCopyToKeep(String title);

  /// No description provided for @deleteFile.
  ///
  /// In en, this message translates to:
  /// **'Delete file'**
  String get deleteFile;

  /// No description provided for @removeFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{title}\" from your device'**
  String removeFromDevice(String title);

  /// No description provided for @keepingTitle.
  ///
  /// In en, this message translates to:
  /// **'Keeping \"{title}\"'**
  String keepingTitle(String title);

  /// No description provided for @deleteThisFile.
  ///
  /// In en, this message translates to:
  /// **'Delete this file?'**
  String get deleteThisFile;

  /// No description provided for @deleteFileConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be permanently removed from your device. This cannot be undone.'**
  String deleteFileConfirmBody(String title);

  /// No description provided for @deleteIsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Delete is unavailable right now'**
  String get deleteIsUnavailable;

  /// No description provided for @failedToDelete.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {message}'**
  String failedToDelete(String message);

  /// No description provided for @deletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{title}\"'**
  String deletedTitle(String title);

  /// No description provided for @duplicateCleaner.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Cleaner'**
  String get duplicateCleaner;

  /// No description provided for @fetchMissingArtworkTooltip.
  ///
  /// In en, this message translates to:
  /// **'Fetch missing artwork'**
  String get fetchMissingArtworkTooltip;

  /// No description provided for @noDuplicatesFound.
  ///
  /// In en, this message translates to:
  /// **'No Duplicates Found!'**
  String get noDuplicatesFound;

  /// No description provided for @libraryCleanlyOrganized.
  ///
  /// In en, this message translates to:
  /// **'Your library is cleanly organized.'**
  String get libraryCleanlyOrganized;

  /// No description provided for @kept.
  ///
  /// In en, this message translates to:
  /// **'Kept'**
  String get kept;

  /// No description provided for @resolveDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Resolve duplicate'**
  String get resolveDuplicate;

  /// No description provided for @sleepTimerMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String sleepTimerMinutes(int minutes);

  /// No description provided for @radioTitle.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get radioTitle;

  /// No description provided for @radioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Internet radio & live streams'**
  String get radioSubtitle;

  /// No description provided for @radioAddStation.
  ///
  /// In en, this message translates to:
  /// **'Add Station'**
  String get radioAddStation;

  /// No description provided for @radioImportPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Import .m3u'**
  String get radioImportPlaylist;

  /// No description provided for @radioEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No radio stations yet'**
  String get radioEmptyTitle;

  /// No description provided for @radioEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add a stream URL or import an .m3u playlist to start listening.'**
  String get radioEmptySubtitle;

  /// No description provided for @radioStationName.
  ///
  /// In en, this message translates to:
  /// **'Station name'**
  String get radioStationName;

  /// No description provided for @radioStationUrl.
  ///
  /// In en, this message translates to:
  /// **'Stream URL'**
  String get radioStationUrl;

  /// No description provided for @radioAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get radioAdd;

  /// No description provided for @radioCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get radioCancel;

  /// No description provided for @radioDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get radioDelete;

  /// No description provided for @radioDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete station?'**
  String get radioDeleteTitle;

  /// No description provided for @radioDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from your stations?'**
  String radioDeleteMessage(String name);

  /// No description provided for @radioInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid http(s) stream URL'**
  String get radioInvalidUrl;

  /// No description provided for @radioImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import .m3u'**
  String get radioImportTitle;

  /// No description provided for @radioImportHint.
  ///
  /// In en, this message translates to:
  /// **'Paste .m3u playlist content'**
  String get radioImportHint;

  /// No description provided for @radioImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get radioImport;

  /// No description provided for @radioImportedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} stations imported'**
  String radioImportedCount(int count);

  /// No description provided for @radioNoStreamsFound.
  ///
  /// In en, this message translates to:
  /// **'No http(s) stream URLs found'**
  String get radioNoStreamsFound;

  /// No description provided for @radioPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get radioPlay;

  /// No description provided for @radioCuratedBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse curated stations'**
  String get radioCuratedBrowse;

  /// No description provided for @radioCuratedAdded.
  ///
  /// In en, this message translates to:
  /// **'{count} curated stations added'**
  String radioCuratedAdded(int count);

  /// No description provided for @radioCuratedUpToDate.
  ///
  /// In en, this message translates to:
  /// **'All curated stations are already in your list'**
  String get radioCuratedUpToDate;

  /// No description provided for @radioCuratedTitle.
  ///
  /// In en, this message translates to:
  /// **'Curated Stations'**
  String get radioCuratedTitle;

  /// No description provided for @radioEditStation.
  ///
  /// In en, this message translates to:
  /// **'Edit Station'**
  String get radioEditStation;

  /// No description provided for @radioEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get radioEdit;

  /// No description provided for @radioSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get radioSave;

  /// No description provided for @radioUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a stream URL'**
  String get radioUrlRequired;

  /// No description provided for @radioUrlMalformed.
  ///
  /// In en, this message translates to:
  /// **'That URL could not be parsed'**
  String get radioUrlMalformed;

  /// No description provided for @radioUrlScheme.
  ///
  /// In en, this message translates to:
  /// **'Only http:// and https:// streams are supported'**
  String get radioUrlScheme;

  /// No description provided for @radioUrlNoHost.
  ///
  /// In en, this message translates to:
  /// **'The URL is missing a host name'**
  String get radioUrlNoHost;

  /// No description provided for @settingsRebuildSearchIndexTitle.
  ///
  /// In en, this message translates to:
  /// **'Rebuild search index'**
  String get settingsRebuildSearchIndexTitle;

  /// No description provided for @settingsRebuildSearchIndexSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fix missing search results by rebuilding the full-text index'**
  String get settingsRebuildSearchIndexSubtitle;

  /// No description provided for @settingsSearchIndexRebuilt.
  ///
  /// In en, this message translates to:
  /// **'Search index rebuilt'**
  String get settingsSearchIndexRebuilt;

  /// No description provided for @settingsSearchIndexRebuildFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not rebuild the search index'**
  String get settingsSearchIndexRebuildFailed;

  /// No description provided for @followTrackSampleRateTitle.
  ///
  /// In en, this message translates to:
  /// **'Follow track sample rate'**
  String get followTrackSampleRateTitle;

  /// No description provided for @followTrackSampleRateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reconfigure the output to each track\'s native rate; de-duplicated and skipped on Bluetooth'**
  String get followTrackSampleRateSubtitle;

  /// No description provided for @followTrackSampleRateBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Skipped on Bluetooth — the codec/AVRCP link owns the sample rate'**
  String get followTrackSampleRateBluetooth;

  /// No description provided for @strictBitPerfectTitle.
  ///
  /// In en, this message translates to:
  /// **'Strict bit-perfect (no resample)'**
  String get strictBitPerfectTitle;

  /// No description provided for @strictBitPerfectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Forces Bit-Perfect + DSP bypass and follows each track\'s rate so the DAC gets the exact source samples'**
  String get strictBitPerfectSubtitle;

  /// No description provided for @strictBitPerfectBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Unavailable: Bluetooth transcodes — strict bit-perfect needs a USB DAC'**
  String get strictBitPerfectBluetooth;

  /// No description provided for @strictBitPerfectActive.
  ///
  /// In en, this message translates to:
  /// **'Strict bit-perfect is ON: EQ, ReplayGain, effects and crossfade are muted so the exact source samples reach the DAC'**
  String get strictBitPerfectActive;

  /// No description provided for @dsdOutputModeTitle.
  ///
  /// In en, this message translates to:
  /// **'DSD output'**
  String get dsdOutputModeTitle;

  /// No description provided for @dsdOutputModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How DSF/DFF files reach the DAC: PCM decode, or native DSD streamed as DSD over PCM'**
  String get dsdOutputModeSubtitle;

  /// No description provided for @dsdDopRequiresUsbDac.
  ///
  /// In en, this message translates to:
  /// **'Requires a connected USB DAC that supports DSD over PCM (DoP)'**
  String get dsdDopRequiresUsbDac;

  /// No description provided for @dsdOutputPcm.
  ///
  /// In en, this message translates to:
  /// **'PCM'**
  String get dsdOutputPcm;

  /// No description provided for @dsdOutputDop.
  ///
  /// In en, this message translates to:
  /// **'DoP'**
  String get dsdOutputDop;

  /// No description provided for @enableShuffle.
  ///
  /// In en, this message translates to:
  /// **'Enable shuffle'**
  String get enableShuffle;

  /// No description provided for @disableShuffle.
  ///
  /// In en, this message translates to:
  /// **'Disable shuffle'**
  String get disableShuffle;

  /// No description provided for @like.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get like;

  /// No description provided for @unlike.
  ///
  /// In en, this message translates to:
  /// **'Unlike'**
  String get unlike;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @audioOutputAndDac.
  ///
  /// In en, this message translates to:
  /// **'Audio Output & DAC'**
  String get audioOutputAndDac;

  /// No description provided for @toggleSideQueue.
  ///
  /// In en, this message translates to:
  /// **'Toggle Side Queue'**
  String get toggleSideQueue;

  /// No description provided for @fullscreenPlayer.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen Player'**
  String get fullscreenPlayer;

  /// No description provided for @nowPlayingSemantics.
  ///
  /// In en, this message translates to:
  /// **'Now playing: {title} by {artist}'**
  String nowPlayingSemantics(String title, String artist);

  /// No description provided for @resumeFromPrompt.
  ///
  /// In en, this message translates to:
  /// **'Resume from {time}?'**
  String resumeFromPrompt(String time);

  /// No description provided for @setLoopPointA.
  ///
  /// In en, this message translates to:
  /// **'Set loop point A ({time})'**
  String setLoopPointA(String time);

  /// No description provided for @setLoopPointB.
  ///
  /// In en, this message translates to:
  /// **'Set loop point B ({time})'**
  String setLoopPointB(String time);

  /// No description provided for @enableAbLoop.
  ///
  /// In en, this message translates to:
  /// **'Enable AB loop'**
  String get enableAbLoop;

  /// No description provided for @disableAbLoop.
  ///
  /// In en, this message translates to:
  /// **'Disable AB loop'**
  String get disableAbLoop;

  /// No description provided for @clearAbLoop.
  ///
  /// In en, this message translates to:
  /// **'Clear AB loop'**
  String get clearAbLoop;

  /// No description provided for @audioDelayTooltip.
  ///
  /// In en, this message translates to:
  /// **'Audio delay ({ms} ms)'**
  String audioDelayTooltip(int ms);

  /// No description provided for @audioDelayMsLabel.
  ///
  /// In en, this message translates to:
  /// **'Audio delay: {ms} ms'**
  String audioDelayMsLabel(int ms);

  /// No description provided for @audioDelayHelp.
  ///
  /// In en, this message translates to:
  /// **'Positive delays audio (e.g. slow Bluetooth/video).'**
  String get audioDelayHelp;

  /// No description provided for @themeExported.
  ///
  /// In en, this message translates to:
  /// **'Theme exported to share sheet'**
  String get themeExported;

  /// No description provided for @themeExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not export theme'**
  String get themeExportFailed;

  /// No description provided for @themeImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to parse theme JSON'**
  String get themeImportFailed;

  /// No description provided for @themeApplied.
  ///
  /// In en, this message translates to:
  /// **'Custom theme applied!'**
  String get themeApplied;

  /// No description provided for @invalidThemeJson.
  ///
  /// In en, this message translates to:
  /// **'Invalid theme JSON format'**
  String get invalidThemeJson;

  /// No description provided for @notificationPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Show playback controls'**
  String get notificationPermissionTitle;

  /// No description provided for @notificationPermissionRationale.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications so Pulsr can show playback controls on your lock screen and in the notification shade.'**
  String get notificationPermissionRationale;

  /// No description provided for @notificationPermissionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get notificationPermissionAllow;

  /// No description provided for @notificationPermissionNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notificationPermissionNotNow;

  /// No description provided for @onboardingNotificationDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off. You can enable them later in Settings.'**
  String get onboardingNotificationDenied;

  /// No description provided for @onboardingScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not scan your library. You can retry from Settings.'**
  String get onboardingScanFailed;

  /// Explains denied permission with limited-access option
  ///
  /// In en, this message translates to:
  /// **'Without audio access your library will be empty. You can continue with limited access and grant permission later from Settings.'**
  String get onboardingPermissionRationale;

  /// Continue onboarding without permission
  ///
  /// In en, this message translates to:
  /// **'Continue with limited access'**
  String get continueLimitedAccess;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get notFoundGeneric;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Album not found — open it from the library.'**
  String get albumNotFoundHint;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Artist not found — open it from the library.'**
  String get artistNotFoundHint;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Genre not found — open it from the library.'**
  String get genreNotFoundHint;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Year not found — open it from the library.'**
  String get yearNotFoundHint;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Playlist not found — open it from the library.'**
  String get playlistNotFoundHint;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Folder not found'**
  String get folderNotFound;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Song not found'**
  String get songNotFound;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Could not load album songs'**
  String get couldNotLoadAlbumSongs;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Could not load folder songs'**
  String get couldNotLoadFolderSongs;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while reading your library.'**
  String get libraryReadError;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Folder excluded from library scan'**
  String get folderExcluded;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Folder included in library scan'**
  String get folderIncluded;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Clear queue? (Playing track will be kept)'**
  String get clearQueueConfirm;

  /// queue cleared snackbar message
  ///
  /// In en, this message translates to:
  /// **'Queue cleared'**
  String get queueCleared;

  /// max-rate l10n tranche 3
  ///
  /// In en, this message translates to:
  /// **'Saved queue playlist'**
  String get queueSaved;

  /// queue l10n
  ///
  /// In en, this message translates to:
  /// **'Save as Playlist'**
  String get saveAsPlaylist;

  /// queue l10n
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get saveFailed;

  /// detail header
  ///
  /// In en, this message translates to:
  /// **'Add to Queue'**
  String get addToQueue;

  /// tranche4 l10n
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// tranche4 l10n
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// tranche4 l10n
  ///
  /// In en, this message translates to:
  /// **'Name (A-Z)'**
  String get sortAZ;

  /// tranche4 l10n
  ///
  /// In en, this message translates to:
  /// **'No tracks in this playlist.'**
  String get emptyPlaylist;

  /// tranche4 l10n
  ///
  /// In en, this message translates to:
  /// **'Failed to load playlist.'**
  String get playlistLoadFailed;

  /// tranche4 l10n
  ///
  /// In en, this message translates to:
  /// **'Import failed.'**
  String get importFailed;

  /// tranche4 l10n
  ///
  /// In en, this message translates to:
  /// **'Export failed.'**
  String get exportFailed;

  /// tranche4 l10n
  ///
  /// In en, this message translates to:
  /// **'Edit smart rules'**
  String get editSmartRules;

  /// detail sort
  ///
  /// In en, this message translates to:
  /// **'Track number'**
  String get sortTrackNumber;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Set as ringtone'**
  String get setAsRingtone;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Ringtone set successfully'**
  String get ringtoneSet;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Failed to set ringtone.'**
  String get ringtoneFailed;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Change Cover'**
  String get changeCover;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Remove Cover'**
  String get removeCover;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Track BPM'**
  String get trackBpm;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'BPM override cleared.'**
  String get bpmCleared;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Bookmark cleared.'**
  String get bookmarkCleared;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Backup export failed.'**
  String get backupExportFailed;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Backup import failed.'**
  String get backupImportFailed;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Proxy settings saved.'**
  String get proxySaved;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Cast device'**
  String get castDevice;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Cast Current Track'**
  String get castCurrentTrack;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopCast;

  /// tranche5 l10n
  ///
  /// In en, this message translates to:
  /// **'Scanning for Cast devices...'**
  String get scanningCastDevices;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'All Equalizer & DSP settings restored to defaults'**
  String get eqResetNotice;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Save Custom EQ Preset'**
  String get saveCustomEqPreset;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Import EQ Preset'**
  String get importEqPreset;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Custom band frequencies applied.'**
  String get customFreqsApplied;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Room Correction'**
  String get roomCorrection;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Measure room response'**
  String get measureRoom;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Run the stepped-sine wizard'**
  String get roomWizardDesc;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Export current EQ as FIR'**
  String get exportEqFir;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Loads the curve into the convolution stage'**
  String get firDesc;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Export Preset (JSON)'**
  String get exportPresetJson;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Import Preset (JSON)'**
  String get importPresetJson;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'DSP Signal Inspector'**
  String get dspInspector;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'AutoEQ 2.0 Search'**
  String get autoEqSearch;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Dynamics Compressor'**
  String get dynamicsCompressor;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'DSP Chain'**
  String get dspChain;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Frequencies'**
  String get frequencies;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Native DSP unavailable on this device'**
  String get nativeDspUnavailable;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get width;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Bass Mono'**
  String get bassMono;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Anti-Pop'**
  String get antiPop;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Add Band'**
  String get addBand;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get modeLabel;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cutAction;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Boost'**
  String get boostAction;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterLabel;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Peaking'**
  String get peakingFilter;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Low Shelf'**
  String get lowShelfFilter;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'High Shelf'**
  String get highShelfFilter;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Loudness Contour'**
  String get loudnessContour;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Equal-loudness bass/treble lift at low volume'**
  String get loudnessContourDesc;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'TPDF Dither'**
  String get tpdfDither;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Target Bit Depth'**
  String get targetBitDepth;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Sinc Resampler'**
  String get sincResampler;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'High-quality resampling when rates differ'**
  String get sincDesc;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Wet / Dry Mix'**
  String get wetDryMix;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Release Time'**
  String get releaseTime;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get monoLabel;

  /// tranche6 eq l10n
  ///
  /// In en, this message translates to:
  /// **'Neutral / Custom'**
  String get neutralCustom;

  /// tranche6 eq interpolation
  ///
  /// In en, this message translates to:
  /// **'Preset \"{name}\" saved!'**
  String eqPresetSaved(Object name);

  /// tranche6 eq interpolation
  ///
  /// In en, this message translates to:
  /// **'Custom {count}-band Frequencies'**
  String customBandFreqs(Object count);

  /// tranche6 eq interpolation
  ///
  /// In en, this message translates to:
  /// **'Band {number}'**
  String eqBandLabel(Object number);

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Equalizer (EQ)'**
  String get equalizerTitle;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'DSP & Spatial Effects'**
  String get dspSpatialTitle;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'A/B Flat'**
  String get abFlat;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Arbitrary EQ'**
  String get arbitraryEq;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'LiveProg DSP'**
  String get liveProgDsp;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Dynamic Bass'**
  String get dynamicBass;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Bands'**
  String get bandsLabel;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Preamp'**
  String get preampLabel;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Bass Enhancer'**
  String get bassEnhancer;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Volume Boost'**
  String get volumeBoost;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'High boost may cause audio distortion or hearing fatigue.'**
  String get highBoostWarn;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Applied Tuning Profile'**
  String get appliedTuningProfile;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Reset to Flat'**
  String get resetToFlat;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'No headphone profiles found.'**
  String get noHpProfiles;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeLabel;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'All DSP is bypassed by Bit-Perfect. Disable it in Settings to re-enable.'**
  String get allDspBypassed;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Spatial Audio'**
  String get spatialAudio;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Spatial API'**
  String get spatialApi;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Android Spatializer API with head tracking'**
  String get spatialApiDesc;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Soundstage Widening'**
  String get soundstageWidening;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Virtualizer stereo field expansion'**
  String get virtualizerDesc;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Studio Dynamics & Limiter'**
  String get studioDynamics;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Multiband compression engine'**
  String get multibandDesc;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Crossfeed (Headphones)'**
  String get crossfeedHp;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Natural acoustic room speaker simulation'**
  String get crossfeedNatural;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Crossfeed Algorithm'**
  String get crossfeedAlgorithm;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Authentic BS2B IIR crossfeed network (low-pass + high-boost biquads) active.'**
  String get bs2bActive;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Custom Delay-Line'**
  String get customDelayLine;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Delay Time'**
  String get delayTime;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Opposite Ear Bleed'**
  String get oppositeEarBleed;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Lookahead Brickwall Limiter'**
  String get lookaheadLimiter;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Zero-overshoot anti-clipping protection'**
  String get lookaheadDesc;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Ceiling Threshold'**
  String get ceilingThreshold;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Stereo Balance & Mono Mix'**
  String get stereoBalanceMono;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Left / Right acoustic panning balance'**
  String get panDesc;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Acoustic Room Convolution'**
  String get roomConv;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Impulse Response spatial acoustic simulation'**
  String get irDesc;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Multiband Warmth'**
  String get multibandWarmth;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Forces low bass to mono, eliminates headphone phase cancellation'**
  String get bassMonoDesc;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Soft-limits transient bass bursts to protect speakers'**
  String get antiPopDesc;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Bit-depth dithering (auto-skipped on Bluetooth)'**
  String get ditherDesc;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Edit GraphicEq Text & Presets...'**
  String get editGraphicEq;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Open EEL Script Editor...'**
  String get openEelEditor;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Acoustic Calibration Model'**
  String get acousticCalibModel;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Not applied by the audio engine on this device/session - this control may have no audible effect.'**
  String get notAppliedWarn;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Hardware Effects Unavailable'**
  String get hwFxUnavailable;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Hardware AudioFX, Equalizer, Virtualizer and DynamicsProcessing are supported on Android devices.'**
  String get hwFxDesc;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'System-level audio enhancement is active on your device. Running Pulsr DSP on top may cause double-processing. Consider disabling system Dolby/OEM effects or using Bit-Perfect output.'**
  String get systemFxActive;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Paste a JSON preset string below:'**
  String get pasteJsonPreset;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Set the center frequency (Hz) for each band. Values must be strictly ascending between 10 Hz and 30 kHz.'**
  String get centerFreqHelp;

  /// tranche6 eq batch2
  ///
  /// In en, this message translates to:
  /// **'Measure your room, then export the correction as a convolution impulse response.'**
  String get roomMeasureHelp;

  /// tranche6 eq batch2b
  ///
  /// In en, this message translates to:
  /// **'DSP disabled by Bit-Perfect bypass. Disable Bit-Perfect or Bypass DSP in Settings to re-enable.'**
  String get dspDisabledBp;

  /// tranche6 eq batch2b
  ///
  /// In en, this message translates to:
  /// **'Restricts saturation to the mid band for clean sub-bass.'**
  String get saturationBandDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'MATCH LOGIC'**
  String get matchLogic;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'RULES'**
  String get rulesLabel;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'SORTING & LIMIT'**
  String get sortingLimit;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Sort Field'**
  String get sortField;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Play Count'**
  String get playCountLabel;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Last Played'**
  String get lastPlayedLabel;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get yearLabel;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Track Limit'**
  String get trackLimit;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'MATCHING TRACKS PREVIEW'**
  String get matchingPreview;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Yes (True)'**
  String get yesBool;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'No (False)'**
  String get noBool;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'No tracks match the selected rules.'**
  String get noRuleMatch;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Cannot download an empty playlist.'**
  String get cannotDownloadEmpty;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Cannot export an empty playlist.'**
  String get cannotExportEmpty;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Cannot share an empty playlist.'**
  String get cannotShareEmpty;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Download All Tracks'**
  String get downloadAllTracks;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Export as M3U'**
  String get exportM3u;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Manage Songs'**
  String get manageSongs;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Share Playlist'**
  String get sharePlaylist;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Download All'**
  String get downloadAll;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Save to Pulsr'**
  String get saveToPulsr;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Fetching playlist tracks from YouTube Music...'**
  String get fetchingYtmTracks;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'YOUTUBE MUSIC'**
  String get ytmHeader;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Import Tracks'**
  String get importTracks;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Import YouTube Music Favorites'**
  String get importYtmFav;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Paste a playlist link or Liked playlist from YouTube Music'**
  String get pastePlaylistLink;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'No favorite songs to download.'**
  String get noFavToDownload;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Syncing YouTube Music Liked Songs...'**
  String get syncingYtm;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'YouTube Music session expired. Please sign in again.'**
  String get sessionExpired;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Could not load your library.'**
  String get libLoadFailed;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Scan your device storage to load your audio tracks.'**
  String get scanPrompt;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'No Music Loaded Yet'**
  String get noMusicYet;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Find millions of songs, artists & stream online'**
  String get ytmPromo;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Load More History'**
  String get loadMoreHistory;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'No recently played songs'**
  String get noRecentSongs;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Play your favorite music and it will appear here.'**
  String get recentEmptyHint;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Song info'**
  String get songInfo;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'RECITER STYLE'**
  String get reciterStyle;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Learning Speed'**
  String get learningSpeed;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Slow recitation down for memorization'**
  String get reciterSpeedDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'OUTPUT HARDWARE'**
  String get outputHardware;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Reset Profile'**
  String get resetProfile;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Vocal-optimized recitation profiles'**
  String get reciterDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Sibilance is tamed with a high-shelf EQ cut. Spectral noise and breath reduction are not available in the current audio engine.'**
  String get sibilanceDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Multiband Compressor'**
  String get compressorTitle;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Native 4-band compressor with Linkwitz-Riley crossovers. Tames each frequency band independently before the limiter.'**
  String get compressorDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Ratio, Attack and Make-up Gain need the Android DynamicsProcessing engine.'**
  String get compressorLimitDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Reset to Studio Defaults'**
  String get resetStudioDefaults;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Studio Dynamics Compressor'**
  String get studioCompressor;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Studio-grade lookahead dynamics processing and peak brickwall limiting.'**
  String get studioCompressorDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Bytecode JIT'**
  String get bytecodeJit;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Compile & Run'**
  String get compileRun;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'EEL Script Compiled & Loaded into DSP Engine'**
  String get eelCompiled;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Example Scripts & Algorithms'**
  String get exampleScripts;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Jesusonic / EEL Script Editor'**
  String get eelEditor;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Live Control Sliders'**
  String get liveSliders;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Live Programmable DSP'**
  String get liveProgDspTitle;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Synced Lyrics Editor'**
  String get lyricsEditorTitle;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Now at'**
  String get nowAtLabel;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Pitch / Tone Shift'**
  String get pitchShift;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Active Profile'**
  String get activeProfile;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Open .vdc'**
  String get openVdc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Reference Headphone Profiles'**
  String get refHpProfiles;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get bookmarkLabel;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Bookmarks are available for the track currently playing.'**
  String get bookmarkHint;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Default (Global EQ)'**
  String get defaultGlobalEq;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'DSP settings saved for this album.'**
  String get dspSavedAlbum;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Save DSP settings for this album'**
  String get saveDspAlbum;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Playback Tools'**
  String get playbackTools;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Track EQ Override'**
  String get trackEqOverride;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Track Rating'**
  String get trackRating;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Track Volume Offset'**
  String get trackVolumeOffset;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Used by BPM-synced crossfade to align fades to the beat. Range 40-240.'**
  String get bpmXfadeDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get rgOff;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get rgTrack;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get rgAlbum;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get rgAuto;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Auto-calibrate'**
  String get autoCalibrate;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'No audio session logs recorded yet'**
  String get noSessionLogs;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'DSP Signal Inspector & Debug'**
  String get dspInspectorDebug;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Resolved: Bit-Perfect bypass disabled - ReplayGain is adjustable again'**
  String get bpResolved;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'ReplayGain Loudness Normalization'**
  String get replayGainTitle;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'App Color Source'**
  String get appColorSource;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Import .milk Preset'**
  String get importMilk;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Import JSON Visualizer Preset'**
  String get importJsonViz;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Load a Custom visualizer preset (.json) from storage'**
  String get loadJsonVizDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Load a Winamp/Milkdrop preset file from storage'**
  String get loadMilkDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Now Playing Artwork Swipe'**
  String get npArtworkSwipe;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Now Playing Double-Tap Action'**
  String get npDoubleTap;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Select Player Theme'**
  String get selectPlayerTheme;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'An audiophile-grade local music player with bit-perfect output, a full DSP chain, per-device profiles and automation.'**
  String get aboutBlurb;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Accent Color Palette'**
  String get accentPalette;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Ambient Acoustic Glow'**
  String get ambientGlow;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Apply Theme'**
  String get applyTheme;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Custom Theme Studio'**
  String get themeStudio;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Glows with the active track artwork'**
  String get glowDesc;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Import Theme JSON'**
  String get importThemeJson;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Live Theme Preview'**
  String get livePreview;

  /// tranche7 batch
  ///
  /// In en, this message translates to:
  /// **'Paste a valid Pulsr theme JSON string below:'**
  String get pasteThemeJson;

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Play All ({count})'**
  String playAllCount(Object count);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String noResultsFor(Object query);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'{count} Selected'**
  String selectedCount(Object count);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Added {count} tracks to queue'**
  String addedToQueue(Object count);

  /// No description provided for @autoDjAdded.
  ///
  /// In en, this message translates to:
  /// **'Auto-DJ added {count} similar tracks'**
  String autoDjAdded(int count);

  /// No description provided for @autoDjEmpty.
  ///
  /// In en, this message translates to:
  /// **'No similar tracks found in your library'**
  String get autoDjEmpty;

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Saved \"{title}\" to Local Playlists ({count} tracks)'**
  String savedToLocal(Object title, Object count);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Playlist exported successfully ({count} tracks).'**
  String playlistExported(Object count);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Queued {count} tracks for download (3 active downloads)...'**
  String queuedForDownload(Object count);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'{count} tracks'**
  String previewTrackCount(Object count);

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @invalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number greater than 0'**
  String get invalidNumber;

  /// Smart playlist preview is capped
  ///
  /// In en, this message translates to:
  /// **'Showing first {count} matches'**
  String previewTruncated(Object count);

  /// No description provided for @expandPlayer.
  ///
  /// In en, this message translates to:
  /// **'Expand player'**
  String get expandPlayer;

  /// No description provided for @dismissPlayer.
  ///
  /// In en, this message translates to:
  /// **'Dismiss player'**
  String get dismissPlayer;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @loadingMoreSongs.
  ///
  /// In en, this message translates to:
  /// **'Loading more songs…'**
  String get loadingMoreSongs;

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Bluetooth latency calibrated to {ms} ms'**
  String btCalibrated(Object ms);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Successfully imported {count} tracks to Online Favorites!'**
  String importedOnline(Object count);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Synced {count} tracks from your YouTube Music Liked library!'**
  String syncedOnline(Object count);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncFailed(Object error);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Scan complete! {count} tracks loaded.'**
  String scanComplete(Object count);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Could not load songs for {title}'**
  String loadSongsFailed(Object title);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Removed \"{title}\" from favorites'**
  String removedFavorite(Object title);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Card & Artwork Corner Radius ({px}px)'**
  String cornerRadiusLabel(Object px);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Loaded ViPER-DDC profile: {name}'**
  String vdcLoaded(Object name);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Failed to load .vdc file: {error}'**
  String vdcFailed(Object error);

  /// tranche7 tpl
  ///
  /// In en, this message translates to:
  /// **'Conflicts with: {name}'**
  String conflictsWith(Object name);

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Audio Visualizer Style'**
  String get visualizerStyleLabel;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneAction;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Scrobbler credentials saved securely.'**
  String get scrobblerSaved;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'USB permission denied - hardware volume unavailable'**
  String get usbPermDenied;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Hardware Volume'**
  String get hwVolume;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Disconnected from YouTube Music'**
  String get ytmDisconnected;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Allow Background Playback'**
  String get allowBackground;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Total Scrobbles:'**
  String get totalScrobbles;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Last Scrobbled:'**
  String get lastScrobbled;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'QUICK PRESETS'**
  String get quickPresets;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'SAVED PROXY POOL'**
  String get savedProxyPool;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'No Proxies in Pool'**
  String get noProxiesPool;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Import Proxies'**
  String get importProxies;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Import your proxy list (.txt) or paste lines in IP:PORT:USER:PASS format.'**
  String get importProxiesDesc;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Paste proxy lines or pick a text file. Lines will be parsed automatically.'**
  String get pasteOrPick;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Requests matching these hosts will connect directly without routing through proxy.'**
  String get bypassHostsDesc;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Paste Clipboard'**
  String get pasteClipboard;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Pick File'**
  String get pickFile;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Import & Parse'**
  String get importParse;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Import / Paste'**
  String get importPaste;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Sort by Speed'**
  String get sortBySpeed;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Testing'**
  String get testingLabel;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failedLabel;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get unverifiedLabel;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAll;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Could not create the suggested playlist.'**
  String get suggestCreateFailed;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Most compatible'**
  String get mostCompatible;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Could not load tracks for this playlist.'**
  String get loadTracksFailed;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'No liked songs to download. Sync first.'**
  String get noLikedToDownload;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Fetching account playlists...'**
  String get fetchingAccount;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'No playlists found in your YouTube Music library.'**
  String get noAccountPlaylists;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Select a playlist to view tracks'**
  String get selectPlaylistHint;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync your Liked Music library and account playlists.'**
  String get signInToSync;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'SUGGESTED FOR YOU'**
  String get suggestedForYou;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT PLAYLISTS'**
  String get accountPlaylists;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'ADDED PLAYLISTS'**
  String get addedPlaylists;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Add YouTube Playlist URL'**
  String get addYtmUrl;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Connect YouTube Music'**
  String get connectYtm;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Export Backup'**
  String get exportBackup;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Import Backup'**
  String get importBackup;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Save favorites, playlists, history & settings to JSON'**
  String get backupExportDesc;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Restore favorites, playlists, history & settings from JSON file'**
  String get backupImportDesc;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Backup file too large (max 10 MB)'**
  String get backupTooLarge;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Selected backup file does not exist'**
  String get backupMissing;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON backup file format'**
  String get backupInvalid;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Clear Cache & Reset'**
  String get clearCacheReset;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Cookies and cache cleared. Reloading YouTube Music...'**
  String get cookiesCleared;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Force Egypt Mode'**
  String get forceEgypt;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'If Google blocks embedded browser login on this device, you can paste your raw cookie string directly:'**
  String get googleBlockHelp;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Import Cookies / Token Manually'**
  String get importCookiesToken;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Import Cookies Manually'**
  String get importCookiesManual;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Login detected! Tap the green \"Done\" button to complete setup.'**
  String get loginDetected;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Make sure you sign into the correct Google account. Tap \"Done\" once logged in.'**
  String get confirmAccount;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Open YouTube Music web directly'**
  String get openYtmWebDirect;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Open YouTube Web'**
  String get openYtWeb;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Please complete sign in on YouTube Music first.'**
  String get completeSignInFirst;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google TV (no captcha)'**
  String get googleTvSignIn;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Tip: if Google continues to block in-app sign-in on this device, paste your cookies from your browser using the button above.'**
  String get googleBlockTip;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'Your network IP is outside YouTube Music Web support. Force Egypt mode or switch to YouTube Web (never geo-blocked).'**
  String get ipOutsideYtm;

  /// tranche7 sup
  ///
  /// In en, this message translates to:
  /// **'YouTube Music is restricted in your region'**
  String get ytmRestricted;

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Imported {preset}: {name}'**
  String importedPresetTpl(Object preset, Object name);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Applied {profile}: {name}'**
  String appliedProfileTpl(Object profile, Object name);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Successfully imported {count} new proxies'**
  String proxyImported(Object count);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Activated proxy: {addr}'**
  String proxyActivated(Object addr);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Applied preset: {name} ({host}:{port})'**
  String proxyPresetApplied(Object name, Object host, Object port);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Failed to pick file: {error}'**
  String pickFileFailed(Object error);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Failed to import playlist: {error}'**
  String importPlaylistFailed(Object error);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Fetching \"{title}\" for download...'**
  String fetchingForDownload(Object title);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Created \"{title}\" with {count} tracks.'**
  String suggestedCreated(Object title, Object count);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'{count} tracks - Added'**
  String entryAdded(Object count);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'{count} tracks - Tap to create'**
  String tapToCreate(Object count);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'{matched} of {total} tracks matched.'**
  String importMatched(Object matched, Object total);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'{count} playlists'**
  String accountPlaylistCount(Object count);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'History: {count}'**
  String historyLine(Object count);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Backup exported successfully to {uri}'**
  String backupExportedTo(Object uri);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Try {name}'**
  String tryIdentity(Object name);

  /// tranche7 sup tpl
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all {count} saved proxies?'**
  String clearPoolConfirm(Object count);

  /// tranche7 sup3
  ///
  /// In en, this message translates to:
  /// **'Playing on Cast'**
  String get playingOnCast;

  /// tranche7 sup3
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get castConnected;

  /// tranche7 sup4
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeAction;

  /// tranche7 fix
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSetLabel;

  /// tranche7 fix
  ///
  /// In en, this message translates to:
  /// **'Bookmark saved.'**
  String get bookmarkSaved;

  /// tranche7 fix
  ///
  /// In en, this message translates to:
  /// **'Play past 0:05 to save a bookmark.'**
  String get bookmarkEarly;

  /// tranche7 fix tpl
  ///
  /// In en, this message translates to:
  /// **'Resume at {time}'**
  String resumeAtTpl(Object time);

  /// tranche7 final
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAllAction;

  /// tranche7 final
  ///
  /// In en, this message translates to:
  /// **'Clear Proxy Pool?'**
  String get clearPoolTitle;

  /// tranche7 final
  ///
  /// In en, this message translates to:
  /// **'Winamp/Milkdrop preset renderer (built-in or imported .milk file)'**
  String get milkRendererDesc;

  /// tranche7 final
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get includedLabel;

  /// tranche7 final
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noneLabel;

  /// tranche7 final tpl
  ///
  /// In en, this message translates to:
  /// **'Queued {count} tracks from \"{title}\" for download...'**
  String queuedFromTitle(Object count, Object title);

  /// tranche7 final tpl
  ///
  /// In en, this message translates to:
  /// **'All tracks from \"{title}\" are already downloaded or queued.'**
  String allDownloaded(Object title);

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'HARDWARE OUTPUT ROUTING'**
  String get hwOutputRouting;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'USB DAC ATTACHED'**
  String get usbDacAttached;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'OUTPUT PATH DIAGNOSTICS'**
  String get outputPathDiag;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'DSD files decode to PCM; native DSD streaming is not supported yet'**
  String get dsdPcmNote;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'TARGET OUTPUT SAMPLE RATE'**
  String get targetSampleRate;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'TARGET BIT DEPTH & BIT-PERFECT'**
  String get targetBitPerfect;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'TRACK SOURCE SPECIFICATIONS'**
  String get trackSourceSpecs;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'LIVE AUDIO SIGNAL CHAIN'**
  String get liveSignalChain;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Apply & Done'**
  String get applyDone;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Switch output in system panel'**
  String get switchOutputPanel;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Direct Bit-Perfect Mode'**
  String get directBpMode;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'ARMED'**
  String get armedLabel;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Bit-Perfect Guardrails Active: DSP processing & software volume bypassed. Adjust volume via hardware DAC.'**
  String get bpGuardrails;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'BLUETOOTH AUDIO CODEC'**
  String get btAudioCodec;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Earbuds connected. See specs below.'**
  String get earbudsConnected;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'SUPPORTED CODECS (TAP TO SWITCH)'**
  String get supportedCodecs;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'SAMPLE RATE'**
  String get sampleRateLabel;

  /// No description provided for @btSelectSampleRate.
  ///
  /// In en, this message translates to:
  /// **'Select sample rate'**
  String get btSelectSampleRate;

  /// No description provided for @btSelectBitDepth.
  ///
  /// In en, this message translates to:
  /// **'Select bit depth'**
  String get btSelectBitDepth;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'BIT DEPTH'**
  String get bitDepthLabel;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'LDAC QUALITY'**
  String get ldacQuality;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Change Bluetooth Codec'**
  String get changeBtCodec;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Nearby Devices permission needed to read and control codec settings.'**
  String get nearbyPermDesc;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Grant Bluetooth Permission'**
  String get grantBtPerm;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'LE AUDIO'**
  String get leAudio;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Android negotiates the LC3 stream with your earbuds. Codec, sample rate and bit depth are not app-adjustable on LE Audio.'**
  String get lc3Negotiation;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Connecting to Bluetooth stack...'**
  String get connectingBt;

  /// tranche7 quality
  ///
  /// In en, this message translates to:
  /// **'Bit-Perfect Mode'**
  String get bitPerfectMode;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'YouTube Music session expired. Sign in again to keep streaming.'**
  String get ytmSessionExpired;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'No matching online metadata found.'**
  String get noOnlineMetadata;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Online metadata applied successfully!'**
  String get onlineMetadataApplied;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'YouTube Music Explore'**
  String get ytmExplore;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Could not load songs for this year'**
  String get couldNotLoadYear;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'STUDIO AUDIO'**
  String get studioAudio;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyricsLabel;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Cloud Backup & Sync'**
  String get cloudBackupSync;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Cloud Storage Status'**
  String get cloudStorageStatus;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Encrypted bidirectional Firestore backup across all your devices.'**
  String get cloudBackupDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'What gets synced'**
  String get whatGetsSynced;

  /// No description provided for @cloudSyncFavoritesLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync favorites'**
  String get cloudSyncFavoritesLabel;

  /// No description provided for @cloudSyncFavoritesDesc.
  ///
  /// In en, this message translates to:
  /// **'Upload and restore liked songs across devices'**
  String get cloudSyncFavoritesDesc;

  /// No description provided for @cloudSyncPlaylistsLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync playlists'**
  String get cloudSyncPlaylistsLabel;

  /// No description provided for @cloudSyncPlaylistsDesc.
  ///
  /// In en, this message translates to:
  /// **'Upload and restore your playlists across devices'**
  String get cloudSyncPlaylistsDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Favorites, playlists, play history and library metadata are '**
  String get syncItemsPrefix;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Auto-Filter Voice Notes & Messengers'**
  String get autoFilterVoiceNotes;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Automatically ignores WhatsApp audio, voice notes, Telegram, Call Recordings, and sound recorder files.'**
  String get autoFilterVoiceNotesDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Ignore short clips and sound effects'**
  String get shortAudioFilterDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Min File Size'**
  String get minFileSize;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Exclude small audio snippets & corrupt files'**
  String get minFileSizeDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'DEVICE AUDIO DIRECTORIES'**
  String get deviceAudioDirectories;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'HTTP / HTTPS'**
  String get httpHttps;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'SOCKS5'**
  String get socks5;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Scrobbling Analytics'**
  String get scrobblingAnalytics;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Universal Scrobbling Engine'**
  String get universalScrobblingEngine;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Connected to Last.fm, ListenBrainz, Libre.fm, and Custom Webhooks.'**
  String get scrobblingServicesDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Last 7 Days Activity'**
  String get last7DaysActivity;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Most Played Artists'**
  String get topScrobbledArtists;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'THEME MODE'**
  String get themeModeLabel;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'AMOLED'**
  String get amoledLabel;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Try searching for \"equalizer\", \"dark mode\", \"crossfade\", \"proxy\", \"cache\", or \"scrobble\".'**
  String get settingsSearchHint;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'BIT-PERFECT'**
  String get bitPerfectLabel;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Automation Rules'**
  String get automationRules;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Apply a settings profile automatically when a device event fires.'**
  String get automationRulesDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'No automation rules configured.'**
  String get noAutomationRules;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Playback stops when screen is off?'**
  String get playbackStopsScreenOff;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Some device manufacturers aggressively stop background playback. Granting battery exemption ensures uninterrupted music playback.'**
  String get batteryExemptionDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Device Guide'**
  String get deviceGuide;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'SponsorBlock categories'**
  String get sponsorBlockCategoriesLabel;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'SYNCED'**
  String get syncedLabel;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'QUICK DISCOVERY'**
  String get quickDiscovery;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Stream and download millions of songs from YouTube Music, ad-free.'**
  String get ytmSearchDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'POPULAR SEARCHES'**
  String get popularSearches;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Quran Mode'**
  String get quranMode;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Manage Playlist'**
  String get managePlaylist;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Export failed. Please try again.'**
  String get exportFailedRetry;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Applied EqualizerAPO GraphicEq curve'**
  String get appliedGraphicEq;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Arbitrary Response EQ'**
  String get arbitraryResponseEq;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'EqualizerAPO GraphicEq Spec'**
  String get graphicEqSpec;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'512-tap FIR Filter'**
  String get fir512;

  /// Arbitrary EQ linear-phase toggle title
  ///
  /// In en, this message translates to:
  /// **'Linear-phase FIR'**
  String get linearPhaseFir;

  /// Arbitrary EQ linear-phase enabled subtitle
  ///
  /// In en, this message translates to:
  /// **'Constant delay, exact phase (pre-ringing possible)'**
  String get linearPhaseOnDesc;

  /// Arbitrary EQ minimum-phase subtitle
  ///
  /// In en, this message translates to:
  /// **'Minimum-phase, zero extra delay (default)'**
  String get linearPhaseOffDesc;

  /// DSD DoP PCM container width label
  ///
  /// In en, this message translates to:
  /// **'DoP container'**
  String get dopContainer;

  /// Multiband compressor per-band section title
  ///
  /// In en, this message translates to:
  /// **'Per-band dynamics'**
  String get mbcPerBandTitle;

  /// Multiband compressor per-band section subtitle
  ///
  /// In en, this message translates to:
  /// **'Threshold, ratio and make-up gain for each of the 4 LR4 bands.'**
  String get mbcPerBandSubtitle;

  /// Multiband compressor band 1 name
  ///
  /// In en, this message translates to:
  /// **'Band 1 · Low'**
  String get mbcBandLow;

  /// Multiband compressor band 2 name
  ///
  /// In en, this message translates to:
  /// **'Band 2 · Low-Mid'**
  String get mbcBandLowMid;

  /// Multiband compressor band 3 name
  ///
  /// In en, this message translates to:
  /// **'Band 3 · High-Mid'**
  String get mbcBandHighMid;

  /// Multiband compressor band 4 name
  ///
  /// In en, this message translates to:
  /// **'Band 4 · High'**
  String get mbcBandHigh;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Apply Curve'**
  String get applyCurve;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Preset Acoustic Targets'**
  String get presetAcousticTargets;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Opens Developer Options -> Bluetooth Audio Codec'**
  String get devOptionsBtCodec;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'AutoEQ 2.0 Database'**
  String get autoEqDatabase;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'No matching headphone profiles found'**
  String get noHpMatch;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'DSP Debug Report copied to clipboard!'**
  String get dspReportCopied;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Real-time Audio Engine & DSP Debugging'**
  String get dspInspectorDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'ACTIVE AUDIO STAGES'**
  String get activeAudioStages;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'No DSP stages reported from platform engine.'**
  String get noDspStages;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Dolby Atmos is hijacking the HAL session. Native limiter/crossfeed still run, but EQ needs HAL. Fix: tap below to switch to OEM (lets system handle EQ) or disable Dolby in system Sound settings, then restart track.'**
  String get dolbyHijackDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Switched DSP Preference -> OEM. Restart track to attach.'**
  String get switchedToOem;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Failed to switch preference - change in Settings -> Audio'**
  String get switchPrefFailed;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Fix: Switch to OEM'**
  String get fixSwitchOem;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Retrying HAL attach... play a track if idle'**
  String get retryingHal;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Retry Attach'**
  String get retryAttach;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Place a .lrc file in the same folder as your audio track or embed lyrics into file tags.'**
  String get placeLrcHint;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Search Lyrics'**
  String get searchLyrics;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Queue is empty'**
  String get queueEmpty;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skipAction;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Your Music, Your Privacy'**
  String get onboardingHeading;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'100% offline local playback. No accounts, no cloud dependencies, zero tracking, and absolute privacy for your music collection.'**
  String get onboardingPrivacyDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Powerful Playback'**
  String get onboardingPowerful;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Tailor your sound with a 10-band graphic equalizer, smooth crossfade transitions, gapless playback, and smart sleep timers.'**
  String get onboardingPowerfulDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'4 DISTINCT PLAYER THEMES'**
  String get onboardingThemes;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Beautiful & Personal'**
  String get onboardingBeautiful;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Express your style with real-time dynamic color extraction from album art and switch between 4 unique player themes.'**
  String get onboardingBeautifulDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Album Artwork Wall'**
  String get artworkWall;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'No albums found in library'**
  String get noAlbumsFound;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Listening & Library Stats'**
  String get listeningStats;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Audio Quality Tiers'**
  String get audioQualityTiers;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'No play history recorded yet. Listen to tracks to track your top hits!'**
  String get noPlayHistory;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'DOWNLOADS'**
  String get downloadsLabel;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'No music files indexed'**
  String get noMusicIndexed;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Parent Directory'**
  String get parentDirectory;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Folder is empty'**
  String get folderEmpty;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Other Genres'**
  String get otherGenres;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Could not load genre songs'**
  String get couldNotLoadGenre;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Sync your favorites & playlists across devices'**
  String get syncAcrossDevices;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'OR WITH EMAIL'**
  String get orWithEmail;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Enter your email first'**
  String get enterEmailFirst;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google TV'**
  String get signInGoogleTv;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'No captcha - approve on another device'**
  String get noCaptchaDesc;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'1. On your phone or computer, open this address:'**
  String get oauthStep1;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'2. Enter this code:'**
  String get oauthStep2;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval...'**
  String get waitingApproval;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'About Artist'**
  String get aboutArtist;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Opening YouTube Music track...'**
  String get openingYtmTrack;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'Format not supported on this device'**
  String get formatNotSupported;

  /// tranche8 l10n
  ///
  /// In en, this message translates to:
  /// **'WAVEFORM'**
  String get waveformLabel;

  /// tranche8 fix
  ///
  /// In en, this message translates to:
  /// **'USB bit-perfect streaming could not start (unsupported DAC or claim failed)'**
  String get usbBpFailed;

  /// tranche8 final
  ///
  /// In en, this message translates to:
  /// **'Favorites, playlists, play history and library metadata are synced in both directions. DSP presets and app settings stay on this device.'**
  String get cloudSyncItemsDesc;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'Copy JSON Report'**
  String get dspCopyJsonReport;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'Refresh Status'**
  String get dspRefreshStatus;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'{count} ACTIVE'**
  String dspActiveEffectsCount(int count);

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'Bit-Perfect Direct Pass-Through'**
  String get dspBitPerfectDirectPassThrough;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'AudioEffect Session Active (#{sessionId})'**
  String dspAudioEffectSessionActive(int sessionId);

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'Session Pending — Play a track to attach'**
  String get dspSessionPendingPlayTrack;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'HAL Detached (Dolby) — Native DSP Active'**
  String get dspHalDetachedDolbyNativeDsp;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'AudioEffect Session Detached'**
  String get dspAudioEffectSessionDetached;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'BYPASSED'**
  String get dspStatusBypassed;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'ATTACHED'**
  String get dspStatusAttached;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'PENDING'**
  String get dspStatusPending;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'HAL OFF'**
  String get dspStatusHalOff;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'DETACHED'**
  String get dspStatusDetached;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'DEGRADED'**
  String get dspStatusDegraded;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get dspStageStatusActive;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get dspStageStatusOff;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'DSP Engine'**
  String get dspStatDspEngine;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'C++ & HAL'**
  String get dspStatDspEngineNative;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'Android HAL'**
  String get dspStatDspEngineAndroid;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'DSP Preference'**
  String get dspStatDspPreference;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'NATIVE'**
  String get dspStatNative;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'Master EQ'**
  String get dspStatMasterEq;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'Master DSP'**
  String get dspStatMasterDsp;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'ON'**
  String get dspStatOn;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get dspStatOff;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'OEM Audio Alert'**
  String get dspStatOemAudioAlert;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'Detected'**
  String get dspStatDetected;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'Output Target'**
  String get dspStatOutputTarget;

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'{rate} Hz / {bits}-bit'**
  String dspStatOutputFormat(int rate, int bits);

  /// dsp inspector l10n
  ///
  /// In en, this message translates to:
  /// **'{label}: '**
  String dspStatChipLabel(String label);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'Export Backup JSON'**
  String get exportBackupDialogTitle;

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailedWithError(String error);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailedWithError(String error);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'• Favorites: {count}'**
  String confirmFavoritesCount(int count);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'• Playlists: {count}'**
  String confirmPlaylistsCount(int count);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'• History: {count}'**
  String confirmHistoryCount(int count);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'• Settings: {value}'**
  String confirmSettingsValue(String value);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'• Restored Favorites: {count}'**
  String restoredFavoritesCount(int count);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'• Restored Playlists: {count}'**
  String restoredPlaylistsCount(int count);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'• Restored History Entries: {count}'**
  String restoredHistoryCount(int count);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'• Restored Settings: {count} keys'**
  String restoredSettingsKeys(int count);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'• Restored Excluded Folders: {count}'**
  String restoredExcludedFoldersCount(int count);

  /// backup section l10n
  ///
  /// In en, this message translates to:
  /// **'⚠️ {count} song paths could not be matched in your current library.'**
  String unmatchedPathsWarning(int count);

  /// No description provided for @settingsHeaderTagline.
  ///
  /// In en, this message translates to:
  /// **'Pulsr v{version} • Audiophile Music Experience'**
  String settingsHeaderTagline(String version);

  /// No description provided for @settingsHeaderTaglineShort.
  ///
  /// In en, this message translates to:
  /// **'Pulsr v{version} • Audiophile Engine'**
  String settingsHeaderTaglineShort(String version);

  /// No description provided for @settingsSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search settings, sound, appearance...'**
  String get settingsSearchPlaceholder;

  /// No description provided for @settingsCategoryAudioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Equalizer, DSP, Hi-Res, ReplayGain'**
  String get settingsCategoryAudioSubtitle;

  /// No description provided for @settingsCategoryPlaybackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Crossfade, gapless, sleep timer, skip'**
  String get settingsCategoryPlaybackSubtitle;

  /// No description provided for @settingsCategoryAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Theme mode, accent colors, visualizer'**
  String get settingsCategoryAppearanceSubtitle;

  /// No description provided for @settingsCategoryGesturesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mini-player swipes, artwork double-tap'**
  String get settingsCategoryGesturesSubtitle;

  /// No description provided for @settingsCategoryProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles & Rules'**
  String get settingsCategoryProfiles;

  /// No description provided for @settingsCategoryProfilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hardware DAC mappings, trigger rules'**
  String get settingsCategoryProfilesSubtitle;

  /// No description provided for @settingsCategoryLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Folders, hidden media, duration filter'**
  String get settingsCategoryLibrarySubtitle;

  /// No description provided for @settingsCategoryOnline.
  ///
  /// In en, this message translates to:
  /// **'Network & YTM'**
  String get settingsCategoryOnline;

  /// No description provided for @settingsCategoryOnlineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Audio quality, streaming cache, proxy'**
  String get settingsCategoryOnlineSubtitle;

  /// No description provided for @settingsCategoryStorageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Disk usage, cached artwork, cleanup'**
  String get settingsCategoryStorageSubtitle;

  /// No description provided for @settingsCategoryPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Backup'**
  String get settingsCategoryPrivacy;

  /// No description provided for @settingsCategoryPrivacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Offline guarantee, scrobbling, backups'**
  String get settingsCategoryPrivacySubtitle;

  /// No description provided for @settingsCategoryAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsCategoryAbout;

  /// No description provided for @settingsCategoryAboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version {version}, licenses, specs'**
  String settingsCategoryAboutSubtitle(String version);

  /// No description provided for @settingsCategoryAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsCategoryAppearance;

  /// No description provided for @settingsAutomationTitle.
  ///
  /// In en, this message translates to:
  /// **'Automation'**
  String get settingsAutomationTitle;

  /// No description provided for @settingsSmartAudioSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic headphone correction and best-quality output'**
  String get settingsSmartAudioSectionSubtitle;

  /// No description provided for @settingsQuranModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vocal EQ, mosque ambience, memorization speed'**
  String get settingsQuranModeSubtitle;

  /// No description provided for @settingsDeviceProfilesSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Per-output DAC and Bluetooth profile mappings'**
  String get settingsDeviceProfilesSectionSubtitle;

  /// No description provided for @settingsAutomationSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Trigger profiles automatically on hardware events'**
  String get settingsAutomationSectionSubtitle;

  /// No description provided for @settingsAutomationTileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Apply profiles on headphone plug, Bluetooth or charge events'**
  String get settingsAutomationTileSubtitle;

  /// No description provided for @settingsStorageSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage disk usage and audio cache'**
  String get settingsStorageSectionSubtitle;

  /// No description provided for @settingsAboutSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version info, licenses and architecture'**
  String get settingsAboutSectionSubtitle;

  /// No description provided for @settingsAboutVersionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version {version} • Open-source Audiophile Engine'**
  String settingsAboutVersionSubtitle(String version);

  /// No description provided for @settingsAppearanceSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Theme, accent colors, visualizer and player UI style'**
  String get settingsAppearanceSectionSubtitle;

  /// No description provided for @settingsAutoDarkModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto Dark Mode by Time'**
  String get settingsAutoDarkModeTitle;

  /// No description provided for @settingsAutoDarkModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follow a 7 PM – 6 AM day/night schedule'**
  String get settingsAutoDarkModeSubtitle;

  /// No description provided for @settingsHighContrastTitle.
  ///
  /// In en, this message translates to:
  /// **'High Contrast'**
  String get settingsHighContrastTitle;

  /// No description provided for @settingsHighContrastSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Boost contrast with an AMOLED-friendly palette'**
  String get settingsHighContrastSubtitle;

  /// No description provided for @settingsDimWhitePointTitle.
  ///
  /// In en, this message translates to:
  /// **'Dim White Point'**
  String get settingsDimWhitePointTitle;

  /// No description provided for @settingsDimWhitePointSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Soften bright text for easier night listening'**
  String get settingsDimWhitePointSubtitle;

  /// No description provided for @settingsReduceMotionTitle.
  ///
  /// In en, this message translates to:
  /// **'Reduce Motion'**
  String get settingsReduceMotionTitle;

  /// No description provided for @settingsReduceMotionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Snap animations instead of tweening them'**
  String get settingsReduceMotionSubtitle;

  /// No description provided for @settingsLiquidGlassTitle.
  ///
  /// In en, this message translates to:
  /// **'Liquid Glass Tint'**
  String get settingsLiquidGlassTitle;

  /// No description provided for @settingsLiquidGlassSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust refraction between Ultra Clear (0%) and Tinted (100%)'**
  String get settingsLiquidGlassSubtitle;

  /// No description provided for @settingsBadgeStyle.
  ///
  /// In en, this message translates to:
  /// **'STYLE'**
  String get settingsBadgeStyle;

  /// No description provided for @settingsBadgeDsp.
  ///
  /// In en, this message translates to:
  /// **'DSP'**
  String get settingsBadgeDsp;

  /// No description provided for @settingsBadgePalette.
  ///
  /// In en, this message translates to:
  /// **'PALETTE'**
  String get settingsBadgePalette;

  /// No description provided for @settingsGesturesSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure swipe and double-tap gestures across mini-player and artwork'**
  String get settingsGesturesSectionSubtitle;

  /// No description provided for @settingsLibrarySectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Device media indexing, exclusion rules and cleanup'**
  String get settingsLibrarySectionSubtitle;

  /// No description provided for @settingsOnlineSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Online streams, downloads, proxy routing and quality settings'**
  String get settingsOnlineSectionSubtitle;

  /// No description provided for @settingsTapToManage.
  ///
  /// In en, this message translates to:
  /// **'Tap to manage'**
  String get settingsTapToManage;

  /// No description provided for @settingsBadgeConnected.
  ///
  /// In en, this message translates to:
  /// **'CONNECTED'**
  String get settingsBadgeConnected;

  /// No description provided for @settingsDownloadsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and manage offline tracks and downloads'**
  String get settingsDownloadsSubtitle;

  /// No description provided for @settingsProxyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get settingsProxyEnabled;

  /// No description provided for @settingsProxyDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'Disabled • Tap to configure HTTP / SOCKS5'**
  String get settingsProxyDisabledHint;

  /// No description provided for @settingsPrivacySectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Data sovereignty, database backups and scrobbler integrations'**
  String get settingsPrivacySectionSubtitle;

  /// No description provided for @settingsScrobblingTitle.
  ///
  /// In en, this message translates to:
  /// **'Scrobbling (Last.fm & ListenBrainz)'**
  String get settingsScrobblingTitle;

  /// No description provided for @settingsScrobblingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Direct API scrobbling and Now Playing metadata broadcast'**
  String get settingsScrobblingSubtitle;

  /// No description provided for @settingsScrobbleStatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Scrobble Stats'**
  String get settingsScrobbleStatsTitle;

  /// No description provided for @settingsScrobbleStatsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Listening history and scrobble analytics overview'**
  String get settingsScrobbleStatsSubtitle;

  /// No description provided for @settingsCloudBackupDashboard.
  ///
  /// In en, this message translates to:
  /// **'Cloud Backup Dashboard'**
  String get settingsCloudBackupDashboard;

  /// No description provided for @settingsCloudBackupDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage synchronized devices and cloud backup snapshots'**
  String get settingsCloudBackupDashboardSubtitle;

  /// No description provided for @settingsNoSettingsFound.
  ///
  /// In en, this message translates to:
  /// **'No settings found for \"{query}\"'**
  String settingsNoSettingsFound(String query);

  /// No description provided for @settingsCloudSyncCompleted.
  ///
  /// In en, this message translates to:
  /// **'Cloud backup & sync completed!'**
  String get settingsCloudSyncCompleted;

  /// No description provided for @settingsCloudSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed. Please check internet connection.'**
  String get settingsCloudSyncFailed;

  /// No description provided for @settingsNeverLabel.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get settingsNeverLabel;

  /// No description provided for @settingsSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get settingsSyncing;

  /// No description provided for @settingsAddCustomFolder.
  ///
  /// In en, this message translates to:
  /// **'Add Custom Folder'**
  String get settingsAddCustomFolder;

  /// No description provided for @settingsRescanningLibrary.
  ///
  /// In en, this message translates to:
  /// **'Rescanning library…'**
  String get settingsRescanningLibrary;

  /// No description provided for @settingsApplyRescanLibrary.
  ///
  /// In en, this message translates to:
  /// **'Apply & Rescan Library'**
  String get settingsApplyRescanLibrary;

  /// No description provided for @settingsLibraryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Library updated! {count} tracks loaded.'**
  String settingsLibraryUpdated(int count);

  /// No description provided for @settingsHiddenCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Hidden'**
  String settingsHiddenCount(int count);

  /// No description provided for @settingsSearchDirectoriesHint.
  ///
  /// In en, this message translates to:
  /// **'Search directories by name or path...'**
  String get settingsSearchDirectoriesHint;

  /// No description provided for @settingsNoDirectoriesMatch.
  ///
  /// In en, this message translates to:
  /// **'No directories match {query}'**
  String settingsNoDirectoriesMatch(String query);

  /// No description provided for @settingsNoAudioFolders.
  ///
  /// In en, this message translates to:
  /// **'No audio folders discovered yet. Scan storage to populate.'**
  String get settingsNoAudioFolders;

  /// No description provided for @settingsUnhide.
  ///
  /// In en, this message translates to:
  /// **'Unhide'**
  String get settingsUnhide;

  /// No description provided for @settingsHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get settingsHide;

  /// No description provided for @settingsPlaysCount.
  ///
  /// In en, this message translates to:
  /// **'{count} plays'**
  String settingsPlaysCount(int count);

  /// No description provided for @settingsManufacturerBackgroundGuide.
  ///
  /// In en, this message translates to:
  /// **'{manufacturer} Background Guide'**
  String settingsManufacturerBackgroundGuide(String manufacturer);

  /// No description provided for @settingsAggressiveBatteryGuide.
  ///
  /// In en, this message translates to:
  /// **'Your device manufacturer is known for aggressive background process killing.\n\nVisit {url} to configure lock screen and battery settings.'**
  String settingsAggressiveBatteryGuide(String url);

  /// No description provided for @settingsApplyProfileName.
  ///
  /// In en, this message translates to:
  /// **'Apply: {name}'**
  String settingsApplyProfileName(String name);

  /// No description provided for @settingsArabicNative.
  ///
  /// In en, this message translates to:
  /// **'Arabic (RTL)'**
  String get settingsArabicNative;

  /// No description provided for @settingsArtworkSwipeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsArtworkSwipeDisabled;

  /// No description provided for @settingsArtworkSwipeIgnoreDesc.
  ///
  /// In en, this message translates to:
  /// **'Ignore horizontal swipe on album artwork'**
  String get settingsArtworkSwipeIgnoreDesc;

  /// No description provided for @settingsArtworkSwipeNextPrev.
  ///
  /// In en, this message translates to:
  /// **'Next / Previous Track'**
  String get settingsArtworkSwipeNextPrev;

  /// No description provided for @settingsArtworkSwipeNextPrevDesc.
  ///
  /// In en, this message translates to:
  /// **'Swipe left for next track, swipe right for previous track'**
  String get settingsArtworkSwipeNextPrevDesc;

  /// No description provided for @settingsAudioNormalization.
  ///
  /// In en, this message translates to:
  /// **'Audio normalization'**
  String get settingsAudioNormalization;

  /// No description provided for @settingsAudioNormalizationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Even out loudness for tracks without ReplayGain tags'**
  String get settingsAudioNormalizationSubtitle;

  /// No description provided for @settingsAudioOutputDevice.
  ///
  /// In en, this message translates to:
  /// **'Audio Output Device'**
  String get settingsAudioOutputDevice;

  /// No description provided for @settingsAuthenticationOptional.
  ///
  /// In en, this message translates to:
  /// **'AUTHENTICATION (OPTIONAL)'**
  String get settingsAuthenticationOptional;

  /// No description provided for @settingsBitPerfectBtUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable: Bluetooth transcodes — use USB / wired DAC'**
  String get settingsBitPerfectBtUnavailable;

  /// No description provided for @settingsBitPerfectUsb.
  ///
  /// In en, this message translates to:
  /// **'Bit-Perfect USB Pass-Through'**
  String get settingsBitPerfectUsb;

  /// No description provided for @settingsBitPerfectUsbDesc.
  ///
  /// In en, this message translates to:
  /// **'Direct hardware streaming to USB / wired DACs (bypasses Android resampler)'**
  String get settingsBitPerfectUsbDesc;

  /// No description provided for @settingsBpmSyncCrossfade.
  ///
  /// In en, this message translates to:
  /// **'BPM-Synced Crossfade'**
  String get settingsBpmSyncCrossfade;

  /// No description provided for @settingsBpmSyncCrossfadeDesc.
  ///
  /// In en, this message translates to:
  /// **'Aligns the crossfade duration to the nearest 2/4/8/16/32 beats of the incoming track when its BPM is known (set per track in Song Info); otherwise the configured duration is used'**
  String get settingsBpmSyncCrossfadeDesc;

  /// No description provided for @settingsBypassDspBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Bypass DSP in Bit-Perfect Mode'**
  String get settingsBypassDspBitPerfect;

  /// No description provided for @settingsBypassDspBitPerfectDesc.
  ///
  /// In en, this message translates to:
  /// **'Bypasses Equalizer and virtualizer for an uncolored, pure audio bitstream to the DAC'**
  String get settingsBypassDspBitPerfectDesc;

  /// No description provided for @settingsBypassList.
  ///
  /// In en, this message translates to:
  /// **'Bypass List (comma-separated)'**
  String get settingsBypassList;

  /// No description provided for @settingsCalibrateBtLatency.
  ///
  /// In en, this message translates to:
  /// **'Calibrate Bluetooth latency'**
  String get settingsCalibrateBtLatency;

  /// No description provided for @settingsCalibrateBtLatencySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-probe offset (currently {ms} ms)'**
  String settingsCalibrateBtLatencySubtitle(int ms);

  /// No description provided for @settingsCastFailed.
  ///
  /// In en, this message translates to:
  /// **'Cast failed'**
  String get settingsCastFailed;

  /// No description provided for @settingsCastingTitle.
  ///
  /// In en, this message translates to:
  /// **'Casting {title}'**
  String settingsCastingTitle(String title);

  /// No description provided for @settingsCastingTo.
  ///
  /// In en, this message translates to:
  /// **'Casting to {device}'**
  String settingsCastingTo(String device);

  /// No description provided for @settingsCastNoSdkDesc.
  ///
  /// In en, this message translates to:
  /// **'Cast sessions require the Play Services Cast SDK (only in the dev/ytm builds). Device discovery is shown here.'**
  String get settingsCastNoSdkDesc;

  /// No description provided for @settingsCastSdkDesc.
  ///
  /// In en, this message translates to:
  /// **'Uses Google\'s Default Media Receiver. Local files are served over your LAN; remote artwork/URLs are cast directly.'**
  String get settingsCastSdkDesc;

  /// No description provided for @settingsColorSourceArtwork.
  ///
  /// In en, this message translates to:
  /// **'Album Artwork'**
  String get settingsColorSourceArtwork;

  /// No description provided for @settingsColorSourceArtworkDesc.
  ///
  /// In en, this message translates to:
  /// **'Adapt colors from the current track\'s album art (changes per song)'**
  String get settingsColorSourceArtworkDesc;

  /// No description provided for @settingsColorSourceCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom Accent'**
  String get settingsColorSourceCustom;

  /// No description provided for @settingsColorSourceCustomDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the fixed accent color you pick in settings'**
  String get settingsColorSourceCustomDesc;

  /// No description provided for @settingsColorSourceSystemDesc.
  ///
  /// In en, this message translates to:
  /// **'Follow the system wallpaper palette on Android 12+ • falls back to album art on older devices'**
  String get settingsColorSourceSystemDesc;

  /// No description provided for @settingsColorSourceWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Material You (Wallpaper)'**
  String get settingsColorSourceWallpaper;

  /// No description provided for @settingsConnectedAs.
  ///
  /// In en, this message translates to:
  /// **'Connected as: {name}\n\nManage your YouTube Music account or disconnect from this device.'**
  String settingsConnectedAs(String name);

  /// No description provided for @settingsConnectedDeviceQuality.
  ///
  /// In en, this message translates to:
  /// **'Connected device & audio quality'**
  String get settingsConnectedDeviceQuality;

  /// No description provided for @settingsConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection Failed'**
  String get settingsConnectionFailed;

  /// No description provided for @settingsConnectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Connection Successful'**
  String get settingsConnectionSuccessful;

  /// No description provided for @settingsDacNoUacVolume.
  ///
  /// In en, this message translates to:
  /// **'DAC exposes no UAC Volume control'**
  String get settingsDacNoUacVolume;

  /// No description provided for @settingsDisableBitPerfectBypass.
  ///
  /// In en, this message translates to:
  /// **'Disable Bit-Perfect bypass'**
  String get settingsDisableBitPerfectBypass;

  /// No description provided for @settingsDisabledBadge.
  ///
  /// In en, this message translates to:
  /// **'DISABLED'**
  String get settingsDisabledBadge;

  /// No description provided for @settingsDoubleTapDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsDoubleTapDisabled;

  /// No description provided for @settingsDoubleTapFavoriteDesc.
  ///
  /// In en, this message translates to:
  /// **'Add or remove active song from favorites'**
  String get settingsDoubleTapFavoriteDesc;

  /// No description provided for @settingsDoubleTapIgnoreDesc.
  ///
  /// In en, this message translates to:
  /// **'Ignore double-tap gesture'**
  String get settingsDoubleTapIgnoreDesc;

  /// No description provided for @settingsDoubleTapLyricsDesc.
  ///
  /// In en, this message translates to:
  /// **'Show or hide synchronized lyrics overlay'**
  String get settingsDoubleTapLyricsDesc;

  /// No description provided for @settingsDoubleTapToggleFavorite.
  ///
  /// In en, this message translates to:
  /// **'Toggle Favorite'**
  String get settingsDoubleTapToggleFavorite;

  /// No description provided for @settingsDoubleTapToggleLyrics.
  ///
  /// In en, this message translates to:
  /// **'Toggle Lyrics Overlay'**
  String get settingsDoubleTapToggleLyrics;

  /// No description provided for @settingsDspAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically bypass OEM sound effects when DSP active'**
  String get settingsDspAutoDesc;

  /// No description provided for @settingsDspInspectorDesc.
  ///
  /// In en, this message translates to:
  /// **'Inspect live active DSP stages, HAL effects & engine state'**
  String get settingsDspInspectorDesc;

  /// No description provided for @settingsDspNativeDesc.
  ///
  /// In en, this message translates to:
  /// **'64-bit float, zero-latency real-time native DSP'**
  String get settingsDspNativeDesc;

  /// No description provided for @settingsDspOemDesc.
  ///
  /// In en, this message translates to:
  /// **'System / vendor-level sound effects (Dolby, Dirac, etc.)'**
  String get settingsDspOemDesc;

  /// No description provided for @settingsDuckLevel.
  ///
  /// In en, this message translates to:
  /// **'Duck level'**
  String get settingsDuckLevel;

  /// No description provided for @settingsDuckOnNavigation.
  ///
  /// In en, this message translates to:
  /// **'Duck on navigation'**
  String get settingsDuckOnNavigation;

  /// No description provided for @settingsDuckOnNavigationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lower music instead of pausing for prompts'**
  String get settingsDuckOnNavigationSubtitle;

  /// No description provided for @settingsDvcDesc.
  ///
  /// In en, this message translates to:
  /// **'Pins the Android media stream to maximum and applies volume in the native float DSP path, for higher dynamic range and lower distortion at low volumes. Unavailable during Bit-Perfect playback and on the AAudio Direct output path'**
  String get settingsDvcDesc;

  /// No description provided for @settingsDvcTitle.
  ///
  /// In en, this message translates to:
  /// **'Direct Volume Control (DVC)'**
  String get settingsDvcTitle;

  /// No description provided for @settingsEnableBitPerfectFirst.
  ///
  /// In en, this message translates to:
  /// **'Enable Bit-Perfect USB Pass-Through first'**
  String get settingsEnableBitPerfectFirst;

  /// No description provided for @settingsEnglishNative.
  ///
  /// In en, this message translates to:
  /// **'English (US/UK)'**
  String get settingsEnglishNative;

  /// No description provided for @settingsEnterProxyHost.
  ///
  /// In en, this message translates to:
  /// **'Please enter a proxy host'**
  String get settingsEnterProxyHost;

  /// No description provided for @settingsExclusiveUsb.
  ///
  /// In en, this message translates to:
  /// **'Exclusive USB Interface'**
  String get settingsExclusiveUsb;

  /// No description provided for @settingsExclusiveUsbDesc.
  ///
  /// In en, this message translates to:
  /// **'Claims the AudioStreaming interface when the kernel driver releases it. Non-forced: never detaches Android\'s audio driver'**
  String get settingsExclusiveUsbDesc;

  /// No description provided for @settingsExportSessionLogs.
  ///
  /// In en, this message translates to:
  /// **'Export audio session logs'**
  String get settingsExportSessionLogs;

  /// No description provided for @settingsExportSessionLogsDesc.
  ///
  /// In en, this message translates to:
  /// **'Share the on-device JSONL log of your recent playback sessions'**
  String get settingsExportSessionLogsDesc;

  /// No description provided for @settingsExtendedSpeedRange.
  ///
  /// In en, this message translates to:
  /// **'Extended speed range'**
  String get settingsExtendedSpeedRange;

  /// No description provided for @settingsExtendedSpeedRangeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Allow 0.1x–8.0x playback speed (default 0.25x–4.0x)'**
  String get settingsExtendedSpeedRangeSubtitle;

  /// No description provided for @settingsFloatDspDesc.
  ///
  /// In en, this message translates to:
  /// **'Hi-res first: feeds the native DSP chain float32 samples so 24/32-bit sources keep their depth (16-bit content is unaffected). Unsupported devices safely fall back to 16-bit'**
  String get settingsFloatDspDesc;

  /// No description provided for @settingsFloatDspPath.
  ///
  /// In en, this message translates to:
  /// **'24/32-bit Float DSP Path'**
  String get settingsFloatDspPath;

  /// No description provided for @settingsGoogleCast.
  ///
  /// In en, this message translates to:
  /// **'Google Cast'**
  String get settingsGoogleCast;

  /// No description provided for @settingsHardwareAudioOutput.
  ///
  /// In en, this message translates to:
  /// **'Hardware Audio Output'**
  String get settingsHardwareAudioOutput;

  /// No description provided for @settingsHedgedStreaming.
  ///
  /// In en, this message translates to:
  /// **'Hedged streaming'**
  String get settingsHedgedStreaming;

  /// No description provided for @settingsHedgedStreamingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Race two resolvers, take the fastest URL'**
  String get settingsHedgedStreamingSubtitle;

  /// No description provided for @settingsHttpLabel.
  ///
  /// In en, this message translates to:
  /// **'HTTP'**
  String get settingsHttpLabel;

  /// No description provided for @settingsImportPasteProxies.
  ///
  /// In en, this message translates to:
  /// **'Import / Paste Proxies'**
  String get settingsImportPasteProxies;

  /// No description provided for @settingsInteractionLabel.
  ///
  /// In en, this message translates to:
  /// **'Interaction reminders'**
  String get settingsInteractionLabel;

  /// No description provided for @settingsInternalUsbDac.
  ///
  /// In en, this message translates to:
  /// **'Internal / USB DAC'**
  String get settingsInternalUsbDac;

  /// No description provided for @settingsIntroLabel.
  ///
  /// In en, this message translates to:
  /// **'Intros / intermissions'**
  String get settingsIntroLabel;

  /// No description provided for @settingsInvalidPort.
  ///
  /// In en, this message translates to:
  /// **'Invalid port (1-65535)'**
  String get settingsInvalidPort;

  /// No description provided for @settingsLatencyMs.
  ///
  /// In en, this message translates to:
  /// **'Latency: {ms} ms'**
  String settingsLatencyMs(int ms);

  /// No description provided for @settingsLeaveBlankAuth.
  ///
  /// In en, this message translates to:
  /// **'Leave blank if unauthenticated'**
  String get settingsLeaveBlankAuth;

  /// No description provided for @settingsLowerVolume.
  ///
  /// In en, this message translates to:
  /// **'Lower playback volume'**
  String get settingsLowerVolume;

  /// No description provided for @settingsManageYtm.
  ///
  /// In en, this message translates to:
  /// **'Manage YouTube Music'**
  String get settingsManageYtm;

  /// No description provided for @settingsMasterAudioEngine.
  ///
  /// In en, this message translates to:
  /// **'Master Audio Engine'**
  String get settingsMasterAudioEngine;

  /// No description provided for @settingsNoneSelectedAutoSkip.
  ///
  /// In en, this message translates to:
  /// **'None selected — auto-skip disabled'**
  String get settingsNoneSelectedAutoSkip;

  /// No description provided for @settingsNonMusicLabel.
  ///
  /// In en, this message translates to:
  /// **'Non-music sections'**
  String get settingsNonMusicLabel;

  /// No description provided for @settingsNotAvailablePlatform.
  ///
  /// In en, this message translates to:
  /// **'Not available on this platform'**
  String get settingsNotAvailablePlatform;

  /// No description provided for @settingsNotDetectable.
  ///
  /// In en, this message translates to:
  /// **'Not detectable on this platform'**
  String get settingsNotDetectable;

  /// No description provided for @settingsNothingToCast.
  ///
  /// In en, this message translates to:
  /// **'Nothing is playing to cast'**
  String get settingsNothingToCast;

  /// No description provided for @settingsOutputAudioQuality.
  ///
  /// In en, this message translates to:
  /// **'Output & Audio Quality'**
  String get settingsOutputAudioQuality;

  /// No description provided for @settingsOutputDeviceConfigHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to configure Output Device • Sample Rate ({rate} kHz) • Bit Depth ({bits}-bit)'**
  String settingsOutputDeviceConfigHint(int rate, int bits);

  /// No description provided for @settingsOutroLabel.
  ///
  /// In en, this message translates to:
  /// **'Outros / endcards'**
  String get settingsOutroLabel;

  /// No description provided for @settingsPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get settingsPasswordLabel;

  /// No description provided for @settingsPerAlbumEqMemory.
  ///
  /// In en, this message translates to:
  /// **'Per-album EQ memory'**
  String get settingsPerAlbumEqMemory;

  /// No description provided for @settingsPerAlbumEqMemorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore EQ snapshot per album/artist'**
  String get settingsPerAlbumEqMemorySubtitle;

  /// No description provided for @settingsPerTrackFormatDesc.
  ///
  /// In en, this message translates to:
  /// **'Hi-res first: requests each track\'s native sample rate / bit depth from the output device (device-capped). Bit-Perfect keeps its exclusive format. Turn off to use one manual output format'**
  String get settingsPerTrackFormatDesc;

  /// No description provided for @settingsPerTrackFormatNegotiation.
  ///
  /// In en, this message translates to:
  /// **'Per-Track Output Format Negotiation'**
  String get settingsPerTrackFormatNegotiation;

  /// No description provided for @settingsPortHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 8080'**
  String get settingsPortHint;

  /// No description provided for @settingsPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get settingsPortLabel;

  /// No description provided for @settingsPreampWithoutRg.
  ///
  /// In en, this message translates to:
  /// **'Preamp (Without RG tag fallback)'**
  String get settingsPreampWithoutRg;

  /// No description provided for @settingsPreampWithRg.
  ///
  /// In en, this message translates to:
  /// **'Preamp (With RG tag)'**
  String get settingsPreampWithRg;

  /// No description provided for @settingsPrivacyControlBody.
  ///
  /// In en, this message translates to:
  /// **'Cloud sync and remote metadata can be disabled. Automation rules and device profiles are stored locally.'**
  String get settingsPrivacyControlBody;

  /// No description provided for @settingsPrivacyControlTitle.
  ///
  /// In en, this message translates to:
  /// **'You stay in control'**
  String get settingsPrivacyControlTitle;

  /// No description provided for @settingsPrivacyNoTrackersBody.
  ///
  /// In en, this message translates to:
  /// **'Pure (Play Store) builds ship without the INTERNET permission, analytics SDKs or advertising identifiers.'**
  String get settingsPrivacyNoTrackersBody;

  /// No description provided for @settingsPrivacyNoTrackersTitle.
  ///
  /// In en, this message translates to:
  /// **'No trackers in Pure'**
  String get settingsPrivacyNoTrackersTitle;

  /// No description provided for @settingsPrivacyOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Your library, playback and settings live on this device. Nothing is uploaded unless you explicitly sign in for cloud sync.'**
  String get settingsPrivacyOfflineBody;

  /// No description provided for @settingsPrivacyOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline-first'**
  String get settingsPrivacyOfflineTitle;

  /// No description provided for @settingsPrivacyPermissionsBody.
  ///
  /// In en, this message translates to:
  /// **'Storage/media access is used only to scan and play your local audio. Bluetooth and notification access are requested only for connected-audio features and playback controls.'**
  String get settingsPrivacyPermissionsBody;

  /// No description provided for @settingsPrivacyPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions are purposeful'**
  String get settingsPrivacyPermissionsTitle;

  /// No description provided for @settingsProxyActiveDesc.
  ///
  /// In en, this message translates to:
  /// **'Traffic routes through configured proxy'**
  String get settingsProxyActiveDesc;

  /// No description provided for @settingsProxyHttpDesc.
  ///
  /// In en, this message translates to:
  /// **'Routes standard HTTP & HTTPS web and stream extraction traffic.'**
  String get settingsProxyHttpDesc;

  /// No description provided for @settingsProxyInactiveDesc.
  ///
  /// In en, this message translates to:
  /// **'Direct connection (proxy disabled)'**
  String get settingsProxyInactiveDesc;

  /// No description provided for @settingsProxySocksDesc.
  ///
  /// In en, this message translates to:
  /// **'Routes network packets via SOCKS5 (recommended for Tor, Clash, Shadowsocks). Note: SOCKS5 applies on the native stream layer; in-app Dart API calls (search, artwork, lyrics) fall back to DIRECT when SOCKS5 is active.'**
  String get settingsProxySocksDesc;

  /// No description provided for @settingsQualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High (~160+ kbps • Best)'**
  String get settingsQualityHigh;

  /// No description provided for @settingsQualityHighDownloadDesc.
  ///
  /// In en, this message translates to:
  /// **'Highest quality audio files (~160+ kbps M4A)'**
  String get settingsQualityHighDownloadDesc;

  /// No description provided for @settingsQualityHighStreamDesc.
  ///
  /// In en, this message translates to:
  /// **'Highest available bitrate (~160+ kbps) for crystal clear sound'**
  String get settingsQualityHighStreamDesc;

  /// No description provided for @settingsQualityLow.
  ///
  /// In en, this message translates to:
  /// **'Low (~64 kbps • Data Saver)'**
  String get settingsQualityLow;

  /// No description provided for @settingsQualityLowDownloadDesc.
  ///
  /// In en, this message translates to:
  /// **'Smallest file size (~64 kbps)'**
  String get settingsQualityLowDownloadDesc;

  /// No description provided for @settingsQualityLowStreamDesc.
  ///
  /// In en, this message translates to:
  /// **'Reduced data usage (~64 kbps) for slow connections'**
  String get settingsQualityLowStreamDesc;

  /// No description provided for @settingsQualityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium (~128 kbps)'**
  String get settingsQualityMedium;

  /// No description provided for @settingsQualityMediumDownloadDesc.
  ///
  /// In en, this message translates to:
  /// **'Standard file size and quality (~128 kbps M4A)'**
  String get settingsQualityMediumDownloadDesc;

  /// No description provided for @settingsQualityMediumStreamDesc.
  ///
  /// In en, this message translates to:
  /// **'Standard bitrate (~128 kbps) with balanced data usage'**
  String get settingsQualityMediumStreamDesc;

  /// No description provided for @settingsRaiseVolume.
  ///
  /// In en, this message translates to:
  /// **'Raise playback volume'**
  String get settingsRaiseVolume;

  /// No description provided for @settingsRemoveProxy.
  ///
  /// In en, this message translates to:
  /// **'Remove proxy'**
  String get settingsRemoveProxy;

  /// No description provided for @settingsReplayGainDesc.
  ///
  /// In en, this message translates to:
  /// **'Track / album gain from tags, applied during playback'**
  String get settingsReplayGainDesc;

  /// No description provided for @settingsRequiresUacDac.
  ///
  /// In en, this message translates to:
  /// **'Requires a UAC DAC with volume control'**
  String get settingsRequiresUacDac;

  /// No description provided for @settingsResamplerFast.
  ///
  /// In en, this message translates to:
  /// **'Fast (Linear)'**
  String get settingsResamplerFast;

  /// No description provided for @settingsResamplerHigh.
  ///
  /// In en, this message translates to:
  /// **'High (32-tap)'**
  String get settingsResamplerHigh;

  /// No description provided for @settingsResamplerQuality.
  ///
  /// In en, this message translates to:
  /// **'Resampler Quality'**
  String get settingsResamplerQuality;

  /// No description provided for @settingsResamplerQualityDesc.
  ///
  /// In en, this message translates to:
  /// **'Sample-rate conversion quality. Ultra is the full 64-tap polyphase sinc (historical default); Fast is linear interpolation for minimal CPU on battery'**
  String get settingsResamplerQualityDesc;

  /// No description provided for @settingsResamplerStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard (16-tap)'**
  String get settingsResamplerStandard;

  /// No description provided for @settingsResamplerUltra.
  ///
  /// In en, this message translates to:
  /// **'Ultra (64-tap)'**
  String get settingsResamplerUltra;

  /// No description provided for @settingsResetToDefaultValue.
  ///
  /// In en, this message translates to:
  /// **'Reset to default ({value})'**
  String settingsResetToDefaultValue(String value);

  /// No description provided for @settingsResolvedCrossfade.
  ///
  /// In en, this message translates to:
  /// **'Resolved: Gapless off — Crossfade set to {seconds}s'**
  String settingsResolvedCrossfade(String seconds);

  /// No description provided for @settingsResolvedGapless.
  ///
  /// In en, this message translates to:
  /// **'Resolved: Gapless disabled'**
  String get settingsResolvedGapless;

  /// No description provided for @settingsSearchAboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version {version}, build details and licenses'**
  String settingsSearchAboutSubtitle(String version);

  /// No description provided for @settingsSearchAccentColorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Custom color accent palette for buttons and active highlights'**
  String get settingsSearchAccentColorSubtitle;

  /// No description provided for @settingsSearchAccentColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get settingsSearchAccentColorTitle;

  /// No description provided for @settingsSearchBitPerfectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Direct USB DAC hardware sample-rate matching'**
  String get settingsSearchBitPerfectSubtitle;

  /// No description provided for @settingsSearchBitPerfectTitle.
  ///
  /// In en, this message translates to:
  /// **'Bit-Perfect & Hi-Res Output'**
  String get settingsSearchBitPerfectTitle;

  /// No description provided for @settingsSearchCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clear cached cover artwork and stream chunks'**
  String get settingsSearchCacheSubtitle;

  /// No description provided for @settingsSearchCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Artwork & Audio Cache'**
  String get settingsSearchCacheTitle;

  /// No description provided for @settingsSearchCategoryAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSearchCategoryAbout;

  /// No description provided for @settingsSearchCategoryAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get settingsSearchCategoryAudio;

  /// No description provided for @settingsSearchCategoryNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsSearchCategoryNetwork;

  /// No description provided for @settingsSearchCategoryPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsSearchCategoryPrivacy;

  /// No description provided for @settingsSearchCategoryStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get settingsSearchCategoryStorage;

  /// No description provided for @settingsSearchCrossfadeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Seamless transitions and crossfade seconds slider'**
  String get settingsSearchCrossfadeSubtitle;

  /// No description provided for @settingsSearchCrossfadeTitle.
  ///
  /// In en, this message translates to:
  /// **'Crossfade & Gapless'**
  String get settingsSearchCrossfadeTitle;

  /// No description provided for @settingsSearchEqualizerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'10-band equalizer, bass boost, virtualizer, reverb'**
  String get settingsSearchEqualizerSubtitle;

  /// No description provided for @settingsSearchHiddenFoldersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Exclude voice memos, ringtones, and specific directories'**
  String get settingsSearchHiddenFoldersSubtitle;

  /// No description provided for @settingsSearchHighContrastTitle.
  ///
  /// In en, this message translates to:
  /// **'High Contrast Mode'**
  String get settingsSearchHighContrastTitle;

  /// No description provided for @settingsSearchNowPlayingThemeTitle.
  ///
  /// In en, this message translates to:
  /// **'Now Playing Theme Style'**
  String get settingsSearchNowPlayingThemeTitle;

  /// No description provided for @settingsSearchPrivacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Offline-first principles and permissions explanations'**
  String get settingsSearchPrivacySubtitle;

  /// No description provided for @settingsSearchPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Guarantee'**
  String get settingsSearchPrivacyTitle;

  /// No description provided for @settingsSearchProxySubtitle.
  ///
  /// In en, this message translates to:
  /// **'HTTP & SOCKS5 proxy routing with latency checks'**
  String get settingsSearchProxySubtitle;

  /// No description provided for @settingsSearchQualitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bitrate preferences for online streaming and saved files'**
  String get settingsSearchQualitySubtitle;

  /// No description provided for @settingsSearchQualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Streaming & Download Audio Quality'**
  String get settingsSearchQualityTitle;

  /// No description provided for @settingsSearchRescanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Discover newly downloaded songs and update metadata'**
  String get settingsSearchRescanSubtitle;

  /// No description provided for @settingsSearchRescanTitle.
  ///
  /// In en, this message translates to:
  /// **'Rescan Device Storage'**
  String get settingsSearchRescanTitle;

  /// No description provided for @settingsSearchScrobblingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track listening history and broadcast Now Playing status'**
  String get settingsSearchScrobblingSubtitle;

  /// No description provided for @settingsSearchSleepTimerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically stop playback after duration or end of track'**
  String get settingsSearchSleepTimerSubtitle;

  /// No description provided for @settingsSearchSwipeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Left & Right swipe actions (Skip, Previous, Volume)'**
  String get settingsSearchSwipeSubtitle;

  /// No description provided for @settingsSearchSwipeTitle.
  ///
  /// In en, this message translates to:
  /// **'Mini-Player Swipe Gestures'**
  String get settingsSearchSwipeTitle;

  /// No description provided for @settingsSearchThemeModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'System Default, Light, Dark, or AMOLED high contrast'**
  String get settingsSearchThemeModeSubtitle;

  /// No description provided for @settingsSearchThemeModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get settingsSearchThemeModeTitle;

  /// No description provided for @settingsSearchVisualizerStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Visualizer Style'**
  String get settingsSearchVisualizerStyleTitle;

  /// No description provided for @settingsSelfPromoLabel.
  ///
  /// In en, this message translates to:
  /// **'Self-promotion'**
  String get settingsSelfPromoLabel;

  /// No description provided for @settingsServerHost.
  ///
  /// In en, this message translates to:
  /// **'Server Host / IP Address'**
  String get settingsServerHost;

  /// No description provided for @settingsServerHostHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 127.0.0.1 or proxy.example.com'**
  String get settingsServerHostHint;

  /// No description provided for @settingsSessionDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Session Audio Diagnostics'**
  String get settingsSessionDiagnostics;

  /// No description provided for @settingsSessionDiagnosticsDesc.
  ///
  /// In en, this message translates to:
  /// **'Records one log per track: route type, Bluetooth codec, negotiated sample rate / bit depth, interruptions and dropout counts'**
  String get settingsSessionDiagnosticsDesc;

  /// No description provided for @settingsSessionLogsShareText.
  ///
  /// In en, this message translates to:
  /// **'Pulsr audio session logs'**
  String get settingsSessionLogsShareText;

  /// No description provided for @settingsSilenceSkipSensitivity.
  ///
  /// In en, this message translates to:
  /// **'Silence-skip sensitivity'**
  String get settingsSilenceSkipSensitivity;

  /// No description provided for @settingsSkipCategories.
  ///
  /// In en, this message translates to:
  /// **'Skip categories'**
  String get settingsSkipCategories;

  /// No description provided for @settingsSpanishNative.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get settingsSpanishNative;

  /// No description provided for @settingsSpeakerBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Speaker + Bluetooth'**
  String get settingsSpeakerBluetooth;

  /// No description provided for @settingsSpeakerBluetoothSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Best-effort simultaneous output (falls back gracefully)'**
  String get settingsSpeakerBluetoothSubtitle;

  /// No description provided for @settingsSponsorBlock.
  ///
  /// In en, this message translates to:
  /// **'SponsorBlock'**
  String get settingsSponsorBlock;

  /// No description provided for @settingsSponsorBlockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-skip sponsor and non-music segments in YouTube tracks'**
  String get settingsSponsorBlockSubtitle;

  /// No description provided for @settingsSponsorLabel.
  ///
  /// In en, this message translates to:
  /// **'Sponsors'**
  String get settingsSponsorLabel;

  /// No description provided for @settingsStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get settingsStarting;

  /// No description provided for @settingsStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String settingsStatusLabel(String status);

  /// No description provided for @settingsStreamingClaimed.
  ///
  /// In en, this message translates to:
  /// **'Streaming interface claimed exclusively'**
  String get settingsStreamingClaimed;

  /// No description provided for @settingsSwipeAdjustVolume.
  ///
  /// In en, this message translates to:
  /// **'Adjust Volume'**
  String get settingsSwipeAdjustVolume;

  /// No description provided for @settingsSwipeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsSwipeDisabled;

  /// No description provided for @settingsSwipeIgnoreDesc.
  ///
  /// In en, this message translates to:
  /// **'Ignore swipe gesture'**
  String get settingsSwipeIgnoreDesc;

  /// No description provided for @settingsSwipeLeftAction.
  ///
  /// In en, this message translates to:
  /// **'MiniPlayer Swipe Left Action'**
  String get settingsSwipeLeftAction;

  /// No description provided for @settingsSwipeNextDesc.
  ///
  /// In en, this message translates to:
  /// **'Skip to the next song in the queue'**
  String get settingsSwipeNextDesc;

  /// No description provided for @settingsSwipeNextTrack.
  ///
  /// In en, this message translates to:
  /// **'Next Track'**
  String get settingsSwipeNextTrack;

  /// No description provided for @settingsSwipePrevDesc.
  ///
  /// In en, this message translates to:
  /// **'Skip to the previous song or restart track'**
  String get settingsSwipePrevDesc;

  /// No description provided for @settingsSwipePreviousTrack.
  ///
  /// In en, this message translates to:
  /// **'Previous Track'**
  String get settingsSwipePreviousTrack;

  /// No description provided for @settingsSwipeRightAction.
  ///
  /// In en, this message translates to:
  /// **'MiniPlayer Swipe Right Action'**
  String get settingsSwipeRightAction;

  /// No description provided for @settingsSyncingLibrary.
  ///
  /// In en, this message translates to:
  /// **'Syncing your library...'**
  String get settingsSyncingLibrary;

  /// No description provided for @settingsSyncOffset.
  ///
  /// In en, this message translates to:
  /// **'Sync Offset'**
  String get settingsSyncOffset;

  /// No description provided for @settingsTestAllSpeeds.
  ///
  /// In en, this message translates to:
  /// **'Test All Speeds'**
  String get settingsTestAllSpeeds;

  /// No description provided for @settingsTestingAll.
  ///
  /// In en, this message translates to:
  /// **'Testing All...'**
  String get settingsTestingAll;

  /// No description provided for @settingsTestingProxyConnectivity.
  ///
  /// In en, this message translates to:
  /// **'Testing Proxy Connectivity...'**
  String get settingsTestingProxyConnectivity;

  /// No description provided for @settingsTestLatency.
  ///
  /// In en, this message translates to:
  /// **'Test latency'**
  String get settingsTestLatency;

  /// No description provided for @settingsThemeCardGlass.
  ///
  /// In en, this message translates to:
  /// **'Card Glass Overlay'**
  String get settingsThemeCardGlass;

  /// No description provided for @settingsThemeCardGlassDesc.
  ///
  /// In en, this message translates to:
  /// **'Full-bleed background artwork with frosted glass controls'**
  String get settingsThemeCardGlassDesc;

  /// No description provided for @settingsThemeClassicStandard.
  ///
  /// In en, this message translates to:
  /// **'Classic Standard'**
  String get settingsThemeClassicStandard;

  /// No description provided for @settingsThemeClassicStandardDesc.
  ///
  /// In en, this message translates to:
  /// **'Traditional high-definition layout with ambient glow'**
  String get settingsThemeClassicStandardDesc;

  /// No description provided for @settingsThemeFullBleed.
  ///
  /// In en, this message translates to:
  /// **'Full-Bleed Waveform'**
  String get settingsThemeFullBleed;

  /// No description provided for @settingsThemeFullBleedDesc.
  ///
  /// In en, this message translates to:
  /// **'Full screen audio-reactive glowing waveform visualizer backdrop'**
  String get settingsThemeFullBleedDesc;

  /// No description provided for @settingsThemeKaraoke.
  ///
  /// In en, this message translates to:
  /// **'Karaoke Lyrics Immersion'**
  String get settingsThemeKaraoke;

  /// No description provided for @settingsThemeKaraokeDesc.
  ///
  /// In en, this message translates to:
  /// **'Magnified synchronized lyrics-first karaoke player interface'**
  String get settingsThemeKaraokeDesc;

  /// No description provided for @settingsThemeMinimalist.
  ///
  /// In en, this message translates to:
  /// **'Minimalist Waveform'**
  String get settingsThemeMinimalist;

  /// No description provided for @settingsThemeMinimalistDesc.
  ///
  /// In en, this message translates to:
  /// **'Spacious studio focus on dynamic audio waveform visualizer'**
  String get settingsThemeMinimalistDesc;

  /// No description provided for @settingsThemeRetroCassette.
  ///
  /// In en, this message translates to:
  /// **'Retro Cassette Deck'**
  String get settingsThemeRetroCassette;

  /// No description provided for @settingsThemeRetroCassetteDesc.
  ///
  /// In en, this message translates to:
  /// **'Vintage cassette tape with spinning spools & magnetic tape counter'**
  String get settingsThemeRetroCassetteDesc;

  /// No description provided for @settingsThemeVinylCircle.
  ///
  /// In en, this message translates to:
  /// **'Vinyl Circle (Spinning)'**
  String get settingsThemeVinylCircle;

  /// No description provided for @settingsThemeVinylCircleDesc.
  ///
  /// In en, this message translates to:
  /// **'Centered circular artwork with continuous spinning animation'**
  String get settingsThemeVinylCircleDesc;

  /// No description provided for @settingsThemeVinylTurntable.
  ///
  /// In en, this message translates to:
  /// **'Vinyl Turntable Studio'**
  String get settingsThemeVinylTurntable;

  /// No description provided for @settingsThemeVinylTurntableDesc.
  ///
  /// In en, this message translates to:
  /// **'True vinyl record with realistic grooves, center label & tonearm'**
  String get settingsThemeVinylTurntableDesc;

  /// No description provided for @settingsTurnOffGapless.
  ///
  /// In en, this message translates to:
  /// **'Turn off Gapless'**
  String get settingsTurnOffGapless;

  /// No description provided for @settingsTurnOffGaplessEnableCrossfade.
  ///
  /// In en, this message translates to:
  /// **'Turn off Gapless & enable Crossfade'**
  String get settingsTurnOffGaplessEnableCrossfade;

  /// No description provided for @settingsUnavailableAaudio.
  ///
  /// In en, this message translates to:
  /// **'Unavailable while AAudio Direct output is enabled'**
  String get settingsUnavailableAaudio;

  /// No description provided for @settingsUnknownConnectionFailure.
  ///
  /// In en, this message translates to:
  /// **'Unknown connection failure'**
  String get settingsUnknownConnectionFailure;

  /// No description provided for @settingsUsbBitPerfectStreaming.
  ///
  /// In en, this message translates to:
  /// **'USB Bit-Perfect Streaming (Experimental)'**
  String get settingsUsbBitPerfectStreaming;

  /// No description provided for @settingsUsbDacHardwareVolume.
  ///
  /// In en, this message translates to:
  /// **'USB DAC Hardware Volume'**
  String get settingsUsbDacHardwareVolume;

  /// No description provided for @settingsUsbHwVolumeDesc.
  ///
  /// In en, this message translates to:
  /// **'Drives the {uac} DAC\'s own volume stage directly (lower distortion at low volume). {device}'**
  String settingsUsbHwVolumeDesc(String uac, String device);

  /// No description provided for @settingsUsbHwVolumeGrant.
  ///
  /// In en, this message translates to:
  /// **'Grant USB access to control the DAC\'s hardware volume directly'**
  String get settingsUsbHwVolumeGrant;

  /// No description provided for @settingsUsbStreamingActive.
  ///
  /// In en, this message translates to:
  /// **'Raw UAC2 isochronous streaming is active'**
  String get settingsUsbStreamingActive;

  /// No description provided for @settingsUsbStreamingDesc.
  ///
  /// In en, this message translates to:
  /// **'Claims the DAC exclusively and streams processed PCM directly over USB isochronous URBs. Unvalidated on hardware; falls back safely if the claim or endpoint setup fails'**
  String get settingsUsbStreamingDesc;

  /// No description provided for @settingsUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get settingsUsernameLabel;

  /// No description provided for @settingsVisualizerAlbumReactive.
  ///
  /// In en, this message translates to:
  /// **'Album Art Reactive Glow'**
  String get settingsVisualizerAlbumReactive;

  /// No description provided for @settingsVisualizerBarClassic.
  ///
  /// In en, this message translates to:
  /// **'Bar (Classic Frequency Spectrum)'**
  String get settingsVisualizerBarClassic;

  /// No description provided for @settingsVisualizerCircular.
  ///
  /// In en, this message translates to:
  /// **'Circular (Radial Spectrum)'**
  String get settingsVisualizerCircular;

  /// No description provided for @settingsVisualizerCustomJson.
  ///
  /// In en, this message translates to:
  /// **'Custom JSON Visualizer'**
  String get settingsVisualizerCustomJson;

  /// No description provided for @settingsVisualizerMilkdrop.
  ///
  /// In en, this message translates to:
  /// **'Milkdrop Preset Visualizer'**
  String get settingsVisualizerMilkdrop;

  /// No description provided for @settingsVisualizerOff.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsVisualizerOff;

  /// No description provided for @settingsVisualizerParticles.
  ///
  /// In en, this message translates to:
  /// **'Particles (Audio Field)'**
  String get settingsVisualizerParticles;

  /// No description provided for @settingsVisualizerTerrain3d.
  ///
  /// In en, this message translates to:
  /// **'3D Terrain (Wireframe Mountain)'**
  String get settingsVisualizerTerrain3d;

  /// No description provided for @settingsVisualizerWaveSmooth.
  ///
  /// In en, this message translates to:
  /// **'Wave (Smooth Line Spectrum)'**
  String get settingsVisualizerWaveSmooth;

  /// No description provided for @settingsVizBarDesc.
  ///
  /// In en, this message translates to:
  /// **'Classic vertical frequency bars with smooth height animation'**
  String get settingsVizBarDesc;

  /// No description provided for @settingsVizCircularDesc.
  ///
  /// In en, this message translates to:
  /// **'Futuristic radial frequency bars surrounding album centerpiece'**
  String get settingsVizCircularDesc;

  /// No description provided for @settingsVizCustomDesc.
  ///
  /// In en, this message translates to:
  /// **'User-authored JSON preset: bars / wave / radial / particles / lissajous'**
  String get settingsVizCustomDesc;

  /// No description provided for @settingsVizLabelBar.
  ///
  /// In en, this message translates to:
  /// **'BAR'**
  String get settingsVizLabelBar;

  /// No description provided for @settingsVizLabelCircular.
  ///
  /// In en, this message translates to:
  /// **'CIRCULAR'**
  String get settingsVizLabelCircular;

  /// No description provided for @settingsVizLabelCustom.
  ///
  /// In en, this message translates to:
  /// **'CUSTOM (JSON)'**
  String get settingsVizLabelCustom;

  /// No description provided for @settingsVizLabelMilkdrop.
  ///
  /// In en, this message translates to:
  /// **'MILKDROP'**
  String get settingsVizLabelMilkdrop;

  /// No description provided for @settingsVizLabelOff.
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get settingsVizLabelOff;

  /// No description provided for @settingsVizLabelWave.
  ///
  /// In en, this message translates to:
  /// **'WAVE'**
  String get settingsVizLabelWave;

  /// Visualizer particles style label
  ///
  /// In en, this message translates to:
  /// **'PARTICLES'**
  String get settingsVizLabelParticles;

  /// Visualizer particles style description
  ///
  /// In en, this message translates to:
  /// **'GPU particle field pulsing with bass energy'**
  String get settingsVizParticlesDesc;

  /// Visualizer 3D terrain style label
  ///
  /// In en, this message translates to:
  /// **'TERRAIN 3D'**
  String get settingsVizLabelTerrain;

  /// Visualizer 3D terrain style description
  ///
  /// In en, this message translates to:
  /// **'3D audio terrain landscape sculpted by the spectrum'**
  String get settingsVizTerrainDesc;

  /// Visualizer album-reactive style label
  ///
  /// In en, this message translates to:
  /// **'ALBUM REACTIVE'**
  String get settingsVizLabelAlbumReactive;

  /// Visualizer album-reactive style description
  ///
  /// In en, this message translates to:
  /// **'Album artwork that breathes with the music'**
  String get settingsVizAlbumReactiveDesc;

  /// No description provided for @settingsVizOffDesc.
  ///
  /// In en, this message translates to:
  /// **'Disable audio visualizer spectrum animation'**
  String get settingsVizOffDesc;

  /// No description provided for @settingsVizWaveDesc.
  ///
  /// In en, this message translates to:
  /// **'Smooth continuous Bézier waveform line with ambient gradient fill'**
  String get settingsVizWaveDesc;

  /// No description provided for @settingsAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About {title}'**
  String settingsAboutTitle(String title);

  /// No description provided for @settingsActiveBadge.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get settingsActiveBadge;

  /// No description provided for @settingsActiveProxyProtocol.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE PROXY PROTOCOL'**
  String get settingsActiveProxyProtocol;

  /// No description provided for @settingsActiveServerConfig.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE SERVER CONFIGURATION'**
  String get settingsActiveServerConfig;

  /// No description provided for @settingsAdaptiveQuality.
  ///
  /// In en, this message translates to:
  /// **'Adaptive quality'**
  String get settingsAdaptiveQuality;

  /// No description provided for @settingsAdaptiveQualitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Step bitrate down/up mid-track on stalls'**
  String get settingsAdaptiveQualitySubtitle;

  /// No description provided for @settingsAaudioBufferSize.
  ///
  /// In en, this message translates to:
  /// **'AAudio Buffer Size'**
  String get settingsAaudioBufferSize;

  /// No description provided for @settingsAaudioBufferSizeDesc.
  ///
  /// In en, this message translates to:
  /// **'Stream buffer capacity hint in milliseconds. Lower = lower latency (wired), higher = more stall resistance'**
  String get settingsAaudioBufferSizeDesc;

  /// No description provided for @settingsAaudioDirect.
  ///
  /// In en, this message translates to:
  /// **'AAudio Direct Output (Bit-Perfect)'**
  String get settingsAaudioDirect;

  /// No description provided for @settingsAaudioDirectDesc.
  ///
  /// In en, this message translates to:
  /// **'Bypasses the system mixer with a native AAudio stream opened at each track rate (EXCLUSIVE attempt, SHARED fallback). The DSP chain and speed/pitch controls are inactive in this mode; applies to newly built players'**
  String get settingsAaudioDirectDesc;

  /// No description provided for @dspAboutBassBoost.
  ///
  /// In en, this message translates to:
  /// **'About Bass Boost'**
  String get dspAboutBassBoost;

  /// No description provided for @dspAboutBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'About Bit-Perfect'**
  String get dspAboutBitPerfect;

  /// No description provided for @dspAboutCrossfeed.
  ///
  /// In en, this message translates to:
  /// **'About Crossfeed'**
  String get dspAboutCrossfeed;

  /// No description provided for @dspAboutDspEngine.
  ///
  /// In en, this message translates to:
  /// **'About DSP Engine'**
  String get dspAboutDspEngine;

  /// No description provided for @dspAboutDynamics.
  ///
  /// In en, this message translates to:
  /// **'About Dynamics'**
  String get dspAboutDynamics;

  /// No description provided for @dspAboutEqualizer.
  ///
  /// In en, this message translates to:
  /// **'About Equalizer'**
  String get dspAboutEqualizer;

  /// No description provided for @dspAboutLimiter.
  ///
  /// In en, this message translates to:
  /// **'About Limiter'**
  String get dspAboutLimiter;

  /// No description provided for @dspAboutReverb.
  ///
  /// In en, this message translates to:
  /// **'About Reverb'**
  String get dspAboutReverb;

  /// No description provided for @dspAboutSpatializer.
  ///
  /// In en, this message translates to:
  /// **'About Spatializer'**
  String get dspAboutSpatializer;

  /// No description provided for @dspAboutStereoBalance.
  ///
  /// In en, this message translates to:
  /// **'About Stereo Balance'**
  String get dspAboutStereoBalance;

  /// No description provided for @dspAboutVirtualizer.
  ///
  /// In en, this message translates to:
  /// **'About Virtualizer'**
  String get dspAboutVirtualizer;

  /// No description provided for @dspAboutVolumeBoost.
  ///
  /// In en, this message translates to:
  /// **'About Volume Boost'**
  String get dspAboutVolumeBoost;

  /// No description provided for @dspActiveEffects.
  ///
  /// In en, this message translates to:
  /// **'active effects (Reverb, Limiter...)'**
  String get dspActiveEffects;

  /// No description provided for @dspAddLine.
  ///
  /// In en, this message translates to:
  /// **'Add Line'**
  String get dspAddLine;

  /// No description provided for @dspAllEffectsBypassed.
  ///
  /// In en, this message translates to:
  /// **'All DSP effects bypassed'**
  String get dspAllEffectsBypassed;

  /// No description provided for @dspAppliedProfile.
  ///
  /// In en, this message translates to:
  /// **'Applied profile:'**
  String get dspAppliedProfile;

  /// No description provided for @dspAttackTime.
  ///
  /// In en, this message translates to:
  /// **'Attack Time'**
  String get dspAttackTime;

  /// No description provided for @dspAudioFormatCodec.
  ///
  /// In en, this message translates to:
  /// **'Audio Format & Codec'**
  String get dspAudioFormatCodec;

  /// No description provided for @dspAutoEqVerified.
  ///
  /// In en, this message translates to:
  /// **'AutoEQ Verified'**
  String get dspAutoEqVerified;

  /// No description provided for @dspBassStrength.
  ///
  /// In en, this message translates to:
  /// **'Bass Strength'**
  String get dspBassStrength;

  /// No description provided for @dspBitPerfectLosslessStream.
  ///
  /// In en, this message translates to:
  /// **'Bit-perfect Lossless Stream'**
  String get dspBitPerfectLosslessStream;

  /// No description provided for @dspBlocked.
  ///
  /// In en, this message translates to:
  /// **'BLOCKED'**
  String get dspBlocked;

  /// No description provided for @dspBlockedBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Blocked: Bit-Perfect bypass active'**
  String get dspBlockedBitPerfect;

  /// No description provided for @dspBluetoothCompensationDesc.
  ///
  /// In en, this message translates to:
  /// **'Lossy Bluetooth gets a small presence compensation and a shorter reverb tail.'**
  String get dspBluetoothCompensationDesc;

  /// No description provided for @dspCodec.
  ///
  /// In en, this message translates to:
  /// **'Codec'**
  String get dspCodec;

  /// No description provided for @dspCompressedStream.
  ///
  /// In en, this message translates to:
  /// **'Compressed Audio Stream'**
  String get dspCompressedStream;

  /// No description provided for @dspCrossfeedChuMoy.
  ///
  /// In en, this message translates to:
  /// **'Chu Moy (700Hz / 6dB)'**
  String get dspCrossfeedChuMoy;

  /// No description provided for @dspCrossfeedDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (700Hz / 4.5dB)'**
  String get dspCrossfeedDefault;

  /// No description provided for @dspCrossfeedJanMeier.
  ///
  /// In en, this message translates to:
  /// **'Jan Meier (650Hz / 9.5dB)'**
  String get dspCrossfeedJanMeier;

  /// No description provided for @dspCrossoverHigh.
  ///
  /// In en, this message translates to:
  /// **'Crossover 3 (High)'**
  String get dspCrossoverHigh;

  /// No description provided for @dspCrossoverLow.
  ///
  /// In en, this message translates to:
  /// **'Crossover 1 (Low)'**
  String get dspCrossoverLow;

  /// No description provided for @dspCrossoverMid.
  ///
  /// In en, this message translates to:
  /// **'Crossover 2 (Mid)'**
  String get dspCrossoverMid;

  /// No description provided for @dspDeleteCustomPreset.
  ///
  /// In en, this message translates to:
  /// **'Delete custom preset'**
  String get dspDeleteCustomPreset;

  /// No description provided for @dspDeleteLine.
  ///
  /// In en, this message translates to:
  /// **'Delete line'**
  String get dspDeleteLine;

  /// No description provided for @dspDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get dspDevice;

  /// No description provided for @dspDr12Audiophile.
  ///
  /// In en, this message translates to:
  /// **'DR 12+ Audiophile'**
  String get dspDr12Audiophile;

  /// No description provided for @dspDrHighDynamic.
  ///
  /// In en, this message translates to:
  /// **'DR High Dynamic'**
  String get dspDrHighDynamic;

  /// No description provided for @dspDrStandard.
  ///
  /// In en, this message translates to:
  /// **'DR Standard'**
  String get dspDrStandard;

  /// No description provided for @dspDspProcessing.
  ///
  /// In en, this message translates to:
  /// **'DSP PROCESSING'**
  String get dspDspProcessing;

  /// No description provided for @dspDynamicRangeLra.
  ///
  /// In en, this message translates to:
  /// **'Dynamic Range (LRA)'**
  String get dspDynamicRangeLra;

  /// No description provided for @dspEbuR128.
  ///
  /// In en, this message translates to:
  /// **'EBU R128 Loudness Range Analysis'**
  String get dspEbuR128;

  /// No description provided for @dspEditLyrics.
  ///
  /// In en, this message translates to:
  /// **'Edit lyrics'**
  String get dspEditLyrics;

  /// No description provided for @dspEmbedded.
  ///
  /// In en, this message translates to:
  /// **'Embedded'**
  String get dspEmbedded;

  /// No description provided for @dspEmbeddedUnsynced.
  ///
  /// In en, this message translates to:
  /// **'Embedded (unsynced)'**
  String get dspEmbeddedUnsynced;

  /// No description provided for @dspEqCurvesBypassed.
  ///
  /// In en, this message translates to:
  /// **'Equalizer curves bypassed'**
  String get dspEqCurvesBypassed;

  /// No description provided for @dspEveryBandValidNumber.
  ///
  /// In en, this message translates to:
  /// **'Every band needs a valid number.'**
  String get dspEveryBandValidNumber;

  /// No description provided for @dspExportThemeJson.
  ///
  /// In en, this message translates to:
  /// **'Export Theme JSON'**
  String get dspExportThemeJson;

  /// No description provided for @dspFileSizeDuration.
  ///
  /// In en, this message translates to:
  /// **'File Size & Duration'**
  String get dspFileSizeDuration;

  /// No description provided for @dspFirLoaded.
  ///
  /// In en, this message translates to:
  /// **'Room-correction FIR loaded into the convolution stage.'**
  String get dspFirLoaded;

  /// No description provided for @dspFirRejected.
  ///
  /// In en, this message translates to:
  /// **'The audio engine rejected the FIR export.'**
  String get dspFirRejected;

  /// No description provided for @dspFreqRange10To30k.
  ///
  /// In en, this message translates to:
  /// **'Frequencies must stay within 10-30000 Hz.'**
  String get dspFreqRange10To30k;

  /// No description provided for @dspFreqStrictlyAscending.
  ///
  /// In en, this message translates to:
  /// **'Frequencies must be strictly ascending.'**
  String get dspFreqStrictlyAscending;

  /// No description provided for @dspHardwareEndpoint.
  ///
  /// In en, this message translates to:
  /// **'HARDWARE ENDPOINT'**
  String get dspHardwareEndpoint;

  /// No description provided for @dspHeadset.
  ///
  /// In en, this message translates to:
  /// **'Headset'**
  String get dspHeadset;

  /// No description provided for @dspKaraokeMode.
  ///
  /// In en, this message translates to:
  /// **'Karaoke Mode'**
  String get dspKaraokeMode;

  /// No description provided for @dspLatency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get dspLatency;

  /// No description provided for @dspLoadingLyrics.
  ///
  /// In en, this message translates to:
  /// **'Loading lyrics…'**
  String get dspLoadingLyrics;

  /// No description provided for @dspLrcLibSynced.
  ///
  /// In en, this message translates to:
  /// **'LRCLIB Synced'**
  String get dspLrcLibSynced;

  /// No description provided for @dspLyricsSaved.
  ///
  /// In en, this message translates to:
  /// **'Lyrics saved'**
  String get dspLyricsSaved;

  /// No description provided for @dspLyricsSessionOnly.
  ///
  /// In en, this message translates to:
  /// **'Lyrics updated for this session only'**
  String get dspLyricsSessionOnly;

  /// No description provided for @dspMakeupGain.
  ///
  /// In en, this message translates to:
  /// **'Makeup Gain'**
  String get dspMakeupGain;

  /// Compressor knee width label
  ///
  /// In en, this message translates to:
  /// **'Knee'**
  String get dspKnee;

  /// No description provided for @dspMaxBoost.
  ///
  /// In en, this message translates to:
  /// **'Max Boost'**
  String get dspMaxBoost;

  /// No description provided for @dspMosqueAmbience.
  ///
  /// In en, this message translates to:
  /// **'Mosque Ambience'**
  String get dspMosqueAmbience;

  /// No description provided for @dspMosqueAmbienceDesc.
  ///
  /// In en, this message translates to:
  /// **'Convolution reverb for a hall-like space'**
  String get dspMosqueAmbienceDesc;

  /// No description provided for @dspMuteBand.
  ///
  /// In en, this message translates to:
  /// **'Mute band'**
  String get dspMuteBand;

  /// No description provided for @dspMyCustomEq.
  ///
  /// In en, this message translates to:
  /// **'My Custom EQ'**
  String get dspMyCustomEq;

  /// No description provided for @dspNoProfileLoaded.
  ///
  /// In en, this message translates to:
  /// **'No profile loaded'**
  String get dspNoProfileLoaded;

  /// No description provided for @dspNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get dspNormal;

  /// No description provided for @dspOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get dspOff;

  /// No description provided for @dspOriginalPitch.
  ///
  /// In en, this message translates to:
  /// **'Original Pitch (1.00x)'**
  String get dspOriginalPitch;

  /// No description provided for @dspOutputDriver.
  ///
  /// In en, this message translates to:
  /// **'OUTPUT DRIVER'**
  String get dspOutputDriver;

  /// No description provided for @dspPresetImportInvalid.
  ///
  /// In en, this message translates to:
  /// **'Failed to import preset: invalid JSON format'**
  String get dspPresetImportInvalid;

  /// No description provided for @dspPresetImported.
  ///
  /// In en, this message translates to:
  /// **'EQ Preset imported successfully!'**
  String get dspPresetImported;

  /// No description provided for @dspPresetLabel.
  ///
  /// In en, this message translates to:
  /// **'Preset:'**
  String get dspPresetLabel;

  /// No description provided for @dspPresetName.
  ///
  /// In en, this message translates to:
  /// **'Preset Name'**
  String get dspPresetName;

  /// No description provided for @dspPresetNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Warm Bass, Vocal Punch'**
  String get dspPresetNameHint;

  /// No description provided for @dspPresetOptions.
  ///
  /// In en, this message translates to:
  /// **'Preset Options'**
  String get dspPresetOptions;

  /// No description provided for @dspPulsrAudiophileEdition.
  ///
  /// In en, this message translates to:
  /// **'Pulsr Audiophile Edition'**
  String get dspPulsrAudiophileEdition;

  /// No description provided for @dspQBandwidth.
  ///
  /// In en, this message translates to:
  /// **'Q / Bandwidth'**
  String get dspQBandwidth;

  /// No description provided for @dspQuranModeOff.
  ///
  /// In en, this message translates to:
  /// **'Quran Mode: Off'**
  String get dspQuranModeOff;

  /// No description provided for @dspQuranModeOn.
  ///
  /// In en, this message translates to:
  /// **'Quran Mode: On'**
  String get dspQuranModeOn;

  /// No description provided for @dspRatio.
  ///
  /// In en, this message translates to:
  /// **'Ratio'**
  String get dspRatio;

  /// No description provided for @dspResamplingEngine.
  ///
  /// In en, this message translates to:
  /// **'RESAMPLING ENGINE'**
  String get dspResamplingEngine;

  /// No description provided for @dspResetAllEqTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset all DSP & EQ to defaults'**
  String get dspResetAllEqTooltip;

  /// No description provided for @dspResetBalanceCenter.
  ///
  /// In en, this message translates to:
  /// **'Reset Balance to Center'**
  String get dspResetBalanceCenter;

  /// No description provided for @dspResetBassEnhancer.
  ///
  /// In en, this message translates to:
  /// **'Reset Bass Enhancer (Off)'**
  String get dspResetBassEnhancer;

  /// No description provided for @dspResetPreamp.
  ///
  /// In en, this message translates to:
  /// **'Reset preamp'**
  String get dspResetPreamp;

  /// No description provided for @dspResetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get dspResetToDefault;

  /// No description provided for @dspResetToDefault0.
  ///
  /// In en, this message translates to:
  /// **'Reset to default (0%)'**
  String get dspResetToDefault0;

  /// No description provided for @dspResetToDefault02dbfs.
  ///
  /// In en, this message translates to:
  /// **'Reset to default (-0.2 dBFS)'**
  String get dspResetToDefault02dbfs;

  /// No description provided for @dspResetToDefault20wet.
  ///
  /// In en, this message translates to:
  /// **'Reset to default (20% Wet)'**
  String get dspResetToDefault20wet;

  /// No description provided for @dspResetToDefault350us.
  ///
  /// In en, this message translates to:
  /// **'Reset to default (350 µs)'**
  String get dspResetToDefault350us;

  /// No description provided for @dspResetToDefault50ms.
  ///
  /// In en, this message translates to:
  /// **'Reset to default (50 ms)'**
  String get dspResetToDefault50ms;

  /// No description provided for @dspResetToDefault9db.
  ///
  /// In en, this message translates to:
  /// **'Reset to default (-9.0 dB)'**
  String get dspResetToDefault9db;

  /// No description provided for @dspResetVolumeBoost.
  ///
  /// In en, this message translates to:
  /// **'Reset Volume Boost (Off)'**
  String get dspResetVolumeBoost;

  /// No description provided for @dspSearchHeadphones.
  ///
  /// In en, this message translates to:
  /// **'Search headphones (Sony, Sennheiser, Apple...)'**
  String get dspSearchHeadphones;

  /// No description provided for @dspSearchHeadphonesHint.
  ///
  /// In en, this message translates to:
  /// **'Search headphones (e.g. AirPods, Sony, Moondrop)...'**
  String get dspSearchHeadphonesHint;

  /// No description provided for @dspSlider1Label.
  ///
  /// In en, this message translates to:
  /// **'slider1 (Rate / Drive)'**
  String get dspSlider1Label;

  /// No description provided for @dspSlider2Label.
  ///
  /// In en, this message translates to:
  /// **'slider2 (Depth / Mix)'**
  String get dspSlider2Label;

  /// No description provided for @dspSoloBand.
  ///
  /// In en, this message translates to:
  /// **'Solo band'**
  String get dspSoloBand;

  /// No description provided for @dspSortByTime.
  ///
  /// In en, this message translates to:
  /// **'Sort by time'**
  String get dspSortByTime;

  /// No description provided for @dspSourceBitrate.
  ///
  /// In en, this message translates to:
  /// **'Source Bitrate'**
  String get dspSourceBitrate;

  /// No description provided for @dspSourceFile.
  ///
  /// In en, this message translates to:
  /// **'SOURCE FILE'**
  String get dspSourceFile;

  /// No description provided for @dspSourceSampleRateDepth.
  ///
  /// In en, this message translates to:
  /// **'Source Sample Rate & Depth'**
  String get dspSourceSampleRateDepth;

  /// No description provided for @dspSpatialTab.
  ///
  /// In en, this message translates to:
  /// **'Spatial & DSP'**
  String get dspSpatialTab;

  /// No description provided for @dspSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get dspSpeaker;

  /// No description provided for @dspStandardDynamicRange.
  ///
  /// In en, this message translates to:
  /// **'Standard Dynamic Range'**
  String get dspStandardDynamicRange;

  /// No description provided for @dspStandby.
  ///
  /// In en, this message translates to:
  /// **'STANDBY'**
  String get dspStandby;

  /// No description provided for @dspTapeLoaded.
  ///
  /// In en, this message translates to:
  /// **'Tape Loaded'**
  String get dspTapeLoaded;

  /// No description provided for @dspTarget.
  ///
  /// In en, this message translates to:
  /// **'Target:'**
  String get dspTarget;

  /// No description provided for @dspThreshold.
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get dspThreshold;

  /// No description provided for @dspTunedFor.
  ///
  /// In en, this message translates to:
  /// **'Tuned for'**
  String get dspTunedFor;

  /// No description provided for @dspUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get dspUnknown;

  /// No description provided for @dspUnmuteBand.
  ///
  /// In en, this message translates to:
  /// **'Unmute band'**
  String get dspUnmuteBand;

  /// No description provided for @dspUnsoloBand.
  ///
  /// In en, this message translates to:
  /// **'Unsolo band'**
  String get dspUnsoloBand;

  /// No description provided for @dspVariableBitrate.
  ///
  /// In en, this message translates to:
  /// **'Variable Bitrate'**
  String get dspVariableBitrate;

  /// No description provided for @dspVocalWarmth.
  ///
  /// In en, this message translates to:
  /// **'Vocal Warmth'**
  String get dspVocalWarmth;

  /// No description provided for @dspVocalWarmthDesc.
  ///
  /// In en, this message translates to:
  /// **'Harmonic richness on the reciter\'s voice'**
  String get dspVocalWarmthDesc;

  /// No description provided for @dspWiredCompensationDesc.
  ///
  /// In en, this message translates to:
  /// **'Wired / USB output is left untouched by hardware compensation.'**
  String get dspWiredCompensationDesc;

  /// No description provided for @browseAccountConnectedDone.
  ///
  /// In en, this message translates to:
  /// **'Account connected! Tap \"Done\" to finish.'**
  String get browseAccountConnectedDone;

  /// No description provided for @browseAcoustic.
  ///
  /// In en, this message translates to:
  /// **'Acoustic'**
  String get browseAcoustic;

  /// No description provided for @browseActiveDownloadsSuffix.
  ///
  /// In en, this message translates to:
  /// **'(3 active downloads)...'**
  String get browseActiveDownloadsSuffix;

  /// No description provided for @browseAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get browseAdded;

  /// No description provided for @browseAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get browseAddress;

  /// No description provided for @browseAlarmSound.
  ///
  /// In en, this message translates to:
  /// **'Alarm sound'**
  String get browseAlarmSound;

  /// No description provided for @browseAllLikedSongsDownloadedOffline.
  ///
  /// In en, this message translates to:
  /// **'All liked songs are already downloaded offline.'**
  String get browseAllLikedSongsDownloadedOffline;

  /// No description provided for @browseAllOnlineLikedDownloaded.
  ///
  /// In en, this message translates to:
  /// **'All online liked songs are already downloaded or in progress.'**
  String get browseAllOnlineLikedDownloaded;

  /// No description provided for @browseAllOnlineTracksDownloaded.
  ///
  /// In en, this message translates to:
  /// **'All online tracks are already downloaded or in progress.'**
  String get browseAllOnlineTracksDownloaded;

  /// No description provided for @browseAllSongsOffline.
  ///
  /// In en, this message translates to:
  /// **'All songs in this list are already offline local tracks.'**
  String get browseAllSongsOffline;

  /// No description provided for @browseAllTracksAlreadyDownloaded.
  ///
  /// In en, this message translates to:
  /// **'All tracks are already downloaded or local'**
  String get browseAllTracksAlreadyDownloaded;

  /// No description provided for @browseAllTracksFrom.
  ///
  /// In en, this message translates to:
  /// **'All tracks from'**
  String get browseAllTracksFrom;

  /// No description provided for @browseAllTracksOfflineLocal.
  ///
  /// In en, this message translates to:
  /// **'All tracks in this playlist are already offline local files.'**
  String get browseAllTracksOfflineLocal;

  /// No description provided for @browseAlreadyDownloadedOffline.
  ///
  /// In en, this message translates to:
  /// **'are already downloaded offline.'**
  String get browseAlreadyDownloadedOffline;

  /// No description provided for @browseAlreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign In'**
  String get browseAlreadyHaveAccount;

  /// No description provided for @browseApplyChanges.
  ///
  /// In en, this message translates to:
  /// **'Apply Changes'**
  String get browseApplyChanges;

  /// No description provided for @browseArabicPop.
  ///
  /// In en, this message translates to:
  /// **'Arabic Pop'**
  String get browseArabicPop;

  /// No description provided for @browseAudioTracks.
  ///
  /// In en, this message translates to:
  /// **'audio tracks'**
  String get browseAudioTracks;

  /// No description provided for @browseAutoFetchTags.
  ///
  /// In en, this message translates to:
  /// **'Auto-Fetch Tags & Cover Art'**
  String get browseAutoFetchTags;

  /// No description provided for @browseBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get browseBack;

  /// No description provided for @browseBatchEdit.
  ///
  /// In en, this message translates to:
  /// **'Batch Edit'**
  String get browseBatchEdit;

  /// No description provided for @browseBatchEditingBody.
  ///
  /// In en, this message translates to:
  /// **'Batch editing {count} tracks. Common tags and cover art will be updated on all selected files.'**
  String browseBatchEditingBody(int count);

  /// No description provided for @browseBatchEditTags.
  ///
  /// In en, this message translates to:
  /// **'Batch Edit Tags'**
  String get browseBatchEditTags;

  /// No description provided for @browseBy.
  ///
  /// In en, this message translates to:
  /// **'by'**
  String get browseBy;

  /// No description provided for @browseCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get browseCannotBeUndone;

  /// No description provided for @browseCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get browseCategories;

  /// No description provided for @browseChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get browseChecking;

  /// No description provided for @browseCheckOut.
  ///
  /// In en, this message translates to:
  /// **'Check out'**
  String get browseCheckOut;

  /// No description provided for @browseChillLofi.
  ///
  /// In en, this message translates to:
  /// **'Chill & Lo-Fi'**
  String get browseChillLofi;

  /// No description provided for @browseChillout.
  ///
  /// In en, this message translates to:
  /// **'Chillout'**
  String get browseChillout;

  /// No description provided for @browseClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get browseClearHistory;

  /// No description provided for @browseClearHistoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear history'**
  String get browseClearHistoryFailed;

  /// No description provided for @browseClearListeningHistoryMessage.
  ///
  /// In en, this message translates to:
  /// **'This will remove all tracks from your Recently Played history. Your actual audio files and playlists will not be affected.'**
  String get browseClearListeningHistoryMessage;

  /// No description provided for @browseClearListeningHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Listening History?'**
  String get browseClearListeningHistoryTitle;

  /// No description provided for @browseClearPlayHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear Play History'**
  String get browseClearPlayHistory;

  /// No description provided for @browseClearPlayHistoryMessage.
  ///
  /// In en, this message translates to:
  /// **'This will reset your recently played list and listening history. Your song files and playlists will not be affected.'**
  String get browseClearPlayHistoryMessage;

  /// No description provided for @browseClearPlayHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Play History?'**
  String get browseClearPlayHistoryTitle;

  /// No description provided for @browseClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get browseClose;

  /// No description provided for @browseCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get browseCode;

  /// No description provided for @browseComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get browseComment;

  /// No description provided for @browseConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get browseConnect;

  /// No description provided for @browseConnectToSync.
  ///
  /// In en, this message translates to:
  /// **'Connect account to sync Liked Music automatically'**
  String get browseConnectToSync;

  /// No description provided for @browseCookiesRejected.
  ///
  /// In en, this message translates to:
  /// **'YouTube rejected these cookies — they have expired or belong to a signed-out session'**
  String get browseCookiesRejected;

  /// No description provided for @browseCookieVerifyOffline.
  ///
  /// In en, this message translates to:
  /// **'Could not reach YouTube to verify — the cookies are saved, try again when back online'**
  String get browseCookieVerifyOffline;

  /// No description provided for @browseCopied.
  ///
  /// In en, this message translates to:
  /// **'copied'**
  String get browseCopied;

  /// No description provided for @browseCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get browseCopy;

  /// No description provided for @browseCouldNotLoadAlbums.
  ///
  /// In en, this message translates to:
  /// **'Could not load albums.'**
  String get browseCouldNotLoadAlbums;

  /// No description provided for @browseCouldNotLoadTopTracks.
  ///
  /// In en, this message translates to:
  /// **'Could not load top tracks.'**
  String get browseCouldNotLoadTopTracks;

  /// No description provided for @browseCouldNotLoadTracks.
  ///
  /// In en, this message translates to:
  /// **'Could not load tracks for this playlist. Please check your internet connection or URL.'**
  String get browseCouldNotLoadTracks;

  /// No description provided for @browseCreateCloudAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Cloud Account'**
  String get browseCreateCloudAccount;

  /// No description provided for @browseCrossfade.
  ///
  /// In en, this message translates to:
  /// **'Crossfade'**
  String get browseCrossfade;

  /// No description provided for @browseCurrentIdentity.
  ///
  /// In en, this message translates to:
  /// **'Current identity'**
  String get browseCurrentIdentity;

  /// No description provided for @browseDeselect.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get browseDeselect;

  /// No description provided for @browseDisc.
  ///
  /// In en, this message translates to:
  /// **'Disc'**
  String get browseDisc;

  /// No description provided for @browseDiscNumber.
  ///
  /// In en, this message translates to:
  /// **'Disc Number'**
  String get browseDiscNumber;

  /// No description provided for @browseDiskStorage.
  ///
  /// In en, this message translates to:
  /// **'Disk Storage'**
  String get browseDiskStorage;

  /// No description provided for @browseDontHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Sign Up'**
  String get browseDontHaveAccount;

  /// No description provided for @browseDownloadActionsFor.
  ///
  /// In en, this message translates to:
  /// **'Download actions for'**
  String get browseDownloadActionsFor;

  /// No description provided for @browseDownloadAllLikedSongs.
  ///
  /// In en, this message translates to:
  /// **'Download All Liked Songs'**
  String get browseDownloadAllLikedSongs;

  /// No description provided for @browseDownloadAllOfflineActive.
  ///
  /// In en, this message translates to:
  /// **'Download all offline (3 active downloads)'**
  String get browseDownloadAllOfflineActive;

  /// No description provided for @browseDownloadAllOnlineFavorites.
  ///
  /// In en, this message translates to:
  /// **'Download All Online Favorites'**
  String get browseDownloadAllOnlineFavorites;

  /// No description provided for @browseDownloadOffline.
  ///
  /// In en, this message translates to:
  /// **'Download offline'**
  String get browseDownloadOffline;

  /// No description provided for @browseEgyptMode.
  ///
  /// In en, this message translates to:
  /// **'Egypt Mode'**
  String get browseEgyptMode;

  /// No description provided for @browseElectronic.
  ///
  /// In en, this message translates to:
  /// **'Electronic'**
  String get browseElectronic;

  /// No description provided for @browseEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get browseEmailAddress;

  /// No description provided for @browseEnter.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get browseEnter;

  /// No description provided for @browseEnterBpmRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a BPM between 40 and 240.'**
  String get browseEnterBpmRange;

  /// No description provided for @browseEnterLyrics.
  ///
  /// In en, this message translates to:
  /// **'Enter song lyrics...'**
  String get browseEnterLyrics;

  /// No description provided for @browseEnterPlaylistUrl.
  ///
  /// In en, this message translates to:
  /// **'Please enter a playlist URL or ID'**
  String get browseEnterPlaylistUrl;

  /// No description provided for @browseEta.
  ///
  /// In en, this message translates to:
  /// **'ETA:'**
  String get browseEta;

  /// No description provided for @browseExcludeFromScan.
  ///
  /// In en, this message translates to:
  /// **'Exclude from Scan'**
  String get browseExcludeFromScan;

  /// No description provided for @browseExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get browseExplore;

  /// No description provided for @browseFailedLoadFeed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load feed. Check connection and retry.'**
  String get browseFailedLoadFeed;

  /// No description provided for @browseFailedToFetch.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch'**
  String get browseFailedToFetch;

  /// No description provided for @browseFailedToLoadAccountPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Failed to load account playlists'**
  String get browseFailedToLoadAccountPlaylists;

  /// No description provided for @browseFetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching'**
  String get browseFetching;

  /// No description provided for @browseFlac.
  ///
  /// In en, this message translates to:
  /// **'FLAC'**
  String get browseFlac;

  /// No description provided for @browseFlat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get browseFlat;

  /// No description provided for @browseForDownload.
  ///
  /// In en, this message translates to:
  /// **'for download'**
  String get browseForDownload;

  /// No description provided for @browseForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get browseForward;

  /// No description provided for @browseForYou.
  ///
  /// In en, this message translates to:
  /// **'For You'**
  String get browseForYou;

  /// No description provided for @browseGenreArabicRegional.
  ///
  /// In en, this message translates to:
  /// **'Arabic & Regional'**
  String get browseGenreArabicRegional;

  /// No description provided for @browseGenreClassicalInstrumental.
  ///
  /// In en, this message translates to:
  /// **'Classical & Instrumental'**
  String get browseGenreClassicalInstrumental;

  /// No description provided for @browseGenreElectronicDance.
  ///
  /// In en, this message translates to:
  /// **'Electronic & Dance'**
  String get browseGenreElectronicDance;

  /// No description provided for @browseGenreHipHopRnb.
  ///
  /// In en, this message translates to:
  /// **'Hip-Hop & R&B'**
  String get browseGenreHipHopRnb;

  /// No description provided for @browseGenreJazzBlues.
  ///
  /// In en, this message translates to:
  /// **'Jazz & Blues'**
  String get browseGenreJazzBlues;

  /// No description provided for @browseGenrePopAcoustic.
  ///
  /// In en, this message translates to:
  /// **'Pop & Acoustic'**
  String get browseGenrePopAcoustic;

  /// No description provided for @browseGenreRockMetal.
  ///
  /// In en, this message translates to:
  /// **'Rock & Metal'**
  String get browseGenreRockMetal;

  /// No description provided for @browseGlobalTopHits.
  ///
  /// In en, this message translates to:
  /// **'Global Top Hits'**
  String get browseGlobalTopHits;

  /// No description provided for @browseGoogleBlocking.
  ///
  /// In en, this message translates to:
  /// **'Google is blocking this sign-in'**
  String get browseGoogleBlocking;

  /// No description provided for @browseGoogleBlockingBody.
  ///
  /// In en, this message translates to:
  /// **'Google blocks sign-in inside embedded browsers for some accounts, and the automatic retries (clearing cookies and switching the browser identity) didn\'t get past it.\n\nUse the reliable option below to sign in with Google TV: approve on your own browser and Google never sees an embedded WebView, so there is no captcha. Pulsr will sync your library and playlists; playback keeps working as usual.'**
  String get browseGoogleBlockingBody;

  /// No description provided for @browseHipHop.
  ///
  /// In en, this message translates to:
  /// **'Hip-Hop'**
  String get browseHipHop;

  /// No description provided for @browseHistoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Listening history cleared'**
  String get browseHistoryCleared;

  /// No description provided for @browseHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get browseHome;

  /// No description provided for @browseHoursShort.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get browseHoursShort;

  /// No description provided for @browseIncludeInScan.
  ///
  /// In en, this message translates to:
  /// **'Include in Scan'**
  String get browseIncludeInScan;

  /// No description provided for @browseInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get browseInvalidEmail;

  /// No description provided for @browseJazz.
  ///
  /// In en, this message translates to:
  /// **'Jazz'**
  String get browseJazz;

  /// No description provided for @browseLatestTracksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Latest tracks played on this device'**
  String get browseLatestTracksSubtitle;

  /// No description provided for @browseLibraryStats.
  ///
  /// In en, this message translates to:
  /// **'Library Stats'**
  String get browseLibraryStats;

  /// No description provided for @browseLikedSongsForDownload.
  ///
  /// In en, this message translates to:
  /// **'liked songs for download'**
  String get browseLikedSongsForDownload;

  /// No description provided for @browseList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get browseList;

  /// No description provided for @browseListeningTime.
  ///
  /// In en, this message translates to:
  /// **'Listening Time'**
  String get browseListeningTime;

  /// No description provided for @browseLofiBeats.
  ///
  /// In en, this message translates to:
  /// **'Lo-Fi Beats'**
  String get browseLofiBeats;

  /// No description provided for @browseLoggedInSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Logged In Successfully'**
  String get browseLoggedInSuccessfully;

  /// No description provided for @browseLossless.
  ///
  /// In en, this message translates to:
  /// **'Lossless'**
  String get browseLossless;

  /// No description provided for @browseLosslessHiRes.
  ///
  /// In en, this message translates to:
  /// **'Lossless / Hi-Res:'**
  String get browseLosslessHiRes;

  /// No description provided for @browseMahraganat.
  ///
  /// In en, this message translates to:
  /// **'Mahraganat'**
  String get browseMahraganat;

  /// No description provided for @browseMissingSessionCookies.
  ///
  /// In en, this message translates to:
  /// **'Missing session cookies — the paste needs an SAPISID and a __Secure-3PSID (or 1PSID)'**
  String get browseMissingSessionCookies;

  /// No description provided for @browseMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get browseMoreOptions;

  /// No description provided for @browseMoreTools.
  ///
  /// In en, this message translates to:
  /// **'More tools'**
  String get browseMoreTools;

  /// No description provided for @browseMostPlayedTracks.
  ///
  /// In en, this message translates to:
  /// **'Most Played Tracks'**
  String get browseMostPlayedTracks;

  /// No description provided for @browseMostPlayedTracksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your all-time favorites leaderboard'**
  String get browseMostPlayedTracksSubtitle;

  /// No description provided for @browseNoArtistsFound.
  ///
  /// In en, this message translates to:
  /// **'No Artists Found'**
  String get browseNoArtistsFound;

  /// No description provided for @browseNoChangesToSave.
  ///
  /// In en, this message translates to:
  /// **'No Changes to Save'**
  String get browseNoChangesToSave;

  /// No description provided for @browseNoGenresFound.
  ///
  /// In en, this message translates to:
  /// **'No Genres Found'**
  String get browseNoGenresFound;

  /// No description provided for @browseNoRecommendations.
  ///
  /// In en, this message translates to:
  /// **'No recommendations right now.'**
  String get browseNoRecommendations;

  /// No description provided for @browseNoResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No Results Found'**
  String get browseNoResultsFound;

  /// No description provided for @browseNoSongsInLibrary.
  ///
  /// In en, this message translates to:
  /// **'No songs in library'**
  String get browseNoSongsInLibrary;

  /// No description provided for @browseNoSongsMatch.
  ///
  /// In en, this message translates to:
  /// **'No songs match'**
  String get browseNoSongsMatch;

  /// No description provided for @browseNotificationSound.
  ///
  /// In en, this message translates to:
  /// **'Notification sound'**
  String get browseNotificationSound;

  /// No description provided for @browseNoTracks.
  ///
  /// In en, this message translates to:
  /// **'No Tracks'**
  String get browseNoTracks;

  /// No description provided for @browseNoTracksFound.
  ///
  /// In en, this message translates to:
  /// **'No Tracks Found'**
  String get browseNoTracksFound;

  /// No description provided for @browseNoTracksInFolder.
  ///
  /// In en, this message translates to:
  /// **'No playable audio tracks found in this directory.'**
  String get browseNoTracksInFolder;

  /// No description provided for @browseNoTracksInGenre.
  ///
  /// In en, this message translates to:
  /// **'No tracks found in this genre.'**
  String get browseNoTracksInGenre;

  /// No description provided for @browseNoTracksInYear.
  ///
  /// In en, this message translates to:
  /// **'No tracks found for this year.'**
  String get browseNoTracksInYear;

  /// No description provided for @browseNoTracksMatchSmartRules.
  ///
  /// In en, this message translates to:
  /// **'No tracks match the rules for this smart playlist.'**
  String get browseNoTracksMatchSmartRules;

  /// No description provided for @browseNoTracksPrivateLiked.
  ///
  /// In en, this message translates to:
  /// **'No tracks found. If this is your private Liked Music, please ensure you are signed in or tap \"Sync\".'**
  String get browseNoTracksPrivateLiked;

  /// No description provided for @browseNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get browseNotSet;

  /// No description provided for @browseNoYearsFound.
  ///
  /// In en, this message translates to:
  /// **'No Years Found'**
  String get browseNoYearsFound;

  /// No description provided for @browseNoYtmMatchesFor.
  ///
  /// In en, this message translates to:
  /// **'No YouTube Music matches for'**
  String get browseNoYtmMatchesFor;

  /// No description provided for @browseOauthAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Access was denied on the Google page.'**
  String get browseOauthAccessDenied;

  /// No description provided for @browseOauthExpired.
  ///
  /// In en, this message translates to:
  /// **'The code expired before it was approved. Try again.'**
  String get browseOauthExpired;

  /// No description provided for @browseOauthGoogleError.
  ///
  /// In en, this message translates to:
  /// **'Google returned an error'**
  String get browseOauthGoogleError;

  /// No description provided for @browseOauthStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start the Google sign-in. Check your connection.'**
  String get browseOauthStartFailed;

  /// No description provided for @browseOfflinePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Offline playlist'**
  String get browseOfflinePlaylist;

  /// No description provided for @browseOnPulsr.
  ///
  /// In en, this message translates to:
  /// **'on Pulsr Music!'**
  String get browseOnPulsr;

  /// No description provided for @browseOpenFolderDetails.
  ///
  /// In en, this message translates to:
  /// **'Open folder details'**
  String get browseOpenFolderDetails;

  /// No description provided for @browsePassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get browsePassword;

  /// No description provided for @browsePasswordMinChars.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get browsePasswordMinChars;

  /// No description provided for @browsePasswordResetSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset link sent to'**
  String get browsePasswordResetSent;

  /// No description provided for @browsePasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get browsePasteFromClipboard;

  /// No description provided for @browsePastePlaylistLinkHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a YouTube or YouTube Music playlist link.'**
  String get browsePastePlaylistLinkHint;

  /// No description provided for @browsePersonalized.
  ///
  /// In en, this message translates to:
  /// **'Personalized'**
  String get browsePersonalized;

  /// No description provided for @browsePlaylistExportedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Playlist exported successfully'**
  String get browsePlaylistExportedSuccess;

  /// No description provided for @browsePlaylistHasNoSongs.
  ///
  /// In en, this message translates to:
  /// **'This playlist has no songs.'**
  String get browsePlaylistHasNoSongs;

  /// No description provided for @browsePlaylistSharePrefix.
  ///
  /// In en, this message translates to:
  /// **'Playlist:'**
  String get browsePlaylistSharePrefix;

  /// No description provided for @browsePlaylistUpdated.
  ///
  /// In en, this message translates to:
  /// **'Playlist updated'**
  String get browsePlaylistUpdated;

  /// No description provided for @browsePlays.
  ///
  /// In en, this message translates to:
  /// **'plays'**
  String get browsePlays;

  /// No description provided for @browsePleaseEnterCookieText.
  ///
  /// In en, this message translates to:
  /// **'Please enter cookie text'**
  String get browsePleaseEnterCookieText;

  /// No description provided for @browsePleaseEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter email'**
  String get browsePleaseEnterEmail;

  /// No description provided for @browsePop.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get browsePop;

  /// No description provided for @browsePopMix.
  ///
  /// In en, this message translates to:
  /// **'Pop Mix'**
  String get browsePopMix;

  /// No description provided for @browsePopular.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get browsePopular;

  /// No description provided for @browseQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get browseQueued;

  /// No description provided for @browseRadioNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Chillhop Radio'**
  String get browseRadioNameHint;

  /// No description provided for @browseRecentSongs.
  ///
  /// In en, this message translates to:
  /// **'recent songs'**
  String get browseRecentSongs;

  /// No description provided for @browseRecommendedForYou.
  ///
  /// In en, this message translates to:
  /// **'Recommended For You'**
  String get browseRecommendedForYou;

  /// No description provided for @browseRecommendedYtmTitle.
  ///
  /// In en, this message translates to:
  /// **'✨ Recommended For You (YouTube Music)'**
  String get browseRecommendedYtmTitle;

  /// No description provided for @browseRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get browseRefresh;

  /// No description provided for @browseRefreshPage.
  ///
  /// In en, this message translates to:
  /// **'Refresh page'**
  String get browseRefreshPage;

  /// No description provided for @browseRefreshPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Refresh playlist'**
  String get browseRefreshPlaylist;

  /// No description provided for @browseRelaxing.
  ///
  /// In en, this message translates to:
  /// **'Relaxing'**
  String get browseRelaxing;

  /// No description provided for @browseReleaseYear.
  ///
  /// In en, this message translates to:
  /// **'Release Year'**
  String get browseReleaseYear;

  /// No description provided for @browseRenamePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Rename Playlist'**
  String get browseRenamePlaylist;

  /// No description provided for @browseRequiresModifySettings.
  ///
  /// In en, this message translates to:
  /// **'directly, Android requires the \"Modify system settings\" permission.'**
  String get browseRequiresModifySettings;

  /// No description provided for @browseRock.
  ///
  /// In en, this message translates to:
  /// **'Rock'**
  String get browseRock;

  /// No description provided for @browseRockClassics.
  ///
  /// In en, this message translates to:
  /// **'Rock Classics'**
  String get browseRockClassics;

  /// No description provided for @browseRockMetal.
  ///
  /// In en, this message translates to:
  /// **'Rock & Metal'**
  String get browseRockMetal;

  /// No description provided for @browseScanForAlbums.
  ///
  /// In en, this message translates to:
  /// **'Scan your media library to view your albums.'**
  String get browseScanForAlbums;

  /// No description provided for @browseScanForArtists.
  ///
  /// In en, this message translates to:
  /// **'Scan your media library to view all artists.'**
  String get browseScanForArtists;

  /// No description provided for @browseScanForGenres.
  ///
  /// In en, this message translates to:
  /// **'Scan your media library to view all song genres.'**
  String get browseScanForGenres;

  /// No description provided for @browseScanForYears.
  ///
  /// In en, this message translates to:
  /// **'Scan your media library to view release years.'**
  String get browseScanForYears;

  /// No description provided for @browseSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search Failed'**
  String get browseSearchFailed;

  /// No description provided for @browseSearchingOnlineMetadata.
  ///
  /// In en, this message translates to:
  /// **'Searching Online Metadata...'**
  String get browseSearchingOnlineMetadata;

  /// No description provided for @browseSearchSongsHint.
  ///
  /// In en, this message translates to:
  /// **'Search songs by title or artist...'**
  String get browseSearchSongsHint;

  /// No description provided for @browseSearchWithinPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Search within playlist…'**
  String get browseSearchWithinPlaylist;

  /// No description provided for @browseSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get browseSeeAll;

  /// No description provided for @browseSelectBestMatch.
  ///
  /// In en, this message translates to:
  /// **'Select Best Match'**
  String get browseSelectBestMatch;

  /// No description provided for @browseSignedInLoading.
  ///
  /// In en, this message translates to:
  /// **'Signed in. Loading your library…'**
  String get browseSignedInLoading;

  /// No description provided for @browseSignInToCloud.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Cloud'**
  String get browseSignInToCloud;

  /// No description provided for @browseSignInToYtm.
  ///
  /// In en, this message translates to:
  /// **'Sign in to YouTube Music'**
  String get browseSignInToYtm;

  /// No description provided for @browseSignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get browseSignUp;

  /// No description provided for @browseSmart.
  ///
  /// In en, this message translates to:
  /// **'Smart'**
  String get browseSmart;

  /// No description provided for @browseSmoothCrossfade.
  ///
  /// In en, this message translates to:
  /// **'Smooth Crossfade'**
  String get browseSmoothCrossfade;

  /// No description provided for @browseSongsOnYtm.
  ///
  /// In en, this message translates to:
  /// **'Songs on YouTube Music…'**
  String get browseSongsOnYtm;

  /// No description provided for @browseStandardLossy.
  ///
  /// In en, this message translates to:
  /// **'Standard Lossy:'**
  String get browseStandardLossy;

  /// No description provided for @browseSubGenres.
  ///
  /// In en, this message translates to:
  /// **'sub-genres'**
  String get browseSubGenres;

  /// No description provided for @browseSynced.
  ///
  /// In en, this message translates to:
  /// **'synced'**
  String get browseSynced;

  /// No description provided for @browseSyncingLikedSongs.
  ///
  /// In en, this message translates to:
  /// **'Syncing liked songs…'**
  String get browseSyncingLikedSongs;

  /// No description provided for @browseSyncPullSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap sync below to pull your latest YouTube Music Liked Songs library.'**
  String get browseSyncPullSubtitle;

  /// No description provided for @browseTapToPlayOrDownload.
  ///
  /// In en, this message translates to:
  /// **'Tap to play or download'**
  String get browseTapToPlayOrDownload;

  /// No description provided for @browseTapToSyncYtm.
  ///
  /// In en, this message translates to:
  /// **'Tap to sync from YouTube Music'**
  String get browseTapToSyncYtm;

  /// No description provided for @browseTenBandGraphicEq.
  ///
  /// In en, this message translates to:
  /// **'10-Band Graphic EQ'**
  String get browseTenBandGraphicEq;

  /// No description provided for @browseTopArtists.
  ///
  /// In en, this message translates to:
  /// **'Top Artists'**
  String get browseTopArtists;

  /// No description provided for @browseTopArtistsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ranked by total listening plays'**
  String get browseTopArtistsSubtitle;

  /// No description provided for @browseTopChartsSongs.
  ///
  /// In en, this message translates to:
  /// **'Top Charts & Songs'**
  String get browseTopChartsSongs;

  /// No description provided for @browseTopHits.
  ///
  /// In en, this message translates to:
  /// **'Top Hits'**
  String get browseTopHits;

  /// No description provided for @browseTopRated.
  ///
  /// In en, this message translates to:
  /// **'Top Rated'**
  String get browseTopRated;

  /// No description provided for @browseTopTracks.
  ///
  /// In en, this message translates to:
  /// **'Top Tracks'**
  String get browseTopTracks;

  /// No description provided for @browseToSet.
  ///
  /// In en, this message translates to:
  /// **'To set'**
  String get browseToSet;

  /// No description provided for @browseTotalPlays.
  ///
  /// In en, this message translates to:
  /// **'Total Plays'**
  String get browseTotalPlays;

  /// No description provided for @browseTotalTracks.
  ///
  /// In en, this message translates to:
  /// **'Total Tracks'**
  String get browseTotalTracks;

  /// No description provided for @browseTracks.
  ///
  /// In en, this message translates to:
  /// **'tracks'**
  String get browseTracks;

  /// No description provided for @browseTracksForDownload.
  ///
  /// In en, this message translates to:
  /// **'tracks for download'**
  String get browseTracksForDownload;

  /// No description provided for @browseTracksFrom.
  ///
  /// In en, this message translates to:
  /// **'tracks from'**
  String get browseTracksFrom;

  /// No description provided for @browseTracksInLibrary.
  ///
  /// In en, this message translates to:
  /// **'tracks in library'**
  String get browseTracksInLibrary;

  /// No description provided for @browseTracksSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'tracks successfully!'**
  String get browseTracksSuccessfully;

  /// No description provided for @browseTracksTo.
  ///
  /// In en, this message translates to:
  /// **'tracks to'**
  String get browseTracksTo;

  /// No description provided for @browseTree.
  ///
  /// In en, this message translates to:
  /// **'Tree'**
  String get browseTree;

  /// No description provided for @browseTrending.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get browseTrending;

  /// No description provided for @browseTrendingEgypt.
  ///
  /// In en, this message translates to:
  /// **'Trending Egypt'**
  String get browseTrendingEgypt;

  /// No description provided for @browseTrendingInEgypt.
  ///
  /// In en, this message translates to:
  /// **'Trending in Egypt 🇪🇬'**
  String get browseTrendingInEgypt;

  /// No description provided for @browseUpdatedPrefix.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get browseUpdatedPrefix;

  /// No description provided for @browseUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get browseUser;

  /// No description provided for @browseWillAdd.
  ///
  /// In en, this message translates to:
  /// **'Will add'**
  String get browseWillAdd;

  /// No description provided for @browseWillRemove.
  ///
  /// In en, this message translates to:
  /// **'Will remove'**
  String get browseWillRemove;

  /// No description provided for @browseWorkoutEnergy.
  ///
  /// In en, this message translates to:
  /// **'Workout Energy'**
  String get browseWorkoutEnergy;

  /// No description provided for @browseYouTubeMusic.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music'**
  String get browseYouTubeMusic;

  /// No description provided for @browseYoutubeWeb.
  ///
  /// In en, this message translates to:
  /// **'YouTube Web'**
  String get browseYoutubeWeb;

  /// No description provided for @browseYtmSearchScreenDesc.
  ///
  /// In en, this message translates to:
  /// **'Stream and download songs from YouTube Music, ad-free.'**
  String get browseYtmSearchScreenDesc;

  /// No description provided for @dspPreampClipWarning.
  ///
  /// In en, this message translates to:
  /// **'Preamp {preamp} dB with peak EQ +{boost} dB may clip. Lower the preamp.'**
  String dspPreampClipWarning(String preamp, String boost);

  /// No description provided for @dspVolumeClipWarning.
  ///
  /// In en, this message translates to:
  /// **'Combined with EQ preamp (+{preamp} dB), total gain may clip. Consider reducing boost.'**
  String dspVolumeClipWarning(String preamp);

  /// No description provided for @errSaveQueue.
  ///
  /// In en, this message translates to:
  /// **'Failed to save queue'**
  String get errSaveQueue;

  /// No description provided for @errClearQueue.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear queue'**
  String get errClearQueue;

  /// No description provided for @errReorderQueue.
  ///
  /// In en, this message translates to:
  /// **'Failed to reorder queue'**
  String get errReorderQueue;

  /// No description provided for @errRemoveTrack.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove track'**
  String get errRemoveTrack;

  /// No description provided for @errQueueSlotEmpty.
  ///
  /// In en, this message translates to:
  /// **'Queue slot is empty'**
  String get errQueueSlotEmpty;

  /// No description provided for @errSwitchQueueSlot.
  ///
  /// In en, this message translates to:
  /// **'Failed to switch queue slot'**
  String get errSwitchQueueSlot;

  /// No description provided for @errInvalidStreamUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid stream URL'**
  String get errInvalidStreamUrl;

  /// No description provided for @errPitchFailed.
  ///
  /// In en, this message translates to:
  /// **'Pitch change failed'**
  String get errPitchFailed;

  /// No description provided for @errPlaybackActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Playback action failed'**
  String get errPlaybackActionFailed;

  /// No description provided for @errSpeedFailed.
  ///
  /// In en, this message translates to:
  /// **'Speed change failed'**
  String get errSpeedFailed;

  /// No description provided for @errVolumeFailed.
  ///
  /// In en, this message translates to:
  /// **'Volume change failed'**
  String get errVolumeFailed;

  /// No description provided for @errShuffleFailed.
  ///
  /// In en, this message translates to:
  /// **'Shuffle failed'**
  String get errShuffleFailed;

  /// No description provided for @errRepeatFailed.
  ///
  /// In en, this message translates to:
  /// **'Repeat failed'**
  String get errRepeatFailed;

  /// No description provided for @errSkipFailed.
  ///
  /// In en, this message translates to:
  /// **'Skip failed'**
  String get errSkipFailed;

  /// No description provided for @errSeekFailed.
  ///
  /// In en, this message translates to:
  /// **'Seek failed, position restored'**
  String get errSeekFailed;

  /// No description provided for @errIrRejected.
  ///
  /// In en, this message translates to:
  /// **'Impulse response rejected by the audio engine'**
  String get errIrRejected;

  /// No description provided for @errLocalMatchStreaming.
  ///
  /// In en, this message translates to:
  /// **'Local match unavailable, streaming online'**
  String get errLocalMatchStreaming;

  /// No description provided for @errPlayFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to play \"{title}\"'**
  String errPlayFailed(String title);

  /// No description provided for @errAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to add \"{title}\"'**
  String errAddFailed(String title);

  /// No description provided for @errQueueFull.
  ///
  /// In en, this message translates to:
  /// **'Queue is full ({max}) — cannot add more'**
  String errQueueFull(String max);

  /// No description provided for @errAudioSettingFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply audio setting: {detail}'**
  String errAudioSettingFailed(String detail);

  /// No description provided for @errYtmNoConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your network.'**
  String get errYtmNoConnection;

  /// No description provided for @errYtmPlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'Playback failed. Please try again.'**
  String get errYtmPlaybackFailed;

  /// No description provided for @errYtmGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong with YouTube Music.'**
  String get errYtmGeneric;

  /// No description provided for @errYtmRegionRestricted.
  ///
  /// In en, this message translates to:
  /// **'This track is restricted in your region.'**
  String get errYtmRegionRestricted;

  /// No description provided for @errYtmUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This track is unavailable.'**
  String get errYtmUnavailable;

  /// No description provided for @errYtmSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'YouTube session expired. Tap to reconnect.'**
  String get errYtmSessionExpired;

  /// No description provided for @errYtmNotInBuild.
  ///
  /// In en, this message translates to:
  /// **'YouTube Music is not available in this build.'**
  String get errYtmNotInBuild;

  /// No description provided for @errYtmProxyAuth.
  ///
  /// In en, this message translates to:
  /// **'Backend proxy authentication failed.'**
  String get errYtmProxyAuth;

  /// No description provided for @errYtmSigFail.
  ///
  /// In en, this message translates to:
  /// **'Signature deciphering unavailable for this format.'**
  String get errYtmSigFail;

  /// No description provided for @errYtmBusy.
  ///
  /// In en, this message translates to:
  /// **'YouTube is busy. Cooling down.'**
  String get errYtmBusy;

  /// No description provided for @errYtmTrouble.
  ///
  /// In en, this message translates to:
  /// **'YouTube is having trouble. Retrying.'**
  String get errYtmTrouble;

  /// No description provided for @errYtmExtractFail.
  ///
  /// In en, this message translates to:
  /// **'Stream extraction failed. Switching route.'**
  String get errYtmExtractFail;

  /// No description provided for @errYtmVerify.
  ///
  /// In en, this message translates to:
  /// **'YouTube needs verification. Trying alternate route.'**
  String get errYtmVerify;

  /// No description provided for @errSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign in failed. Please try again.'**
  String get errSignInFailed;

  /// No description provided for @errSignUpFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign up failed. Please try again.'**
  String get errSignUpFailed;

  /// No description provided for @errLoadDownloads.
  ///
  /// In en, this message translates to:
  /// **'Failed to load downloads'**
  String get errLoadDownloads;

  /// No description provided for @errRetryDownloads.
  ///
  /// In en, this message translates to:
  /// **'Could not retry failed downloads'**
  String get errRetryDownloads;

  /// No description provided for @errYtmNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in to YouTube Music'**
  String get errYtmNotSignedIn;

  /// No description provided for @errYtmSyncLikes.
  ///
  /// In en, this message translates to:
  /// **'Failed to sync YouTube Music likes'**
  String get errYtmSyncLikes;

  /// No description provided for @errSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed. Please try again.'**
  String get errSearchFailed;

  /// No description provided for @errPlaylistNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a playlist name.'**
  String get errPlaylistNameRequired;

  /// No description provided for @dspMultibandLabel.
  ///
  /// In en, this message translates to:
  /// **'Multiband'**
  String get dspMultibandLabel;

  /// No description provided for @dspBandLow.
  ///
  /// In en, this message translates to:
  /// **'Low (<160 Hz)'**
  String get dspBandLow;

  /// No description provided for @dspBandMid.
  ///
  /// In en, this message translates to:
  /// **'Mid'**
  String get dspBandMid;

  /// No description provided for @dspBandHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get dspBandHigh;

  /// No description provided for @eqModeEssential.
  ///
  /// In en, this message translates to:
  /// **'Essential'**
  String get eqModeEssential;

  /// No description provided for @eqModeStudioPro.
  ///
  /// In en, this message translates to:
  /// **'Studio (Pro)'**
  String get eqModeStudioPro;

  /// No description provided for @eqSoundProfiles.
  ///
  /// In en, this message translates to:
  /// **'SOUND PROFILES'**
  String get eqSoundProfiles;

  /// No description provided for @eqCalibrate.
  ///
  /// In en, this message translates to:
  /// **'Calibrate'**
  String get eqCalibrate;

  /// No description provided for @eqFreqResponseCurve.
  ///
  /// In en, this message translates to:
  /// **'FREQUENCY RESPONSE CURVE'**
  String get eqFreqResponseCurve;

  /// No description provided for @eqQuickToneDials.
  ///
  /// In en, this message translates to:
  /// **'QUICK TONE DIALS'**
  String get eqQuickToneDials;

  /// No description provided for @eqUnlockStudioConsole.
  ///
  /// In en, this message translates to:
  /// **'Unlock Studio DSP Console'**
  String get eqUnlockStudioConsole;

  /// No description provided for @eqUnlockStudioDesc.
  ///
  /// In en, this message translates to:
  /// **'Access 10/32/64 parametric bands, room correction, limiter & spatializer'**
  String get eqUnlockStudioDesc;

  /// No description provided for @queueConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get queueConfirmDelete;

  /// No description provided for @headsetRestartNotice.
  ///
  /// In en, this message translates to:
  /// **'Takes effect after an app restart.'**
  String get headsetRestartNotice;

  /// No description provided for @nowPlayingSwipeHint.
  ///
  /// In en, this message translates to:
  /// **'Pull down to close - Swipe art to skip'**
  String get nowPlayingSwipeHint;

  /// No description provided for @vinylDirectDrive.
  ///
  /// In en, this message translates to:
  /// **'STUDIO • DIRECT DRIVE'**
  String get vinylDirectDrive;

  /// No description provided for @cassetteSideA.
  ///
  /// In en, this message translates to:
  /// **'SIDE A • TYPE II (CrO2)'**
  String get cassetteSideA;

  /// No description provided for @vinylSpeedRpm.
  ///
  /// In en, this message translates to:
  /// **'33⅓ RPM'**
  String get vinylSpeedRpm;

  /// No description provided for @exclusiveUsbActive.
  ///
  /// In en, this message translates to:
  /// **'Exclusive USB Active'**
  String get exclusiveUsbActive;

  /// No description provided for @underrunsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} underruns'**
  String underrunsCount(int count);

  /// No description provided for @dspEngineTelemetry.
  ///
  /// In en, this message translates to:
  /// **'DSP Engine Telemetry'**
  String get dspEngineTelemetry;

  /// No description provided for @rtfPercent.
  ///
  /// In en, this message translates to:
  /// **'RTF: {pct}%'**
  String rtfPercent(String pct);

  /// No description provided for @limiterReduction.
  ///
  /// In en, this message translates to:
  /// **'Limiter Reduction'**
  String get limiterReduction;

  /// No description provided for @multibandCompReduction.
  ///
  /// In en, this message translates to:
  /// **'Multiband Comp Reduction'**
  String get multibandCompReduction;

  /// No description provided for @dynamicEqAdjustments.
  ///
  /// In en, this message translates to:
  /// **'Dynamic EQ Adjustments'**
  String get dynamicEqAdjustments;

  /// No description provided for @resetWeeklyDoseTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset Weekly Sound Dose?'**
  String get resetWeeklyDoseTitle;

  /// No description provided for @resetWeeklyDoseDesc.
  ///
  /// In en, this message translates to:
  /// **'This will reset your accumulated acoustic exposure counter to 0% and lift safety attenuation. Only reset if starting a new monitoring week or switching listening environments.'**
  String get resetWeeklyDoseDesc;

  /// No description provided for @resetDoseAction.
  ///
  /// In en, this message translates to:
  /// **'Reset Dose'**
  String get resetDoseAction;

  /// No description provided for @weeklyDoseResetSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Weekly sound dose has been reset to 0.0%'**
  String get weeklyDoseResetSnackbar;

  /// No description provided for @headphoneSafetyTitle.
  ///
  /// In en, this message translates to:
  /// **'Headphone Safety & Dose'**
  String get headphoneSafetyTitle;

  /// No description provided for @headphoneSafetyStandard.
  ///
  /// In en, this message translates to:
  /// **'WHO-ITU H.870 / EN 62368-1 Acoustic Standard'**
  String get headphoneSafetyStandard;

  /// No description provided for @weeklySoundAllowance.
  ///
  /// In en, this message translates to:
  /// **'Weekly Sound Allowance'**
  String get weeklySoundAllowance;

  /// No description provided for @safetyLimiterActiveDesc.
  ///
  /// In en, this message translates to:
  /// **'Safety Limiter Active (-6 dBFS ceiling engaged to prevent hearing damage)'**
  String get safetyLimiterActiveDesc;

  /// No description provided for @highSoundDoseWarning.
  ///
  /// In en, this message translates to:
  /// **'High sound dose: Consider reducing volume to protect hearing'**
  String get highSoundDoseWarning;

  /// No description provided for @optimalExposureDesc.
  ///
  /// In en, this message translates to:
  /// **'Optimal exposure: Safe listening levels within 40-hour allowance'**
  String get optimalExposureDesc;

  /// No description provided for @latencySyncDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Latency & Sync Diagnostics'**
  String get latencySyncDiagnostics;

  /// No description provided for @latencySyncDiagnosticsDesc.
  ///
  /// In en, this message translates to:
  /// **'Real-time output and processing delay metrics reported directly from native hardware sinks.'**
  String get latencySyncDiagnosticsDesc;

  /// No description provided for @dspPipelineDelay.
  ///
  /// In en, this message translates to:
  /// **'DSP Pipeline Delay'**
  String get dspPipelineDelay;

  /// No description provided for @dspPipelineDelayDesc.
  ///
  /// In en, this message translates to:
  /// **'Lookahead Limiter + Resampler group delay + Reverb partitioned delay'**
  String get dspPipelineDelayDesc;

  /// No description provided for @usbBufferedDelay.
  ///
  /// In en, this message translates to:
  /// **'USB Hardware Buffered Delay'**
  String get usbBufferedDelay;

  /// No description provided for @usbBufferedDelayDesc.
  ///
  /// In en, this message translates to:
  /// **'Ring buffer occupancy + URB kernel queue slack'**
  String get usbBufferedDelayDesc;

  /// No description provided for @totalMonitoredLatency.
  ///
  /// In en, this message translates to:
  /// **'Total Monitored Latency'**
  String get totalMonitoredLatency;

  /// No description provided for @totalMonitoredLatencyDesc.
  ///
  /// In en, this message translates to:
  /// **'Sum of active digital processing & hardware buffering'**
  String get totalMonitoredLatencyDesc;

  /// No description provided for @directUsbExclusivePath.
  ///
  /// In en, this message translates to:
  /// **'Direct USB Exclusive Path'**
  String get directUsbExclusivePath;

  /// No description provided for @lowLatencyDirectOutput.
  ///
  /// In en, this message translates to:
  /// **'Low-Latency Direct Output'**
  String get lowLatencyDirectOutput;

  /// No description provided for @dacRateSwitchTitle.
  ///
  /// In en, this message translates to:
  /// **'DAC Sample Rate Switch'**
  String get dacRateSwitchTitle;

  /// No description provided for @dacRateSwitchBody.
  ///
  /// In en, this message translates to:
  /// **'Your DAC supports {supported} kHz, but the current track is {track} kHz.'**
  String dacRateSwitchBody(String supported, String track);

  /// No description provided for @dacRateSwitchResample.
  ///
  /// In en, this message translates to:
  /// **'Resample to {target} kHz for bit-perfect output?'**
  String dacRateSwitchResample(String target);

  /// No description provided for @dacRateSwitchRemember.
  ///
  /// In en, this message translates to:
  /// **'Always auto-switch in the future'**
  String get dacRateSwitchRemember;

  /// No description provided for @dacRateSwitchConfirm.
  ///
  /// In en, this message translates to:
  /// **'Switch ({target} k)'**
  String dacRateSwitchConfirm(String target);

  /// No description provided for @miniPlayerSwipeHint.
  ///
  /// In en, this message translates to:
  /// **'Swipe left/right to skip'**
  String get miniPlayerSwipeHint;

  /// No description provided for @phoneSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Phone Speaker'**
  String get phoneSpeaker;

  /// No description provided for @usbDacNoneAttached.
  ///
  /// In en, this message translates to:
  /// **'USB DAC: None attached'**
  String get usbDacNoneAttached;

  /// No description provided for @directPlaybackNotReported.
  ///
  /// In en, this message translates to:
  /// **'DIRECT PLAYBACK: Not reported'**
  String get directPlaybackNotReported;

  /// No description provided for @directPlaybackUpTo.
  ///
  /// In en, this message translates to:
  /// **'DIRECT PLAYBACK: Up to {rate} Hz / {bits}'**
  String directPlaybackUpTo(String rate, String bits);

  /// No description provided for @activeSystemOutputDesc.
  ///
  /// In en, this message translates to:
  /// **'Active system output device • Up to {rate} kHz / {bits}-bit'**
  String activeSystemOutputDesc(String rate, String bits);

  /// No description provided for @deviceOutputSpecsDesc.
  ///
  /// In en, this message translates to:
  /// **'{typeName} • Up to {rate} kHz / {bits}-bit'**
  String deviceOutputSpecsDesc(String typeName, String rate, String bits);

  /// No description provided for @bpDirectActiveUsb.
  ///
  /// In en, this message translates to:
  /// **'Hardware direct pass-through active on USB DAC'**
  String get bpDirectActiveUsb;

  /// No description provided for @bpDirectActiveWired.
  ///
  /// In en, this message translates to:
  /// **'Hardware direct pass-through active (wired direct)'**
  String get bpDirectActiveWired;

  /// No description provided for @bpPassThroughArmed.
  ///
  /// In en, this message translates to:
  /// **'Pass-through armed • Engages automatically when capable DAC is connected'**
  String get bpPassThroughArmed;

  /// No description provided for @bpBypassesAndroidMixer.
  ///
  /// In en, this message translates to:
  /// **'Bypasses Android mixer & DSP for bit-matched output (USB needs Android 14+, wired needs direct)'**
  String get bpBypassesAndroidMixer;

  /// No description provided for @settingsResultsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 setting found} other{{count} settings found}}'**
  String settingsResultsCount(int count);

  /// No description provided for @cassettePulsrTape.
  ///
  /// In en, this message translates to:
  /// **'PULSR C-90'**
  String get cassettePulsrTape;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;
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
