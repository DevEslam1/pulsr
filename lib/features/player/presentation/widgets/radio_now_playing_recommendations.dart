// lib/features/player/presentation/widgets/radio_now_playing_recommendations.dart
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
    if (song?.source != SongSource.radio) {
      return const SizedBox.shrink();
    }
    if (widget.props.state.isLyricsVisible || widget.props.state.isQueueVisible) {
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

    return AnimatedContainer(
      duration: context.motion(PulsrMotion.layout),
      curve: context.motionCurve(Curves.easeOutCubic),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: p.isDark
            ? AppColors.specularAt(0.06)
            : p.surfaceContainer.withValues(alpha: 0.85),
        borderRadius: AppRadii.r16All,
        border: Border.all(
          color: _selectedTab == _RecommendationTab.quran
              ? AppColors.quranEmerald.withValues(alpha: 0.28)
              : widget.props.activeColor.withValues(alpha: 0.28),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadii.r16All,
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

  Widget _buildHeader(
    BuildContext context,
    PulsrPalette p,
    dynamic l10n,
  ) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.s12,
        AppSpacing.s6,
        AppSpacing.s6,
        AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: p.isDark
            ? Colors.black.withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: p.hairline, width: 0.7)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 15,
            color: widget.props.activeColor,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            l10n.radioRecommendations,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w800,
              letterSpacing: AppTracking.overline,
            ),
          ),
          const Spacer(),

          // Segmented Tab: Quran Mode vs Ambient
          Container(
            padding: const EdgeInsets.all(2.0),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.r20All,
              border: Border.all(color: p.hairline, width: 0.6),
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
                _buildTabButton(
                  tab: _RecommendationTab.ambient,
                  icon: Icons.water_drop_rounded,
                  label: l10n.ambientSounds,
                  activeColor: widget.props.activeColor,
                  p: p,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),

          // Collapse / Expand toggle button
          IconButton(
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
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
          ),
        ],
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
      borderRadius: AppRadii.r16All,
      child: AnimatedContainer(
        duration: context.motionMs(200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: AppRadii.r16All,
          border: Border.all(
            color: isSelected
                ? activeColor.withValues(alpha: 0.40)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? activeColor : p.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? p.textPrimary : p.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuranSection(BuildContext context, PulsrPalette p) {
    final state = widget.props.state;
    final isQuranOn = state.isQuranModeEnabled;
    final currentStyle = state.quranReciterStyle;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Power switch row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.quranEmerald.withValues(alpha: 0.16),
                  borderRadius: AppRadii.r8All,
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  size: 18,
                  color: AppColors.quranEmerald,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
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
                    Text(
                      '${currentStyle.label} • ${currentStyle.tagline}',
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                      ),
                    ),
                  ],
                ),
              ),
              PulsrSwitch(
                value: isQuranOn,
                onChanged: (v) {
                  PulsrHaptics.lightImpact();
                  unawaited(widget.cubit.setQuranModeEnabled(v));
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),

          // Style chips (Tajweed / Mujawwad is default; user choice saved as default)
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: QuranReciterStyle.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xxs),
              itemBuilder: (context, i) {
                final style = QuranReciterStyle.values[i];
                final isSelected = style == currentStyle;
                return ChoiceChip(
                  selected: isSelected,
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                  label: Text(
                    style == QuranReciterStyle.mujawwad
                        ? '${style.label} (Tajweed)'
                        : style.label,
                  ),
                  labelStyle: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : p.textPrimary,
                  ),
                  selectedColor: AppColors.quranEmerald,
                  backgroundColor: p.surfaceContainer,
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.quranEmerald
                        : p.hairline,
                  ),
                  onSelected: (_) {
                    PulsrHaptics.selectionClick();
                    unawaited(widget.cubit.setQuranReciterStyle(style));
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            context.l10n.styleDefaultNotice,
            style: TextStyle(
              color: p.textTertiary,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: AppSpacing.s6),

          // Always on Radio row
          Row(
            children: [
              Icon(
                Icons.radio_rounded,
                size: 16,
                color: _quranAlwaysOnRadio ? AppColors.quranEmerald : p.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  context.l10n.alwaysOnRadio,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PulsrSwitch(
                value: _quranAlwaysOnRadio,
                onChanged: (v) {
                  PulsrHaptics.selectionClick();
                  setState(() => _quranAlwaysOnRadio = v);
                  unawaited(widget.cubit.setQuranAlwaysOnRadio(v));
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.open_in_new_rounded, size: 16, color: p.textSecondary),
                tooltip: context.l10n.quranMode,
                onPressed: () => QuranModeSheet.show(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientSection(BuildContext context, PulsrPalette p) {
    final ambientService = AmbientSoundService();

    return ListenableBuilder(
      listenable: ambientService,
      builder: (context, _) {
        final isAmbientOn = ambientService.isEnabled;
        final masterVol = ambientService.masterVolume;
        final percent = (masterVol * 100).round();
        final alwaysOnRadio = ambientService.alwaysOnRadio;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.s10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Power switch row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: widget.props.activeColor.withValues(alpha: 0.16),
                      borderRadius: AppRadii.r8All,
                    ),
                    child: Icon(
                      Icons.water_drop_rounded,
                      size: 18,
                      color: widget.props.activeColor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
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
                        Text(
                          isAmbientOn && ambientService.activeEffects.isNotEmpty
                              ? ambientService.activeEffects
                                  .map((e) =>
                                      '${e.emoji} ${(ambientService.volumeFor(e) * 100).round()}%')
                                  .join('  ')
                              : context.l10n.ambientSoundsDesc,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PulsrSwitch(
                    value: isAmbientOn,
                    onChanged: (v) {
                      PulsrHaptics.lightImpact();
                      unawaited(ambientService.setEnabled(v));
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),

              // Effects chips
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: AmbientSoundEffect.values.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.xxs),
                  itemBuilder: (context, i) {
                    final effect = AmbientSoundEffect.values[i];
                    final isSelected = ambientService.isEffectActive(effect);
                    final effectVolPercent =
                        (ambientService.volumeFor(effect) * 100).round();

                    return ChoiceChip(
                      selected: isSelected,
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                      avatar: Text(
                        effect.emoji,
                        style: const TextStyle(fontSize: 13),
                      ),
                      label: Text(
                        isSelected
                            ? '${effect.localizedLabel(context.l10n)} $effectVolPercent%'
                            : effect.localizedLabel(context.l10n),
                      ),
                      labelStyle: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? Colors.white : p.textPrimary,
                      ),
                      selectedColor: widget.props.activeColor,
                      backgroundColor: p.surfaceContainer,
                      side: BorderSide(
                        color: isSelected
                            ? widget.props.activeColor
                            : p.hairline,
                      ),
                      onSelected: (_) {
                        PulsrHaptics.selectionClick();
                        unawaited(ambientService.toggleEffect(effect));
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.s8),

              // Volume percentage slider
              Row(
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
                      activeColor: widget.props.activeColor,
                      onChanged: (v) {
                        unawaited(ambientService.setMasterVolume(v));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              Divider(height: 1, color: p.hairline),
              const SizedBox(height: AppSpacing.s6),

              // Always on Radio row
              Row(
                children: [
                  Icon(
                    Icons.radio_rounded,
                    size: 16,
                    color: alwaysOnRadio
                        ? widget.props.activeColor
                        : p.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      context.l10n.alwaysOnRadio,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PulsrSwitch(
                    value: alwaysOnRadio,
                    onChanged: (v) {
                      PulsrHaptics.selectionClick();
                      unawaited(ambientService.setAlwaysOnRadio(v));
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.open_in_new_rounded,
                        size: 16, color: p.textSecondary),
                    tooltip: context.l10n.ambientSounds,
                    onPressed: () => AmbientSoundSheet.show(context),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
