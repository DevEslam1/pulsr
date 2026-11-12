// lib/features/shell/presentation/widgets/dock_style_picker_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_adaptive_sheet.dart';
import 'stacked_bottom_dock.dart';

import '../../../../core/utils/pulsr_haptics.dart';
/// Explicit picker for the mini-player dock stacking style.
///
/// Features:
/// - Realistic labeled micro-mockups showing the "▶ Now Playing" pill and 3-icon nav strip.
/// - Live animated preview that updates on hover/selection to demonstrate stacking behaviour.
/// - "Best for…" contextual guidance for each stacking configuration.
class DockStylePickerSheet extends StatefulWidget {
  final DockStackMode current;
  final ValueChanged<DockStackMode> onSelected;

  const DockStylePickerSheet({
    super.key,
    required this.current,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required DockStackMode current,
    required ValueChanged<DockStackMode> onSelected,
  }) {
    return PulsrAdaptiveSheet.show<void>(
      context: context,
      titleText: context.l10n.dockStyleTitle,
      subtitle: Text(context.l10n.dockStyleSubtitle),
      builder: (_) => DockStylePickerSheet(
        current: current,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<DockStylePickerSheet> createState() => _DockStylePickerSheetState();
}

class _DockStylePickerSheetState extends State<DockStylePickerSheet> {
  late DockStackMode _previewMode;

  @override
  void initState() {
    super.initState();
    _previewMode = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    final options = <(DockStackMode, String, String, String)>[
      (
        DockStackMode.defaultLayout,
        context.l10n.dockStyleDefault,
        context.l10n.dockStyleDefaultDesc,
        context.l10n.dockStyleDefaultBestFor,
      ),
      (
        DockStackMode.system,
        context.l10n.dockStyleSystem,
        context.l10n.dockStyleSystemDesc,
        context.l10n.dockStyleSystemBestFor,
      ),
      (
        DockStackMode.miniPlayerOnTop,
        context.l10n.dockStyleMiniTop,
        context.l10n.dockStyleMiniTopDesc,
        context.l10n.dockStyleMiniTopBestFor,
      ),
      (
        DockStackMode.navBarOnTop,
        context.l10n.dockStyleNavTop,
        context.l10n.dockStyleNavTopDesc,
        context.l10n.dockStyleNavTopBestFor,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live Interactive Preview Banner
          _LiveDockPreviewBanner(
            previewMode: _previewMode,
            selectedMode: widget.current,
          ),
          const SizedBox(height: AppSpacing.sm),

          for (final (mode, name, desc, bestFor) in options)
            _DockStyleOption(
              mode: mode,
              name: name,
              description: desc,
              bestFor: bestFor,
              selected: mode == widget.current,
              onHover: () {
                if (_previewMode != mode) {
                  setState(() => _previewMode = mode);
                }
              },
              onTap: () {
                PulsrHaptics.selectionClick();
                Navigator.of(context).pop();
                widget.onSelected(mode);
              },
            ),
        ],
      ),
    );
  }
}

class _DockStyleOption extends StatelessWidget {
  final DockStackMode mode;
  final String name;
  final String description;
  final String bestFor;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  const _DockStyleOption({
    required this.mode,
    required this.name,
    required this.description,
    required this.bestFor,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: '$name. $description.$bestFor',
      child: Material(
        color: Colors.transparent,
        child: MouseRegion(
          onEnter: (_) => onHover(),
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadii.r16All,
            child: AnimatedContainer(
              duration: context.motion(PulsrDurations.state),
              curve: context.motionCurve(Curves.easeOutCubic),
              margin: const EdgeInsets.only(bottom: AppSpacing.xs),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.s10,
              ),
              decoration: BoxDecoration(
                gradient: selected
                    ? LinearGradient(
                        begin: AlignmentDirectional.centerStart,
                        end: AlignmentDirectional.centerEnd,
                        colors: [
                          Color.alphaBlend(
                            p.accent.withValues(alpha: p.isDark ? 0.16 : 0.10),
                            p.surfaceContainerHigh,
                          ),
                          p.surfaceContainer,
                        ],
                      )
                    : null,
                color: selected
                    ? null
                    : p.surfaceContainer.withValues(alpha: 0.62),
                borderRadius: AppRadii.r16All,
                border: Border.all(
                  color: selected
                      ? p.accent.withValues(alpha: 0.65)
                      : p.hairline.withValues(alpha: 0.8),
                  width: selected ? 1.5 : 1.0,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: p.accent.withValues(alpha: 0.14),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: p.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: AppRadii.r12All,
                      border: Border.all(
                        color: selected
                            ? p.accent.withValues(alpha: 0.30)
                            : p.hairline.withValues(alpha: 0.5),
                      ),
                    ),
                    child: _DockMicroMockup(mode: mode, selected: selected),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: AppFontSize.body,
                            fontWeight: FontWeight.w800,
                            color: selected ? p.accent : p.textPrimary,
                            letterSpacing: -0.15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w500,
                            color: p.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bestFor,
                          style: TextStyle(
                            fontSize: AppFontSize.tiny,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? p.accent.withValues(alpha: 0.92)
                                : p.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AnimatedSwitcher(
                    duration: context.motion(PulsrDurations.state),
                    child: selected
                        ? Icon(
                            Icons.check_circle_rounded,
                            key: const ValueKey('selected'),
                            color: p.accent,
                            size: 22,
                          )
                        : Icon(
                            Icons.circle_outlined,
                            key: const ValueKey('unselected'),
                            color: p.textTertiary.withValues(alpha: 0.65),
                            size: 22,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Localized display name for a [DockStackMode] (used by pickers/settings).
String dockStyleName(BuildContext context, DockStackMode mode) {
  switch (mode) {
    case DockStackMode.defaultLayout:
      return context.l10n.dockStyleDefault;
    case DockStackMode.system:
      return context.l10n.dockStyleSystem;
    case DockStackMode.miniPlayerOnTop:
      return context.l10n.dockStyleMiniTop;
    case DockStackMode.navBarOnTop:
      return context.l10n.dockStyleNavTop;
  }
}

/// Large interactive preview banner showing how the two cards stack in real-time.
class _LiveDockPreviewBanner extends StatelessWidget {
  final DockStackMode previewMode;
  final DockStackMode selectedMode;

  const _LiveDockPreviewBanner({
    required this.previewMode,
    required this.selectedMode,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              p.accent.withValues(alpha: p.isDark ? 0.08 : 0.05),
              p.surfaceContainerHigh,
            ),
            p.surfaceContainer,
          ],
        ),
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.14),
                  borderRadius: AppRadii.r6All,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.layers_outlined, size: 13, color: p.accent),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      context.l10n.dockStylePreviewBadge,
                      style: TextStyle(
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w800,
                        color: p.accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                dockStyleName(context, previewMode),
                style: TextStyle(
                  fontSize: AppFontSize.tiny,
                  fontWeight: FontWeight.w700,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: SizedBox(
              height: 54,
              child: AnimatedSwitcher(
                duration: context.motionMs(260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale:
                        Tween<double>(begin: 0.95, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(previewMode),
                  child: _HeroDockStage(mode: previewMode),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stage rendering the labeled micro-cards for the banner.
class _HeroDockStage extends StatelessWidget {
  final DockStackMode mode;

  const _HeroDockStage({required this.mode});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    Widget nowPlayingCard({
      double opacity = 1.0,
      double scale = 1.0,
      bool elevated = false,
    }) =>
        Transform.scale(
          scale: scale,
          child: Container(
            width: 176,
            height: 23,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6),
            decoration: BoxDecoration(
              color: elevated
                  ? p.surface
                  : p.surfaceContainer.withValues(alpha: opacity),
              borderRadius: AppRadii.r12All,
              border: Border.all(
                color:
                    elevated ? p.accent : p.hairline.withValues(alpha: opacity),
                width: elevated ? 1.2 : 1,
              ),
              boxShadow: elevated
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(Icons.play_arrow_rounded, size: 12, color: p.accent),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    context.l10n.dockStyleNowPlaying,
                    style: TextStyle(
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary.withValues(alpha: opacity),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.skip_next_rounded, size: 11, color: p.textSecondary),
              ],
            ),
          ),
        );

    Widget navBarCard({
      double opacity = 1.0,
      double scale = 1.0,
      bool elevated = false,
    }) =>
        Transform.scale(
          scale: scale,
          child: Container(
            width: 176,
            height: 23,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: elevated
                  ? p.surface
                  : p.surfaceContainerHigh.withValues(alpha: opacity),
              borderRadius: AppRadii.r12All,
              border: Border.all(
                color:
                    elevated ? p.accent : p.hairline.withValues(alpha: opacity),
                width: elevated ? 1.2 : 1,
              ),
              boxShadow: elevated
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.home_rounded, size: 12, color: p.accent),
                Icon(Icons.search_rounded, size: 12, color: p.textTertiary),
                Icon(
                  Icons.library_music_rounded,
                  size: 12,
                  color: p.textTertiary,
                ),
              ],
            ),
          ),
        );

    switch (mode) {
      case DockStackMode.defaultLayout:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            nowPlayingCard(opacity: 1.0),
            const SizedBox(height: 5),
            navBarCard(opacity: 1.0),
          ],
        );
      case DockStackMode.system:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            nowPlayingCard(opacity: 1.0, scale: 0.96),
            const SizedBox(height: 1),
            navBarCard(opacity: 1.0),
          ],
        );
      case DockStackMode.miniPlayerOnTop:
        return SizedBox(
          width: 176,
          height: 48,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                  bottom: 2, child: navBarCard(opacity: 0.5, scale: 0.92)),
              Positioned(bottom: 12, child: nowPlayingCard(elevated: true)),
            ],
          ),
        );
      case DockStackMode.navBarOnTop:
        return SizedBox(
          width: 176,
          height: 48,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                  bottom: 14, child: nowPlayingCard(opacity: 0.5, scale: 0.92)),
              Positioned(bottom: 2, child: navBarCard(elevated: true)),
            ],
          ),
        );
    }
  }
}

