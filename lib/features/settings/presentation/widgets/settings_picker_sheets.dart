// lib/features/settings/presentation/widgets/settings_picker_sheets.dart
import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/ytm_web_login_sheet.dart';
import '../../../player/presentation/widgets/audio_visualizer.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';

// ============================================================================
// Title formatters
// ============================================================================

String getThemeModeTitle(PlayerThemeMode mode) {
  switch (mode) {
    case PlayerThemeMode.classic:
      return 'Classic Standard';
    case PlayerThemeMode.card:
      return 'Card Glass Overlay';
    case PlayerThemeMode.circle:
      return 'Vinyl Circle (Spinning)';
    case PlayerThemeMode.minimal:
      return 'Minimalist Waveform';
    case PlayerThemeMode.vinyl:
      return 'Vinyl Turntable Studio';
    case PlayerThemeMode.cassette:
      return 'Retro Cassette Deck';
    case PlayerThemeMode.waveform:
      return 'Full-Bleed Waveform';
    case PlayerThemeMode.lyricsFocus:
      return 'Karaoke Lyrics Immersion';
  }
}

String getVisualizerStyleTitle(VisualizerStyle style) {
  switch (style) {
    case VisualizerStyle.off:
      return 'Disabled';
    case VisualizerStyle.bar:
      return 'Bar (Classic Frequency Spectrum)';
    case VisualizerStyle.wave:
      return 'Wave (Smooth Line Spectrum)';
    case VisualizerStyle.circular:
      return 'Circular (Radial Spectrum)';
    case VisualizerStyle.particles:
      return 'Particles (Audio Field)';
    case VisualizerStyle.terrain3D:
      return '3D Terrain (Wireframe Mountain)';
    case VisualizerStyle.albumArtReactive:
      return 'Album Art Reactive Glow';
    case VisualizerStyle.custom:
      return 'Custom JSON Visualizer';
  }
}

String getColorSourceTitle(ThemeColorSource source) {
  switch (source) {
    case ThemeColorSource.system:
      return 'Material You (Wallpaper)';
    case ThemeColorSource.artwork:
      return 'Album Artwork';
    case ThemeColorSource.custom:
      return 'Custom Accent';
  }
}

String getLanguageTitle(String code, AppLocalizations l10n) {
  switch (code) {
    case 'en':
      return 'English';
    case 'ar':
      return 'العربية (Arabic)';
    case 'es':
      return 'Español (Spanish)';
    default:
      return l10n.systemDefault;
  }
}

String getMiniPlayerSwipeTitle(MiniPlayerSwipeAction action) {
  switch (action) {
    case MiniPlayerSwipeAction.next:
      return 'Next Track';
    case MiniPlayerSwipeAction.prev:
      return 'Previous Track';
    case MiniPlayerSwipeAction.volume:
      return 'Adjust Volume';
    case MiniPlayerSwipeAction.none:
      return 'Disabled';
  }
}

String getNowPlayingDoubleTapTitle(NowPlayingDoubleTapAction action) {
  switch (action) {
    case NowPlayingDoubleTapAction.toggleFavorite:
      return 'Toggle Favorite';
    case NowPlayingDoubleTapAction.toggleLyrics:
      return 'Toggle Lyrics Overlay';
    case NowPlayingDoubleTapAction.none:
      return 'Disabled';
  }
}

String getNowPlayingArtworkSwipeTitle(NowPlayingArtworkSwipeAction action) {
  switch (action) {
    case NowPlayingArtworkSwipeAction.nextPrev:
      return 'Next / Previous Track';
    case NowPlayingArtworkSwipeAction.none:
      return 'Disabled';
  }
}

String getQualityTitle(YtmAudioQuality quality) {
  switch (quality) {
    case YtmAudioQuality.high:
      return 'High (~160+ kbps • Best)';
    case YtmAudioQuality.medium:
      return 'Medium (~128 kbps)';
    case YtmAudioQuality.low:
      return 'Low (~64 kbps • Data Saver)';
  }
}

// ============================================================================
// Picker Modal Sheets
// ============================================================================

