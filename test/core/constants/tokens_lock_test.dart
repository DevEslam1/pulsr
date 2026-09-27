// test/core/constants/tokens_lock_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

void main() {
  group('Design Tokens Invariant Locks (Phase 0)', () {
    test('AppRadii semantic and geometric invariants hold', () {
      expect(AppRadii.tile, 14.0);
      expect(AppRadii.card, 18.0);
      expect(AppRadii.button, 14.0);
      expect(AppRadii.artwork, 20.0);
      expect(AppRadii.bottomSheet, 28.0);
      expect(AppRadii.chip, 10.0);
      expect(AppRadii.miniPlayer, 24.0);
      expect(AppRadii.dialog, 26.0);
      expect(AppRadii.squircleMultiplier, 2.2);

      // Verify numeric scale is monotonically strictly increasing
      const scale = [
        AppRadii.r2,
        AppRadii.r4,
        AppRadii.r6,
        AppRadii.r8,
        AppRadii.r10,
        AppRadii.r12,
        AppRadii.r14,
        AppRadii.r16,
        AppRadii.r18,
        AppRadii.r20,
        AppRadii.r22,
        AppRadii.r24,
        AppRadii.r28,
        AppRadii.r32,
      ];
      for (int i = 0; i < scale.length - 1; i++) {
        expect(scale[i] < scale[i + 1], isTrue,
            reason:
                'Radii scale must strictly increase: ${scale[i]} < ${scale[i + 1]}');
      }

      // Verify ContinuousRectangleBorder squircle curvature
      expect(
          AppRadii.squircleCard.borderRadius,
          BorderRadius.all(
              Radius.circular(AppRadii.card * AppRadii.squircleMultiplier)));
      expect(
          AppRadii.squircleTile.borderRadius,
          BorderRadius.all(
              Radius.circular(AppRadii.tile * AppRadii.squircleMultiplier)));
    });

    test('AppSpacing semantic scale and touch target standards hold', () {
      expect(AppSpacing.xxs, 4.0);
      expect(AppSpacing.xs, 8.0);
      expect(AppSpacing.sm, 12.0);
      expect(AppSpacing.md, 16.0);
      expect(AppSpacing.lg, 24.0);
      expect(AppSpacing.xl, 32.0);
      expect(AppSpacing.xxl, 48.0);

      // WCAG 2.5.5 / Material Touch Target requirement
      expect(AppSpacing.minTouchTarget, greaterThanOrEqualTo(48.0));

      const semanticScale = [
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
      ];
      for (int i = 0; i < semanticScale.length - 1; i++) {
        expect(semanticScale[i] < semanticScale[i + 1], isTrue);
      }
    });

    test('AppFontSize hierarchy scale is strictly monotonically ordered', () {
      expect(AppFontSize.micro, 9.0);
      expect(AppFontSize.tiny, 10.0);
      expect(AppFontSize.caption, 11.0);
      expect(AppFontSize.label, 12.0);
      expect(AppFontSize.bodySmall, 13.0);
      expect(AppFontSize.body, 14.0);
      expect(AppFontSize.callout, 15.0);
      expect(AppFontSize.bodyLarge, 16.0);
      expect(AppFontSize.title, 18.0);
      expect(AppFontSize.titleLarge, 20.0);
      expect(AppFontSize.headline, 24.0);
      expect(AppFontSize.display, 28.0);
      expect(AppFontSize.displayLarge, 32.0);

      const typeScale = [
        AppFontSize.micro,
        AppFontSize.tiny,
        AppFontSize.caption,
        AppFontSize.label,
        AppFontSize.bodySmall,
        AppFontSize.body,
        AppFontSize.callout,
        AppFontSize.bodyLarge,
        AppFontSize.title,
        AppFontSize.titleLarge,
        AppFontSize.headline,
        AppFontSize.display,
        AppFontSize.displayLarge,
      ];
      for (int i = 0; i < typeScale.length - 1; i++) {
        expect(typeScale[i] < typeScale[i + 1], isTrue);
      }
    });

    test('AppTracking tracking constants preserve typographic rhythm', () {
      expect(AppTracking.display, -0.8);
      expect(AppTracking.heading, -0.4);
      expect(AppTracking.title, -0.2);
      expect(AppTracking.none, 0.0);
      expect(AppTracking.label, 0.3);
      expect(AppTracking.medium, 0.5);
      expect(AppTracking.overline, 0.8);
      expect(AppTracking.wide, 1.2);
      expect(AppTracking.widest, 2.0);
    });

    test(
        'AppColors core brand and semantic tones exist and are non-transparent',
        () {
      expect(AppColors.primary.a, greaterThan(0.0));
      expect(AppColors.accentCyan.a, greaterThan(0.0));
      expect(AppColors.dacGold.a, greaterThan(0.0));
      expect(AppColors.error.a, greaterThan(0.0));
    });
  });
}
