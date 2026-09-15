// lib/features/settings/presentation/widgets/settings_picker_sheets.dart
import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/visualizer/milkdrop_preset_store.dart';
import '../../../../data/visualizer/visualizer_preset_store.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/ytm_web_login_sheet.dart';
import '../../../player/presentation/widgets/audio_visualizer.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';

// ============================================================================
// Title formatters
// ============================================================================

String getThemeModeTitle(PlayerThemeMode mode, AppLocalizations l10n) {
  switch (mode) {
    case PlayerThemeMode.classic:
      return l10n.settingsThemeClassicStandard;
    case PlayerThemeMode.card:
      return l10n.settingsThemeCardGlass;
    case PlayerThemeMode.circle:
      return l10n.settingsThemeVinylCircle;
    case PlayerThemeMode.minimal:
      return l10n.settingsThemeMinimalist;
    case PlayerThemeMode.vinyl:
      return l10n.settingsThemeVinylTurntable;
    case PlayerThemeMode.cassette:
      return l10n.settingsThemeRetroCassette;
    case PlayerThemeMode.waveform:
      return l10n.settingsThemeFullBleed;
    case PlayerThemeMode.lyricsFocus:
      return l10n.settingsThemeKaraoke;
  }
}

String getVisualizerStyleTitle(VisualizerStyle style, AppLocalizations l10n) {
  switch (style) {
    case VisualizerStyle.off:
      return l10n.settingsVisualizerOff;
    case VisualizerStyle.bar:
      return l10n.settingsVisualizerBarClassic;
    case VisualizerStyle.wave:
      return l10n.settingsVisualizerWaveSmooth;
    case VisualizerStyle.circular:
      return l10n.settingsVisualizerCircular;
    case VisualizerStyle.particles:
      return l10n.settingsVisualizerParticles;
    case VisualizerStyle.terrain3D:
      return l10n.settingsVisualizerTerrain3d;
    case VisualizerStyle.albumArtReactive:
      return l10n.settingsVisualizerAlbumReactive;
    case VisualizerStyle.custom:
      return l10n.settingsVisualizerCustomJson;
    case VisualizerStyle.milkdrop:
      return l10n.settingsVisualizerMilkdrop;
  }
}

