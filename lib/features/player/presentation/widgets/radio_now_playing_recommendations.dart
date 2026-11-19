// lib/features/player/presentation/widgets/radio_now_playing_recommendations.dart
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/services/ambient_sound_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../core/widgets/pulsr_switch.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/quran_mode_profile.dart';
import '../../cubit/player_cubit.dart';
import '../themes/player_theme.dart';
import '../themes/player_theme_scaffold.dart';
import 'ambient_sound_sheet.dart';
import 'quran_mode_sheet.dart';

enum _RecommendationTab {
  quran,
  ambient,
}

/// Dynamic recommendation surface displayed on the Now Playing screen when
/// listening to live radio.
///
/// Features:
/// 1. Quran Mode recommendations: defaults to Tajweed (Mujawwad); changing style
///    saves the user's choice as the new default. Supports "Always on Radio"
///    which auto-enables during radio and disables during local/online playback.
/// 2. Ambient Sounds recommendations: quick toggle, effect selection, and volume
///    percentage control, saving user choices and percentage values. Supports
///    "Always on Radio".
class RadioNowPlayingRecommendations extends StatefulWidget {
  final PlayerThemeProps props;
  final PlayerCubit cubit;
  final PlayerThemeMetrics? metrics;

  const RadioNowPlayingRecommendations({
    super.key,
    required this.props,
    required this.cubit,
    this.metrics,
  });

  /// Only a live radio stream gets this recommendation surface. A net-library
  /// file ([SongSource.remote]) is finite and seekable, so it must not show the
  /// radio card (the Quran/ambient offers assume an endless live broadcast).
  static bool shouldShowFor(SongsTableData? song) =>
      SongSource.isLive(song?.source);

  @override
  State<RadioNowPlayingRecommendations> createState() =>
      _RadioNowPlayingRecommendationsState();
}