void showThemePickerSheet(
  BuildContext context,
  SettingsCubit cubit,
  PlayerThemeMode currentMode,
) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final surfaceColor = Theme.of(context).colorScheme.surface;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final themes = [
    (
      mode: PlayerThemeMode.classic,
      title: 'Classic Standard',
      subtitle: 'Traditional high-definition layout with ambient glow',
      icon: Icons.square_outlined,
    ),
    (
      mode: PlayerThemeMode.card,
      title: 'Card Glass Overlay',
      subtitle: 'Full-bleed background artwork with frosted glass controls',
      icon: Icons.layers_rounded,
    ),
    (
      mode: PlayerThemeMode.circle,
      title: 'Vinyl Circle',
      subtitle: 'Centered circular artwork with continuous spinning animation',
      icon: Icons.album_rounded,
    ),
    (
      mode: PlayerThemeMode.minimal,
      title: 'Minimalist Waveform',
      subtitle: 'Spacious studio focus on dynamic audio waveform visualizer',
      icon: Icons.graphic_eq_rounded,
    ),
    (
      mode: PlayerThemeMode.vinyl,
      title: 'Vinyl Turntable Studio',
      subtitle:
          'True vinyl record with realistic grooves, center label & tonearm',
      icon: Icons.album_rounded,
    ),
    (
      mode: PlayerThemeMode.cassette,
      title: 'Retro Cassette Deck',
      subtitle:
          'Vintage cassette tape with spinning spools & magnetic tape counter',
      icon: Icons.radio_rounded,
    ),
    (
      mode: PlayerThemeMode.waveform,
      title: 'Full-Bleed Waveform',
      subtitle:
          'Full screen audio-reactive glowing waveform visualizer backdrop',
      icon: Icons.waves_rounded,
    ),
    (
      mode: PlayerThemeMode.lyricsFocus,
      title: 'Karaoke Lyrics Immersion',
      subtitle: 'Magnified synchronized lyrics-first karaoke player interface',
      icon: Icons.mic_rounded,
    ),
  ];

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: outlineColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                'Select Player Theme',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: themes.length,
                itemBuilder: (context, index) {
                  final t = themes[index];
                  final isSelected = t.mode == currentMode;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: isSelected
                          ? primaryColor.withValues(alpha: 0.12)
                          : cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected ? primaryColor : outlineColor,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          t.icon,
                          color: isSelected ? primaryColor : textSecondary,
                        ),
                        title: Text(
                          t.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isSelected ? primaryColor : textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          t.subtitle,
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_circle_rounded,
                                color: primaryColor)
                            : null,
                        onTap: () {
                          cubit.setPlayerThemeMode(t.mode);
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

void showLanguagePickerSheet(
  BuildContext context,
  SettingsCubit cubit,
  String currentCode,
) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final surfaceColor = Theme.of(context).colorScheme.surface;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final languages = [
    (
      code: 'system',
      name: 'System Default',
      nativeName: 'الافتراضي للنظام / Predeterminado',
      flag: Icons.settings_suggest_rounded
    ),
    (
      code: 'en',
      name: 'English',
      nativeName: 'English (US/UK)',
      flag: Icons.language_rounded
    ),
    (
      code: 'ar',
      name: 'العربية',
      nativeName: 'Arabic (RTL)',
      flag: Icons.translate_rounded
    ),
    (
      code: 'es',
      name: 'Español',
      nativeName: 'Spanish',
      flag: Icons.public_rounded
    ),
  ];

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              context.l10n.appLanguage,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...languages.map((lang) {
            final isSelected = lang.code == currentCode;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.12)
                    : cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected ? primaryColor : outlineColor,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    lang.flag,
                    color: isSelected ? primaryColor : textSecondary,
                  ),
                  title: Text(
                    lang.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isSelected ? primaryColor : textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    lang.nativeName,
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: primaryColor)
                      : null,
                  onTap: () {
                    cubit.setLanguage(lang.code);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

void showColorSourcePickerSheet(
  BuildContext context,
  SettingsCubit cubit,
  ThemeColorSource currentSource,
) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final surfaceColor = Theme.of(context).colorScheme.surface;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final sources = [
    (
      source: ThemeColorSource.system,
      title: 'Material You (Wallpaper)',
      subtitle:
          'Follow the system wallpaper palette on Android 12+ • falls back to album art on older devices',
      icon: Icons.wallpaper_rounded,
    ),
    (
      source: ThemeColorSource.artwork,
      title: 'Album Artwork',
      subtitle:
          'Adapt colors from the current track\'s album art (changes per song)',
      icon: Icons.album_rounded,
    ),
    (
      source: ThemeColorSource.custom,
      title: 'Custom Accent',
      subtitle: 'Use the fixed accent color you pick in settings',
      icon: Icons.color_lens_rounded,
    ),
  ];

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'App Color Source',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...sources.map((s) {
            final isSelected = s.source == currentSource;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.12)
                    : cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected ? primaryColor : outlineColor,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    s.icon,
                    color: isSelected ? primaryColor : textSecondary,
                  ),
                  title: Text(
                    s.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isSelected ? primaryColor : textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    s.subtitle,
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: primaryColor)
                      : null,
                  onTap: () {
                    cubit.setThemeColorSource(s.source);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

void showVisualizerStylePickerSheet(
  BuildContext context,
  SettingsCubit cubit,
  VisualizerStyle currentStyle,
) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final surfaceColor = Theme.of(context).colorScheme.surface;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final styles = [
    (
      style: VisualizerStyle.bar,
      title: 'BAR',
      subtitle: 'Classic vertical frequency bars with smooth height animation',
      icon: Icons.bar_chart_rounded,
    ),
    (
      style: VisualizerStyle.wave,
      title: 'WAVE',
      subtitle:
          'Smooth continuous Bézier waveform line with ambient gradient fill',
      icon: Icons.waves_rounded,
    ),
    (
      style: VisualizerStyle.circular,
      title: 'CIRCULAR',
      subtitle:
          'Futuristic radial frequency bars surrounding album centerpiece',
      icon: Icons.motion_photos_on_rounded,
    ),
    (
      style: VisualizerStyle.off,
      title: 'OFF',
      subtitle: 'Disable audio visualizer spectrum animation',
      icon: Icons.align_vertical_bottom_rounded,
    ),
  ];

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Audio Visualizer Style',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...styles.map((s) {
            final isSelected = s.style == currentStyle;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.12)
                    : cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected ? primaryColor : outlineColor,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    s.icon,
                    color: isSelected ? primaryColor : textSecondary,
                  ),
                  title: Text(
                    s.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isSelected ? primaryColor : textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    s.subtitle,
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: primaryColor)
                      : null,
                  onTap: () {
                    cubit.setVisualizerStyle(s.style);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

void showMiniPlayerSwipePickerSheet(
  BuildContext context,
  SettingsCubit cubit, {
  required bool isLeft,
  required MiniPlayerSwipeAction currentAction,
}) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final surfaceColor = Theme.of(context).colorScheme.surface;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final options = [
    (
      action: MiniPlayerSwipeAction.next,
      title: 'Next Track',
      subtitle: 'Skip to the next song in the queue',
      icon: Icons.skip_next_rounded,
    ),
    (
      action: MiniPlayerSwipeAction.prev,
      title: 'Previous Track',
      subtitle: 'Skip to the previous song or restart track',
      icon: Icons.skip_previous_rounded,
    ),
    (
      action: MiniPlayerSwipeAction.volume,
      title: 'Adjust Volume',
      subtitle: isLeft ? 'Lower playback volume' : 'Raise playback volume',
      icon: isLeft ? Icons.volume_down_rounded : Icons.volume_up_rounded,
    ),
    (
      action: MiniPlayerSwipeAction.none,
      title: 'Disabled',
      subtitle: 'Ignore swipe gesture',
      icon: Icons.block_rounded,
    ),
  ];

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              isLeft
                  ? 'MiniPlayer Swipe Left Action'
                  : 'MiniPlayer Swipe Right Action',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 12),
          ...options.map((opt) {
            final isSelected = opt.action == currentAction;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.12)
                    : cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected ? primaryColor : outlineColor,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(opt.icon,
                      color: isSelected ? primaryColor : textSecondary),
                  title: Text(opt.title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isSelected ? primaryColor : textPrimary)),
                  subtitle: Text(opt.subtitle,
                      style: TextStyle(fontSize: 12, color: textSecondary)),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: primaryColor)
                      : null,
                  onTap: () {
                    if (isLeft) {
                      cubit.setMiniPlayerSwipeLeft(opt.action);
                    } else {
                      cubit.setMiniPlayerSwipeRight(opt.action);
                    }
                    Navigator.pop(ctx);
                  },
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

