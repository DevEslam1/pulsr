// lib/core/services/coach_mark_service.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../constants/prefs_keys.dart';
import '../theme/aura_theme.dart';
import '../utils/l10n_extensions.dart';
import '../widgets/pulsr_bottom_sheet.dart';

/// Coordinator for first-encounter contextual coach marks.
///
/// Rules:
/// - Maximum one coach mark per session (process lifetime).
/// - Shown on first encounter only (persisted in [PrefsKeys]).
class CoachMarkService {
  CoachMarkService._();

  /// Session gate: true if any coach mark has been displayed in this process session.
  static bool sessionCoachMarkShown = false;

  /// Resets the session gate (primarily for unit tests).
  @visibleForTesting
  static void resetSession() {
    sessionCoachMarkShown = false;
  }

  /// Core evaluator: verifies session and persistence gates, then displays the coach mark.
  static Future<bool> maybeShow({
    required BuildContext context,
    required String prefsKey,
    required String title,
    required String body,
    IconData icon = Icons.lightbulb_rounded,
    SharedPreferences? customPrefs,
  }) async {
    if (sessionCoachMarkShown) return false;

    final prefs = customPrefs ?? await SharedPreferences.getInstance();
    if (prefs.getBool(prefsKey) == true) return false;

    // Claim session and persist encounter before showing so race conditions cannot double-fire
    sessionCoachMarkShown = true;
    await prefs.setBool(prefsKey, true);

    if (!context.mounted) return true;

    await PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (ctx) {
        final p = ctx.palette;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: p.accent, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.title,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                body,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.body,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadii.buttonRadius,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    ctx.l10n.gotIt,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    return true;
  }

  /// 1. First DSP open: Essential vs Studio explainer.
  static Future<bool> maybeShowDspExplainer(
    BuildContext context, {
    SharedPreferences? customPrefs,
  }) {
    return maybeShow(
      context: context,
      prefsKey: PrefsKeys.coachMarkDspSeen,
      title: context.l10n.coachMarkDspTitle,
      body: context.l10n.coachMarkDspBody,
      icon: Icons.tune_rounded,
      customPrefs: customPrefs,
    );
  }

  /// 2. First USB DAC attach: Bit-perfect explainer with honest verdict copy.
  static Future<bool> maybeShowUsbDacExplainer(
    BuildContext context, {
    SharedPreferences? customPrefs,
  }) {
    return maybeShow(
      context: context,
      prefsKey: PrefsKeys.coachMarkUsbDacSeen,
      title: context.l10n.coachMarkUsbDacTitle,
      body: context.l10n.coachMarkUsbDacBody,
      icon: Icons.usb_rounded,
      customPrefs: customPrefs,
    );
  }

  /// 3. First dock swipe: Style hint.
  static Future<bool> maybeShowDockSwipeHint(
    BuildContext context, {
    SharedPreferences? customPrefs,
  }) {
    return maybeShow(
      context: context,
      prefsKey: PrefsKeys.coachMarkDockSwipeSeen,
      title: context.l10n.coachMarkDockSwipeTitle,
      body: context.l10n.coachMarkDockSwipeBody,
      icon: Icons.swipe_rounded,
      customPrefs: customPrefs,
    );
  }
}
