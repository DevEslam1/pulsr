// lib/features/command_palette/presentation/command_palette_sheet.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/pulsr_haptics.dart';
import '../../../core/widgets/gestures_sheet.dart';
import '../../../core/widgets/highlighted_text.dart';
import '../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../core/widgets/pulsr_pressable.dart';
import '../../../core/widgets/pulsr_search_field.dart';
import '../../../domain/models/genre_item.dart';
import '../../audio_profiles/audio_profiles_screen.dart';
import '../../diagnostics/diagnostics_screen.dart';
import '../../dlna/dlna_screen.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/presentation/widgets/audio_quality_sheet.dart';
import '../../player/presentation/widgets/equalizer_sheet.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/presentation/widgets/settings_picker_sheets.dart';
import '../../sheets/sleep_timer_sheet.dart';
import '../../shell/presentation/widgets/shortcut_help_sheet.dart';

enum CommandPaletteSection {
  recent,
  navigation,
  actions,
  settings,
}

class CommandPaletteItem {
  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final CommandPaletteSection section;
  final List<String> keywords;
  final String? shortcut;
  final void Function(BuildContext context) onSelect;

  const CommandPaletteItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.section,
    this.keywords = const [],
    this.shortcut,
    required this.onSelect,
  });

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if (title.toLowerCase().contains(q)) return true;
    if (subtitle?.toLowerCase().contains(q) == true) return true;
    if (shortcut?.toLowerCase().contains(q) == true) return true;
    return keywords.any((k) => k.toLowerCase().contains(q));
  }
}

class _PaletteEntry {
  final CommandPaletteItem item;
  final CommandPaletteSection displaySection;

  const _PaletteEntry({
    required this.item,
    required this.displaySection,
  });
}

class CommandPaletteSheet extends StatefulWidget {
  static const String _recentActionsPrefsKey = 'command_palette_recent_actions';
  static const int maxRecentActions = 5;

  static final List<String> _recentActionIds = <String>[];
  static bool _recentLoadedFromPrefs = false;

  /// Most recently executed command IDs (most recent first, capped at
  /// [maxRecentActions]).
  static List<String> get recentActionIds =>
      List<String>.unmodifiable(_recentActionIds);

  /// Records a command execution in MRU order (capped at [maxRecentActions])
  /// and persists it to [SharedPreferences].
  static void recordRecentAction(String id) {
    _recentActionIds.remove(id);
    _recentActionIds.insert(0, id);
    if (_recentActionIds.length > maxRecentActions) {
      _recentActionIds.removeRange(maxRecentActions, _recentActionIds.length);
    }
    _recentLoadedFromPrefs = true;
    unawaited(_persistRecentActions());
  }

  static Future<void> _persistRecentActions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _recentActionsPrefsKey,
        List<String>.of(_recentActionIds),
      );
    } catch (_) {
      // Safe fallback when SharedPreferences is unavailable in isolated tests.
    }
  }

  static Future<bool> _hydrateRecentActions() async {
    if (_recentLoadedFromPrefs) return false;
    _recentLoadedFromPrefs = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_recentActionsPrefsKey);
      if (stored == null || stored.isEmpty) return false;
      var changed = false;
      for (final id in stored.take(maxRecentActions)) {
        if (!_recentActionIds.contains(id) &&
            _recentActionIds.length < maxRecentActions) {
          _recentActionIds.add(id);
          changed = true;
        }
      }
      return changed;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void debugResetRecentActions() {
    _recentActionIds.clear();
    _recentLoadedFromPrefs = false;
  }

  /// App-level context captured by [show] before the sheet is pushed.
  ///
  /// Item callbacks navigate, read cubits and open other sheets; they must not
  /// run against the sheet's own context because popping it deactivates that
  /// context. The sheet prefers the live root-navigator context and falls back
  /// to this one.
  final BuildContext? appContext;

  const CommandPaletteSheet({super.key, this.appContext});

  static Future<void> show(BuildContext context) {
    PulsrHaptics.selectionClick();
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => CommandPaletteSheet(appContext: context),
    );
  }

  @override
  State<CommandPaletteSheet> createState() => _CommandPaletteSheetState();
}