class _RadioNowPlayingRecommendationsState
    extends State<RadioNowPlayingRecommendations> {
  _RecommendationTab _selectedTab = _RecommendationTab.quran;
  bool _isCollapsed = false;
  bool _quranAlwaysOnRadio = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.cubit.isQuranAlwaysOnRadio().then((v) {
      if (mounted) setState(() => _quranAlwaysOnRadio = v);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.props.state.currentSong;
    if (!RadioNowPlayingRecommendations.shouldShowFor(song)) {
      return const SizedBox.shrink();
    }
    if (widget.props.state.isLyricsVisible ||
        widget.props.state.isQueueVisible) {
      return const SizedBox.shrink();
    }

    final p = context.palette;
    final l10n = context.l10n;
    final isVeryShort = widget.metrics?.isVeryShortHeight ?? false;
    final isLandscape = widget.metrics?.isLandscape ?? false;

    // Compact pill mode for very short displays or landscape orientation
    if (isVeryShort || isLandscape) {
      return _buildCompactBar(context, p);
    }

    final accent = _selectedTab == _RecommendationTab.quran
        ? AppColors.quranEmerald
        : widget.props.activeColor;

    return AnimatedContainer(
      duration: context.motion(PulsrMotion.layout),
      curve: context.motionCurve(Curves.easeOutCubic),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              accent.withValues(alpha: p.isDark ? 0.10 : 0.05),
              p.surfaceContainer.withValues(alpha: p.isDark ? 0.92 : 0.98),
            ),
            p.surfaceContainer.withValues(alpha: p.isDark ? 0.70 : 0.90),
          ],
        ),
        borderRadius: AppRadii.r20All,
        border: Border.all(
          color: accent.withValues(alpha: p.isDark ? 0.30 : 0.24),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.22 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 18,
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadii.r20All,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top tab selector & collapse header
            _buildHeader(context, p, l10n),

            if (!_isCollapsed) ...[
              AnimatedSwitcher(
                duration: context.motionMs(260),
                switchInCurve: context.motionCurve(Curves.easeOutCubic),
                switchOutCurve: context.motionCurve(Curves.easeInCubic),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: KeyedSubtree(
                  key: ValueKey(_selectedTab),
                  child: _selectedTab == _RecommendationTab.quran
                      ? _buildQuranSection(context, p)
                      : _buildAmbientSection(context, p),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactBar(BuildContext context, PulsrPalette p) {
    final isQuranOn = widget.props.state.isQuranModeEnabled;
    final ambientService = AmbientSoundService();
    final isAmbientOn = ambientService.isEnabled;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Compact Quran chip
          InkWell(
            onTap: () {
              PulsrHaptics.lightImpact();
              QuranModeSheet.show(context);
            },
            borderRadius: AppRadii.r20All,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: isQuranOn
                    ? AppColors.quranEmerald.withValues(alpha: 0.20)
                    : p.surfaceContainer,
                borderRadius: AppRadii.r20All,
                border: Border.all(
                  color: isQuranOn
                      ? AppColors.quranEmerald.withValues(alpha: 0.50)
                      : p.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_stories_rounded,
                    size: 14,
                    color: AppColors.quranEmerald,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Quran: ${widget.props.state.quranReciterStyle.label}',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),

          // Compact Ambient chip
          ListenableBuilder(
            listenable: ambientService,
            builder: (context, _) {
              final activeCount = ambientService.activeEffects.length;
              final percent = (ambientService.masterVolume * 100).round();
              return InkWell(
                onTap: () {
                  PulsrHaptics.lightImpact();
                  AmbientSoundSheet.show(context);
                },
                borderRadius: AppRadii.r20All,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s10,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: isAmbientOn
                        ? widget.props.activeColor.withValues(alpha: 0.20)
                        : p.surfaceContainer,
                    borderRadius: AppRadii.r20All,
                    border: Border.all(
                      color: isAmbientOn
                          ? widget.props.activeColor.withValues(alpha: 0.50)
                          : p.hairline,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.water_drop_rounded,
                        size: 14,
                        color: widget.props.activeColor,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        activeCount > 0
                            ? 'Ambient $percent%'
                            : context.l10n.ambientSounds,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _readableOn(Color color) =>
      color.computeLuminance() > 0.5 ? AppColors.controlInk : Colors.white;

  Widget _buildHeader(
    BuildContext context,
    PulsrPalette p,
    dynamic l10n,
  ) {
    final accent = _selectedTab == _RecommendationTab.quran
        ? AppColors.quranEmerald
        : widget.props.activeColor;

    final brand = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: p.isDark ? 0.30 : 0.20),
            accent.withValues(alpha: p.isDark ? 0.10 : 0.06),
          ],
        ),
        borderRadius: AppRadii.r10All,
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Icon(Icons.auto_awesome_rounded, size: 15, color: accent),
    );

    final title = Text(
      l10n.radioRecommendations,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: p.textPrimary,
        fontSize: AppFontSize.label,
        fontWeight: FontWeight.w800,
        letterSpacing: AppTracking.label,
      ),
    );

    final collapseButton = IconButton(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      tooltip:
          _isCollapsed ? 'Expand recommendations' : 'Collapse recommendations',
      icon: Icon(
        _isCollapsed
            ? Icons.keyboard_arrow_down_rounded
            : Icons.keyboard_arrow_up_rounded,
        size: 20,
        color: p.textSecondary,
      ),
      onPressed: () {
        PulsrHaptics.selectionClick();
        setState(() => _isCollapsed = !_isCollapsed);
      },
    );

    final tabSelector = Container(
      padding: const EdgeInsets.all(3.0),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Colors.black.withValues(alpha: p.isDark ? 0.28 : 0.03),
          p.surfaceContainer,
        ),
        borderRadius: AppRadii.r14All,
        border: Border.all(color: p.hairline, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabButton(
            tab: _RecommendationTab.quran,
            icon: Icons.auto_stories_rounded,
            label: l10n.quranMode,
            activeColor: AppColors.quranEmerald,
            p: p,
          ),
          const SizedBox(width: 3),
          _buildTabButton(
            tab: _RecommendationTab.ambient,
            icon: Icons.water_drop_rounded,
            label: l10n.ambientSounds,
            activeColor: widget.props.activeColor,
            p: p,
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.s10,
        AppSpacing.s8,
        AppSpacing.s6,
        AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.hairline, width: 0.7)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The label, both tab labels and the collapse button cannot share a
          // single line on phones (~460dp of natural width), so the selector
          // drops to its own line instead of overflowing the banner.
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    brand,
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(child: title),
                    collapseButton,
                  ],
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.xs,
                    top: AppSpacing.xxs,
                    bottom: AppSpacing.xxs,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: tabSelector,
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              brand,
              const SizedBox(width: AppSpacing.s10),
              Expanded(child: title),
              const SizedBox(width: AppSpacing.sm),
              tabSelector,
              const SizedBox(width: AppSpacing.xxs),
              collapseButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabButton({
    required _RecommendationTab tab,
    required IconData icon,
    required String label,
    required Color activeColor,
    required PulsrPalette p,
  }) {
    final isSelected = _selectedTab == tab;
    final foreground = isSelected ? _readableOn(activeColor) : p.textSecondary;
    return InkWell(
      onTap: () {
        if (!isSelected) {
          PulsrHaptics.selectionClick();
          setState(() {
            _selectedTab = tab;
            _isCollapsed = false;
          });
        }
      },
      borderRadius: AppRadii.r10All,
      child: AnimatedContainer(
        duration: context.motionMs(200),
        curve: context.motionCurve(Curves.easeOutCubic),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    activeColor,
                    Color.alphaBlend(
                      Colors.black.withValues(alpha: 0.16),
                      activeColor,
                    ),
                  ],
                )
              : null,
          borderRadius: AppRadii.r10All,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.32),
                    blurRadius: 10,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionIcon({
    required IconData icon,
    required Color accent,
    required PulsrPalette p,
  }) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: p.isDark ? 0.24 : 0.16),
            accent.withValues(alpha: p.isDark ? 0.08 : 0.05),
          ],
        ),
        borderRadius: AppRadii.r14All,
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Icon(icon, size: 20, color: accent),
    );
  }

  Widget _buildChoicePill({
    required String label,
    required bool isSelected,
    required Color accent,
    required PulsrPalette p,
    required VoidCallback onTap,
  }) {
    final foreground = isSelected ? _readableOn(accent) : p.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.r12All,
      child: AnimatedContainer(
        duration: context.motionMs(200),
        curve: context.motionCurve(Curves.easeOutCubic),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent,
                    Color.alphaBlend(
                      Colors.black.withValues(alpha: 0.16),
                      accent,
                    ),
                  ],
                )
              : null,
          color: isSelected
              ? null
              : p.surfaceContainerHigh.withValues(alpha: p.isDark ? 0.55 : 0.8),
          borderRadius: AppRadii.r12All,
          border: Border.all(
            color: isSelected ? Colors.transparent : p.hairline,
            width: 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.28),
                    blurRadius: 10,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(Icons.check_rounded, size: 13, color: foreground),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: foreground,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlwaysOnRow({
    required PulsrPalette p,
    required Color accent,
    required bool value,
    required ValueChanged<bool> onChanged,
    required VoidCallback onOpen,
    required String openTooltip,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.s10,
        AppSpacing.s2,
        AppSpacing.s2,
        AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Colors.black.withValues(alpha: p.isDark ? 0.18 : 0.02),
          p.surfaceContainer.withValues(alpha: p.isDark ? 0.55 : 0.8),
        ),
        borderRadius: AppRadii.r14All,
        border: Border.all(color: p.hairline, width: 0.7),
      ),
      child: Row(
        children: [
          Icon(
            Icons.radio_rounded,
            size: 16,
            color: value ? accent : p.textSecondary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          PulsrSwitch(
            value: value,
            activeColor: accent,
            onChanged: onChanged,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.open_in_new_rounded,
              size: 15,
              color: p.textSecondary,
            ),
            tooltip: openTooltip,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }

  Widget _buildQuranSection(BuildContext context, PulsrPalette p) {
    final state = widget.props.state;
    final isQuranOn = state.isQuranModeEnabled;
    final currentStyle = state.quranReciterStyle;
    const accent = AppColors.quranEmerald;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reciter hero row
          Row(
            children: [
              _sectionIcon(
                icon: Icons.auto_stories_rounded,
                accent: accent,
                p: p,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.quranMode,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${currentStyle.label} • ${currentStyle.tagline}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              PulsrSwitch(
                value: isQuranOn,
                activeColor: accent,
                onChanged: (v) {
                  PulsrHaptics.lightImpact();
                  unawaited(widget.cubit.setQuranModeEnabled(v));
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),

          // Reciter style pills (user choice saved as the new default)
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: QuranReciterStyle.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s6),
              itemBuilder: (context, i) {
                final style = QuranReciterStyle.values[i];
                final isSelected = style == currentStyle;
                return _buildChoicePill(
                  label: style == QuranReciterStyle.mujawwad
                      ? '${style.label} (Tajweed)'
                      : style.label,
                  isSelected: isSelected,
                  accent: accent,
                  p: p,
                  onTap: () {
                    PulsrHaptics.selectionClick();
                    unawaited(widget.cubit.setQuranReciterStyle(style));
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: p.textTertiary,
              ),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  context.l10n.styleDefaultNotice,
                  style: TextStyle(
                    color: p.textTertiary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Always on Radio footer
          _buildAlwaysOnRow(
            p: p,
            accent: accent,
            value: _quranAlwaysOnRadio,
            label: context.l10n.alwaysOnRadio,
            openTooltip: context.l10n.quranMode,
            onOpen: () => QuranModeSheet.show(context),
            onChanged: (v) {
              PulsrHaptics.selectionClick();
              setState(() => _quranAlwaysOnRadio = v);
              unawaited(widget.cubit.setQuranAlwaysOnRadio(v));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientSection(BuildContext context, PulsrPalette p) {
    final ambientService = AmbientSoundService();
    final accent = widget.props.activeColor;

    return ListenableBuilder(
      listenable: ambientService,
      builder: (context, _) {
        final isAmbientOn = ambientService.isEnabled;
        final masterVol = ambientService.masterVolume;
        final percent = (masterVol * 100).round();
        final alwaysOnRadio = ambientService.alwaysOnRadio;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ambient hero row
              Row(
                children: [
                  _sectionIcon(
                    icon: Icons.water_drop_rounded,
                    accent: accent,
                    p: p,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.ambientSounds,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAmbientOn && ambientService.activeEffects.isNotEmpty
                              ? ambientService.activeEffects
                                  .map((e) =>
                                      '${e.emoji} ${(ambientService.volumeFor(e) * 100).round()}%')
                                  .join('  ')
                              : context.l10n.ambientSoundsDesc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  PulsrSwitch(
                    value: isAmbientOn,
                    activeColor: accent,
                    onChanged: (v) {
                      PulsrHaptics.lightImpact();
                      unawaited(ambientService.setEnabled(v));
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),

              // Effect pills
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: AmbientSoundEffect.values.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.s6),
                  itemBuilder: (context, i) {
                    final effect = AmbientSoundEffect.values[i];
                    final isSelected = ambientService.isEffectActive(effect);
                    final effectVolPercent =
                        (ambientService.volumeFor(effect) * 100).round();
                    final effectLabel = isSelected
                        ? '${effect.localizedLabel(context.l10n)} $effectVolPercent%'
                        : effect.localizedLabel(context.l10n);

                    return _buildChoicePill(
                      label: '${effect.emoji} $effectLabel',
                      isSelected: isSelected,
                      accent: accent,
                      p: p,
                      onTap: () {
                        PulsrHaptics.selectionClick();
                        unawaited(ambientService.toggleEffect(effect));
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.s8),

              // Volume percentage slider
              Container(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.s10,
                  AppSpacing.s2,
                  AppSpacing.s10,
                  AppSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    Colors.black.withValues(alpha: p.isDark ? 0.18 : 0.02),
                    p.surfaceContainer.withValues(alpha: p.isDark ? 0.55 : 0.8),
                  ),
                  borderRadius: AppRadii.r14All,
                  border: Border.all(color: p.hairline, width: 0.7),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.volume_up_rounded,
                      size: 16,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      context.l10n.ambientVolumePercent(percent),
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Expanded(
                      child: PulsrSlider(
                        value: masterVol,
                        min: 0.0,
                        max: 1.0,
                        activeColor: accent,
                        onChanged: (v) {
                          unawaited(ambientService.setMasterVolume(v));
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Always on Radio footer
              _buildAlwaysOnRow(
                p: p,
                accent: accent,
                value: alwaysOnRadio,
                label: context.l10n.alwaysOnRadio,
                openTooltip: context.l10n.ambientSounds,
                onOpen: () => AmbientSoundSheet.show(context),
                onChanged: (v) {
                  PulsrHaptics.selectionClick();
                  unawaited(ambientService.setAlwaysOnRadio(v));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