void showNowPlayingDoubleTapPickerSheet(
  BuildContext context,
  SettingsCubit cubit,
  NowPlayingDoubleTapAction currentAction,
) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final surfaceColor = Theme.of(context).colorScheme.surface;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final options = [
    (
      action: NowPlayingDoubleTapAction.toggleFavorite,
      title: 'Toggle Favorite',
      subtitle: 'Add or remove active song from favorites',
      icon: Icons.favorite_rounded,
    ),
    (
      action: NowPlayingDoubleTapAction.toggleLyrics,
      title: 'Toggle Lyrics',
      subtitle: 'Show or hide synchronized lyrics overlay',
      icon: Icons.lyrics_rounded,
    ),
    (
      action: NowPlayingDoubleTapAction.none,
      title: 'Disabled',
      subtitle: 'Ignore double-tap gesture',
      icon: Icons.block_rounded,
    ),
  ];

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Now Playing Double-Tap Action',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 12),
          ...options.map((opt) {
            final isSelected = opt.action == currentAction;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.12)
                    : cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected ? primaryColor : outlineColor,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(opt.icon,
                      color: isSelected ? primaryColor : textSecondary),
                  title: Text(opt.title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isSelected ? primaryColor : textPrimary)),
                  subtitle: Text(opt.subtitle,
                      style: TextStyle(fontSize: 12, color: textSecondary)),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: primaryColor)
                      : null,
                  onTap: () {
                    cubit.setNowPlayingDoubleTap(opt.action);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

void showNowPlayingArtworkSwipePickerSheet(
  BuildContext context,
  SettingsCubit cubit,
  NowPlayingArtworkSwipeAction currentAction,
) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final surfaceColor = Theme.of(context).colorScheme.surface;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final options = [
    (
      action: NowPlayingArtworkSwipeAction.nextPrev,
      title: 'Next / Previous Track',
      subtitle: 'Swipe left for next track, swipe right for previous track',
      icon: Icons.swipe_rounded,
    ),
    (
      action: NowPlayingArtworkSwipeAction.none,
      title: 'Disabled',
      subtitle: 'Ignore horizontal swipe on album artwork',
      icon: Icons.block_rounded,
    ),
  ];

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Now Playing Artwork Swipe',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 12),
          ...options.map((opt) {
            final isSelected = opt.action == currentAction;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.12)
                    : cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected ? primaryColor : outlineColor,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(opt.icon,
                      color: isSelected ? primaryColor : textSecondary),
                  title: Text(opt.title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isSelected ? primaryColor : textPrimary)),
                  subtitle: Text(opt.subtitle,
                      style: TextStyle(fontSize: 12, color: textSecondary)),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: primaryColor)
                      : null,
                  onTap: () {
                    cubit.setNowPlayingArtworkSwipe(opt.action);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

void showQualityPickerSheet(
  BuildContext context,
  SettingsCubit cubit, {
  required bool isStreaming,
  required YtmAudioQuality currentQuality,
}) {
  final primaryColor = Theme.of(context).colorScheme.primary;
  final surfaceColor = Theme.of(context).colorScheme.surface;
  final cardColor =
      Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
  final outlineColor = Theme.of(context).colorScheme.outline;
  final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
      context.palette.textPrimary;
  final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
      context.palette.textSecondary;

  final options = [
    (
      quality: YtmAudioQuality.high,
      title: 'High Quality',
      subtitle: isStreaming
          ? 'Highest available bitrate (~160+ kbps) for crystal clear sound'
          : 'Highest quality audio files (~160+ kbps M4A)',
      icon: Icons.high_quality_rounded,
    ),
    (
      quality: YtmAudioQuality.medium,
      title: 'Medium Quality',
      subtitle: isStreaming
          ? 'Standard bitrate (~128 kbps) with balanced data usage'
          : 'Standard file size and quality (~128 kbps M4A)',
      icon: Icons.graphic_eq_rounded,
    ),
    (
      quality: YtmAudioQuality.low,
      title: 'Low / Data Saver',
      subtitle: isStreaming
          ? 'Reduced data usage (~64 kbps) for slow connections'
          : 'Smallest file size (~64 kbps)',
      icon: Icons.data_saver_on_rounded,
    ),
  ];

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              isStreaming
                  ? 'Streaming Audio Quality'
                  : 'Download Audio Quality',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 12),
          ...options.map((opt) {
            final isSelected = opt.quality == currentQuality;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.12)
                    : cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected ? primaryColor : outlineColor,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  leading: Icon(opt.icon,
                      color: isSelected ? primaryColor : textSecondary),
                  title: Text(opt.title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isSelected ? primaryColor : textPrimary)),
                  subtitle: Text(opt.subtitle,
                      style: TextStyle(fontSize: 12, color: textSecondary)),
                  trailing: isSelected
                      ? Icon(Icons.check_circle_rounded, color: primaryColor)
                      : null,
                  onTap: () {
                    if (isStreaming) {
                      cubit.setStreamingQuality(opt.quality);
                    } else {
                      cubit.setDownloadQuality(opt.quality);
                    }
                    Navigator.pop(ctx);
                  },
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

void showYtmWebOptionsSheet(BuildContext context) {
  final p = context.palette;
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Adaptive.sheetConstraints(ctx).maxWidth,
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Material(
            color: p.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: p.textTertiary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: p.accentContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.language_rounded,
                              color: p.accent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ctx.l10n.youtubeMusicWeb,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                              ),
                              Text(
                                ctx.l10n.selectPageToOpen,
                                style: TextStyle(
                                    color: p.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.home_rounded,
                      title: ctx.l10n.homePage,
                      subtitle: ctx.l10n.homePageSubtitle,
                      url: 'https://music.youtube.com/?gl=EG&hl=en',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.video_library_rounded,
                      title: ctx.l10n.youtubeWeb,
                      subtitle: ctx.l10n.youtubeWebSubtitle,
                      url: 'https://www.youtube.com',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.explore_rounded,
                      title: ctx.l10n.exploreAndCharts,
                      subtitle: ctx.l10n.exploreAndChartsSubtitle,
                      url: 'https://music.youtube.com/explore?gl=EG&hl=en',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.library_music_rounded,
                      title: ctx.l10n.yourLibrary,
                      subtitle: ctx.l10n.yourLibrarySubtitle,
                      url: 'https://music.youtube.com/library?gl=EG&hl=en',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.favorite_rounded,
                      title: ctx.l10n.likedMusic,
                      subtitle: ctx.l10n.likedMusicSubtitle,
                      url: 'https://music.youtube.com/playlist?list=LM&gl=EG&hl=en',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.fiber_new_rounded,
                      title: ctx.l10n.newReleases,
                      subtitle: ctx.l10n.newReleasesSubtitle,
                      url: 'https://music.youtube.com/new_releases?gl=EG&hl=en',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.history_rounded,
                      title: ctx.l10n.listeningHistory,
                      subtitle: ctx.l10n.listeningHistorySubtitle,
                      url: 'https://music.youtube.com/history?gl=EG&hl=en',
                      p: p,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget _ytmWebOptionTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required String url,
  required PulsrPalette p,
}) {
  return Material(
    color: Colors.transparent,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.hairline),
        ),
        child: Icon(icon, color: p.accent, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
            color: p.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: p.textSecondary, fontSize: 11.5),
      ),
      trailing: Icon(Icons.arrow_forward_ios_rounded,
          size: 14, color: p.textTertiary),
      onTap: () {
        Navigator.pop(context);
        YtmWebLoginSheet.show(
          context,
          initialUrl: url,
          title: title,
          isBrowseMode: true,
        );
      },
    ),
  );
}

