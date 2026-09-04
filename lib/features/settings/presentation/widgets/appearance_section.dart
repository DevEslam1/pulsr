// lib/features/settings/presentation/widgets/appearance_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../player/presentation/widgets/audio_visualizer.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import 'settings_section.dart';
import 'settings_tiles.dart';

/// Theme mode, accent color, player theme, visualizer, color source, language.
class AppearanceSection extends StatelessWidget {
  final SettingsState state;

  const AppearanceSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    return SettingsSection(
      icon: Icons.palette_outlined,
      title: context.l10n.themeAndAppearance,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<AppThemeMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 2),
                ),
              ),
              segments: [
                ButtonSegment(
                  value: AppThemeMode.system,
                  label: Text(
                    context.l10n.systemDefault,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.brightness_auto_rounded, size: 15),
                ),
                ButtonSegment(
                  value: AppThemeMode.light,
                  label: Text(
                    context.l10n.themeLight,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.light_mode_rounded, size: 15),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text(
                    context.l10n.themeDark,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.dark_mode_rounded, size: 15),
                ),
                ButtonSegment(
                  value: AppThemeMode.amoled,
                  label: Text(
                    'AMOLED',
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.contrast_rounded, size: 15),
                ),
              ],
              selected: {state.themeMode},
              onSelectionChanged: (sel) => cubit.setThemeMode(sel.first),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.accentColor,
                  style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: AppColors.customAccents.map((color) {
                    final isSelected =
                        state.customAccentColorValue == color.toARGB32();
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () => cubit.setCustomAccentColor(color),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? p.textPrimary
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                        color: color.withValues(alpha: 0.5),
                                        blurRadius: 12,
                                        spreadRadius: 1)
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 20,
                                  color: color.computeLuminance() > 0.5
                                      ? Colors.black
                                      : Colors.white,
                                )
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        settingsCardDivider(p),
        SettingsNavTile(
            Icons.art_track_rounded,
            context.l10n.nowPlayingTheme,
            _getThemeModeTitle(state.playerThemeMode),
            onTap: () => _showThemePickerSheet(
                context, cubit, state.playerThemeMode)),
        settingsCardDivider(p),
        SettingsNavTile(
            Icons.graphic_eq_rounded,
            context.l10n.visualizerStyle,
            _getVisualizerStyleTitle(state.visualizerStyle),
            onTap: () => _showVisualizerStylePickerSheet(
                context, cubit, state.visualizerStyle)),
        settingsCardDivider(p),
        SettingsNavTile(
            Icons.palette_outlined,
            context.l10n.colorSource,
            _getColorSourceTitle(state.themeColorSource),
            onTap: () => _showColorSourcePickerSheet(
                context, cubit, state.themeColorSource)),
        settingsCardDivider(p),
        SettingsNavTile(
            Icons.language_rounded,
            context.l10n.language,
            _getLanguageTitle(state.languageCode),
            onTap: () => _showLanguagePickerSheet(
                context, cubit, state.languageCode)),
      ],
    );
  }

  String _getThemeModeTitle(PlayerThemeMode mode) {
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

  String _getVisualizerStyleTitle(VisualizerStyle style) {
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

  String _getLanguageTitle(String code) {
    switch (code) {
      case 'ar':
        return 'العربية (Arabic)';
      case 'es':
        return 'Español (Spanish)';
      case 'en':
        return 'English';
      default:
        return 'System Default';
    }
  }

  String _getColorSourceTitle(ThemeColorSource source) {
    switch (source) {
      case ThemeColorSource.system:
        return 'Material You (Wallpaper)';
      case ThemeColorSource.artwork:
        return 'Album Artwork';
      case ThemeColorSource.custom:
        return 'Custom Accent';
    }
  }

  void _showThemePickerSheet(
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
        subtitle:
            'Centered circular artwork with continuous spinning animation',
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
        subtitle:
            'Magnified synchronized lyrics-first karaoke player interface',
        icon: Icons.mic_rounded,
      ),
    ];

    showModalBottomSheet<void>(
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
                'Select Player Theme',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...themes.map((t) {
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
                        ? Icon(Icons.check_circle_rounded, color: primaryColor)
                        : null,
                    onTap: () {
                      cubit.setPlayerThemeMode(t.mode);
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

  void _showLanguagePickerSheet(
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

    showModalBottomSheet<void>(
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

  void _showColorSourcePickerSheet(
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
        subtitle: 'Use the fixed accent color you pick above',
        icon: Icons.color_lens_rounded,
      ),
    ];

    showModalBottomSheet<void>(
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

  void _showVisualizerStylePickerSheet(
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
        subtitle:
            'Classic vertical frequency bars with smooth height animation',
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

    showModalBottomSheet<void>(
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
}
