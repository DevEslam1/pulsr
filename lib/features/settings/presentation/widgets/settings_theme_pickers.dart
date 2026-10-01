// lib/features/settings/presentation/widgets/settings_picker_sheets.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/visualizer/milkdrop_preset_store.dart';
import '../../../../data/visualizer/visualizer_preset_store.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../player/presentation/widgets/audio_visualizer.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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

String getMiniPlayerSwipeTitle(
    MiniPlayerSwipeAction action, AppLocalizations l10n) {
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

String getNowPlayingDoubleTapTitle(
    NowPlayingDoubleTapAction action, AppLocalizations l10n) {
  switch (action) {
    case NowPlayingDoubleTapAction.toggleFavorite:
      return l10n.settingsDoubleTapToggleFavorite;
    case NowPlayingDoubleTapAction.toggleLyrics:
      return l10n.settingsDoubleTapToggleLyrics;
    case NowPlayingDoubleTapAction.none:
      return l10n.settingsDoubleTapDisabled;
  }
}

String getNowPlayingArtworkSwipeTitle(
    NowPlayingArtworkSwipeAction action, AppLocalizations l10n) {
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

class _ThemePreviewThumbnail extends StatelessWidget {
  final PlayerThemeMode mode;
  final bool isSelected;
  final Color primaryColor;

  const _ThemePreviewThumbnail({
    required this.mode,
    required this.isSelected,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final tint = isSelected
        ? primaryColor
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isSelected
            ? primaryColor.withValues(alpha: 0.15)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.r10),
        border: Border.all(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.4)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: Center(
        child: _buildPreviewIcon(tint),
      ),
    );
  }

  Widget _buildPreviewIcon(Color tint) {
    switch (mode) {
      case PlayerThemeMode.classic:
        return Icon(Icons.crop_square_rounded, size: 22, color: tint);
      case PlayerThemeMode.card:
        return Icon(Icons.layers_rounded, size: 22, color: tint);
      case PlayerThemeMode.circle:
        return Icon(Icons.album_rounded, size: 22, color: tint);
      case PlayerThemeMode.minimal:
        return Icon(Icons.graphic_eq_rounded, size: 22, color: tint);
      case PlayerThemeMode.vinyl:
        return Icon(Icons.radio_button_checked_rounded, size: 22, color: tint);
      case PlayerThemeMode.cassette:
        return Icon(Icons.developer_board_rounded, size: 22, color: tint);
      case PlayerThemeMode.waveform:
        return Icon(Icons.waves_rounded, size: 22, color: tint);
      case PlayerThemeMode.lyricsFocus:
        return Icon(Icons.mic_external_on_rounded, size: 22, color: tint);
    }
  }
}

void showThemePickerSheet(
  BuildContext context,
  SettingsCubit cubit,
  PlayerThemeMode currentMode,
) {
  final primaryColor = Theme.of(context).colorScheme.primary;
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

  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => _ThemePickerSheetContent(
      themes: themes,
      currentMode: currentMode,
      cubit: cubit,
      primaryColor: primaryColor,
      cardColor: cardColor,
      outlineColor: outlineColor,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
    ),
  );
}

class _ThemePickerSheetContent extends StatefulWidget {
  final List<
      ({
        PlayerThemeMode mode,
        String title,
        String subtitle,
        IconData icon
      })> themes;
  final PlayerThemeMode currentMode;
  final SettingsCubit cubit;
  final Color primaryColor;
  final Color cardColor;
  final Color outlineColor;
  final Color textPrimary;
  final Color textSecondary;