void showPrivacyGuaranteeSheet(BuildContext context) {
  final p = context.palette;
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: p.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.security_rounded, color: p.accent, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Privacy Guarantee',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _privacyPoint(
                context,
                Icons.offline_bolt_rounded,
                'Offline-first',
                'Your library, playback and settings live on this device. Nothing is uploaded unless you explicitly sign in for cloud sync.',
              ),
              _privacyPoint(
                context,
                Icons.visibility_off_rounded,
                'No trackers in Pure',
                'Pure (Play Store) builds ship without the INTERNET permission, analytics SDKs or advertising identifiers.',
              ),
              _privacyPoint(
                context,
                Icons.folder_shared_rounded,
                'Permissions are purposeful',
                'Storage/media access is used only to scan and play your local audio. Bluetooth and notification access are requested only for connected-audio features and playback controls.',
              ),
              _privacyPoint(
                context,
                Icons.cloud_off_rounded,
                'You stay in control',
                'Cloud sync and remote metadata can be disabled. Automation rules and device profiles are stored locally.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _privacyPoint(
    BuildContext context, IconData icon, String title, String body) {
  final p = context.palette;
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: p.accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

void showAboutSheet(BuildContext context) {
  final p = context.palette;
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: p.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: p.accentContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.graphic_eq_rounded, color: p.accent, size: 34),
            ),
            const SizedBox(height: 14),
            Text(
              AppConfig.appTitle,
              style: TextStyle(
                color: p.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Version ${AppConfig.appVersion}',
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(
              'An audiophile-grade local music player with bit-perfect output, a full DSP chain, per-device profiles and automation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
