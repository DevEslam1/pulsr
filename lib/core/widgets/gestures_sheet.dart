import 'package:material_ui/material_ui.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/gesture_map.dart';
import '../theme/aura_theme.dart';
import '../utils/l10n_extensions.dart';
import 'pulsr_adaptive_sheet.dart';

/// Modal guide rendering every gesture registered in [PulsrGestureMap].
class GesturesSheet extends StatelessWidget {
  const GesturesSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrAdaptiveSheet.show<void>(
      context: context,
      titleText: context.l10n.gesturesGuideTitle,
      subtitle: Text(context.l10n.gesturesGuideSubtitle),
      builder: (_) => const GesturesSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final surface in GestureSurface.values) ...[
              if (PulsrGestureMap.forSurface(surface).isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.xs,
                    start: AppSpacing.xxs,
                  ),
                  child: Text(
                    surface.label(l10n),
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w800,
                      letterSpacing: AppTracking.overline,
                      color: p.accent,
                    ),
                  ),
                ),
                for (final entry in PulsrGestureMap.forSurface(surface))
                  _GestureEntryCard(entry: entry),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _GestureEntryCard extends StatelessWidget {
  final PulsrGestureEntry entry;

  const _GestureEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final title = entry.titleBuilder(l10n);
    final desc = entry.descriptionBuilder(l10n);

    return Semantics(
      label: '$title. $desc',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.s10,
        ),
        decoration: BoxDecoration(
          color: p.surfaceContainer.withValues(alpha: 0.65),
          borderRadius: AppRadii.r14All,
          border: Border.all(
            color: p.hairline.withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: p.isDark ? 0.16 : 0.12),
                borderRadius: AppRadii.r10All,
                border: Border.all(
                  color: p.accent.withValues(alpha: 0.28),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(entry.icon, size: 20, color: p.accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: AppFontSize.body,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: p.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