  const _ThemePickerSheetContent({
    required this.themes,
    required this.currentMode,
    required this.cubit,
    required this.primaryColor,
    required this.cardColor,
    required this.outlineColor,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  State<_ThemePickerSheetContent> createState() =>
      _ThemePickerSheetContentState();
}

class _ThemePickerSheetContentState extends State<_ThemePickerSheetContent> {
  late PageController _pageController;
  late PlayerThemeMode _selectedMode;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.currentMode;
    final initialIndex =
        widget.themes.indexWhere((t) => t.mode == _selectedMode);
    _pageController = PageController(
      viewportFraction: 0.82,
      initialPage: initialIndex >= 0 ? initialIndex : 0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s20, vertical: AppSpacing.xxs),
              child: Text(
                context.l10n.selectPlayerTheme,
                style: TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: FontWeight.w900,
                  color: widget.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Live Preview Carousel
            SizedBox(
              height: 140,
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.themes.length,
                onPageChanged: (idx) {
                  final newMode = widget.themes[idx].mode;
                  setState(() => _selectedMode = newMode);
                  widget.cubit.setPlayerThemeMode(newMode);
                },
                itemBuilder: (context, index) {
                  final t = widget.themes[index];
                  final isSelected = t.mode == _selectedMode;
                  return AnimatedScale(
                    scale: isSelected ? 1.0 : 0.92,
                    duration: const Duration(milliseconds: 200),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedMode = t.mode);
                        widget.cubit.setPlayerThemeMode(t.mode);
                      },
                      child: _ThemeMockupCard(
                        mode: t.mode,
                        title: t.title,
                        isSelected: isSelected,
                        primaryColor: widget.primaryColor,
                        cardColor: widget.cardColor,
                        textPrimary: widget.textPrimary,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Theme List
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: widget.themes.length,
                itemBuilder: (context, index) {
                  final t = widget.themes[index];
                  final isSelected = t.mode == _selectedMode;
                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Material(
                      color: isSelected
                          ? widget.primaryColor.withValues(alpha: 0.12)
                          : widget.cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.r16),
                        side: BorderSide(
                          color: isSelected
                              ? widget.primaryColor
                              : widget.outlineColor,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        leading: _ThemePreviewThumbnail(
                          mode: t.mode,
                          isSelected: isSelected,
                          primaryColor: widget.primaryColor,
                        ),
                        title: Text(
                          t.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? widget.primaryColor
                                : widget.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          t.subtitle,
                          style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: widget.textSecondary),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_circle_rounded,
                                color: widget.primaryColor)
                            : null,
                        onTap: () {
                          setState(() => _selectedMode = t.mode);
                          widget.cubit.setPlayerThemeMode(t.mode);
                          _pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _ThemeMockupCard extends StatelessWidget {
  final PlayerThemeMode mode;
  final String title;
  final bool isSelected;
  final Color primaryColor;
  final Color cardColor;
  final Color textPrimary;

  const _ThemeMockupCard({
    required this.mode,
    required this.title,
    required this.isSelected,
    required this.primaryColor,
    required this.cardColor,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(
          color: isSelected ? primaryColor : p.hairline,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? primaryColor : textPrimary,
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, size: 14, color: primaryColor),
            ],
          ),
          const Spacer(),
          Center(
            child: _buildMockupVisual(context),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildMockupVisual(BuildContext context) {
    final p = context.palette;
    switch (mode) {
      case PlayerThemeMode.vinyl:
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.bg,
            border: Border.all(color: p.hairline, width: 2),
          ),
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor,
              ),
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      case PlayerThemeMode.cassette:
        return Container(
          width: 80,
          height: 50,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: p.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadii.r6),
            border: Border.all(color: primaryColor.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Icon(Icons.trip_origin_rounded, size: 16, color: primaryColor),
              Container(width: 20, height: 10, color: p.hairline),
              Icon(Icons.trip_origin_rounded, size: 16, color: primaryColor),
            ],
          ),
        );
      case PlayerThemeMode.waveform:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(8, (i) {
            final h = [15.0, 32.0, 48.0, 24.0, 40.0, 56.0, 30.0, 18.0][i];
            return Container(
              width: 4,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(AppRadii.r2),
              ),
            );
          }),
        );
      case PlayerThemeMode.lyricsFocus:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 60, height: 4, color: p.hairline),
            const SizedBox(height: 4),
            Container(width: 90, height: 6, color: primaryColor),
            const SizedBox(height: 4),
            Container(width: 70, height: 4, color: p.hairline),
          ],
        );
      case PlayerThemeMode.circle:
        return Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor.withValues(alpha: 0.2),
            border: Border.all(color: primaryColor, width: 2),
          ),
          child: Icon(Icons.music_note_rounded, color: primaryColor, size: 28),
        );
      case PlayerThemeMode.card:
        return Container(
          width: 70,
          height: 48,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(AppRadii.r8),
            border: Border.all(color: primaryColor.withValues(alpha: 0.4)),
          ),
          child: Center(
            child: Icon(Icons.layers_rounded, color: p.textSecondary, size: 22),
          ),
        );
      case PlayerThemeMode.minimal:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 50, height: 3, color: primaryColor),
            const SizedBox(width: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor,
              ),
            ),
          ],
        );
      case PlayerThemeMode.classic:
        return Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadii.r6),
            border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
          ),
          child: Icon(Icons.play_arrow_rounded, color: primaryColor, size: 28),
        );
    }
  }
}

