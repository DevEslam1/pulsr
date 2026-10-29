// F1/F2/F11 controls: AB loop, per-track delay, bookmark resume.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// AB-loop / bookmark labels need a placeholder for an unset point; the
/// duration itself is formatted with the shared [Formatters.formatDuration] so
/// it can never disagree with the seek bar (A-12).
String _fmt(Duration? d) {
  if (d == null) return '--:--';
  return Formatters.formatDuration(d);
}

class AdvancedPlaybackBar extends StatelessWidget {
  final Color? activeColor;
  final double? height;
  final bool disableBlur;

  const AdvancedPlaybackBar({
    super.key,
    this.activeColor,
    this.height,
    this.disableBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final custom = context
        .select<SettingsCubit, ({double radius, bool glow, bool active})>(
            (c) => (
                  radius: c.state.customThemeRadius,
                  glow: c.state.customThemeGlow,
                  active: c.state.themeColorSource == ThemeColorSource.custom,
                ));
    final barRadius = custom.active ? custom.radius : 24.0;
    final resolvedActiveColor = activeColor ?? p.accent;
    final double barHeight = height ?? 48.0;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (p, c) =>
          p.abLoopEnabled != c.abLoopEnabled ||
          p.abPointA != c.abPointA ||
          p.abPointB != c.abPointB ||
          p.trackDelayMs != c.trackDelayMs ||
          p.bookmarkPosition != c.bookmarkPosition ||
          p.currentSong?.id != c.currentSong?.id,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        // A/B loop and per-track delay are pro-audio tools; keep the consumer
        // surface clean in Normal mode while still showing the bookmark prompt.
        final mode = context.select<SettingsCubit, ExperienceMode>(
            (c) => c.state.experienceMode);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.bookmarkPosition != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
                child: Material(
                  color: context.palette.warning.withValues(alpha: 0.15),
                  borderRadius: AppRadii.r12All,
                  child: ListTile(
                    dense: true,
                    leading:
                        Icon(Icons.bookmark, color: context.palette.warning),
                    title: Text(
                        l10n.resumeFromPrompt(_fmt(state.bookmarkPosition))),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                            onPressed: cubit.seekToBookmark,
                            child: Text(l10n.resume)),
                        IconButton(
                            constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTouchTarget,
                                minHeight: AppSpacing.minTouchTarget),
                            tooltip: l10n.close,
                            onPressed: cubit.dismissBookmark,
                            icon: const Icon(Icons.close, size: 18)),
                      ],
                    ),
                  ),
                ),
              ),
            if (mode == ExperienceMode.professional)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: ClipRRect(
                    borderRadius: AppRadii.circular(barRadius),
                    child: Builder(
                      builder: (context) {
                        final dockContainer = Container(
                          constraints: BoxConstraints(
                            minHeight: barHeight,
                            maxHeight: barHeight,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          decoration: BoxDecoration(
                            color: p.surfaceContainer,
                            borderRadius: AppRadii.circular(barRadius),
                            border: Border.all(
                              color: p.hairline,
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                    alpha: p.isDark ? 0.20 : 0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // F1: AB loop - Point A
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: AppSpacing.minTouchTarget,
                                    minHeight: AppSpacing.minTouchTarget),
                                tooltip:
                                    l10n.setLoopPointA(_fmt(state.abPointA)),
                                color: state.abPointA != null
                                    ? resolvedActiveColor
                                    : null,
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  cubit.setAbPointA();
                                },
                                icon: _buildPointPill(
                                  context: context,
                                  label: 'A',
                                  isActive: state.abPointA != null,
                                  activeColor: resolvedActiveColor,
                                ),
                              ),
                              // Point B
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: AppSpacing.minTouchTarget,
                                    minHeight: AppSpacing.minTouchTarget),
                                tooltip:
                                    l10n.setLoopPointB(_fmt(state.abPointB)),
                                color: state.abPointB != null
                                    ? resolvedActiveColor
                                    : null,
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  cubit.setAbPointB();
                                },
                                icon: _buildPointPill(
                                  context: context,
                                  label: 'B',
                                  isActive: state.abPointB != null,
                                  activeColor: resolvedActiveColor,
                                ),
                              ),
                              // Loop Toggle
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: AppSpacing.minTouchTarget,
                                    minHeight: AppSpacing.minTouchTarget),
                                tooltip: state.abLoopEnabled
                                    ? l10n.disableAbLoop
                                    : l10n.enableAbLoop,
                                color: state.abLoopEnabled
                                    ? context.palette.success
                                    : null,
                                onPressed: (state.abPointA != null &&
                                        state.abPointB != null)
                                    ? () {
                                        HapticFeedback.lightImpact();
                                        cubit.toggleAbLoop();
                                      }
                                    : null,
                                icon: AnimatedContainer(
                                  duration: context.motionMs(200),
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: state.abLoopEnabled
                                        ? context.palette.success
                                            .withValues(alpha: 0.22)
                                        : Colors.transparent,
                                    border: state.abLoopEnabled
                                        ? Border.all(
                                            color: context.palette.success
                                                .withValues(alpha: 0.45),
                                            width: 1.2,
                                          )
                                        : null,
                                  ),
                                  child: Icon(
                                    Icons.repeat_one_rounded,
                                    size: 18,
                                    color: (state.abPointA != null &&
                                            state.abPointB != null)
                                        ? (state.abLoopEnabled
                                            ? context.palette.success
                                            : p.textSecondary)
                                        : p.textSecondary
                                            .withValues(alpha: 0.35),
                                  ),
                                ),
                              ),
                              if (state.abPointA != null ||
                                  state.abPointB != null)
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: AppSpacing.minTouchTarget,
                                      minHeight: AppSpacing.minTouchTarget),
                                  tooltip: l10n.clearAbLoop,
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    cubit.clearAbLoop();
                                  },
                                  icon: Container(
                                    width: 26,
                                    height: 26,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: (p.isDark
                                              ? Colors.white
                                              : Colors.black)
                                          .withValues(alpha: 0.08),
                                    ),
                                    child: Icon(Icons.close_rounded,
                                        size: 15, color: p.textSecondary),
                                  ),
                                ),
                              if (state.abPointA != null ||
                                  state.abPointB != null)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                      start: AppSpacing.xxs,
                                      end: AppSpacing.xs),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: resolvedActiveColor.withValues(
                                            alpha: 0.12),
                                        borderRadius: AppRadii.r12All,
                                        border: Border.all(
                                          color: resolvedActiveColor.withValues(
                                              alpha: 0.25),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        'A ${_fmt(state.abPointA)} · B ${_fmt(state.abPointB)}',
                                        style: TextStyle(
                                          fontSize: AppFontSize.tiny,
                                          fontWeight: FontWeight.w700,
                                          color: resolvedActiveColor,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Container(
                                width: 1,
                                height: 18,
                                margin: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xxs),
                                color: (p.isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: 0.14),
                              ),
                              // F2: per-track delay
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: AppSpacing.minTouchTarget,
                                    minHeight: AppSpacing.minTouchTarget),
                                tooltip:
                                    l10n.audioDelayTooltip(state.trackDelayMs),
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  _showDelaySheet(
                                      context, cubit, state.trackDelayMs);
                                },
                                icon: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration: context.motionMs(200),
                                      width: 32,
                                      height: 32,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: state.trackDelayMs != 0
                                            ? resolvedActiveColor.withValues(
                                                alpha: 0.20)
                                            : Colors.transparent,
                                        border: state.trackDelayMs != 0
                                            ? Border.all(
                                                color: resolvedActiveColor
                                                    .withValues(alpha: 0.45),
                                                width: 1.2,
                                              )
                                            : null,
                                      ),
                                      child: Icon(
                                        Icons.av_timer_rounded,
                                        size: 18,
                                        color: state.trackDelayMs != 0
                                            ? resolvedActiveColor
                                            : p.textSecondary,
                                      ),
                                    ),
                                    if (state.trackDelayMs != 0)
                                      PositionedDirectional(
                                        top: -3,
                                        end: -5,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 3.5,
                                            vertical: 1.0,
                                          ),
                                          decoration: BoxDecoration(
                                            color: resolvedActiveColor,
                                            borderRadius: AppRadii.r6All,
                                            border: Border.all(
                                              color: p.surface,
                                              width: 1.2,
                                            ),
                                          ),
                                          child: Text(
                                            '${state.trackDelayMs > 0 ? '+' : ''}${state.trackDelayMs}ms',
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 7.5,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );

                        return dockContainer;
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPointPill({
    required BuildContext context,
    required String label,
    required bool isActive,
    required Color activeColor,
  }) {
    final p = context.palette;
    return AnimatedContainer(
      duration: context.motionMs(200),
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            isActive ? activeColor.withValues(alpha: 0.20) : Colors.transparent,
        border: isActive
            ? Border.all(
                color: activeColor.withValues(alpha: 0.45),
                width: 1.2,
              )
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          color: isActive ? activeColor : p.textSecondary,
        ),
      ),
    );
  }

  void _showDelaySheet(BuildContext context, PlayerCubit cubit, int current) {
    PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => _DelaySheet(initial: current, cubit: cubit),
    );
  }
}

class _DelaySheet extends StatefulWidget {
  final int initial;
  final PlayerCubit cubit;
  const _DelaySheet({required this.initial, required this.cubit});

  @override
  State<_DelaySheet> createState() => _DelaySheetState();
}

class _DelaySheetState extends State<_DelaySheet> {
  late double value;
  @override
  void initState() {
    super.initState();
    value = widget.initial.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.audioDelayMsLabel(value.round()),
                style: Theme.of(context).textTheme.titleMedium),
            Text(l10n.audioDelayHelp),
            PulsrSlider(
              min: -2000,
              max: 2000,
              divisions: 80,
              value: value,
              semanticLabel: l10n.audioDelayMsLabel(value.round()),
              onChanged: (v) => setState(() => value = v),
              onChangeEnd: (v) => widget.cubit.setTrackDelayMs(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    widget.cubit.setTrackDelayMs(0);
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(l10n.reset),
                ),
                FilledButton(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(l10n.done),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