String getColorSourceTitle(ThemeColorSource source, AppLocalizations l10n) {
  switch (source) {
    case ThemeColorSource.system:
      return l10n.settingsColorSourceWallpaper;
    case ThemeColorSource.artwork:
      return l10n.settingsColorSourceArtwork;
    case ThemeColorSource.custom:
      return l10n.settingsColorSourceCustom;
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

String getMiniPlayerSwipeTitle(MiniPlayerSwipeAction action, AppLocalizations l10n) {
  switch (action) {
    case MiniPlayerSwipeAction.next:
      return l10n.settingsSwipeNextTrack;
    case MiniPlayerSwipeAction.prev:
      return l10n.settingsSwipePreviousTrack;
    case MiniPlayerSwipeAction.volume:
      return l10n.settingsSwipeAdjustVolume;
    case MiniPlayerSwipeAction.none:
      return l10n.settingsSwipeDisabled;
  }
}

String getNowPlayingDoubleTapTitle(NowPlayingDoubleTapAction action, AppLocalizations l10n) {
  switch (action) {
    case NowPlayingDoubleTapAction.toggleFavorite:
      return l10n.settingsDoubleTapToggleFavorite;
    case NowPlayingDoubleTapAction.toggleLyrics:
      return l10n.settingsDoubleTapToggleLyrics;
    case NowPlayingDoubleTapAction.none:
      return l10n.settingsDoubleTapDisabled;
  }
}

String getNowPlayingArtworkSwipeTitle(NowPlayingArtworkSwipeAction action, AppLocalizations l10n) {
  switch (action) {
    case NowPlayingArtworkSwipeAction.nextPrev:
      return l10n.settingsArtworkSwipeNextPrev;
    case NowPlayingArtworkSwipeAction.none:
      return l10n.settingsArtworkSwipeDisabled;
  }
}

String getQualityTitle(YtmAudioQuality quality, AppLocalizations l10n) {
  switch (quality) {
    case YtmAudioQuality.high:
      return l10n.settingsQualityHigh;
    case YtmAudioQuality.medium:
      return l10n.settingsQualityMedium;
    case YtmAudioQuality.low:
      return l10n.settingsQualityLow;
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
      title: context.l10n.settingsThemeClassicStandard,
      subtitle: context.l10n.settingsThemeClassicStandardDesc,
      icon: Icons.square_outlined,
    ),
    (
      mode: PlayerThemeMode.card,
      title: context.l10n.settingsThemeCardGlass,
      subtitle: context.l10n.settingsThemeCardGlassDesc,
      icon: Icons.layers_rounded,
    ),
    (
      mode: PlayerThemeMode.circle,
      title: context.l10n.settingsThemeVinylCircle,
      subtitle: context.l10n.settingsThemeVinylCircleDesc,
      icon: Icons.album_rounded,
    ),
    (
      mode: PlayerThemeMode.minimal,
      title: context.l10n.settingsThemeMinimalist,
      subtitle: context.l10n.settingsThemeMinimalistDesc,
      icon: Icons.graphic_eq_rounded,
    ),
    (
      mode: PlayerThemeMode.vinyl,
      title: context.l10n.settingsThemeVinylTurntable,
      subtitle: context.l10n.settingsThemeVinylTurntableDesc,
      icon: Icons.album_rounded,
    ),
    (
      mode: PlayerThemeMode.cassette,
      title: context.l10n.settingsThemeRetroCassette,
      subtitle: context.l10n.settingsThemeRetroCassetteDesc,
      icon: Icons.radio_rounded,
    ),
    (
      mode: PlayerThemeMode.waveform,
      title: context.l10n.settingsThemeFullBleed,
      subtitle: context.l10n.settingsThemeFullBleedDesc,
      icon: Icons.waves_rounded,
    ),
    (
      mode: PlayerThemeMode.lyricsFocus,
      title: context.l10n.settingsThemeKaraoke,
      subtitle: context.l10n.settingsThemeKaraokeDesc,
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
              child: Text(context.l10n.selectPlayerTheme,
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
      name: context.l10n.systemDefault,
      nativeName: 'الافتراضي للنظام / Predeterminado',
      flag: Icons.settings_suggest_rounded
    ),
    (
      code: 'en',
      name: context.l10n.english,
      nativeName: context.l10n.settingsEnglishNative,
      flag: Icons.language_rounded
    ),
    (
      code: 'ar',
      name: context.l10n.arabic,
      nativeName: context.l10n.settingsArabicNative,
      flag: Icons.translate_rounded,
    ),
    (
      code: 'es',
      name: context.l10n.spanish,
      nativeName: context.l10n.settingsSpanishNative,
      flag: Icons.public_rounded,
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
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
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
      title: context.l10n.settingsColorSourceWallpaper,
      subtitle: context.l10n.settingsColorSourceSystemDesc,
      icon: Icons.wallpaper_rounded,
    ),
    (
      source: ThemeColorSource.artwork,
      title: context.l10n.settingsColorSourceArtwork,
      subtitle: context.l10n.settingsColorSourceArtworkDesc,
      icon: Icons.album_rounded,
    ),
    (
      source: ThemeColorSource.custom,
      title: context.l10n.settingsColorSourceCustom,
      subtitle: context.l10n.settingsColorSourceCustomDesc,
      icon: Icons.color_lens_rounded,
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
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(context.l10n.appColorSource,
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
      title: context.l10n.settingsVizLabelBar,
      subtitle: context.l10n.settingsVizBarDesc,
      icon: Icons.bar_chart_rounded,
    ),
    (
      style: VisualizerStyle.wave,
      title: context.l10n.settingsVizLabelWave,
      subtitle: context.l10n.settingsVizWaveDesc,
      icon: Icons.waves_rounded,
    ),
    (
      style: VisualizerStyle.circular,
      title: context.l10n.settingsVizLabelCircular,
      subtitle: context.l10n.settingsVizCircularDesc,
      icon: Icons.motion_photos_on_rounded,
    ),
    (
      style: VisualizerStyle.particles,
      title: context.l10n.settingsVizLabelParticles,
      subtitle: context.l10n.settingsVizParticlesDesc,
      icon: Icons.auto_awesome_rounded,
    ),
    (
      style: VisualizerStyle.terrain3D,
      title: context.l10n.settingsVizLabelTerrain,
      subtitle: context.l10n.settingsVizTerrainDesc,
      icon: Icons.landscape_rounded,
    ),
    (
      style: VisualizerStyle.albumArtReactive,
      title: context.l10n.settingsVizLabelAlbumReactive,
      subtitle: context.l10n.settingsVizAlbumReactiveDesc,
      icon: Icons.album_rounded,
    ),
    (
      style: VisualizerStyle.off,
      title: context.l10n.settingsVizLabelOff,
      subtitle: context.l10n.settingsVizOffDesc,
      icon: Icons.align_vertical_bottom_rounded,
    ),
    (
      style: VisualizerStyle.milkdrop,
      title: context.l10n.settingsVizLabelMilkdrop,
      subtitle: context.l10n.milkRendererDesc,
      icon: Icons.blur_on_rounded,
    ),
    (
      style: VisualizerStyle.custom,
      title: context.l10n.settingsVizLabelCustom,
      subtitle: context.l10n.settingsVizCustomDesc,
      icon: Icons.data_object_rounded,
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
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(context.l10n.visualizerStyleLabel,
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
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: outlineColor),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.file_open_rounded, color: textSecondary),
                    title: Text(context.l10n.importMilk,
                      style:
                          TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
                    ),
                    subtitle: Text(context.l10n.loadMilkDesc,
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    onTap: () async {
                      final preset = await MilkdropPresetStore().importFromFile();
                      if (!context.mounted) return;
                      Navigator.pop(ctx);
                      cubit.setVisualizerStyle(VisualizerStyle.milkdrop);
                      if (preset != null) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content:
                                Text(context.l10n.importedPresetTpl(
                                    'Milkdrop', preset.name)),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: outlineColor),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.data_object_rounded, color: textSecondary),
                    title: Text(context.l10n.importJsonViz,
                      style:
                          TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
                    ),
                    subtitle: Text(context.l10n.loadJsonVizDesc,
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    onTap: () async {
                      final preset = await VisualizerPresetStore().importFromFile();
                      if (!context.mounted) return;
                      Navigator.pop(ctx);
                      cubit.setVisualizerStyle(VisualizerStyle.custom);
                      if (preset != null) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content:
                                Text(context.l10n.importedPresetTpl(
                                    'JSON', preset.name)),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
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
      title: context.l10n.settingsSwipeNextTrack,
      subtitle: context.l10n.settingsSwipeNextDesc,
      icon: Icons.skip_next_rounded,
    ),
    (
      action: MiniPlayerSwipeAction.prev,
      title: context.l10n.settingsSwipePreviousTrack,
      subtitle: context.l10n.settingsSwipePrevDesc,
      icon: Icons.skip_previous_rounded,
    ),
    (
      action: MiniPlayerSwipeAction.volume,
      title: context.l10n.settingsSwipeAdjustVolume,
      subtitle: isLeft ? context.l10n.settingsLowerVolume : context.l10n.settingsRaiseVolume,
      icon: isLeft ? Icons.volume_down_rounded : Icons.volume_up_rounded,
    ),
    (
      action: MiniPlayerSwipeAction.none,
      title: context.l10n.settingsSwipeDisabled,
      subtitle: context.l10n.settingsSwipeIgnoreDesc,
      icon: Icons.block_rounded,
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
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  isLeft
                      ? context.l10n.settingsSwipeLeftAction
                      : context.l10n.settingsSwipeRightAction,
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
      title: context.l10n.settingsDoubleTapToggleFavorite,
      subtitle: context.l10n.settingsDoubleTapFavoriteDesc,
      icon: Icons.favorite_rounded,
    ),
    (
      action: NowPlayingDoubleTapAction.toggleLyrics,
      title: context.l10n.settingsDoubleTapToggleLyrics,
      subtitle: context.l10n.settingsDoubleTapLyricsDesc,
      icon: Icons.lyrics_rounded,
    ),
    (
      action: NowPlayingDoubleTapAction.none,
      title: context.l10n.settingsDoubleTapDisabled,
      subtitle: context.l10n.settingsDoubleTapIgnoreDesc,
      icon: Icons.block_rounded,
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
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(context.l10n.npDoubleTap,
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
      title: context.l10n.settingsArtworkSwipeNextPrev,
      subtitle: context.l10n.settingsArtworkSwipeNextPrevDesc,
      icon: Icons.swipe_rounded,
    ),
    (
      action: NowPlayingArtworkSwipeAction.none,
      title: context.l10n.settingsArtworkSwipeDisabled,
      subtitle: context.l10n.settingsArtworkSwipeIgnoreDesc,
      icon: Icons.block_rounded,
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
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(context.l10n.npArtworkSwipe,
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
      title: context.l10n.settingsQualityHigh,
      subtitle: isStreaming
          ? context.l10n.settingsQualityHighStreamDesc
          : context.l10n.settingsQualityHighDownloadDesc,
      icon: Icons.high_quality_rounded,
    ),
    (
      quality: YtmAudioQuality.medium,
      title: context.l10n.settingsQualityMedium,
      subtitle: isStreaming
          ? context.l10n.settingsQualityMediumStreamDesc
          : context.l10n.settingsQualityMediumDownloadDesc,
      icon: Icons.graphic_eq_rounded,
    ),
    (
      quality: YtmAudioQuality.low,
      title: context.l10n.settingsQualityLow,
      subtitle: isStreaming
          ? context.l10n.settingsQualityLowStreamDesc
          : context.l10n.settingsQualityLowDownloadDesc,
      icon: Icons.data_saver_on_rounded,
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
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  isStreaming
                      ? context.l10n.streamingQuality
                      : context.l10n.downloadQuality,
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
                  Text(context.l10n.privacyGuarantee,
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
                context.l10n.settingsPrivacyOfflineTitle,
                context.l10n.settingsPrivacyOfflineBody,
              ),
              _privacyPoint(
                context,
                Icons.visibility_off_rounded,
                context.l10n.settingsPrivacyNoTrackersTitle,
                context.l10n.settingsPrivacyNoTrackersBody,
              ),
              _privacyPoint(
                context,
                Icons.folder_shared_rounded,
                context.l10n.settingsPrivacyPermissionsTitle,
                context.l10n.settingsPrivacyPermissionsBody,
              ),
              _privacyPoint(
                context,
                Icons.cloud_off_rounded,
                context.l10n.settingsPrivacyControlTitle,
                context.l10n.settingsPrivacyControlBody,
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
              '${context.l10n.version} ${AppConfig.appVersion}',
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.aboutBlurb,
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
                child: Text(context.l10n.close),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
