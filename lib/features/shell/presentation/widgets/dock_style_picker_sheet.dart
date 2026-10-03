// lib/features/shell/presentation/widgets/dock_style_picker_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'stacked_bottom_dock.dart';

/// Explicit picker for the mini-player dock stacking style.
///
/// Replaces the previously invisible swipe-only gesture with a discoverable
/// chooser. The gesture still works as a power-user shortcut.
class DockStylePickerSheet extends StatelessWidget {
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
    return showModalBottomSheet<void>(
      context: context,
      // Root navigator so the single root PulsrModalObserver tracks it and the
      // dock hides even when opened from inside a shell branch.
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DockStylePickerSheet(
        current: current,
        onSelected: onSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final options = <(DockStackMode, String, String)>[
      (
        DockStackMode.defaultLayout,
        context.l10n.dockStyleDefault,
        context.l10n.dockStyleDefaultDesc,
      ),
      (
        DockStackMode.system,
        context.l10n.dockStyleSystem,
        context.l10n.dockStyleSystemDesc,
      ),
      (
        DockStackMode.miniPlayerOnTop,
        context.l10n.dockStyleMiniTop,
        context.l10n.dockStyleMiniTopDesc,
      ),
      (
        DockStackMode.navBarOnTop,
        context.l10n.dockStyleNavTop,
        context.l10n.dockStyleNavTopDesc,
      ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
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
            Text(
              context.l10n.dockStyleTitle,
              style: TextStyle(
                fontSize: AppFontSize.titleLarge,
                fontWeight: FontWeight.w800,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              context.l10n.dockStyleSubtitle,
              style: TextStyle(
                fontSize: AppFontSize.bodySmall,
                fontWeight: FontWeight.w500,
                color: p.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (mode, name, desc) in options)
              _DockStyleOption(
                mode: mode,
                name: name,
                description: desc,
                selected: mode == current,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop();
                  onSelected(mode);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _DockStyleOption extends StatelessWidget {
  final DockStackMode mode;
  final String name;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _DockStyleOption({
    required this.mode,
    required this.name,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: '$name. $description',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.r16All,
          child: AnimatedContainer(
            duration: context.motion(PulsrDurations.state),
            curve: context.motionCurve(Curves.easeOutCubic),
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: selected
                  ? p.accentContainer
                  : p.surfaceContainer.withValues(alpha: 0.6),
              borderRadius: AppRadii.r16All,
              border: Border.all(
                color: selected ? p.accent : p.hairline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                _DockPreview(mode: mode, selected: selected),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: AppFontSize.body,
                          fontWeight: FontWeight.w700,
                          color: selected ? p.accent : p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w500,
                          color: p.textTertiary,
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
                          color: p.textTertiary,
                          size: 22,
                        ),
                ),
              ],
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

/// A compact schematic preview of how the two dock cards stack.
class _DockPreview extends StatelessWidget {
  final DockStackMode mode;
  final bool selected;

  const _DockPreview({required this.mode, required this.selected});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final navColor = p.textTertiary.withValues(alpha: 0.55);
    final miniColor = selected ? p.accent : p.textSecondary;

    Widget mini({double opacity = 1.0, double scale = 1.0}) => Container(
          width: 44 * scale,
          height: 12,
          decoration: BoxDecoration(
            color: miniColor.withValues(alpha: opacity),
            borderRadius: AppRadii.r6All,
          ),
        );
    Widget nav({double opacity = 1.0, double scale = 1.0}) => Container(
          width: 48 * scale,
          height: 12,
          decoration: BoxDecoration(
            color: navColor.withValues(alpha: opacity),
            borderRadius: AppRadii.r6All,
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
            mini(),
            const SizedBox(height: 1),
            nav(),
          ],
        );
        break;
      case DockStackMode.miniPlayerOnTop:
        content = SizedBox(
          width: 48,
          height: 30,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(bottom: 0, child: nav(opacity: 0.5, scale: 0.92)),
              Positioned(bottom: 8, child: mini()),
            ],
          ),
        );
        break;
      case DockStackMode.navBarOnTop:
        content = SizedBox(
          width: 48,
          height: 30,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(bottom: 8, child: mini(opacity: 0.5, scale: 0.92)),
              Positioned(bottom: 0, child: nav()),
            ],
          ),
        );
        break;
    }

    return SizedBox(width: 56, height: 34, child: Center(child: content));
  }
}