void showLanguagePickerSheet(
  BuildContext context,
  SettingsCubit cubit,
  String currentCode,
) {
  final primaryColor = Theme.of(context).colorScheme.primary;
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

  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.s20, horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                child: Text(
                  context.l10n.appLanguage,
                  style: const TextStyle(
                    fontSize: AppFontSize.title,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...languages.map((lang) {
                final isSelected = lang.code == currentCode;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Material(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.12)
                        : cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r16),
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
                        style: TextStyle(
                            fontSize: AppFontSize.label, color: textSecondary),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded,
                              color: primaryColor)
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

  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.s20, horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                child: Text(
                  context.l10n.appColorSource,
                  style: TextStyle(
                    fontSize: AppFontSize.title,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...sources.map((s) {
                final isSelected = s.source == currentSource;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Material(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.12)
                        : cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r16),
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
                        style: TextStyle(
                            fontSize: AppFontSize.label, color: textSecondary),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded,
                              color: primaryColor)
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

  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.s20, horizontal: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                child: Text(
                  context.l10n.visualizerStyleLabel,
                  style: TextStyle(
                    fontSize: AppFontSize.title,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...styles.map((s) {
                final isSelected = s.style == currentStyle;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Material(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.12)
                        : cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r16),
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
                        style: TextStyle(
                            fontSize: AppFontSize.label, color: textSecondary),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded,
                              color: primaryColor)
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
                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Material(
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.r16),
                    side: BorderSide(color: outlineColor),
                  ),
                  child: ListTile(
                    leading:
                        Icon(Icons.file_open_rounded, color: textSecondary),
                    title: Text(
                      context.l10n.importMilk,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: textPrimary),
                    ),
                    subtitle: Text(
                      context.l10n.loadMilkDesc,
                      style: TextStyle(
                          fontSize: AppFontSize.label, color: textSecondary),
                    ),
                    onTap: () async {
                      final preset =
                          await MilkdropPresetStore().importFromFile();
                      if (!context.mounted) return;
                      Navigator.pop(ctx);
                      cubit.setVisualizerStyle(VisualizerStyle.milkdrop);
                      if (preset != null) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text(context.l10n
                                .importedPresetTpl('Milkdrop', preset.name)),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Material(
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.r16),
                    side: BorderSide(color: outlineColor),
                  ),
                  child: ListTile(
                    leading:
                        Icon(Icons.data_object_rounded, color: textSecondary),
                    title: Text(
                      context.l10n.importJsonViz,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: textPrimary),
                    ),
                    subtitle: Text(
                      context.l10n.loadJsonVizDesc,
                      style: TextStyle(
                          fontSize: AppFontSize.label, color: textSecondary),
                    ),
                    onTap: () async {
                      final preset =
                          await VisualizerPresetStore().importFromFile();
                      if (!context.mounted) return;
                      Navigator.pop(ctx);
                      cubit.setVisualizerStyle(VisualizerStyle.custom);
                      if (preset != null) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text(context.l10n
                                .importedPresetTpl('JSON', preset.name)),
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
