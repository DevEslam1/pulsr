import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injection.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _timedOut = false;

  /// Re-entrancy guard: the retry button can be tapped repeatedly (or while the
  /// initial check is still awaiting) which would fire duplicate routed
  /// navigation and double timeouts.
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkNextScreen();
  }

  Future<void> _checkNextScreen() async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      // Hold the intro for its full choreography, but never route before the DI
      // graph is actually ready. The timeout is a safety net so a stuck
      // initializer can never trap the user on the splash (I25).
      bool timedOut = false;
      try {
        await Future.wait<void>([
          Future<void>.delayed(const Duration(milliseconds: 800)),
          initializationReady.timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              timedOut = true;
            },
          ),
        ]);
      } catch (e, st) {
        ErrorLogger.log('Splash initialization wait failed',
            error: e, stackTrace: st, category: 'Splash');
        timedOut = true;
      }
      if (!mounted) return;
      if (timedOut && !getIt.allReadySync()) {
        setState(() => _timedOut = true);
        return;
      }

      var onboardingDone = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        onboardingDone = prefs.getBool('onboarding_completed') ?? false;
      } catch (e, st) {
        // A prefs failure must not strand the user on the splash; fall through
        // to onboarding, which is the safe default.
        ErrorLogger.log('Failed to read onboarding flag',
            error: e, stackTrace: st, category: 'Splash');
      }

      if (!mounted) return;
      if (onboardingDone) {
        context.go('/');
      } else {
        context.go('/onboarding');
      }
    } finally {
      _isChecking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.r24),
                boxShadow: [
                  BoxShadow(
                    color: p.favorite.withValues(alpha: 0.45),
                    blurRadius: 36,
                    spreadRadius: 4,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.r24),
                child: Image.asset(
                  'assets/app_icon/app_icon_plus.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  semanticLabel: context.l10n.appTitle,
                ),
              ),
            )
                .animate()
                .scale(
                    duration: context.motionMs(800),
                    curve: context.motionCurve(Curves.easeOutBack))
                .fadeIn(duration: context.motionMs(600)),
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.l10n.appTitle,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.heading,
                    color: p.textPrimary,
                  ),
            )
                .animate()
                .fadeIn(
                    delay: context.motionMs(300),
                    duration: context.motionMs(600))
                .slideY(begin: 0.2, end: 0),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.l10n.appTagline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: p.textSecondary,
                    letterSpacing: AppTracking.medium,
                  ),
            ).animate().fadeIn(
                delay: context.motionMs(500), duration: context.motionMs(600)),
            if (_timedOut) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.r14),
                  ),
                ),
                onPressed: () {
                  setState(() => _timedOut = false);
                  _checkNextScreen();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