/// A compact labeled micro-mockup of the two cards for the list tiles.
class _DockMicroMockup extends StatelessWidget {
  final DockStackMode mode;
  final bool selected;

  const _DockMicroMockup({required this.mode, required this.selected});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final navColor = p.surfaceContainerHigh;
    final miniColor = selected ? p.accentContainer : p.surfaceContainer;
    final borderColor = selected ? p.accent : p.hairline;

    Widget mini({double opacity = 1.0, double scale = 1.0}) => Container(
          width: 58 * scale,
          height: 14,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: miniColor.withValues(alpha: opacity),
            borderRadius: AppRadii.r6All,
            border: Border.all(
                color: borderColor.withValues(alpha: opacity), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, size: 8, color: p.accent),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  context.l10n.nowPlayingPreview,
                  style: TextStyle(
                    fontSize: 6,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary.withValues(alpha: opacity),
                  ),
                  overflow: TextOverflow.clip,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        );

    Widget nav({double opacity = 1.0, double scale = 1.0}) => Container(
          width: 58 * scale,
          height: 14,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: navColor.withValues(alpha: opacity),
            borderRadius: AppRadii.r6All,
            border: Border.all(
                color: p.hairline.withValues(alpha: opacity), width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.home_rounded, size: 7, color: p.accent),
              Icon(Icons.search_rounded, size: 7, color: p.textTertiary),
              Icon(Icons.library_music_rounded, size: 7, color: p.textTertiary),
            ],
          ),
        );

    late final Widget content;
    switch (mode) {
      case DockStackMode.defaultLayout:
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [mini(), const SizedBox(height: 3), nav()],
        );
        break;
      case DockStackMode.system:
        content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            mini(scale: 0.95),
            const SizedBox(height: 1),
            nav(),
          ],
        );
        break;
      case DockStackMode.miniPlayerOnTop:
        content = SizedBox(
          width: 62,
          height: 34,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(bottom: 1, child: nav(opacity: 0.5, scale: 0.92)),
              Positioned(bottom: 9, child: mini()),
            ],
          ),
        );
        break;
      case DockStackMode.navBarOnTop:
        content = SizedBox(
          width: 62,
          height: 34,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(bottom: 9, child: mini(opacity: 0.5, scale: 0.92)),
              Positioned(bottom: 1, child: nav()),
            ],
          ),
        );
        break;
    }

    return SizedBox(width: 64, height: 38, child: Center(child: content));
  }
}