class _CommandPaletteSheetState extends State<CommandPaletteSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _selectedIndex = 0;
  String _query = '';
  List<CommandPaletteItem>? _cachedAllItems;
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadPersistedRecents());
  }

  Future<void> _loadPersistedRecents() async {
    final changed = await CommandPaletteSheet._hydrateRecentActions();
    if (changed && mounted) {
      setState(() {
        _itemKeys.clear();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedAllItems = _buildAllItems(context);
  }

  void _onSearchChanged() {
    setState(() {
      _query = _searchController.text.trim();
      _selectedIndex = 0;
      _itemKeys.clear();
    });
  }

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[_selectedIndex];
      final itemContext = key?.currentContext;
      if (itemContext != null && itemContext.mounted) {
        final shouldAnimate = PulsrMotion.shouldAnimate(itemContext);
        Scrollable.ensureVisible(
          itemContext,
          alignment: 0.5,
          duration: shouldAnimate ? PulsrDurations.tap : Duration.zero,
          curve: shouldAnimate ? PulsrMotion.enter : Curves.linear,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_PaletteEntry> _buildVisibleEntries(List<CommandPaletteItem> allItems) {
    if (_query.isNotEmpty) {
      return [
        for (final item in allItems)
          if (item.matches(_query))
            _PaletteEntry(item: item, displaySection: item.section),
      ];
    }

    final byId = <String, CommandPaletteItem>{
      for (final item in allItems) item.id: item,
    };
    final entries = <_PaletteEntry>[];
    for (final recentId in CommandPaletteSheet._recentActionIds
        .take(CommandPaletteSheet.maxRecentActions)) {
      final match = byId[recentId];
      if (match != null) {
        entries.add(
          _PaletteEntry(
            item: match,
            displaySection: CommandPaletteSection.recent,
          ),
        );
      }
    }
    for (final item in allItems) {
      entries.add(_PaletteEntry(item: item, displaySection: item.section));
    }
    return entries;
  }

  List<CommandPaletteItem> _buildAllItems(BuildContext context) {
    final l10n = context.l10n;

    return [
      // 1. Navigation
      CommandPaletteItem(
        id: 'nav_home',
        title: l10n.navHome,
        icon: Icons.home_rounded,
        section: CommandPaletteSection.navigation,
        keywords: ['start', 'main', 'feed', 'discover'],
        onSelect: (ctx) => ctx.go('/'),
      ),
      CommandPaletteItem(
        id: 'nav_library',
        title: l10n.navLibrary,
        icon: Icons.library_music_rounded,
        section: CommandPaletteSection.navigation,
        keywords: ['songs', 'tracks', 'albums', 'artists', 'folders', 'genres', 'years'],
        onSelect: (ctx) => ctx.go('/library'),
      ),
      CommandPaletteItem(
        id: 'nav_search',
        title: l10n.navSearch,
        icon: Icons.search_rounded,
        section: CommandPaletteSection.navigation,
        keywords: ['find', 'query', 'lookup'],
        onSelect: (ctx) => ctx.go('/search'),
      ),
      CommandPaletteItem(
        id: 'nav_playlists',
        title: l10n.navPlaylists,
        icon: Icons.queue_music_rounded,
        section: CommandPaletteSection.navigation,
        keywords: ['mix', 'collection'],
        onSelect: (ctx) => ctx.go('/playlists'),
      ),
      CommandPaletteItem(
        id: 'nav_favorites',
        title: l10n.favorites,
        icon: Icons.favorite_rounded,
        section: CommandPaletteSection.navigation,
        keywords: ['loved', 'stars', 'liked'],
        onSelect: (ctx) => ctx.push('/favorites'),
      ),
      CommandPaletteItem(
        id: 'nav_queue',
        title: l10n.queue,
        icon: Icons.format_list_numbered_rounded,
        section: CommandPaletteSection.navigation,
        shortcut: 'Q',
        keywords: ['queue', 'up next', 'tracks', 'slots', 'playing'],
        onSelect: (ctx) => ctx.push('/queue'),
      ),
      CommandPaletteItem(
        id: 'nav_radio',
        title: l10n.radioTitle,
        subtitle: l10n.commandPaletteNavRadioSubtitle,
        icon: Icons.radio_rounded,
        section: CommandPaletteSection.navigation,
        keywords: [
          'radio',
          'stream',
          'broadcast',
          'stations',
          'live',
          'quran',
          'recitation',
        ],
        onSelect: (ctx) => ctx.push('/radio'),
      ),
      CommandPaletteItem(
        id: 'nav_diagnostics',
        title: l10n.commandPaletteNavDiagnostics,
        subtitle: l10n.commandPaletteNavDiagnosticsSubtitle,
        icon: Icons.monitor_heart_rounded,
        section: CommandPaletteSection.navigation,
        keywords: [
          'diagnostics',
          'logs',
          'bundle',
          'usb',
          'safe mode',
          'bug',
          'report',
          'troubleshoot',
        ],
        onSelect: (ctx) => Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()),
        ),
      ),
      CommandPaletteItem(
        id: 'nav_audio_profiles',
        title: l10n.commandPaletteNavAudioProfiles,
        subtitle: l10n.commandPaletteNavAudioProfilesSubtitle,
        icon: Icons.badge_rounded,
        section: CommandPaletteSection.navigation,
        keywords: [
          'profiles',
          'audio profiles',
          'sound profile',
          'preset',
          'dsp',
          'dac',
        ],
        onSelect: (ctx) => Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => const AudioProfilesScreen()),
        ),
      ),
      CommandPaletteItem(
        id: 'nav_dlna',
        title: l10n.commandPaletteNavDlna,
        subtitle: l10n.commandPaletteNavDlnaSubtitle,
        icon: Icons.cast_rounded,
        section: CommandPaletteSection.navigation,
        keywords: [
          'dlna',
          'upnp',
          'cast',
          'stream',
          'renderer',
          'network audio',
          'wifi speaker',
        ],
        onSelect: (ctx) => Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => const DlnaScreen()),
        ),
      ),
      CommandPaletteItem(
        id: 'nav_podcasts_audiobooks',
        title: l10n.commandPaletteNavPodcasts,
        subtitle: l10n.commandPaletteNavPodcastsSubtitle,
        icon: Icons.podcasts_rounded,
        section: CommandPaletteSection.navigation,
        keywords: [
          'podcast',
          'podcasts',
          'audiobook',
          'audiobooks',
          'spoken',
          'bookmark',
          'resume',
        ],
        onSelect: (ctx) => ctx.push(
          '/genre',
          extra: const GenreItem(name: 'Podcasts', songCount: 0),
        ),
      ),
      CommandPaletteItem(
        id: 'nav_downloads',
        title: l10n.downloadsTitle,
        icon: Icons.download_rounded,
        section: CommandPaletteSection.navigation,
        keywords: ['offline', 'cache', 'files'],
        onSelect: (ctx) => ctx.push('/downloads'),
      ),
      CommandPaletteItem(
        id: 'nav_smart_playlists',
        title: l10n.smartPlaylists,
        icon: Icons.auto_awesome_rounded,
        section: CommandPaletteSection.navigation,
        keywords: ['rules', 'filters', 'smart'],
        onSelect: (ctx) => ctx.push('/smart-playlist-builder'),
      ),
      CommandPaletteItem(
        id: 'nav_recents',
        title: l10n.history,
        icon: Icons.history_rounded,
        section: CommandPaletteSection.navigation,
        keywords: ['recent', 'played', 'last'],
        onSelect: (ctx) => ctx.push('/recents'),
      ),

      // 2. Actions
      CommandPaletteItem(
        id: 'action_play_pause',
        title: l10n.commandPaletteActionPlay,
        subtitle: l10n.shortcutPlayPauseDesc,
        icon: Icons.play_arrow_rounded,
        section: CommandPaletteSection.actions,
        shortcut: 'Space',
        keywords: ['playback', 'resume', 'stop'],
        onSelect: (ctx) => ctx.read<PlayerCubit>().togglePlayPause(),
      ),
      CommandPaletteItem(
        id: 'action_next',
        title: l10n.shortcutNext,
        subtitle: l10n.shortcutNextDesc,
        icon: Icons.skip_next_rounded,
        section: CommandPaletteSection.actions,
        shortcut: 'N',
        keywords: ['forward', 'skip'],
        onSelect: (ctx) => ctx.read<PlayerCubit>().next(),
      ),
      CommandPaletteItem(
        id: 'action_prev',
        title: l10n.shortcutPrevious,
        subtitle: l10n.shortcutPreviousDesc,
        icon: Icons.skip_previous_rounded,
        section: CommandPaletteSection.actions,
        shortcut: 'P',
        keywords: ['back', 'rewind'],
        onSelect: (ctx) => ctx.read<PlayerCubit>().previous(),
      ),
      CommandPaletteItem(
        id: 'action_favorite',
        title: l10n.shortcutFavorite,
        subtitle: l10n.shortcutFavoriteDesc,
        icon: Icons.favorite_rounded,
        section: CommandPaletteSection.actions,
        shortcut: 'F',
        keywords: ['like', 'heart', 'favorite', 'love'],
        onSelect: (ctx) => ctx.read<PlayerCubit>().toggleFavorite(),
      ),
      CommandPaletteItem(
        id: 'action_mute',
        title: l10n.shortcutMute,
        subtitle: l10n.shortcutMuteDesc,
        icon: Icons.volume_off_rounded,
        section: CommandPaletteSection.actions,
        shortcut: 'M',
        keywords: ['silence', 'volume', 'mute', 'audio'],
        onSelect: (ctx) => ctx.read<PlayerCubit>().toggleMute(),
      ),
      CommandPaletteItem(
        id: 'action_lyrics',
        title: l10n.shortcutLyrics,
        subtitle: l10n.shortcutLyricsDesc,
        icon: Icons.lyrics_rounded,
        section: CommandPaletteSection.actions,
        shortcut: 'L',
        keywords: ['words', 'karaoke', 'synced', 'lyrics'],
        onSelect: (ctx) => ctx.read<PlayerCubit>().toggleLyrics(),
      ),
      CommandPaletteItem(
        id: 'action_shuffle',
        title: l10n.commandPaletteActionShuffle,
        subtitle: l10n.shuffleAll,
        icon: Icons.shuffle_rounded,
        section: CommandPaletteSection.actions,
        keywords: ['random', 'mix'],
        onSelect: (ctx) => ctx.read<PlayerCubit>().toggleShuffle(),
      ),
      CommandPaletteItem(
        id: 'action_equalizer',
        title: l10n.commandPaletteActionEqualizer,
        subtitle: l10n.equalizerSubtitle,
        icon: Icons.tune_rounded,
        section: CommandPaletteSection.actions,
        keywords: [
          'equalizer',
          'eq',
          'dsp',
          'sound',
          'bands',
          'bass',
          'profile',
          'tone',
        ],
        onSelect: (ctx) => EqualizerSheet.show(ctx),
      ),
      CommandPaletteItem(
        id: 'action_audio_quality',
        title: l10n.commandPaletteActionAudioQuality,
        subtitle: l10n.audioQualityDiagnosticsProHint,
        icon: Icons.high_quality_rounded,
        section: CommandPaletteSection.actions,
        keywords: ['dac', 'bit-perfect', 'khz', 'flac', 'lossless', 'usb'],
        onSelect: (ctx) {
          final song = ctx.read<PlayerCubit>().state.currentSong;
          if (song != null) {
            AudioQualitySheet.show(ctx, song, ctx.palette.accent);
          } else {
            ctx.go('/settings?category=sound');
          }
        },
      ),
      CommandPaletteItem(
        id: 'action_sleep_timer',
        title: l10n.commandPaletteActionSleepTimer,
        subtitle: l10n.sleepTimerSubtitle,
        icon: Icons.bedtime_rounded,
        section: CommandPaletteSection.actions,
        keywords: ['stop', 'countdown', 'auto off'],
        onSelect: (ctx) => SleepTimerSheet.show(ctx),
      ),
      CommandPaletteItem(
        id: 'action_gestures',
        title: l10n.gesturesGuideTitle,
        subtitle: l10n.gesturesGuideSubtitle,
        icon: Icons.gesture_rounded,
        section: CommandPaletteSection.actions,
        keywords: ['touch', 'swipe', 'shortcuts', 'chevrons'],
        onSelect: (ctx) => GesturesSheet.show(ctx),
      ),
      CommandPaletteItem(
        id: 'action_theme',
        title: l10n.commandPaletteActionThemeSwitch,
        subtitle: l10n.appearance,
        icon: Icons.palette_rounded,
        section: CommandPaletteSection.actions,
        keywords: ['theme', 'accent', 'visual density', 'calm', 'dark'],
        onSelect: (ctx) {
          final cubit = ctx.read<SettingsCubit>();
          showThemePickerSheet(ctx, cubit, cubit.state.playerThemeMode);
        },
      ),
      CommandPaletteItem(
        id: 'action_whats_new',
        title: l10n.whatsNewInPulsr,
        subtitle: l10n.whatsNewSubtitle(AppConfig.appVersion),
        icon: Icons.new_releases_rounded,
        section: CommandPaletteSection.actions,
        keywords: ['changelog', 'release', 'update', 'features'],
        onSelect: (ctx) => showWhatsNewSheet(ctx),
      ),
      CommandPaletteItem(
        id: 'action_shortcuts',
        title: l10n.shortcutHelpTitle,
        subtitle: l10n.shortcutHelpSubtitle,
        icon: Icons.keyboard_rounded,
        section: CommandPaletteSection.actions,
        shortcut: '?',
        keywords: ['hotkeys', 'keys', 'desktop'],
        onSelect: (ctx) => ShortcutHelpSheet.show(ctx),
      ),

      // 3. Settings Sections
      CommandPaletteItem(
        id: 'nav_settings',
        title: l10n.openSettings,
        subtitle: l10n.settingsSectionSystemPrivacy,
        icon: Icons.settings_rounded,
        section: CommandPaletteSection.settings,
        keywords: ['settings', 'preferences', 'config', 'options'],
        onSelect: (ctx) => ctx.go('/settings'),
      ),
      CommandPaletteItem(
        id: 'settings_sound',
        title: l10n.settingsSectionSoundPlayback,
        subtitle: l10n.settingsCategoryAudioSubtitle,
        icon: Icons.equalizer_rounded,
        section: CommandPaletteSection.settings,
        keywords: ['dsp', 'gain', 'limiter', 'crossfeed', 'reverb', 'profile'],
        onSelect: (ctx) => ctx.go('/settings?category=sound'),
      ),
      CommandPaletteItem(
        id: 'settings_appearance',
        title: l10n.settingsSectionAppearanceGestures,
        subtitle: l10n.settingsCategoryAppearanceSubtitle,
        icon: Icons.palette_rounded,
        section: CommandPaletteSection.settings,
        keywords: ['theme', 'accent', 'visual density', 'calm', 'amoled', 'dark'],
        onSelect: (ctx) => ctx.go('/settings?category=look'),
      ),
      CommandPaletteItem(
        id: 'settings_library',
        title: l10n.libraryAndScanning,
        subtitle: l10n.settingsCategoryLibrarySubtitle,
        icon: Icons.folder_copy_rounded,
        section: CommandPaletteSection.settings,
        keywords: ['folders', 'scan', 'rescan', 'auto scan'],
        onSelect: (ctx) => ctx.go('/settings?category=library'),
      ),
      CommandPaletteItem(
        id: 'settings_online',
        title: AppConfig.ytmEnabled
            ? l10n.youtubeMusicAndOnline
            : l10n.networkAndProxy,
        subtitle: l10n.settingsCategoryOnlineSubtitle,
        icon: Icons.cloud_sync_rounded,
        section: CommandPaletteSection.settings,
        keywords: ['streaming', 'ytm', 'offline', 'wifi only'],
        onSelect: (ctx) => ctx.go('/settings?category=network'),
      ),
      CommandPaletteItem(
        id: 'settings_privacy',
        title: l10n.privacyAndData,
        subtitle: l10n.settingsCategoryPrivacySubtitle,
        icon: Icons.security_rounded,
        section: CommandPaletteSection.settings,
        keywords: ['backup', 'restore', 'export', 'cache', 'storage'],
        onSelect: (ctx) => ctx.go('/settings?category=privacy'),
      ),
      CommandPaletteItem(
        id: 'settings_about',
        title: l10n.about,
        subtitle: l10n.settingsCategoryAboutSubtitle(AppConfig.appVersion),
        icon: Icons.info_outline_rounded,
        section: CommandPaletteSection.settings,
        keywords: ['about', 'version', 'build', 'license'],
        onSelect: (ctx) => ctx.go('/settings?category=about'),
      ),
    ];
  }

  /// A context that outlives this sheet.
  ///
  /// The root navigator's context is always mounted and still sits under the
  /// app's providers, theme and Router, so `context.go` / `context.read` /
  /// `showModalBottomSheet` all resolve. The caller context from [show] is the
  /// fallback for hosts that build the sheet without a navigator ancestor.
  BuildContext? _resolveAppContext() {
    final fallback = widget.appContext;
    if (fallback != null && fallback.mounted) return fallback;
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    final overlayContext = navigator?.overlay?.context;
    if (overlayContext != null && overlayContext.mounted) return overlayContext;
    final navContext = navigator?.context;
    if (navContext != null && navContext.mounted) return navContext;
    return null;
  }

  void _handleSelect(CommandPaletteItem item) {
    PulsrHaptics.lightImpact();
    CommandPaletteSheet.recordRecentAction(item.id);
    // Capture before the pop: after it the sheet's element is unmounted and
    // every item callback (go/push/read/EqualizerSheet.show) would throw.
    final appContext = _resolveAppContext();
    Navigator.of(context).pop();
    if (appContext == null) return;
    // Post-frame so the palette route is off-screen before the destination
    // route or sheet is pushed (avoids a transition race on small devices).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!appContext.mounted) return;
      try {
        item.onSelect(appContext);
      } catch (e, st) {
        ErrorLogger.log(
          'Command palette action failed: ${item.id}',
          error: e,
          stackTrace: st,
          category: 'CommandPalette',
        );
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final allItems = _cachedAllItems ?? _buildAllItems(context);
    final entries = _buildVisibleEntries(allItems);

    if (entries.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % entries.length;
      });
      _scrollToSelected();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            (_selectedIndex - 1 + entries.length) % entries.length;
      });
      _scrollToSelected();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_selectedIndex >= 0 && _selectedIndex < entries.length) {
        _handleSelect(entries[_selectedIndex].item);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _sectionTitle(BuildContext context, CommandPaletteSection section) {
    final l10n = context.l10n;
    switch (section) {
      case CommandPaletteSection.recent:
        return l10n.sortRadioCardsRecent;
      case CommandPaletteSection.navigation:
        return l10n.commandPaletteSectionRoutes;
      case CommandPaletteSection.actions:
        return l10n.commandPaletteSectionActions;
      case CommandPaletteSection.settings:
        return l10n.commandPaletteSectionSettings;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final shouldAnimate = PulsrMotion.shouldAnimate(context);
    final allItems = _cachedAllItems ?? _buildAllItems(context);
    final entries = _buildVisibleEntries(allItems);

    final maxH = math.min(
      Adaptive.sheetMaxHeight(context),
      MediaQuery.sizeOf(context).height * 0.75,
    );

    return Semantics(
      label: l10n.commandPaletteTitle,
      explicitChildNodes: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search Input Header
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: Semantics(
                  textField: true,
                  label: l10n.commandPaletteHint,
                  child: PulsrSearchField(
                    controller: _searchController,
                    hintText: l10n.commandPaletteHint,
                    autofocus: true,
                    onSubmitted: (_) {
                      if (entries.isNotEmpty &&
                          _selectedIndex >= 0 &&
                          _selectedIndex < entries.length) {
                        _handleSelect(entries[_selectedIndex].item);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Divider(color: p.hairline, height: 1),

              // Filtered Items List
              Expanded(
                child: entries.isEmpty
                    ? Semantics(
                        liveRegion: true,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ExcludeSemantics(
                                  child: Icon(
                                    Icons.search_off_rounded,
                                    size: 36,
                                    color: p.textTertiary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  l10n.commandPaletteNoResults,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.body,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                          horizontal: AppSpacing.sm,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final item = entry.item;
                          final isHighlighted = index == _selectedIndex;

                          // Insert section separator if first item or section changes
                          final showSectionHeader = index == 0 ||
                              entries[index - 1].displaySection !=
                                  entry.displaySection;
                          final sectionTitle =
                              _sectionTitle(context, entry.displaySection);
                          final semanticLabel = item.shortcut != null
                              ? '${item.title}, ${item.shortcut}'
                              : item.title;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showSectionHeader) ...[
                                Semantics(
                                  header: true,
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                      AppSpacing.sm,
                                      AppSpacing.s8,
                                      AppSpacing.sm,
                                      AppSpacing.s4,
                                    ),
                                    child: Text(
                                      sectionTitle,
                                      style: TextStyle(
                                        color: p.textTertiary,
                                        fontSize: AppFontSize.label,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: AppTracking.label,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              Semantics(
                                button: true,
                                selected: isHighlighted,
                                label: semanticLabel,
                                hint: item.subtitle,
                                excludeSemantics: true,
                                child: AnimatedContainer(
                                  key: _itemKeys.putIfAbsent(
                                    index,
                                    GlobalKey.new,
                                  ),
                                  duration: shouldAnimate
                                      ? context.motion(PulsrDurations.tap)
                                      : Duration.zero,
                                  curve:
                                      context.motionCurve(PulsrMotion.enter),
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isHighlighted
                                        ? p.accent.withValues(alpha: 0.14)
                                        : Colors.transparent,
                                    borderRadius: AppRadii.r12All,
                                    border: Border.all(
                                      color: isHighlighted
                                          ? p.accent.withValues(alpha: 0.35)
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: PulsrPressable(
                                    pressedScale: 0.985,
                                    onTap: () => _handleSelect(item),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minWidth: AppSpacing.minTouchTarget,
                                        minHeight: AppSpacing.minTouchTarget,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.sm,
                                          vertical: AppSpacing.xs,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: isHighlighted
                                                    ? p.accent
                                                    : p.surfaceContainerHigh,
                                                shape: BoxShape.circle,
                                              ),
                                              alignment: Alignment.center,
                                              child: Icon(
                                                item.icon,
                                                size: 17,
                                                color: isHighlighted
                                                    ? p.onAccent
                                                    : p.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  PulsrHighlightedText(
                                                    text: item.title,
                                                    query: _query,
                                                    baseStyle: TextStyle(
                                                      color: p.textPrimary,
                                                      fontSize:
                                                          AppFontSize.body,
                                                      fontWeight: isHighlighted
                                                          ? FontWeight.w700
                                                          : FontWeight.w600,
                                                    ),
                                                    matchStyle: TextStyle(
                                                      color: p.accent,
                                                      fontSize:
                                                          AppFontSize.body,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  if (item.subtitle !=
                                                      null) ...[
                                                    const SizedBox(height: 2),
                                                    PulsrHighlightedText(
                                                      text: item.subtitle!,
                                                      query: _query,
                                                      baseStyle: TextStyle(
                                                        color: p.textSecondary,
                                                        fontSize:
                                                            AppFontSize.caption,
                                                      ),
                                                      matchStyle: TextStyle(
                                                        color: p.accent,
                                                        fontSize:
                                                            AppFontSize.caption,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (item.shortcut != null) ...[
                                              const SizedBox(
                                                width: AppSpacing.xs,
                                              ),
                                              _ShortcutKeyBadge(
                                                label: item.shortcut!,
                                                isHighlighted: isHighlighted,
                                                palette: p,
                                              ),
                                            ],
                                            const SizedBox(
                                              width: AppSpacing.xxs,
                                            ),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              size: 16,
                                              color: isHighlighted
                                                  ? p.accent
                                                  : p.textTertiary
                                                      .withValues(alpha: 0.5),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline keyboard shortcut badge rendered on commands with active keybindings.
class _ShortcutKeyBadge extends StatelessWidget {
  final String label;
  final bool isHighlighted;
  final PulsrPalette palette;

  const _ShortcutKeyBadge({
    required this.label,
    required this.isHighlighted,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 26, minHeight: 24),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: isHighlighted
            ? palette.accent.withValues(alpha: 0.16)
            : palette.surfaceContainerHigh,
        borderRadius: AppRadii.r6All,
        border: Border.all(
          color: isHighlighted
              ? palette.accent.withValues(alpha: 0.42)
              : palette.hairline,
          width: 1.0,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: AppFontSize.caption,
          fontWeight: FontWeight.w700,
          color: isHighlighted ? palette.accent : palette.textSecondary,
        ),
      ),
    );
  }
}
